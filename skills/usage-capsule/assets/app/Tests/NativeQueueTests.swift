import Foundation

@MainActor final class NativeQueueTestConnection: CodexServing {
    var notification: ((String,[String:Any])->Void)?
    var methods: [String] = []
    var queue: [[String:Any]] = []
    var history: [[String:Any]] = []
    var loaded: [String] = []
    var addCount = 0
    var failAfterAccept = false
    var failBeforeAccept = false
    var failDelete = false
    var turnReads = 0
    var changedTurn = false
    var onAdd: ((String)->Void)?
    var accountID = "account-a"
    var primaryUsed = 32
    var latestID = "failed-1"
    func connect() async throws {}
    func disconnect() {}
    func request(_ method:String,params:[String:Any]) async throws -> Data {
        methods.append(method)
        func data(_ json:[String:Any]) -> Data { try! JSONSerialization.data(withJSONObject:json) }
        switch method {
        case "account/rateLimits/read": return Data("{\"accountId\":\"\(accountID)\",\"rateLimits\":{\"primary\":{\"usedPercent\":\(primaryUsed),\"windowDurationMins\":300},\"secondary\":{\"usedPercent\":58,\"windowDurationMins\":10080}}}".utf8)
        case "account/usage/read": return Data("{\"dailyUsageBuckets\":[]}".utf8)
        case "thread/turns/list":
            turnReads += 1
            let turnID = changedTurn && turnReads > 1 ? "new-turn" : latestID
            return Data("{\"data\":[{\"id\":\"\(turnID)\",\"status\":\"failed\",\"error\":{\"message\":\"limit\",\"codexErrorInfo\":\"usageLimitExceeded\"}}]}".utf8)
        case "thread/loaded/list": return data(["data":loaded,"nextCursor":NSNull()])
        case "thread/queue/list": return data(["data":queue,"nextCursor":NSNull()])
        case "thread/items/list": return data(["data":history,"nextCursor":NSNull()])
        case "thread/queue/add":
            addCount += 1
            onAdd?(params["clientUserMessageId"] as! String)
            if failBeforeAccept { throw ServiceError(message:"delivery unknown") }
            let entry:[String:Any] = ["id":"queue-1","clientUserMessageId":params["clientUserMessageId"]!,"input":params["input"]!]
            queue.append(entry)
            if failAfterAccept { throw ServiceError(message:"delivery unknown") }
            return data(["queuedSubmission":entry])
        case "thread/queue/delete":
            if failDelete { throw ServiceError(message:"delete unknown") }
            let old = queue.count
            queue.removeAll { $0["id"] as? String == params["queuedSubmissionId"] as? String }
            return data(["deleted":queue.count < old])
        default: throw ServiceError(message:"Unexpected request: \(method)")
        }
    }
}

