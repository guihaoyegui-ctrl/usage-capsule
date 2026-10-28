import Foundation

@main struct ResetTransitionTests {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if condition { print("PASS: \(message)") }
            else { failures += 1; print("FAIL: \(message)") }
        }
        let suite = "usage-capsule.reset-transition.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let ledger = ResumeLedger(defaults:defaults)
        ledger.select(threadID:"thread-a",accountID:"account-a",title:"Task",selectedAt:1000)
        let selection = ledger.selections[0]
        func window(_ mins:Int,_ reset:Double?,_ remaining:Double? = 50) -> ResumeQuotaWindowObservation {
            ResumeQuotaWindowObservation(durationMinutes:mins,resetsAt:reset,remaining:remaining)
        }
        func observation(account:String = "account-a",time:Double,primary:ResumeQuotaWindowObservation,weekly:ResumeQuotaWindowObservation) -> ResumeQuotaObservation {
            ResumeQuotaObservation(accountID:account,observedAt:time,primary:primary,weekly:weekly)
        }
        let old = observation(time:1010,primary:window(300,1060),weekly:window(10080,2000))
        let fiveHourReset = observation(time:1070,primary:window(300,19060,100),weekly:window(10080,2000))
        let failure = ResumeTurn(id:"f1",status:"failed",errorCode:"usageLimitExceeded",completedAt:1059)
        func crossed(_ previous:ResumeQuotaObservation? = old,_ current:ResumeQuotaObservation = fiveHourReset,_ turn:ResumeTurn = failure,_ selection:ResumeSelection = selection) -> Set<ResumeResetWindow> {
            missedQuotaResetWindows(selection:selection,turn:turn,previous:previous,current:current)
        }
        check(crossed() == [.fiveHour],"detects a five-hour reset when the failure occurred between polls")
        let failureBeforePreviousPoll = ResumeTurn(id:"f2",status:"failed",errorCode:"usageLimitExceeded",completedAt:1005)
        check(crossed(old,fiveHourReset,failureBeforePreviousPoll) == [.fiveHour],"detects a selected task that failed shortly before the last pre-reset poll")
        let oldWeek = observation(time:1010,primary:window(300,2000),weekly:window(10080,1060))
        let newWeek = observation(time:1070,primary:window(300,2000),weekly:window(10080,605860,100))
        check(crossed(oldWeek,newWeek) == [.weekly],"detects the weekly window independently")
        let bothOld = observation(time:1010,primary:window(300,1060),weekly:window(10080,1060))
        let bothNew = observation(time:1070,primary:window(300,19060),weekly:window(10080,605860))
        check(crossed(bothOld,bothNew) == [.fiveHour,.weekly],"detects simultaneous valid window resets")
        check(crossed(nil).isEmpty,"missing previous observation cannot imply recovery")
        check(crossed(observation(account:"account-b",time:1010,primary:window(300,1060),weekly:window(10080,2000))).isEmpty,"account switch rejects old reset evidence")
        check(crossed(old,observation(account:"account-b",time:1070,primary:window(300,19060),weekly:window(10080,2000))).isEmpty,"current account must match the selected task")
        check(crossed(old,observation(time:1070,primary:window(300,nil),weekly:window(10080,2000))).isEmpty,"missing reset timestamp fails closed")
        check(crossed(old,observation(time:1070,primary:window(300,19060),weekly:window(10080,nil))).isEmpty,"other quota window timestamp must also be known")
        check(crossed(old,observation(time:1070,primary:window(300,19060),weekly:window(10080,2000,nil))).isEmpty,"unknown remaining quota cannot imply recovery")
        check(crossed(old,observation(time:1070,primary:window(300,19060),weekly:window(10080,2000,0))).isEmpty,"exhausted weekly quota blocks five-hour recovery")
        check(crossed(old,fiveHourReset,ResumeTurn(id:"f1",status:"failed",errorCode:"usageLimitExceeded")).isEmpty,"missing failure time cannot establish order")
        check(crossed(old,fiveHourReset,ResumeTurn(id:"f1",status:"failed",errorCode:"usageLimitExceeded",completedAt:1071)).isEmpty,"future failure timestamp is rejected")
        check(crossed(old,fiveHourReset,ResumeTurn(id:"f1",status:"failed",errorCode:"usageLimitExceeded",completedAt:1060)).isEmpty,"same-second reset and failure are ambiguous")
        check(crossed(old,fiveHourReset,ResumeTurn(id:"f1",status:"failed",errorCode:"usageLimitExceeded",completedAt:999)).isEmpty,"failure before the owner selected the task is not automatically resumed")
        check(crossed(old,fiveHourReset,ResumeTurn(id:"f1",status:"interrupted",errorCode:nil,completedAt:1059)).isEmpty,"ordinary interruption cannot trigger inferred recovery")
        check(crossed(old,fiveHourReset,ResumeTurn(id:"f1",status:"failed",errorCode:"rateLimitExceeded",completedAt:1059)).isEmpty,"generic rate limits are ambiguous without an observed zero quota")
        check(crossed(old,fiveHourReset,ResumeTurn(id:"f1",status:"completed",errorCode:"usageLimitExceeded",completedAt:1059)).isEmpty,"completed task cannot trigger inferred recovery")
        let late = observation(time:1400,primary:window(300,19060),weekly:window(10080,2000))
        check(crossed(old,late).isEmpty,"stale observations after a long gap are not treated as a missed minute poll")
        let changedPlan = observation(time:1070,primary:window(60,19060),weekly:window(10080,2000))
        check(crossed(old,changedPlan).isEmpty,"changed quota window duration is ambiguous")
        var lateSelection = selection
        lateSelection.selectedAt = 1011
        check(crossed(old,fiveHourReset,failure,lateSelection).isEmpty,"selection after prior observation cannot infer a missed reset")
        lateSelection.selectedAt = nil
        check(crossed(old,fiveHourReset,failure,lateSelection).isEmpty,"legacy selection without its activation time cannot infer a reset")
        lateSelection = selection
        lateSelection.dispatchedTurnID = "f1"
        check(crossed(old,fiveHourReset,failure,lateSelection).isEmpty,"already dispatched failure cannot be armed again")
        ledger.recordQuotaObservation(old)
        check(ResumeLedger(defaults:defaults).lastQuotaObservation == old,"previous quota observation survives relaunch")
        ledger.recordQuotaObservation(fiveHourReset)
        check(ResumeLedger(defaults:defaults).lastQuotaObservation == fiveHourReset,"new observation replaces old evidence")
        print("Reset transition: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
