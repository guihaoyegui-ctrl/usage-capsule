import Foundation

@MainActor enum AutoResumeTests {
    static func run() async -> Int {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            if condition { print("PASS: \(label)") }
            else { print("FAIL: \(label)"); failures += 1 }
        }
        let suite = "usage-capsule.resume-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let ledger = ResumeLedger(defaults:defaults)
        ledger.select(threadID:"thread-a",accountID:"account-a",title:"Project A")
        check(ResumeLedger(defaults:defaults).selections.count == 1,"owner selection survives app relaunch")
        let failed = ResumeTurn(id:"turn-1",status:"failed",errorCode:"usageLimitExceeded")
        check(!resumeEligible(ledger.selections[0],accountID:"account-a",turn:failed,primaryRemaining:68,weeklyRemaining:42),"available quota alone is not proof of a quota reset")
        ledger.waitForReset(threadID:"thread-a",turnID:"turn-1")
        let selected = ledger.selections[0]
        check(resumeEligible(selected,accountID:"account-a",turn:failed,primaryRemaining:68,weeklyRemaining:42),"selected quota failure can continue after quota recovery")
        check(!resumeEligible(selected,accountID:"account-b",turn:failed,primaryRemaining:68,weeklyRemaining:42),"account switch blocks continuation")
        check(!resumeEligible(selected,accountID:"account-a",turn:failed,primaryRemaining:68,weeklyRemaining:0),"exhausted weekly quota blocks continuation")
        check(!resumeEligible(selected,accountID:"account-a",turn:failed,primaryRemaining:0,weeklyRemaining:42),"exhausted five-hour quota blocks continuation")
        check(!resumeEligible(selected,accountID:"account-a",turn:failed,primaryRemaining:68,weeklyRemaining:nil),"unknown weekly quota blocks continuation")
        check(!resumeEligible(selected,accountID:"account-a",turn:ResumeTurn(id:"turn-1",status:"interrupted",errorCode:nil),primaryRemaining:68,weeklyRemaining:42),"unstructured interruption never auto-resumes")
        check(!resumeEligible(selected,accountID:"account-a",turn:ResumeTurn(id:"turn-1",status:"completed",errorCode:"rateLimitExceeded"),primaryRemaining:68,weeklyRemaining:42),"completed work never auto-resumes")
        ledger.markDispatched(threadID:"thread-a",turnID:"turn-1")
        check(!resumeEligible(ledger.selections[0],accountID:"account-a",turn:failed,primaryRemaining:68,weeklyRemaining:42),"same failed turn cannot dispatch twice")
        check(!resumeEligible(ResumeLedger(defaults:defaults).selections[0],accountID:"account-a",turn:failed,primaryRemaining:68,weeklyRemaining:42),"dispatch marker survives crash or timeout")
        ledger.remove(threadID:"thread-a")
        check(ledger.selections.isEmpty,"owner can remove a selected task")
        ledger.select(threadID:"thread-a",accountID:"account-a",title:"Project A")
        check(!resumeEligible(ledger.selections[0],accountID:"account-a",turn:failed,primaryRemaining:68,weeklyRemaining:42),"reselecting waits for a new observed exhaustion rather than replaying uncertain work")
        print("Auto-resume policy: \(failures) failures")
        return failures
    }
}