@MainActor enum NativeQueueTests {
    static func run() async -> Int {
        var failures = 0
        func check(_ condition:Bool,_ name:String) {
            if condition { print("PASS: \(name)") } else { print("FAIL: \(name)"); failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capsule-native-queue-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        final class WakeCounter { var count = 0 }
        func fixture() -> (QuotaStore,NativeQueueTestConnection,ResumeLedger,HandoffLedger,WakeCounter) {
            let rpc = NativeQueueTestConnection()
            let prefs = UserDefaults(suiteName:"capsule-native-\(UUID().uuidString)")!
            let selection = ResumeLedger(defaults:prefs)
            selection.select(threadID:"thread-a",accountID:"account-a",title:"Project A")
            selection.waitForReset(threadID:"thread-a",turnID:"failed-1")
            let handoffs = HandoffLedger(fileURL:root.appendingPathComponent("\(UUID().uuidString).json"))
            let wake = WakeCounter()
            let store = QuotaStore(connection:rpc,resumeLedger:selection,handoffLedger:handoffs,wakeThread:{ _ in wake.count += 1; return true },confirmReset:{ _ in false })
            return (store,rpc,selection,handoffs,wake)
        }
        let (store,rpc,_,ledger,wake) = fixture()
        await store.refresh()
        store.lastSync = Date(timeIntervalSince1970:1234)
        check(store.quotaObservation()?.observedAt == 1234,"reset observations use the quota sample time rather than the later usage-read time")
        check(rpc.addCount == 1 && ledger.visibleRecords.first?.state == .queued,"recovered selected task is handed to the native queue")
        check(!rpc.methods.contains("thread/resume") && !rpc.methods.contains("turn/start"),"capsule never starts a second independent execution")
        check(wake.count == 1,"native desktop is woken after queue acceptance")
        await store.refresh()
        check(rpc.addCount == 1,"periodic refresh does not enqueue the same failure twice")
        await store.cancelResumeSelection("thread-a")
        check(rpc.queue.isEmpty && ledger.visibleRecords.first?.state == .cancelled,"cancelling a queued continuation removes it from the native queue")

        let (uncertain,uncertainRPC,_,uncertainLedger,uncertainWake) = fixture()
        uncertainRPC.failAfterAccept = true
        await uncertain.refresh()
        check(uncertainRPC.addCount == 1 && uncertainLedger.hasUnresolved,"uncertain submission persists and blocks further submission")
        await uncertain.refresh()
        check(uncertainRPC.addCount == 1 && uncertainLedger.visibleRecords.first?.state == .queued && uncertainWake.count > 0,"accepted timed-out submission is reconciled using its stable client ID")

        let (missing,missingRPC,_,missingLedger,_) = fixture()
        missingRPC.failBeforeAccept = true
        await missing.refresh(); await missing.refresh()
        check(missingRPC.addCount == 1 && missingLedger.hasUnresolved,"unconfirmed delivery is not silently retried")

        let (busy,busyRPC,_,_,_) = fixture()
        busyRPC.loaded = ["thread-a"]
        await busy.refresh()
        check(busyRPC.addCount == 0,"a locally loaded thread cannot be enqueued from the capsule")

        let (changed,changedRPC,_,_,_) = fixture()
        changedRPC.changedTurn = true
        await changed.refresh()
        check(changedRPC.addCount == 0,"a newer turn before handoff invalidates the queued continuation")

        let (occupied,occupiedRPC,_,_,occupiedWake) = fixture()
        occupiedRPC.queue = [["id":"owner-message","clientUserMessageId":"other","input":[]]]
        await occupied.refresh()
        check(occupiedRPC.addCount == 0 && occupiedWake.count == 0,"existing user queue is neither modified nor woken by the capsule")

        let (cannotCancel,cancelRPC,selection,cancelLedger,_) = fixture()
        await cannotCancel.refresh()
        cancelRPC.failDelete = true
        await cannotCancel.cancelResumeSelection("thread-a")
        check(selection.selections.isEmpty && cancelLedger.hasUnresolved && !cancelLedger.visibleRecords.isEmpty,"failed cancellation keeps the pending handoff visible and blocks new dispatch")

        let (inFlight,inFlightRPC,_,inFlightLedger,_) = fixture()
        inFlightRPC.onAdd = { id in inFlight.clearHandoff(id,acknowledge:true) }
        await inFlight.refresh()
        check(inFlightLedger.hasUnresolved && inFlightLedger.visibleRecords.count == 1,"an in-flight submission cannot be acknowledged or hidden")

        let (cancelDuring,cancelDuringRPC,cancelDuringSelection,cancelDuringLedger,_) = fixture()
        cancelDuringRPC.onAdd = { _ in cancelDuring.removeAutoResume("thread-a") }
        await cancelDuring.refresh()
        check(cancelDuringSelection.selections.isEmpty && cancelDuringRPC.queue.isEmpty && cancelDuringLedger.visibleRecords.first?.state == .cancelled,"deselecting while submission is in flight removes the accepted queued message")

        let (delivered,deliveredRPC,_,deliveredLedger,_) = fixture()
        await delivered.refresh()
        let deliveredID = deliveredLedger.visibleRecords.first!.clientMessageID
        deliveredRPC.queue = []
        deliveredRPC.history = [["turnId":"next","item":["type":"userMessage","id":"item","clientId":deliveredID,"content":[]]]]
        await delivered.refresh()
        check(deliveredLedger.visibleRecords.first?.state == .handedOff && !deliveredLedger.hasUnresolved,"native history confirms a handoff after the queue drains")
        let (stale,staleRPC,_,staleLedger,staleWake) = fixture()
        await stale.refresh()
        staleRPC.latestID = "manual-new-turn"
        await stale.refresh()
        check(staleWake.count == 1 && staleRPC.queue.isEmpty && staleLedger.visibleRecords.first?.state == .cancelled,"a manual new turn cancels the stale queued continuation before another wake")
        let (zero,zeroRPC,_,zeroLedger,zeroWake) = fixture()
        await zero.refresh()
        zeroRPC.primaryUsed = 100
        await zero.refresh()
        check(zeroWake.count == 1 && zeroLedger.visibleRecords.first?.state == .queued,"an exhausted quota prevents another wake while keeping the queue visible")
        let (switched,switchRPC,_,switchLedger,_) = fixture()
        await switched.refresh()
        switchRPC.accountID = "account-b"
        await switched.refresh()
        await switched.cancelResumeSelection("thread-a")
        check(switchRPC.queue.isEmpty && switchLedger.visibleRecords.first?.state == .cancelled,"queued message can be cancelled after switching accounts")

        let clientID = ledger.visibleRecords.first?.clientMessageID ?? ""
        check(!clientID.isEmpty,"handoffs retain a client message identifier for reconciliation")
        print("Native queue: \(failures) failures")
        return failures
    }
}
