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
    var latestCompletedAt: Double = 2000
    var turns: [[String:Any]]?
    var onMethod: ((String)->Void)?
    var quotaPayload: Data?
    func connect() async throws {}
    func disconnect() {}
    func request(_ method:String,params:[String:Any]) async throws -> Data {
        methods.append(method)
        onMethod?(method)
        func data(_ json:[String:Any]) -> Data { try! JSONSerialization.data(withJSONObject:json) }
        switch method {
        case "account/rateLimits/read": return quotaPayload ?? Data("{\"accountId\":\"\(accountID)\",\"ordinaryUsageAllowed\":true,\"rateLimits\":{\"planType\":\"plus\",\"primary\":{\"usedPercent\":\(primaryUsed),\"windowDurationMins\":300},\"secondary\":{\"usedPercent\":58,\"windowDurationMins\":10080}}}".utf8)
        case "account/usage/read": return Data("{\"dailyUsageBuckets\":[]}".utf8)
        case "thread/turns/list":
            if let turns { return data(["data":turns,"nextCursor":NSNull()]) }
            turnReads += 1
            let turnID = changedTurn && turnReads > 1 ? "new-turn" : latestID
            return data(["data":[["id":turnID,"status":"failed","completedAt":latestCompletedAt,"error":["message":"limit","codexErrorInfo":"usageLimitExceeded"]]]])
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
            selection.select(threadID:"thread-a",accountID:"account-a",title:"Project A",selectedAt:1000)
            selection.waitForReset(threadID:"thread-a",turnID:"failed-1")
            let handoffs = HandoffLedger(fileURL:root.appendingPathComponent("\(UUID().uuidString).json"))
            _ = handoffs.authorize(id:selection.selections[0].authorizationID!,threadID:"thread-a",accountID:"account-a")
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
        let (old,oldRPC,_,_,_) = fixture()
        oldRPC.latestCompletedAt = 999
        oldRPC.primaryUsed = 100
        await old.refresh()
        oldRPC.primaryUsed = 32
        await old.refresh()
        check(oldRPC.addCount == 0,"a quota failure before authorization is never revived")

        let (paused,pausedRPC,_,pausedLedger,pausedWake) = fixture()
        _ = pausedLedger.setPaused(true)
        await paused.refresh()
        check(pausedRPC.addCount == 0 && pausedWake.count == 0,"global pause prevents new queue delivery")
        _ = pausedLedger.setPaused(false)
        pausedRPC.onMethod = { method in if method == "thread/loaded/list" { _ = pausedLedger.setPaused(true) } }
        await paused.refresh()
        check(pausedRPC.addCount == 0,"a pause during preflight is rechecked before delivery")

        let (reserved,reserveRPC,_,reserveLedger,_) = fixture()
        _ = reserveLedger.setReserve(accountID:"account-a",primary:70,weekly:0)
        await reserved.refresh()
        check(reserveRPC.addCount == 0,"quota reserve blocks a new dispatch below its threshold")

        let (serial,serialRPC,serialSelections,serialLedger,_) = fixture()
        serialSelections.select(threadID:"thread-b",accountID:"account-a",title:"B",selectedAt:1000)
        serialSelections.waitForReset(threadID:"thread-b",turnID:"failed-1")
        _ = serialLedger.authorize(id:serialSelections.selections.last!.authorizationID!,threadID:"thread-b",accountID:"account-a")
        await serial.refresh()
        let serialID = serialLedger.visibleRecords.first!.id
        serialRPC.queue = []
        serialRPC.history = [["turnId":"actual-round","item":["type":"userMessage","clientId":serialID]]]
        serialRPC.turns = [["id":"actual-round","status":"inProgress","items":[]]]
        await serial.refresh()
        check(serialRPC.addCount == 1 && serialLedger.hasDispatchBlocker,"a running correlated round blocks the next authorized task")
        check(serialLedger.visibleRecords.first?.turnID == "actual-round" && serialLedger.visibleRecords.first?.turnStatus == "inProgress","execution is linked to our exact client message")
        serialRPC.turns = [["id":"actual-round","status":"completed","completedAt":3000,"items":[]]]
        await serial.refresh()
        check(serialRPC.addCount == 1,"missing final reply does not release the serial barrier")
        check(serial.stage(for:serialLedger.visibleRecords.first!) == .unknown,"inconclusive completion cannot keep showing a stale running status")
        serialRPC.history.append(["turnId":"unrelated","item":["type":"agentMessage","phase":"final_answer","text":"Unrelated final"]])
        await serial.refresh()
        check(serialRPC.addCount == 1,"another round's final answer cannot complete our handoff")
        serialRPC.history.append(["turnId":"actual-round","item":["type":"agentMessage","phase":"final_answer","text":"Expected result"]])
        await serial.refresh()
        check(serialLedger.visibleRecords.first?.turnStatus == "completed" && serialLedger.visibleRecords.first?.excerpt == "Expected result","a matching completed round produces a local result card")
        check(serialRPC.addCount == 1,"a changed target round cannot automatically start the next task")

        let (pauseQueue,pauseQueueRPC,_,pauseQueueLedger,pauseQueueWake) = fixture()
        await pauseQueue.refresh()
        _ = pauseQueueLedger.setPaused(true)
        await pauseQueue.refresh()
        check(pauseQueueRPC.queue.count == 1 && pauseQueueWake.count == 1,"pausing keeps accepted queue visible without another wake")

        let (oneShot,oneShotRPC,_,oneShotLedger,_) = fixture()
        await oneShot.refresh()
        let oneID = oneShotLedger.visibleRecords.first!.id
        oneShotRPC.queue = []
        oneShotRPC.history = [["turnId":"continued","item":["type":"userMessage","clientId":oneID]]]
        oneShotRPC.turns = [["id":"continued","status":"failed","completedAt":3000,"error":["codexErrorInfo":"usageLimitExceeded"],"items":[]]]
        oneShotRPC.primaryUsed = 100
        await oneShot.refresh()
        oneShotRPC.primaryUsed = 32
        await oneShot.refresh()
        check(oneShotRPC.addCount == 1,"a second quota failure requires a new explicit authorization")
        let (notifying,notifyRPC,_,notifyLedger,_) = fixture()
        var notices:[String] = []
        notifying.resumeNotificationsEnabled = true
        notifying.deliverResumeNotification = { notices.append($0.id) }
        await notifying.refresh()
        let notifyID = notifyLedger.visibleRecords.first!.id
        notifyRPC.queue = []
        notifyRPC.history = [["turnId":"notified-round","item":["type":"userMessage","clientId":notifyID]], ["turnId":"notified-round","item":["type":"agentMessage","phase":"final_answer","text":"Result"]]]
        notifyRPC.turns = [["id":"notified-round","status":"completed","completedAt":3000]]
        await notifying.refresh(); await notifying.refresh()
        check(notices == [notifyID],"repeated completion polls notify once without extra model generation")
        check(!notifyRPC.methods.contains("turn/start") && !notifyRPC.methods.contains("account/rateLimitResetCredit/consume"),"result cards and notifications never invoke a model or consume a card")

        let (priority,priorityRPC,prioritySelections,priorityLedger,_) = fixture()
        prioritySelections.select(threadID:"thread-b",accountID:"account-a",title:"B",selectedAt:1000)
        prioritySelections.waitForReset(threadID:"thread-b",turnID:"failed-1")
        _ = priorityLedger.authorize(id:prioritySelections.selections.last!.authorizationID!,threadID:"thread-b",accountID:"account-a")
        prioritySelections.move(threadID:"thread-b",offset:-1)
        var priorityThread:String?
        priorityRPC.onMethod = { _ in }
        priority.deliverResumeNotification = { _ in }
        await priority.refresh()
        priorityThread = priority.handoffLedger.visibleRecords.first?.threadID
        check(priorityThread == "thread-b","the owner's reordered priority controls the first handoff")
        let (wakeCancelled,wakeCancelRPC,wakeSelection,_,wakeCancelCounter) = fixture()
        await wakeCancelled.refresh()
        wakeCancelRPC.onMethod = { method in
            if method == "thread/turns/list" { wakeSelection.remove(threadID:"thread-a") }
        }
        await wakeCancelled.refresh()
        check(wakeCancelCounter.count == 1,"cancellation during awaited turn read cannot wake an accepted queue again")
        let (wakeSwitched,wakeSwitchRPC,_,_,wakeSwitchCounter) = fixture()
        await wakeSwitched.refresh()
        wakeSwitchRPC.onMethod = { method in
            if method == "thread/turns/list" {
                wakeSwitched.limits = try! JSONDecoder().decode(LimitsResponse.self,from:Data("{\"accountId\":\"other\",\"rateLimits\":{\"primary\":{\"usedPercent\":32,\"windowDurationMins\":300},\"secondary\":{\"usedPercent\":58,\"windowDurationMins\":10080}}}".utf8))
            }
        }
        await wakeSwitched.refresh()
        check(wakeSwitchCounter.count == 1,"account change during awaited turn read cannot wake the old task")
        let (owner,sharedRPC,_,sharedLedger,_) = fixture()
        await owner.refresh()
        let otherPrefs = UserDefaults(suiteName:"capsule-secondary-\(UUID().uuidString)")!
        let observer = QuotaStore(connection:sharedRPC,resumeLedger:ResumeLedger(defaults:otherPrefs),handoffLedger:sharedLedger,wakeThread:{ _ in false },confirmReset:{ _ in false })
        await observer.refresh()
        check(sharedRPC.queue.count == 1,"another bundle without local selection cannot cancel an owner's authorized shared queue")
        let (proStore,proRPC,_,_,_) = fixture()
        proRPC.quotaPayload = Data("{\"accountId\":\"account-a\",\"ordinaryUsageAllowed\":true,\"rateLimits\":{\"planType\":\"pro\",\"primary\":{\"usedPercent\":58,\"windowDurationMins\":10080}}}".utf8)
        await proStore.refresh()
        check(proStore.primary == nil && proStore.secondary?.remaining == 42,"Pro weekly-only primary slot is not shown as a daily quota")
        check(proRPC.addCount == 1,"Pro can recover a selected task with no five-hour quota")
        let (denied,deniedRPC,_,_,_) = fixture()
        deniedRPC.quotaPayload = Data("{\"accountId\":\"account-a\",\"ordinaryUsageAllowed\":false,\"rateLimits\":{\"planType\":\"plus\",\"primary\":{\"usedPercent\":32,\"windowDurationMins\":300},\"secondary\":{\"usedPercent\":58,\"windowDurationMins\":10080}}}".utf8)
        await denied.refresh()
        check(deniedRPC.addCount == 0,"backend denial blocks continuation despite positive displayed quotas")
        let (eventRace,eventRPC,_,_,_) = fixture()
        var eventSent = false
        eventRPC.onMethod = { method in
            if method == "thread/loaded/list" && !eventSent {
                eventSent = true
                eventRPC.accountID = "other-account"
                eventRace.handleAccountNotification("account/updated")
            }
        }
        await eventRace.refresh()
        for _ in 0..<30 { await Task.yield() }
        check(eventRPC.addCount == 0,"an account event during preflight invalidates the old allowance before enqueue")

        let (eventWake,wakeEventRPC,_,_,eventWakeCount) = fixture()
        await eventWake.refresh()
        var wakeEventSent = false
        wakeEventRPC.onMethod = { method in
            if method == "thread/turns/list" && !wakeEventSent {
                wakeEventSent = true
                wakeEventRPC.accountID = "other-account"
                eventWake.handleAccountNotification("account/updated")
            }
        }
        await eventWake.refresh()
        for _ in 0..<30 { await Task.yield() }
        check(eventWakeCount.count == 1,"an account event during queue reconciliation prevents another stale wake")

        let (configChange,configRPC,configSelection,_,_) = fixture()
        configSelection.remove(threadID:"thread-a")
        configSelection.select(threadID:"thread-a",accountID:"account-a",title:"A",selectedAt:1000)
        _ = configChange.handoffLedger.authorize(id:configSelection.selections[0].authorizationID!,threadID:"thread-a",accountID:"account-a")
        configRPC.latestCompletedAt = 1059
        func config(_ minutes:Int,_ reset:Double) -> LimitsResponse {
            try! JSONDecoder().decode(LimitsResponse.self,from:Data("{\"accountId\":\"account-a\",\"ordinaryUsageAllowed\":true,\"rateLimits\":{\"planType\":\"plus\",\"primary\":{\"usedPercent\":50,\"windowDurationMins\":\(minutes),\"resetsAt\":\(reset)},\"secondary\":{\"usedPercent\":50,\"windowDurationMins\":10080,\"resetsAt\":2000}}}".utf8))
        }
        configChange.limits = config(300,1060); configChange.lastSync = Date(timeIntervalSince1970:1010)
        await configChange.scanAutoResume()
        configChange.limits = config(60,4640); configChange.lastSync = Date(timeIntervalSince1970:1040)
        await configChange.scanAutoResume()
        configChange.limits = config(300,19060); configChange.lastSync = Date(timeIntervalSince1970:1070)
        await configChange.scanAutoResume()
        check(configRPC.addCount == 0,"an unsupported snapshot clears old evidence rather than bridging a changed configuration")
        let (notifyRace,notifyRaceRPC,_,notifyRaceLedger,_) = fixture()
        var staleNotices = 0
        notifyRace.resumeNotificationsEnabled = true
        notifyRace.deliverResumeNotification = { _ in staleNotices += 1 }
        await notifyRace.refresh()
        let notifyRaceID = notifyRaceLedger.visibleRecords.first!.id
        notifyRaceRPC.queue = []
        notifyRaceRPC.history = [["turnId":"old-account-round","item":["type":"userMessage","clientId":notifyRaceID]], ["turnId":"old-account-round","item":["type":"agentMessage","phase":"final_answer","text":"Done"]]]
        notifyRaceRPC.turns = [["id":"old-account-round","status":"completed","completedAt":3000]]
        var notifyEvent = false
        notifyRaceRPC.onMethod = { method in
            if method == "thread/turns/list" && !notifyEvent {
                notifyEvent = true
                notifyRaceRPC.accountID = "other-account"
                notifyRace.handleAccountNotification("account/updated")
            }
        }
        await notifyRace.refresh()
        for _ in 0..<30 { await Task.yield() }
        check(staleNotices == 0,"an invalidated account snapshot cannot send old-account result notifications")
        print("Native queue: \(failures) failures")
        return failures
    }
}
