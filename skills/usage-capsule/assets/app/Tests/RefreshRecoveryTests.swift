import Foundation

@MainActor final class RecoveryTestConnection: CodexServing {
    var notification: ((String, [String: Any]) -> Void)?
    var responses: [Result<Data, Error>]
    var reads = 0
    var disconnects = 0
    init(_ responses: [Result<Data, Error>]) { self.responses = responses }
    func connect() async throws {}
    func disconnect() { disconnects += 1 }
    func request(_ method: String, params: [String: Any]) async throws -> Data {
        switch method {
        case "account/rateLimits/read":
            reads += 1
            return try responses.removeFirst().get()
        case "account/usage/read":
            return Data("{\"dailyUsageBuckets\":[]}".utf8)
        default:
            throw ServiceError(message:"Unexpected request: \(method)")
        }
    }
}

@MainActor enum RefreshRecoveryTests {
    static func run() async -> Int {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            if condition { print("PASS: \(name)") }
            else { print("FAIL: \(name)"); failures += 1 }
        }
        let old = Data("""
        {"accountId":"same-account","rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300},"secondary":null},"rateLimitResetCredits":{"availableCount":1}}
        """.utf8)
        let renewed = Data("""
        {"accountId":"same-account","rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":300},"secondary":{"usedPercent":8,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":1}}
        """.utf8)
        let expired = ServiceError(message:"GET rate limits failed: 401 Unauthorized; token_expired")
        func fixture(_ responses: [Result<Data, Error>]) -> (QuotaStore, RecoveryTestConnection) {
            let connection = RecoveryTestConnection(responses)
            let suite = UserDefaults(suiteName:"usage-capsule.refresh-test.\(UUID().uuidString)")!
            let store = QuotaStore(connection:connection,redemption:RedemptionLedger(defaults:suite),confirmReset:{ _ in false })
            store.limits = try! JSONDecoder().decode(LimitsResponse.self,from:old)
            store.lastSync = Date(timeIntervalSince1970:1)
            return (store,connection)
        }

        let (recovered, recoverConnection) = fixture([.failure(expired),.success(renewed)])
        await recovered.refresh()
        check(recovered.primary?.remaining == 88 && recovered.secondary?.remaining == 92 && recovered.error == nil,
              "expired background connection is replaced and renewed Plus quotas appear")
        check(recoverConnection.reads == 2 && recoverConnection.disconnects == 1,
              "expired token triggers one bounded new-connection read")

        let (blocked, blockedConnection) = fixture([.failure(expired),.failure(expired)])
        await blocked.refresh()
        check(blocked.primary?.remaining == nil && blocked.secondary?.remaining == nil && blocked.lastSync == nil,
              "renewal failure hides misleading stale quota numbers")
        check(blocked.error != nil && blockedConnection.reads == 2,
              "renewal failure asks for recovery without an unbounded retry loop")

        let (offline, offlineConnection) = fixture([.failure(ServiceError(message:"Network temporarily unavailable"))])
        await offline.refresh()
        check(offline.primary?.remaining == 99 && offline.error != nil && offlineConnection.reads == 1,
              "temporary network failure retains the last known reading with an error")
        print("Refresh recovery: \(failures) failures")
        return failures
    }
}
