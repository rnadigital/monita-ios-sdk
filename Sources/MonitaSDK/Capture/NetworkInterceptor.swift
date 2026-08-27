//  Copyright RNA Digital PTY LTD

import Foundation
import ObjectiveC

/// Passive URLSession observation. Never a URLProtocol proxy: URLProtocol
/// must re-issue requests, and this SDK refuses to sit in the request path.
///
/// Installation swizzles URLSessionTask.resume (found by walking the class
/// hierarchy of a real task to the class that owns the implementation) to
/// snapshot the request at send time, and observes task completion through
/// KVO on `state` to read the HTTP status code. Requests are never mutated,
/// re-issued, or consumed; httpBodyStream is never touched.
///
/// A cheap capture predicate runs first on every resume: when it returns
/// false (opted out, killed, or the URL matches no vendor pattern once a
/// config is loaded) the task pays no snapshot, no body copy, no associated
/// objects, and no KVO.
enum NetworkInterceptor {

    /// Holds the observed task weakly so the engine's sweep can re-check
    /// task.state without keeping the task alive.
    final class WeakTaskBox: @unchecked Sendable {
        private(set) weak var task: URLSessionTask?
        init(_ task: URLSessionTask) { self.task = task }
    }

    /// Delivered on an arbitrary thread; the engine hops to its own queue.
    struct TaskEvent: @unchecked Sendable {
        let taskKey: ObjectIdentifier
        let request: CapturedRequest
        let taskRef: WeakTaskBox
    }

    private static let lock = NSLock()
    private static var installed = false
    private static var resumeHandler: (@Sendable (TaskEvent) -> Void)?
    private static var completionHandler: (@Sendable (ObjectIdentifier, Int?, Bool) -> Void)?
    private static var capturePredicate: (@Sendable (String) -> Bool)?
    private static var originalResume: (@convention(c) (AnyObject, Selector) -> Void)?
    private static var seenKey: UInt8 = 0
    private static var observerKey: UInt8 = 0

    static func setHandlers(
        shouldCapture: @escaping @Sendable (String) -> Bool,
        onResume: @escaping @Sendable (TaskEvent) -> Void,
        onCompletion: @escaping @Sendable (ObjectIdentifier, Int?, Bool) -> Void
    ) {
        lock.lock()
        capturePredicate = shouldCapture
        resumeHandler = onResume
        completionHandler = onCompletion
        lock.unlock()
    }

    /// Installs the resume swizzle. Idempotent; double install is a no op.
    /// Returns true when interception is active.
    @discardableResult
    static func install() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if installed { return true }
        let selector = NSSelectorFromString("resume")
        guard let targetClass = resumeImplementingClass(selector: selector),
              let method = class_getInstanceMethod(targetClass, selector) else {
            MonitaLog.error("network interception unavailable, URLSessionTask resume not found")
            return false
        }
        let original = method_getImplementation(method)
        originalResume = unsafeBitCast(original, to: (@convention(c) (AnyObject, Selector) -> Void).self)
        let block: @convention(block) (AnyObject) -> Void = { object in
            handleResume(object)
            NetworkInterceptor.callOriginalResume(object, selector)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
        installed = true
        MonitaLog.debug("network interception installed on \(NSStringFromClass(targetClass))")
        return true
    }

    static var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return installed
    }

    private static func callOriginalResume(_ object: AnyObject, _ selector: Selector) {
        lock.lock()
        let original = originalResume
        lock.unlock()
        original?(object, selector)
    }

    /// Finds the class in the task's hierarchy that owns the resume
    /// implementation instances actually dispatch through. URLSessionTask is
    /// a class cluster, so the concrete class of a real task is inspected.
    static func resumeImplementingClass(selector: Selector) -> AnyClass? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let url = URL(string: "https://cdn.monita.ai/health") else { return nil }
        let task = session.dataTask(with: url)
        defer { task.cancel() }
        var candidate: AnyClass? = object_getClass(task)
        while let current = candidate {
            if let method = class_getInstanceMethod(current, selector) {
                let superclass: AnyClass? = class_getSuperclass(current)
                let superMethod = superclass.flatMap { class_getInstanceMethod($0, selector) }
                if let superMethod = superMethod {
                    if method_getImplementation(method) != method_getImplementation(superMethod) {
                        return current
                    }
                } else {
                    return current
                }
            }
            candidate = class_getSuperclass(current)
        }
        return nil
    }

    private static func handleResume(_ object: AnyObject) {
        lock.lock()
        let handler = resumeHandler
        let completion = completionHandler
        let predicate = capturePredicate
        lock.unlock()
        guard let handler = handler, let task = object as? URLSessionTask else { return }
        guard let request = task.originalRequest ?? task.currentRequest,
              let urlString = request.url?.absoluteString else {
            return
        }
        // Cheap prefilter: uninteresting tasks pay nothing beyond this check.
        if let predicate = predicate, !predicate(urlString) { return }
        // A task resumed more than once reports once.
        if objc_getAssociatedObject(task, &seenKey) != nil { return }
        objc_setAssociatedObject(task, &seenKey, NSNumber(value: true), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        var body = request.httpBody
        if let candidate = body, candidate.count > BodyParser.bodyReadCap {
            body = nil
        }
        let snapshot = CapturedRequest(
            url: urlString,
            method: (request.httpMethod ?? "GET").uppercased(),
            body: body,
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            timestamp: Date().timeIntervalSince1970
        )
        let key = ObjectIdentifier(task)
        handler(TaskEvent(taskKey: key, request: snapshot, taskRef: WeakTaskBox(task)))

        guard let completion = completion else { return }
        let box = ObservationBox()
        box.observation = task.observe(\.state, options: [.new]) { [weak box] observedTask, _ in
            guard observedTask.state == .completed else { return }
            guard let box = box, box.fireOnce() else { return }
            let status = (observedTask.response as? HTTPURLResponse)?.statusCode
            let errored = observedTask.error != nil
            completion(key, status, errored)
            objc_setAssociatedObject(observedTask, &observerKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        objc_setAssociatedObject(task, &observerKey, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private final class ObservationBox: NSObject {
        var observation: NSKeyValueObservation?
        private let fireLock = NSLock()
        private var fired = false

        func fireOnce() -> Bool {
            fireLock.lock()
            defer { fireLock.unlock() }
            if fired { return false }
            fired = true
            observation?.invalidate()
            return true
        }
    }
}
