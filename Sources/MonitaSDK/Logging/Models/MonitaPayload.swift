//
//  MonitaPayload.swift
//  MonitaSDK
//
//  Created by Igor  Vojinovic on 11.3.25..
//

// MonitaPayload.swift
import Foundation

struct MonitaPayload: Codable {
    let t: String      // token
    let dm: String
    let mv: String
    let sv: String
    let tm: String
    let e: String
    let vn: String
    let st: String
    let m: String
    let vu: String
    let u: String
    let p: String
    let dt: [Parameter]
    let s: String
    let rl: String
    let env: String
    let et: String
    let vid: String
    let cn: String
    let sid: String
    let cid: String
    let ev: String

}

extension MonitaPayload {
    enum CodingKeys: String, CodingKey {
        case t, dm, mv, sv, tm, e, vn, st, m, vu, u, p, dt, s, rl, env, et, vid, cn, sid, cid, ev
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(t, forKey: .t)
        try container.encode(dm, forKey: .dm)
        try container.encode(mv, forKey: .mv)
        try container.encode(sv, forKey: .sv)
        try container.encode(tm, forKey: .tm)
        try container.encode(e, forKey: .e)
        try container.encode(vn, forKey: .vn)
        try container.encode(st, forKey: .st)
        try container.encode(m, forKey: .m)
        try container.encode(vu, forKey: .vu)
        try container.encode(u, forKey: .u)
        try container.encode(p, forKey: .p)
        try container.encode(s, forKey: .s)
        try container.encode(rl, forKey: .rl)
        try container.encode(env, forKey: .env)
        try container.encode(et, forKey: .et)
        try container.encode(vid, forKey: .vid)
        try container.encode(cn, forKey: .cn)
        try container.encode(sid, forKey: .sid)
        try container.encode(cid, forKey: .cid)
        try container.encode(ev, forKey: .ev)
        
        // Encode dt as raw JSON
        let dtData = try JSONSerialization.data(withJSONObject: dt, options: [])
        let dtString = String(data: dtData, encoding: .utf8) ?? "[]"
        try container.encode(dtString, forKey: .dt)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(String.self, forKey: .t)
        dm = try container.decode(String.self, forKey: .dm)
        mv = try container.decode(String.self, forKey: .mv)
        sv = try container.decode(String.self, forKey: .sv)
        tm = try container.decode(String.self, forKey: .tm)
        e = try container.decode(String.self, forKey: .e)
        vn = try container.decode(String.self, forKey: .vn)
        st = try container.decode(String.self, forKey: .st)
        m = try container.decode(String.self, forKey: .m)
        vu = try container.decode(String.self, forKey: .vu)
        u = try container.decode(String.self, forKey: .u)
        p = try container.decode(String.self, forKey: .p)
        s = try container.decode(String.self, forKey: .s)
        rl = try container.decode(String.self, forKey: .rl)
        env = try container.decode(String.self, forKey: .env)
        et = try container.decode(String.self, forKey: .et)
        vid = try container.decode(String.self, forKey: .vid)
        cn = try container.decode(String.self, forKey: .cn)
        sid = try container.decode(String.self, forKey: .sid)
        cid = try container.decode(String.self, forKey: .cid)
        ev = try container.decode(String.self, forKey: .ev)
        
        // dt is stored as a JSON string. We'll attempt to decode it:
        let dtString = try container.decode(String.self, forKey: .dt)
        let data = Data(dtString.utf8)
        if let arr = try? JSONSerialization.jsonObject(with: data, options: []) as? [Parameter] {
            dt = arr
        } else {
            dt = []
        }
    }
}
