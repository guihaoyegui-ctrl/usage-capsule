import Foundation

@MainActor enum ContinuousResumeTests {
    static func run() async -> Int {
        var failures = 0
        func check(_ value:Bool,_ label:String) {
            if value { print("PASS: \(label)") } else { print("FAIL: \(label)"); failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("continuous-resume-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        var suites:[String] = []
        defer { for suite in suites { UserDefaults.standard.removePersistentDomain(forName:suite) } }
        func fixture(mode:String = "continuous") -> (QuotaStore,NativeQueueTestConnection,ResumeLedger,HandoffLedger,UserDefaults,URL) {
            let suite = "continuous-tests-\(UUID().uuidString)"; suites.append(suite)
            let prefs = UserDefaults(suiteName:suite)!
            let raw:[[String:Any]] = [["threadID":"thread-a","accountID":"account-a","title":"A","selectedAt":1000,"authorizationVersion":2,"authorizationID":"continuous-auth","waitingTurnID":"failed-1","mode":mode]]
            prefs.set(try! JSONSerialization.data(withJSONObject:raw),forKey:"selectedAutoResume.v1")
            let file = root.appendingPathComponent("\(UUID().uuidString).json")
            let controls:[String:Any] = ["paused":false,"reserves":[:],"authorizations":["continuous-auth":["threadID":"thread-a","accountID":"account-a","state":"active","mode":mode]]]
            try! JSONSerialization.data(withJSONObject:controls).write(to:file.appendingPathExtension("controls.json"))
            let ledger = ResumeLedger(defaults:prefs), handoffs = HandoffLedger(fileURL:file), rpc = NativeQueueTestConnection()
            let store = QuotaStore(connection:rpc,resumeLedger:ledger,handoffLedger:handoffs,wakeThread:{_ in true},confirmReset:{_ in false})
            return (store,rpc,ledger,handoffs,prefs,file)
        }
        func consume(_ rpc:NativeQueueTestConnection,_ record:HandoffRecord,status:String = "failed",code:String = "usageLimitExceeded",ended:Bool = true) {
            rpc.queue = []
            rpc.history = [["turnId":"failed-2","item":["type":"userMessage","clientId":record.id]]]
            if status == "completed" { rpc.history.append(["turnId":"failed-2","item":["type":"agentMessage","phase":"final_answer","text":"Waiting for the owner."]]) }
            var turn:[String:Any] = ["id":"failed-2","status":status]
            if ended { turn["completedAt"] = 2100 }
            if status == "failed" { turn["error"] = ["message":"stopped","codexErrorInfo":code] }
            rpc.turns = [turn]
        }
        let (store,rpc,selection,handoffs,prefs,file) = fixture()
        await store.refresh()
        check(rpc.addCount == 1,"continuous mode dispatches its first observed quota failure")
        let first = handoffs.records[0]
        consume(rpc,first); rpc.primaryUsed = 100
        await store.refresh()
        check(!handoffs.hasDispatchBlocker,"a confirmed terminal quota failure releases the continuous serial barrier")
        check(selection.selections[0].waitingTurnID == "failed-2","continuous mode arms a later observed exhaustion without another owner authorization")
        rpc.primaryUsed = 0
        let restarted = QuotaStore(connection:rpc,resumeLedger:ResumeLedger(defaults:prefs),handoffLedger:HandoffLedger(fileURL:file),wakeThread:{_ in true},confirmReset:{_ in false})
        await restarted.refresh()
        check(rpc.addCount == 2 && restarted.handoffLedger.records.count == 2,"continuous authorization recovers a second distinct failure after restart")
        check(Set(restarted.handoffLedger.records.map(\.clientMessageID)).count == 2,"distinct quota failures keep distinct durable client IDs")
        await restarted.refresh()
        check(rpc.addCount == 2,"repeated polling cannot replay a continuous-mode failed turn")
        await restarted.cancelResumeSelection("thread-a")
        check(!restarted.isAutoResumeSelected("thread-a") && restarted.handoffLedger.authorizationState("continuous-auth") == "revoked","cancelling continuous monitoring revokes durable authorization")
        for status in ["completed","interrupted","other-error","missing-end"] {
            let (s,r,_,h,_,_) = fixture()
            await s.refresh()
            consume(r,h.records[0],status:status == "other-error" || status == "missing-end" ? "failed" : status,code:status == "other-error" ? "internalServerError" : "usageLimitExceeded",ended:status != "missing-end")
            r.primaryUsed = 100; await s.refresh()
            r.primaryUsed = 0; await s.refresh()
            check(r.addCount == 1,"continuous monitoring never restarts \(status) as a new recovery")
            if status != "completed" { check(h.hasDispatchBlocker,"\(status) remains blocked for inspection") }
        }
        let (once,onceRPC,_,onceHandoffs,_,_) = fixture(mode:"once")
        await once.refresh(); consume(onceRPC,onceHandoffs.records[0]); onceRPC.primaryUsed = 100
        await once.refresh(); onceRPC.primaryUsed = 0; await once.refresh()
        check(onceRPC.addCount == 1,"once mode still cannot recover a second quota failure")
        let (stale,staleRPC,_,staleHandoffs,_,staleFile) = fixture()
        _ = HandoffLedger(fileURL:staleFile).revokeAuthorizations(threadID:"thread-a")
        await stale.refresh()
        check(staleRPC.addCount == 0 && staleHandoffs.authorizationState("continuous-auth") == "revoked","a stale widget cannot revive cancelled continuous consent")
        print("Continuous resume: \(failures) failures")
        return failures
    }
}
