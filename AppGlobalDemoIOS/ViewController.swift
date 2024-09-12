//
//  ViewController.swift
//  AppGlobalDemo
//
//  Created by Anis Mansuri on 09/09/24.
//

import UIKit
import AppGlobaliOS

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        testGet()
//        testPost()
    }
    func testGet() {
        print(#function)
        var request = URLRequest(url: URL(string: "https://jsonplaceholder.typicode.com/postshttps://jsonplaceholder.typicode.com/posts")!,timeoutInterval: Double.infinity)
        request.httpMethod = "GET"

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
          guard let data = data else {
            print(String(describing: error))
            return
          }
            print(String(data: data, encoding: .utf8))
            
        }
        task.resume()

    }
    

    func testPost() {
        var request = URLRequest(url: URL(string: "https://facebook.com")!,timeoutInterval: Double.infinity)
        request.httpMethod = "GET"

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
          guard let data = data else {
            print(String(describing: error))
            return
          }
            print(String(data: data, encoding: .utf8))
            
        }
        task.resume()

    }
    @IBAction func getConfigListAction(_ sender: UIButton) {
        testGet()
        let viewCon = self.storyboard!.instantiateViewController(identifier: "ListViewController") as! ListViewController
        viewCon.string = AppGlobal.getConfigList()
        self.navigationController?.pushViewController(viewCon, animated: true)
        
    }
    @IBAction func getRequestListAction(_ sender: UIButton) {
        let viewCon = self.storyboard!.instantiateViewController(identifier: "ListViewController") as! ListViewController
        viewCon.string = AppGlobal.getInterceptedRequestList()
        self.navigationController?.pushViewController(viewCon, animated: true)
    }
    @IBAction func getRequestListAllAction(_ sender: UIButton) {
        let viewCon = self.storyboard!.instantiateViewController(identifier: "ListViewController") as! ListViewController
        viewCon.string = AppGlobal.getInterceptedRequestListAll()
        self.navigationController?.pushViewController(viewCon, animated: true)
    }


}

