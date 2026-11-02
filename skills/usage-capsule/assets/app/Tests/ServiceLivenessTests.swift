import Foundation

@MainActor private final class SlowHistoryConnection: CodexServing {
    var notification: ((String,[String:Any])->Void)?
    let base = NativeQueueTestConnection()
    var holdHistory = true
    var blocked:CheckedContinuation<Void,Never>?
    var quotaReads = 0
    func connect() async throws {}
    func disconnect() { release() }
    func release() { holdHistory = false; blocked?.resume(); blocked = nil }
    func request(_ method:String,params:[String:Any]) async throws -> Data {
        if method == "account/rateLimits/read" { quotaReads += 1 }
        if method == "thread/turns/list", holdHistory { await withCheckedContinuation { blocked = $0 } }
        if method == "thread/list" { return Data("{\"data\":[{\"id\":\"task-choice\",\"name\":\"Available task\",\"cwd\":\"/tmp\"}],\"nextCursor\":null}".utf8) }
        return try await base.request(method,params:params)
    }
}

@MainActor enum ServiceLivenessTests {
    static func run() async -> Int {
        var failures = 0
        func check(_ value:Bool,_ name:String) {
            if value { print("PASS: \(name)") } else { print("FAIL: \(name)"); failures += 1 }
        }
        let suite = "capsule-liveness-\(UUID().uuidString)", defaults = UserDefaults(suiteName:suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:root) }
        let selection = ResumeLedger(defaults:defaults)
        selection.select(threadID:"thread-a",accountID:"account-a",title:"A",mode:.continuous)
        let handoffs = HandoffLedger(fileURL:root.appendingPathComponent("handoffs.json"))
        _ = handoffs.authorize(id:selection.selections[0].authorizationID!,threadID:"thread-a",accountID:"account-a",mode:.continuous)
        let rpc = SlowHistoryConnection()
        let store = QuotaStore(connection:rpc,resumeLedger:selection,handoffLedger:handoffs,wakeThread:{_ in false},confirmReset:{_ in false})
        let refresh = Task { await store.refresh() }
        for _ in 0..<100 {
            if rpc.blocked != nil { break }
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        check(rpc.blocked != nil && store.limits != nil && !store.refreshing,"slow history does not keep the quota-refresh spinner or refresh lock active")
        await store.loadRecentThreads()
        check(store.recentThreads.first?.id == "task-choice" && !store.loadingThreads,"task choices load while unrelated history is stalled")
        await store.refresh()
        check(rpc.quotaReads == 2,"manual quota refresh still works while a history scan is pending")
        rpc.release(); await refresh.value
        selection.remove(threadID:"thread-a")
        _ = handoffs.authorize(id:"cached-quota",threadID:"thread-a",accountID:"account-a",mode:.continuous)
        let quotaRecord = handoffs.begin(threadID:"thread-a",accountID:"account-a",title:"A",failedTurnID:"another-failure",authorizationID:"cached-quota")!
        _ = handoffs.markHandedOff(clientMessageID:quotaRecord.id); _ = handoffs.finishSubmission(clientMessageID:quotaRecord.id)
        _ = handoffs.updateProgress(clientMessageID:quotaRecord.id,turnID:"quota-ended",status:"failed",excerpt:nil,endedAt:2100,quotaFailureConfirmed:true)
        rpc.base.methods = []
        await store.refresh()
        check(!rpc.base.methods.contains("thread/items/list") && !store.resumeTrackingUnavailable.contains(quotaRecord.id),"confirmed terminal quota history is not downloaded on every refresh")
        check(rpc.base.addCount == 0,"liveness checks never dispatch a continuation")
        print("Service liveness: \(failures) failures")
        return failures
    }
}
