import Foundation

@main struct PlanCompatibilityTests {
    static func main() throws {
        var failures = 0
        func check(_ condition:Bool,_ label:String) { if condition { print("PASS: \(label)") } else { print("FAIL: \(label)"); failures += 1 } }
        func profile(_ plan:String?,_ primary:String = "null",_ secondary:String = "null",_ allowed:String = "true") -> QuotaProfile {
            let value = plan.map { "\"\($0)\"" } ?? "null"
            let json = "{\"accountId\":\"a\",\"ordinaryUsageAllowed\":\(allowed),\"rateLimits\":{\"planType\":\(value),\"primary\":\(primary),\"secondary\":\(secondary)}}"
            return try! JSONDecoder().decode(LimitsResponse.self,from:Data(json.utf8)).quotaProfile
        }
        let five = "{\"usedPercent\":32,\"windowDurationMins\":300}"
        let week = "{\"usedPercent\":58,\"windowDurationMins\":10080}"
        let exhausted = "{\"usedPercent\":100,\"windowDurationMins\":10080}"
        let plus = profile("plus",five,week)
        check(plus.fiveHour?.remaining == 68 && plus.weekly?.remaining == 42 && !plus.fiveHourUnlimited,"Plus retains two real windows")
        let pro = profile("pro",week)
        check(pro.fiveHour == nil && pro.weekly?.remaining == 42 && pro.fiveHourUnlimited,"Pro primary weekly slot maps to week, with scoped five-hour infinity")
        check(pro.allowsResume(primaryReserve:90,weeklyReserve:40),"Pro ignores a stored five-hour reserve but respects weekly reserve")
        check(!pro.allowsResume(primaryReserve:0,weeklyReserve:42),"Pro cannot dispatch at the weekly reserve boundary")
        check(!(profile("pro",exhausted)).allowsResume(),"Pro weekly exhaustion still blocks continuation")
        check(!(profile("pro")).allowsResume(),"Pro missing weekly data cannot resume")
        check((profile("prolite",week)).fiveHourUnlimited && (profile("promax",week)).fiveHourUnlimited,"recognized Pro variants share the scoped five-hour policy")
        let explicit = profile("pro",five,week)
        check(!explicit.fiveHourUnlimited && explicit.fiveHour?.remaining == 68,"explicit finite five-hour data overrides Pro default policy")
        check(!(profile("plus",week)).fiveHourUnlimited && !(profile("plus",week)).allowsResume(),"missing Plus five-hour data is unknown, never unlimited")
        check(!(profile("future-plan",week)).fiveHourUnlimited && !(profile("future-plan",week)).allowsResume(),"unknown plan and missing window fail closed")
        check((profile(nil,five,week)).allowsResume(),"legacy dual-window payload remains compatible")
        check(!(profile("plus",five,week,"null")).allowsResume(),"unknown backend usage permission cannot imply recovery")
        check(!(profile("pro",week,"null","false")).allowsResume(),"backend usage denial overrides positive Pro percentages")
        check(!(profile("plus",five,week,"false")).allowsResume(),"backend usage denial overrides Plus percentages")
        let swapped = profile("plus",week,five)
        check(swapped.fiveHour?.remaining == 68 && swapped.weekly?.remaining == 42,"window durations, not slot order, determine labels")
        let ambiguous = profile("pro","{\"usedPercent\":20}",week)
        check(!ambiguous.fiveHourUnlimited && !ambiguous.allowsResume(),"an unclassified window cannot become infinity or be ignored")
        check(!(profile("plus",five,five)).allowsResume(),"duplicate-duration quota slots are ambiguous")
        for plan in ["free","go"] {
            check(!(profile(plan,five,"null","null")).allowsResume(),"\(plan) partial data without backend permission is display-only")
            check((profile(plan,five,"null","true")).allowsResume(),"\(plan) known window and backend permission permit recovery")
            check(!(profile(plan,"null","null","true")).allowsResume(),"\(plan) empty data cannot resume even with permission")
            check(!(profile(plan,week)).fiveHourUnlimited,"\(plan) missing five-hour data never renders infinity")
        }
        let custom = profile("go","{\"usedPercent\":20,\"windowDurationMins\":60}","null","true")
        check(custom.otherWindows.count == 1 && custom.allowsResume(),"a known additional window remains part of eligibility")
        let customZero = profile("go","{\"usedPercent\":100,\"windowDurationMins\":60}","null","true")
        check(!customZero.allowsResume(),"an exhausted nonstandard window cannot be ignored")
        check(plus.configurationID != pro.configurationID,"plan changes invalidate inferred-reset configuration")
        print("Plan compatibility: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
