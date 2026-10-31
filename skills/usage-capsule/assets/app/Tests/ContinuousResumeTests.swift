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
        let choice = ResumeThreadChoice(id:"thread-a",title:"A",folder:"")
        for (original,target) in [("once",ResumeMode.continuous),("continuous",ResumeMode.once)] {
            let (m,r,l,h,_,_) = fixture(mode:original)
            m.limits = try! JSONDecoder().decode(LimitsResponse.self,from:await r.request("account/rateLimits/read",params:[:]))
            m.toggleAutoResume(choice,mode:target)
            check(l.selections.count == 1 && l.selections.first?.effectiveMode == target && m.isAutoResumeSelected("thread-a"),"checking a task in the other mode replaces its authorization instead of removing it: \(original)")
            check(h.authorizationState("continuous-auth") == "revoked","mode replacement revokes the old authorization: \(original)")
            await Task.yield()
            check(l.selections.first?.effectiveMode == target && m.isAutoResumeSelected("thread-a"),"mode replacement remains authorized after pending cancellation tasks run: \(original)")
        }
        let (filtered,filteredRPC,filteredSelection,_,_,_) = fixture(mode:"once")
        filtered.limits = try! JSONDecoder().decode(LimitsResponse.self,from:await filteredRPC.request("account/rateLimits/read",params:[:]))
        let initialID = filteredSelection.selections[0].authorizationID
        check(filtered.isAutoResumeSelected("thread-a",mode:.once) && !filtered.isAutoResumeSelected("thread-a",mode:.continuous),"a once-only task is checked in once mode and unchecked in continuous mode")
        filtered.setAutoResumeSelected(choice,selected:false,mode:.continuous)
        check(filteredSelection.selections[0].authorizationID == initialID && filtered.isAutoResumeSelected("thread-a",mode:.once),"unchecking an unrelated mode cannot cancel the existing authorization")
        filtered.setAutoResumeSelected(choice,selected:true,mode:.continuous)
        let changedID = filteredSelection.selections[0].authorizationID
        filtered.setAutoResumeSelected(choice,selected:true,mode:.continuous)
        check(filteredSelection.selections.count == 1 && filteredSelection.selections[0].authorizationID == changedID && !filtered.isAutoResumeSelected("thread-a",mode:.once) && filtered.isAutoResumeSelected("thread-a",mode:.continuous),"explicit mode change has one stable continuous consent and removes the once check")
        filtered.setAutoResumeSelected(choice,selected:false,mode:.continuous)
        filtered.setAutoResumeSelected(choice,selected:true,mode:.once)
        try? await Task.sleep(nanoseconds:20_000_000)
        check(filtered.isAutoResumeSelected("thread-a",mode:.once),"deferred cancellation cannot revoke a newly reselected task")
        let (inFlight,flightRPC,flightSelection,_,_,_) = fixture(mode:"once")
        await inFlight.refresh()
        let queuedID = flightSelection.selections[0].authorizationID
        inFlight.setAutoResumeSelected(choice,selected:true,mode:.continuous)
        check(flightRPC.addCount == 1 && flightSelection.selections[0].authorizationID == queuedID && flightSelection.selections[0].effectiveMode == .once && inFlight.resumeNotice != nil,"switching mode while a handoff is unresolved preserves its consent and explains why it is blocked")
        let (switchedMode,switchedRPC,switchedSelection,switchedHandoffs,_,_) = fixture(mode:"once")
        switchedRPC.accountID = "account-b"
        switchedMode.limits = try! JSONDecoder().decode(LimitsResponse.self,from:await switchedRPC.request("account/rateLimits/read",params:[:]))
        switchedMode.setAutoResumeSelected(choice,selected:true,mode:.continuous)
        check(switchedSelection.selections.count == 1 && switchedSelection.selections[0].accountID == "account-b" && switchedMode.isAutoResumeSelected("thread-a",mode:.continuous) && switchedHandoffs.authorizationState("continuous-auth") == "revoked","explicit mode selection after an account switch replaces the old-account consent")
        print("Continuous resume: \(failures) failures")
        return failures
    }
}
