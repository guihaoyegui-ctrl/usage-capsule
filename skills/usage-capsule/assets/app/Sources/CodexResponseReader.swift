import Foundation
import Darwin

// One reader per child process; framing and JSON work stay off the UI thread.
final class CodexResponseReader {
    struct Message {
        var closed = false
        var id:Int?
        var result:Data?
        var error:String?
        var method:String?
        var params:[String:Any] = [:]
    }
    private let queue = DispatchQueue(label:"usage-capsule.response-reader",qos:.userInitiated)
    private var buffer = Data()
    private var scannedUntil = 0
    private let deliver:(Message)->Void
    init(deliver:@escaping (Message)->Void) { self.deliver = deliver }
    func append(_ bytes:Data) { queue.async { self.consume(bytes) } }
    func finish() { queue.async { self.deliver(Message(closed:true)) } }
    private func consume(_ bytes:Data) {
        buffer.append(bytes)
        var consumed = 0
        while scannedUntil < buffer.count {
            let end:Int? = buffer.withUnsafeBytes { raw in
                guard let base = raw.baseAddress,
                      let newline = memchr(base.advanced(by:scannedUntil),10,raw.count-scannedUntil) else { return nil }
                return base.distance(to:UnsafeRawPointer(newline))
            }
            guard let end else { scannedUntil = buffer.count; break }
            let line = buffer.subdata(in:consumed..<end)
            consumed = end+1; scannedUntil = consumed
            guard let json = try? JSONSerialization.jsonObject(with:line) as? [String:Any] else { continue }
            if let method = json["method"] as? String {
                deliver(Message(method:method,params:json["params"] as? [String:Any] ?? [:]))
            } else if let id = json["id"] as? Int {
                if let error = json["error"] as? [String:Any] {
                    deliver(Message(id:id,error:error["message"] as? String ?? ""))
                } else if let result = json["result"], let data = try? JSONSerialization.data(withJSONObject:result,options:.fragmentsAllowed) {
                    deliver(Message(id:id,result:data))
                } else { deliver(Message(id:id)) }
            }
        }
        if consumed > 0 {
            buffer = Data(buffer.dropFirst(consumed))
            scannedUntil -= consumed
        }
    }
}
