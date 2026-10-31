import Foundation
import CoreGraphics

enum ResumeMode: String, Codable, CaseIterable {
    case once, continuous
    var label:String { self == .continuous ? L10n.text("持续续跑（不限次数）") : L10n.text("仅续跑一次") }
}

enum CapsulePointerRelease { case none, click, drag }
struct CapsulePointerGesture {
    private var origin:CGPoint?
    private var dragging = false
    mutating func begin(at point:CGPoint) { origin=point; dragging=false }
    mutating func move(to point:CGPoint) -> CGPoint? {
        guard let origin else { return nil }
        let delta=CGPoint(x:point.x-origin.x,y:point.y-origin.y)
        if !dragging && hypot(delta.x,delta.y) < 4 { return nil }
        dragging=true
        return delta
    }
    mutating func end() -> CapsulePointerRelease {
        guard origin != nil else { return .none }
        let result:CapsulePointerRelease = dragging ? .drag : .click
        cancel()
        return result
    }
    mutating func cancel() { origin=nil; dragging=false }
}

func popupAnchor(panel:CGRect,trigger:CGRect) -> CGPoint {
    guard panel.width > 0, panel.height > 0 else { return CGPoint(x:0.5,y:0.5) }
    return CGPoint(x:max(0,min(1,(trigger.midX-panel.minX)/panel.width)),
                   y:max(0,min(1,1-(trigger.midY-panel.minY)/panel.height)))
}

struct OverviewPresentation {
    private(set) var isVisible = false
    private(set) var isPinned = false
    private var hoverSuppressed = false
    mutating func hoverBegan() { if !hoverSuppressed { isVisible = true } }
    mutating func pointerLeftSurfaces() {
        hoverSuppressed = false
        if !isPinned { isVisible = false }
    }
    mutating func open() { hoverSuppressed = false; isVisible = true }
    mutating func togglePin() { isPinned.toggle(); open() }
    mutating func close() { isVisible = false; isPinned = false; hoverSuppressed = true }
}

struct QuotaWindow: Codable {
    var usedPercent: Double?
    var windowDurationMins: Int?
    var resetsAt: Double?
    var remaining: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return min(100, max(0, 100 - usedPercent))
    }
    var title: String {
        guard let windowDurationMins, windowDurationMins > 0 else { return L10n.text("额度窗口") }
        if windowDurationMins == 300 { return L10n.text("5 小时窗口") }
        if windowDurationMins == 10080 { return L10n.text("本周额度") }
        if windowDurationMins % 1440 == 0 { return L10n.format("%@ 天额度",String(windowDurationMins / 1440)) }
        if windowDurationMins % 60 == 0 { return L10n.format("%@ 小时额度",String(windowDurationMins / 60)) }
        return L10n.format("%@ 分钟额度",String(windowDurationMins))
    }
}
struct LimitBucket: Codable { var primary: QuotaWindow?; var secondary: QuotaWindow?; var planType: String? }
struct ResetCredit: Codable { var id: String; var expiresAt: Double?; var status: String?; var description: String? }
struct ResetCredits: Codable { var availableCount: Int?; var credits: [ResetCredit]? }
struct LimitsResponse: Codable {
    var accountId: String?
    var rateLimits: LimitBucket?
    var rateLimitsByLimitId: [String: LimitBucket]?
    var rateLimitResetCredits: ResetCredits?
    var ordinaryUsageAllowed: Bool?
    var bucket: LimitBucket? { rateLimitsByLimitId?["codex"] ?? rateLimits }
    var quotaProfile: QuotaProfile { QuotaProfile(snapshot:self) }
}

