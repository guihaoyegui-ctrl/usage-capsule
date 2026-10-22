import Foundation
import CoreGraphics

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if condition() { print("PASS: \(name)") } else { print("FAIL: \(name)"); failures += 1 }
}
let fixture = Data("""
{"rateLimits":{"primary":{"usedPercent":32,"windowDurationMins":300,"resetsAt":1791827336},"secondary":{"usedPercent":58,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":2,"credits":null}}
""".utf8)
let limits = try! JSONDecoder().decode(LimitsResponse.self, from: fixture)
check(limits.bucket?.primary?.remaining == 68, "used percentage is converted to remaining")
check(limits.bucket?.secondary?.remaining == 42, "secondary quota remains independent")
check(limits.rateLimitResetCredits?.availableCount == 2, "authoritative reset count works without details")
check(QuotaWindow(usedPercent: 150, windowDurationMins: 300, resetsAt: nil).remaining == 0, "over-range usage cannot yield negative remaining")
check(QuotaWindow(usedPercent: nil, windowDurationMins: 300, resetsAt: nil).remaining == nil, "unknown usage is not zero")
check(glowStrength(remaining: 0) == 0, "zero quota extinguishes light")
check(glowStrength(remaining:50) >= 0.95, "half quota keeps a clearly luminous lamp")
check(glowStrength(remaining: 10) > 0, "low quota remains visible")
check(glowStrength(remaining: nil) == 0, "unknown quota cannot light up")
check(glowStrength(remaining:100) >= 0.95, "full quota reaches the bright display range")
check(glowStrength(remaining:60) == glowStrength(remaining:100), "middle quota changes color without fading the lamp")
check(glowStrength(remaining:20) == glowStrength(remaining:100), "critical quota keeps a visible colored warning lamp")
check(glowStrength(remaining:110) == glowStrength(remaining:100), "over-range brightness is clamped")
check(glowStrength(remaining:.nan) == 0, "invalid quota cannot illuminate the display")
let colorCases:[(Double?,QuotaColorTier?)] = [
    (100,.paleGold),(81,.paleGold),(80,.amber),(61,.amber),
    (60,.orange),(50,.orange),(41,.orange),(40,.vermilion),(21,.vermilion),
    (20,.coralRed),(1,.coralRed),(0.1,.coralRed),
    (80.49,.amber),(80.50,.paleGold),(60.49,.orange),(60.50,.amber),
    (40.49,.vermilion),(40.50,.orange),(20.49,.coralRed),(20.50,.vermilion),
    (110,.paleGold),(0,nil),(-5,nil),(nil,nil),(.nan,nil),(.infinity,nil)
]
for (value,expected) in colorCases {
    check(quotaColorTier(remaining:value) == expected,"quota color at \(value.map(String.init(describing:)) ?? "unknown") follows the displayed percentage tier")
}
let buckets = [DailyBucket(startDate:"2026-10-12",tokens:15420),DailyBucket(startDate:"2026-10-11",tokens:0)]
let days = recentDays(buckets: buckets, ending: "2026-10-12")
check(days.count == 7 && days.first?.date == "2026-10-06" && days.last?.date == "2026-10-12", "seven dates ordered across week")
check(days[5].tokens == 0 && days[4].tokens == nil, "missing day differs from zero consumption")
check(days[6].tokens == 15420, "exact daily tokens retained")
let month = recentDays(buckets: [], ending: "2026-03-02")
check(month.first?.date == "2026-02-24", "seven-day query crosses month boundary")
check(resetDecision("reset") == .refresh, "successful reset refreshes official values")
check(resetDecision("alreadyRedeemed") == .refresh, "idempotent success refreshes instead of consuming again")
check(resetDecision("noCredit") == .noCredit, "no card outcome is separate from success")
check(resetDecision("nothingToReset") == .nothingToReset, "ineligible window is separate from success")
check(resetDecision("unexpected") == .unknown, "unknown reset outcome is not treated as success")
let multi = Data("""
{"rateLimits":{"primary":{"usedPercent":90}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":11,"windowDurationMins":300}}}}
""".utf8)
check(try! JSONDecoder().decode(LimitsResponse.self, from: multi).bucket?.primary?.remaining == 89, "multi-bucket codex data wins over legacy view")
print("\(failures) failures")
let suite = "cartridge.tests.\(UUID().uuidString)"
let prefs = UserDefaults(suiteName:suite)!
defer { prefs.removePersistentDomain(forName:suite) }
let ledger = RedemptionLedger(defaults:prefs)
let attempt = ledger.begin(creditID:"opaque-credit-a",accountID:"account-a")
let restored = RedemptionLedger(defaults:prefs)
check(restored.begin(creditID:"opaque-credit-b",accountID:"account-a").key == attempt.key, "unresolved redemption retains idempotency key across relaunch")
check(restored.pending?.creditID == "opaque-credit-a", "retry retains original card instead of selecting next card")
restored.resolve("unknown")
check(RedemptionLedger(defaults:prefs).pending != nil, "uncertain outcome remains persisted")
check(mayRedeem(cardCount:0,pending:restored.pending,busy:false,connected:true,accountID:"account-a"), "last-card uncertainty can be reconciled with same key")
check(!mayRedeem(cardCount:1,pending:restored.pending,busy:false,connected:true,accountID:"account-b"), "pending exchange cannot consume a switched account's card")
check(!mayRedeem(cardCount:1,pending:restored.pending,busy:false,connected:true,accountID:nil), "unknown account cannot reconcile pending exchange")
restored.resolve("alreadyRedeemed")
check(RedemptionLedger(defaults:prefs).pending == nil, "definitive idempotent result clears persisted attempt")
check(!mayRedeem(cardCount:0,pending:nil,busy:false,connected:true,accountID:"account-a"), "zero balance without pending attempt cannot redeem")
check(!mayRedeem(cardCount:1,pending:nil,busy:true,connected:true,accountID:"account-a"), "redemption is locked during submission")
check(knownTokenTotal([DayUsage(date:"a",tokens:nil)]) == nil, "unknown token total is not shown as zero")
check(knownTokenTotal([DayUsage(date:"a",tokens:0)]) == 0, "known zero token total remains zero")
var presentation = OverviewPresentation()
presentation.hoverBegan()
check(presentation.isVisible, "hover opens the overview")
presentation.close()
presentation.hoverBegan()
check(!presentation.isVisible, "closing prevents the same hover from reopening the overview")
presentation.pointerLeftSurfaces()
presentation.hoverBegan()
check(presentation.isVisible, "leaving and reentering restores hover preview")
presentation.togglePin()
presentation.pointerLeftSurfaces()
check(presentation.isVisible && presentation.isPinned, "pinned overview survives pointer exit")
presentation.close()
check(!presentation.isVisible && !presentation.isPinned, "close hides and unpins the overview")
presentation.open()
check(presentation.isVisible, "explicit click can reopen a dismissed overview")
let popupFrame=CGRect(x:200,y:100,width:248,height:324)
let anchorLeft=popupAnchor(panel:popupFrame,trigger:CGRect(x:0,y:100,width:184,height:60))
check(anchorLeft.x == 0 && abs(anchorLeft.y-(1-30.0/324)) < 0.001, "popup on right expands from the capsule-facing edge")
let anchorRight=popupAnchor(panel:popupFrame,trigger:CGRect(x:470,y:100,width:184,height:60))
check(anchorRight.x == 1, "popup on left expands from the opposite edge")
check(popupAnchor(panel:popupFrame,trigger:CGRect(x:200,y:500,width:184,height:60)).y == 0, "clamped popup origin remains on its top edge")
check(popupAnchor(panel:popupFrame,trigger:CGRect(x:200,y:0,width:184,height:60)).y == 1, "clamped popup origin remains on its bottom edge")
var pointer = CapsulePointerGesture()
check(CapsuleLanguage.resolve(selection:"system",preferred:["zh-CN"]) == "zh-Hans", "system Chinese selects Simplified Chinese resources")
check(CapsuleLanguage.resolve(selection:"system",preferred:["fr-FR","ja-JP"]) == "ja", "system language selection finds the first supported preference")
check(CapsuleLanguage.resolve(selection:"ko",preferred:["en-US"]) == "ko", "explicit Korean overrides the system language")
check(CapsuleLanguage.resolve(selection:"en",preferred:["zh-Hans"]) == "en", "explicit English overrides Chinese")
check(CapsuleLanguage.resolve(selection:"bad",preferred:["ja-JP"]) == "ja", "invalid saved language falls back to system preference")
check(CapsuleLanguage.resolve(selection:"system",preferred:["de-DE"]) == "en", "unsupported languages use English")
pointer.begin(at:CGPoint(x:150,y:300))
check(pointer.move(to:CGPoint(x:152,y:301)) == nil, "small pointer jitter does not move the capsule")
check(pointer.end() == .click, "a stationary body press remains a click")
pointer.begin(at:CGPoint(x:150,y:300))
check(pointer.move(to:CGPoint(x:146,y:300)) == CGPoint(x:-4,y:0), "drag starts anywhere on the body at four points")
check(pointer.move(to:CGPoint(x:70,y:340)) == CGPoint(x:-80,y:40), "drag delta uses screen coordinates without accumulating error")
check(pointer.move(to:CGPoint(x:150,y:300)) == .zero, "returning to the press point remains a drag")
check(pointer.end() == .drag, "releasing a drag never pins the overview")
check(pointer.end() == .none, "a second release cannot cause a phantom click")
pointer.begin(at:.zero)
_ = pointer.move(to:CGPoint(x:30,y:20))
pointer.cancel()
check(pointer.end() == .none, "cancelled drag does not activate the capsule")
pointer.begin(at:CGPoint(x:400,y:300))
check(pointer.end() == .click, "a new press works after a cancelled drag")
print("Final: \(failures) failures")
exit(failures == 0 ? 0 : 1)
