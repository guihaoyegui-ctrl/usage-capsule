import Foundation

@main struct HandoffLedgerTests {
    @MainActor static func main() {
        let dir = URL(fileURLWithPath:NSTemporaryDirectory(),isDirectory:true).appendingPathComponent("usage-capsule.handoff-test.\(UUID().uuidString)",isDirectory:true)
        let file = dir.appendingPathComponent("handoffs.json")
        defer { try? FileManager.default.removeItem(at:dir) }
        var failures = 0
        func check(_ value:Bool,_ label:String) {
            if value { print("PASS: \(label)") } else { print("FAIL: \(label)"); failures += 1 }
        }
        let ledger = HandoffLedger(fileURL:file)
        check(!ledger.hasUnresolved && ledger.visibleRecords.isEmpty,"empty ledger starts without pending handoffs")
        check(ledger.begin(threadID:"",accountID:"account-a",title:"Project",failedTurnID:"turn-a") == nil,"invalid task ID cannot create a handoff")
        let first = ledger.begin(threadID:"thread-a",accountID:"account-a",title:"Project A",failedTurnID:"turn-a")!
        check(UUID(uuidString:first.clientMessageID) != nil && first.state == .submitting,"begin reserves a stable client UUID before submission")
        let restarted = HandoffLedger(fileURL:file)
        check(restarted.hasUnresolved && restarted.visibleRecords.first?.state == .submitting && restarted.visibleRecords.first?.clientMessageID == first.clientMessageID,"another instance preserves a live submission and remains blocked")
        check(ledger.begin(threadID:"thread-b",accountID:"account-a",title:"Project B",failedTurnID:"turn-b") == nil,"a pending submission blocks all further handoffs")
        check(!ledger.markQueued(clientMessageID:first.id,queueID:""),"empty queue identifier is rejected")
        check(ledger.markUncertain(clientMessageID:first.id),"ambiguous result is recorded as uncertain")
        let uncertain = HandoffLedger(fileURL:file)
        check(uncertain.hasUnresolved && uncertain.visibleRecords.first?.state == .uncertain,"uncertainty remains visible and blocks after relaunch")
        check(!uncertain.dismissResolved(clientMessageID:first.id),"an uncertain submission cannot be silently dismissed")
        check(!uncertain.acknowledgeUncertain(clientMessageID:first.id),"a live owner must finish submission before acknowledgement")
        check(ledger.finishSubmission(clientMessageID:first.id),"the owner releases its submission after the request finishes")
        check(uncertain.acknowledgeUncertain(clientMessageID:first.id),"explicit owner acknowledgement resolves an uncertain record")
        check(uncertain.dismissResolved(clientMessageID:first.id) && uncertain.visibleRecords.isEmpty,"acknowledged record can be hidden")
        check(uncertain.begin(threadID:"thread-a",accountID:"account-a",title:"Project A",failedTurnID:"turn-a") == nil,"hiding a record cannot replay the same failed turn")
        let second = uncertain.begin(threadID:"thread-b",accountID:"account-a",title:"Project B",failedTurnID:"turn-b")!
        check(uncertain.markQueued(clientMessageID:second.id,queueID:"queue-b"),"server queue ID is recorded after acceptance")
        check(uncertain.finishSubmission(clientMessageID:second.id),"confirmed queue submission releases the live owner")
        let queued = HandoffLedger(fileURL:file)
        check(queued.hasUnresolved && queued.visibleRecords.first?.queueID == "queue-b", "queued handoff survives relaunch with its queue ID")
        check(!queued.acknowledgeUncertain(clientMessageID:second.id),"queued handoff cannot be acknowledged as uncertain")
        check(!queued.dismissResolved(clientMessageID:second.id),"queued handoff remains visible until resolved")
        check(queued.markCancelled(clientMessageID:second.id),"confirmed queue deletion records cancellation")
        check(queued.dismissResolved(clientMessageID:second.id),"confirmed cancellation may be dismissed")
        let third = queued.begin(threadID:"thread-a",accountID:"account-a",title:"Project A",failedTurnID:"turn-new")!
        check(queued.markQueued(clientMessageID:third.id,queueID:"queue-c") && queued.markHandedOff(clientMessageID:third.id),"confirmed desktop handoff is marked as handed to Codex")
        check(queued.finishSubmission(clientMessageID:third.id),"handed-off submission releases its owner")
        check(!queued.hasUnresolved && queued.visibleRecords.first?.state == .handedOff,"confirmed handoff unblocks other tasks while preserving user-visible record")
        check(!queued.markCancelled(clientMessageID:third.id),"a handoff already delivered to Codex cannot be falsely reported cancelled")
        let damaged = dir.appendingPathComponent("damaged.json")
        try! Data("not-json".utf8).write(to:damaged)
        let damagedLedger = HandoffLedger(fileURL:damaged)
        check(damagedLedger.storageCorrupted && damagedLedger.storageError != nil && damagedLedger.hasUnresolved && damagedLedger.begin(threadID:"t",accountID:"a",title:"x",failedTurnID:"f") == nil,"corrupt persistence fails closed instead of permitting a repeat")
        let blockedParent = dir.appendingPathComponent("blocked-parent")
        let blocked = HandoffLedger(fileURL:blockedParent.appendingPathComponent("ledger.json"))
        try! FileManager.default.removeItem(at:blockedParent)
        try! Data("file".utf8).write(to:blockedParent)
        check(blocked.begin(threadID:"t",accountID:"a",title:"x",failedTurnID:"f") == nil && blocked.hasUnresolved && blocked.storageError != nil,"a failed durable intent write blocks dispatch")
        let transitionParent = dir.appendingPathComponent("transition-parent")
        let transition = HandoffLedger(fileURL:transitionParent.appendingPathComponent("ledger.json"))
        let intent = transition.begin(threadID:"t",accountID:"a",title:"x",failedTurnID:"f")!
        try! FileManager.default.removeItem(at:transitionParent)
        try! Data("file".utf8).write(to:transitionParent)
        check(!transition.markUncertain(clientMessageID:intent.id) && transition.hasUnresolved && transition.storageError != nil,"a failed later state write blocks dispatch and exposes the error")
        let sharedFile = dir.appendingPathComponent("shared/ledger.json")
        let processA = HandoffLedger(fileURL:sharedFile)
        let processB = HandoffLedger(fileURL:sharedFile)
        check(processA.begin(threadID:"thread-x",accountID:"account-a",title:"X",failedTurnID:"turn-x") != nil,"first widget instance can persist a handoff")
        check(processB.begin(threadID:"thread-y",accountID:"account-a",title:"Y",failedTurnID:"turn-y") == nil,"a second widget instance cannot dispatch around an existing unresolved intent")
        let liveFile = dir.appendingPathComponent("live/ledger.json")
        let liveOwner = HandoffLedger(fileURL:liveFile)
        let live = liveOwner.begin(threadID:"thread-live",accountID:"account-a",title:"Live",failedTurnID:"turn-live")!
        let secondInstance = HandoffLedger(fileURL:liveFile)
        check(!secondInstance.acknowledgeUncertain(clientMessageID:live.id),"a second widget cannot acknowledge another live submission")
        let deadFile = dir.appendingPathComponent("dead/ledger.json")
        try! FileManager.default.createDirectory(at:deadFile.deletingLastPathComponent(),withIntermediateDirectories:true)
        var dead = live
        dead.ownerPID = Int32.max
        try! JSONEncoder().encode([dead]).write(to:deadFile)
        let afterCrash = HandoffLedger(fileURL:deadFile)
        check(afterCrash.visibleRecords.first?.state == .uncertain && afterCrash.acknowledgeUncertain(clientMessageID:dead.id),"a dead owner's submission is recoverable after explicit inspection")
        print("Handoff ledger: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