/// One interpretation shared by UI, reserve controls and the final handoff.
/// Null windows remain unknown. Only the documented Pro family has a default
/// unmetered five-hour window; actual finite windows always take precedence.
struct QuotaProfile {
    let planType: String?
    let fiveHour: QuotaWindow?
    let weekly: QuotaWindow?
    let otherWindows: [QuotaWindow]
    let ambiguous: Bool
    let ordinaryUsageAllowed: Bool?
    var isPro: Bool { ["pro","prolite","promax"].contains(planType ?? "") }
    var isEntryPlan: Bool { planType == "free" || planType == "go" }
    var fiveHourUnlimited: Bool { isPro && fiveHour == nil && !ambiguous }
    var configurationID: String {
        (planType ?? "unknown") + ":" + ([fiveHour,weekly].compactMap { $0 } + otherWindows).compactMap(\.windowDurationMins).sorted().map(String.init).joined(separator:",") + (ambiguous ? ":ambiguous" : "")
    }
    var planName: String {
        switch planType {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro", "prolite", "promax": return "Pro"
        case "team", "business", "self_serve_business_prolite", "self_serve_business_usage_based": return "Business"
        case "enterprise", "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based": return "Enterprise"
        case "edu", "edu_plus", "edu_pro": return "Edu"
        default: return L10n.text("会员待确认")
        }
    }
    init(snapshot:LimitsResponse) {
        let bucket = snapshot.bucket
        planType = bucket?.planType?.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        ordinaryUsageAllowed = snapshot.ordinaryUsageAllowed
        let windows = [bucket?.primary,bucket?.secondary].compactMap { $0 }
        fiveHour = windows.first { $0.windowDurationMins == 300 }
        weekly = windows.first { $0.windowDurationMins == 10080 }
        otherWindows = windows.filter { $0.windowDurationMins != 300 && $0.windowDurationMins != 10080 }
        let durations = windows.compactMap(\.windowDurationMins)
        ambiguous = windows.contains { ($0.windowDurationMins ?? 0) <= 0 } || Set(durations).count != durations.count
    }
    func allowsResume(primaryReserve:Double = 0,weeklyReserve:Double = 0) -> Bool {
        guard ordinaryUsageAllowed == true, !ambiguous else { return false }
        let windows = [fiveHour,weekly].compactMap { $0 } + otherWindows
        guard !windows.isEmpty else { return false }
        // Partial entry-tier payloads are usable only with an affirmative
        // account-bound backend permission, not an inferred absent restriction.
        if !isEntryPlan || ordinaryUsageAllowed != true {
            guard fiveHour != nil || fiveHourUnlimited, weekly != nil else { return false }
        }
        for window in windows {
            guard let used = window.usedPercent, used.isFinite, (0...100).contains(used), let remaining = window.remaining else { return false }
            let floor = window.windowDurationMins == 300 ? primaryReserve : (window.windowDurationMins == 10080 ? weeklyReserve : 0)
            guard floor.isFinite, floor >= 0, remaining > floor else { return false }
        }
        return true
    }
}
struct DailyBucket: Codable { var startDate: String; var tokens: Int64 }
struct UsageResponse: Codable { var dailyUsageBuckets: [DailyBucket]? }
struct DayUsage: Identifiable { var date: String; var tokens: Int64?; var id: String { date }; var shortDate: String { String(date.suffix(5)) } }
enum ResetDecision: Equatable { case refresh, noCredit, nothingToReset, unknown }
func resetDecision(_ outcome: String) -> ResetDecision {
    switch outcome {
    case "reset", "alreadyRedeemed": return .refresh
    case "noCredit": return .noCredit
    case "nothingToReset": return .nothingToReset
    default: return .unknown
    }
}
enum QuotaColorTier { case paleGold, amber, orange, vermilion, coralRed }
func quotaColorTier(remaining:Double?) -> QuotaColorTier? {
    guard let remaining, remaining.isFinite, remaining > 0 else { return nil }
    // Match the integer shown by the percentage label at each color boundary.
    switch min(100,remaining).rounded() {
    case 81...100: return .paleGold
    case 61..<81: return .amber
    case 41..<61: return .orange
    case 21..<41: return .vermilion
    default: return .coralRed
    }
}

