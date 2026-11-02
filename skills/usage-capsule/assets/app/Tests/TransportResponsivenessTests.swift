import Foundation

@main struct TransportResponsivenessTests {
    @MainActor static func main() async {
        var failures = 0
        func check(_ value:Bool,_ name:String) {
            if value { print("PASS: \(name)") } else { print("FAIL: \(name)"); failures += 1 }
        }
        guard let fixture = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"], CodexConnection.executable() == fixture else {
            print("FAIL: transport tests require their isolated executable fixture"); exit(1)
        }
        let connection = CodexConnection()
        do {
            try await connection.connect()
            var maximumGap:TimeInterval = 0
            let heartbeat = Task { @MainActor in
                var previous = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds:5_000_000)
                    let now = Date(); maximumGap = max(maximumGap,now.timeIntervalSince(previous)); previous = now
                }
            }
            await Task.yield()
            let started = Date()
            let result = try await connection.request("test/large")
            // Let the queued heartbeat observe the last parser interval.
            try? await Task.sleep(nanoseconds:10_000_000)
            heartbeat.cancel()
            let data = try JSONSerialization.jsonObject(with:result) as? [String:Any]
            check((data?["payload"] as? String)?.count == 2*1024*1024,"fragmented multi-megabyte responses preserve their full payload")
            check(maximumGap < 0.15,"fragmented response parsing leaves the main actor responsive (max gap \(String(format:"%.3f",maximumGap))s)")
            check(Date().timeIntervalSince(started) < 4,"fragmented response handling does not repeatedly rescan the accumulated prefix")
            connection.disconnect()
            async let first:Void = connection.connect()
            async let second:Void = connection.connect()
            do {
                _ = try await (first,second)
                let ping = try JSONSerialization.jsonObject(with:await connection.request("test/ping")) as? [String:Any]
                check(ping?["initializations"] as? Int == 1,"simultaneous readers share one connection handshake")
            } catch { check(false,"simultaneous readers share one connection handshake: \(error.localizedDescription)") }
            do {
                let final = try await connection.request("test/final")
                let value = try JSONSerialization.jsonObject(with:final) as? [String:Any]
                check((value?["payload"] as? String)?.count == 2*1024*1024,"a valid final response is delivered before child-process EOF")
            } catch { check(false,"a valid final response is delivered before child-process EOF: \(error.localizedDescription)") }
        } catch { check(false,"transport responds without losing its request: \(error.localizedDescription)") }
        connection.disconnect()
        print("Transport responsiveness: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