func glowStrength(remaining: Double?) -> Double {
    guard let remaining, remaining.isFinite, remaining > 0 else { return 0 }
    // Quantity changes the lit area and color, never the lamp's core opacity.
    return 1
}
func todayKey() -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}
func recentDays(buckets: [DailyBucket]?, ending: String = todayKey()) -> [DayUsage] {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let end = f.date(from: ending) else { return [] }
    var values: [String: Int64] = [:]
    for b in buckets ?? [] where b.tokens >= 0 { values[b.startDate] = b.tokens }
    return (-6...0).compactMap { offset in
        guard let date = calendar.date(byAdding: .day, value: offset, to: end) else { return nil }
        let key = f.string(from: date); return DayUsage(date: key, tokens: values[key])
    }
}
func fullTokens(_ value: Int64?) -> String {
    guard let value else { return L10n.text("暂无数据") }
    return value.formatted(.number)
}
func compactTokens(_ value: Int64?) -> String {
    guard let value else { return "—" }
    if value >= 1_000_000 { return String(format:"%.1fM", Double(value)/1_000_000) }
    if value >= 1000 { return String(format:"%.1fk", Double(value)/1000) }
    return String(value)
}
struct RedemptionAttempt: Codable { let key: String; let creditID: String?; let accountID:String? }
struct ResetConfirmation: Equatable {
    let accountID: String
    let creditID: String?
    let pendingKey: String?
    let availableCount: Int?
}
final class RedemptionLedger {
    private let defaults: UserDefaults
    private let storageKey = "unresolvedRedemption.v1"
    private(set) var pending: RedemptionAttempt?
    init(defaults:UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey:storageKey) { pending = try? JSONDecoder().decode(RedemptionAttempt.self,from:data) }
    }
    func begin(creditID:String?,accountID:String) -> RedemptionAttempt {
        if let pending { return pending }
        let attempt = RedemptionAttempt(key:UUID().uuidString,creditID:creditID,accountID:accountID)
        pending = attempt
        defaults.set(try? JSONEncoder().encode(attempt),forKey:storageKey)
        defaults.synchronize()
        return attempt
    }
    func resolve(_ outcome:String) {
        if resetDecision(outcome) != .unknown { pending = nil; defaults.removeObject(forKey:storageKey) }
    }
}
func mayRedeem(cardCount:Int?,pending:RedemptionAttempt?,busy:Bool,connected:Bool,accountID:String?) -> Bool {
    guard connected, !busy, let accountID, !accountID.isEmpty else { return false }
    if let pending { return pending.accountID == accountID }
    return (cardCount ?? 0) > 0
}
func knownTokenTotal(_ days:[DayUsage]) -> Int64? {
    let values = days.compactMap(\.tokens)
    guard !values.isEmpty else { return nil }
    var total:Int64 = 0
    for value in values { let sum = total.addingReportingOverflow(value); if sum.overflow { return nil }; total = sum.partialValue }
    return total
}
func percentLabel(_ value: Double?) -> String { value.map { String(format:"%.0f%%", $0) } ?? "—" }
func resetTime(_ window: QuotaWindow?) -> String {
    guard let time = window?.resetsAt else { return L10n.text("暂无时间") }
    let f = DateFormatter(); f.dateFormat = "MM/dd HH:mm"; return f.string(from: Date(timeIntervalSince1970: time))
}
func countdown(_ window: QuotaWindow?, now: Date = Date()) -> String {
    guard let time = window?.resetsAt else { return "—" }
    let secs = max(0, Int(time - now.timeIntervalSince1970))
    if secs >= 86400 { return L10n.format("%@天 %@时", String(describing: (secs/86400)), String(describing: ((secs%86400)/3600))) }
    return String(format:"%02d:%02d:%02d",secs/3600,(secs%3600)/60,secs%60)
}
