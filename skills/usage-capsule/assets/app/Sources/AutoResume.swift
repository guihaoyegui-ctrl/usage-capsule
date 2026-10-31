import Foundation
import Darwin

struct ResumeSelection: Codable, Equatable, Identifiable {
    let threadID: String
    let accountID: String
    var title: String
    var dispatchedTurnID: String?
    var waitingTurnID: String?
    var selectedAt: Double? = nil
    // Missing on the older unlimited opt-in records: require explicit renewal.
    var authorizationVersion: Int? = nil
    var authorizationID: String? = nil
    var mode: ResumeMode? = nil
    var effectiveMode:ResumeMode { mode ?? .once }
    var canAwaitFailure:Bool { authorizationVersion == 2 && authorizationID != nil && (effectiveMode == .continuous || dispatchedTurnID == nil) }
    var id: String { threadID }
}

struct ResumeTurn: Equatable {
    let id: String
    let status: String
    let errorCode: String?
    var completedAt: Double? = nil
}

enum ResumeResetWindow: Hashable { case fiveHour, weekly }

struct ResumeQuotaWindowObservation: Codable, Equatable {
    let durationMinutes: Int
    let resetsAt: Double?
    let remaining: Double?
}

struct ResumeQuotaObservation: Codable, Equatable {
    let accountID: String
    let observedAt: Double
    let primary: ResumeQuotaWindowObservation?
    let weekly: ResumeQuotaWindowObservation?
    var planType: String? = nil
    var ordinaryUsageAllowed: Bool? = nil
}

/// Infers a reset missed between two nearby successful reads. The caller must
/// retain the previous observation until every selected task has been checked.
/// A missing timestamp, changed account/window, stale read, or ambiguous order
/// produces no result. Generic rate limits are not enough evidence unless zero
/// quota was observed separately by the caller.
func missedQuotaResetWindows(selection:ResumeSelection,turn:ResumeTurn,previous:ResumeQuotaObservation?,current:ResumeQuotaObservation) -> Set<ResumeResetWindow> {
    guard let previous, !selection.accountID.isEmpty,
          previous.accountID == selection.accountID, current.accountID == selection.accountID,
          previous.planType == current.planType,
          let selectedAt = selection.selectedAt, selectedAt.isFinite, selectedAt > 0,
          previous.observedAt.isFinite, current.observedAt.isFinite,
          previous.observedAt >= selectedAt,
          current.observedAt > previous.observedAt,
          current.observedAt - previous.observedAt <= 300,
          let finished = turn.completedAt, finished.isFinite,
          finished > selectedAt, finished <= current.observedAt,
          !turn.id.isEmpty, selection.dispatchedTurnID != turn.id,
          turn.status == "failed" || turn.status == "interrupted",
          turn.errorCode == "usageLimitExceeded" else { return [] }

    func valid(_ old:ResumeQuotaWindowObservation,_ new:ResumeQuotaWindowObservation,_ duration:Int) -> Bool {
        guard old.durationMinutes == duration, new.durationMinutes == duration,
              let oldReset = old.resetsAt, let newReset = new.resetsAt,
              oldReset.isFinite, newReset.isFinite,
              oldReset > previous.observedAt, newReset > current.observedAt,
              newReset >= oldReset,
              let oldRemaining = old.remaining, oldRemaining.isFinite, (0...100).contains(oldRemaining),
              let newRemaining = new.remaining, newRemaining.isFinite, newRemaining > 0, newRemaining <= 100 else { return false }
        return true
    }
    let pro = ["pro","prolite","promax"].contains(current.planType ?? "")
    let entry = ["free","go"].contains(current.planType ?? "") && previous.ordinaryUsageAllowed == true && current.ordinaryUsageAllowed == true
    func validPair(_ old:ResumeQuotaWindowObservation?,_ new:ResumeQuotaWindowObservation?,_ duration:Int,_ mayBeAbsent:Bool) -> Bool {
        if let old, let new { return valid(old,new,duration) }
        return old == nil && new == nil && mayBeAbsent
    }
    guard validPair(previous.primary,current.primary,300,pro), validPair(previous.weekly,current.weekly,10080,entry) else { return [] }
    var windows: Set<ResumeResetWindow> = []
    func crossed(_ old:ResumeQuotaWindowObservation,_ new:ResumeQuotaWindowObservation) -> Bool {
        guard let oldReset = old.resetsAt, let newReset = new.resetsAt else { return false }
        return finished > oldReset - Double(old.durationMinutes) * 60 && finished < oldReset && oldReset <= current.observedAt && newReset > oldReset
    }
    if let old = previous.primary, let new = current.primary, crossed(old,new) { windows.insert(.fiveHour) }
    if let old = previous.weekly, let new = current.weekly, crossed(old,new) { windows.insert(.weekly) }
    return windows
}

struct ResumeThreadChoice: Identifiable {
    let id: String
    let title: String
    let folder: String
}

func resumeEligible(_ selection: ResumeSelection, accountID: String?, turn: ResumeTurn?, primaryRemaining: Double?, weeklyRemaining: Double?,quotaProfile:QuotaProfile? = nil) -> Bool {
    let usable:Bool
    if let quotaProfile { usable = quotaProfile.allowsResume() }
    else { usable = primaryRemaining.map { $0.isFinite && $0 > 0 } == true && weeklyRemaining.map { $0.isFinite && $0 > 0 } == true }
    guard let accountID, accountID == selection.accountID,
          usable,
          let turn, turn.status == "failed" || turn.status == "interrupted",
          turn.errorCode == "usageLimitExceeded" || turn.errorCode == "rateLimitExceeded",
          selection.canAwaitFailure, selection.dispatchedTurnID != turn.id,
          selection.waitingTurnID == turn.id else { return false }
    return true
}

final class ResumeLedger {
    private let defaults: UserDefaults
    private let key = "selectedAutoResume.v1"
    private let quotaObservationKey = "selectedAutoResumeQuotaObservation.v1"
    private(set) var selections: [ResumeSelection] = []
    private(set) var lastQuotaObservation: ResumeQuotaObservation?
    private(set) var storageError: String?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _ = refresh()
    }
    @discardableResult func refresh() -> Bool { locked { self.load() } }
    private func load() -> Bool {
        defaults.synchronize()
        do {
            selections = try defaults.data(forKey:key).map { try JSONDecoder().decode([ResumeSelection].self,from:$0) } ?? []
            lastQuotaObservation = try defaults.data(forKey:quotaObservationKey).map { try JSONDecoder().decode(ResumeQuotaObservation.self,from:$0) }
            return true
        } catch { storageError = error.localizedDescription; return false }
    }
    private func locked(_ operation:()->Bool) -> Bool {
        // All capsule bundles use the same per-user temporary lock. The actual
        // preference domain stays bundle-specific; authorization is shared in
        // HandoffLedger and remains the authority for dispatch.
        let path = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("usage-capsule-selection-preferences.lock").path
        let fd = Darwin.open(path,O_CREAT | O_RDWR | O_NOFOLLOW,mode_t(0o600))
        guard fd >= 0 else { storageError = String(errno); return false }
        defer { Darwin.close(fd) }
        guard Darwin.lockf(fd,F_LOCK,0) == 0 else { storageError = String(errno); return false }
        defer { _ = Darwin.lockf(fd,F_ULOCK,0) }
        return operation()
    }
    private func mutate(_ update:()->Void) {
        _ = locked {
            guard load() else { return false }
            update()
            do { defaults.set(try JSONEncoder().encode(selections),forKey:key) }
            catch { storageError = error.localizedDescription; return false }
            return defaults.synchronize()
        }
    }
    func select(threadID:String,accountID:String,title:String,selectedAt:Double = Date().timeIntervalSince1970,mode:ResumeMode = .once) {
        guard !threadID.isEmpty, !accountID.isEmpty else { return }
        mutate {
            if let index = selections.firstIndex(where: { $0.threadID == threadID }) { selections[index].title = title }
            else {
                selections.append(ResumeSelection(threadID:threadID,accountID:accountID,title:title,dispatchedTurnID:nil,waitingTurnID:nil,selectedAt:selectedAt,authorizationVersion:2,authorizationID:UUID().uuidString.lowercased(),mode:mode))
            }
        }
    }
    func remove(threadID:String) { mutate { selections.removeAll { $0.threadID == threadID } } }
    func move(threadID:String,offset:Int) {
        mutate {
            guard let index = selections.firstIndex(where: { $0.threadID == threadID }) else { return }
            let destination = index + offset
            guard selections.indices.contains(destination) else { return }
            selections.swapAt(index,destination)
        }
    }
    func markDispatched(threadID:String,turnID:String,authorizationID:String? = nil) {
        mutate {
            guard let index = selections.firstIndex(where: { $0.threadID == threadID }),
                  authorizationID == nil || selections[index].authorizationID == authorizationID else { return }
            selections[index].dispatchedTurnID = turnID
            selections[index].waitingTurnID = nil
        }
    }
    func waitForReset(threadID:String,turnID:String,authorizationID:String? = nil) {
        mutate {
            guard let index = selections.firstIndex(where: { $0.threadID == threadID }),
                  authorizationID == nil || selections[index].authorizationID == authorizationID,
                  selections[index].canAwaitFailure, selections[index].dispatchedTurnID != turnID,
                  selections[index].waitingTurnID != turnID else { return }
            selections[index].waitingTurnID = turnID
        }
    }
    func recordQuotaObservation(_ observation:ResumeQuotaObservation) {
        _ = locked {
            guard load() else { return false }
            lastQuotaObservation = observation
            do { defaults.set(try JSONEncoder().encode(observation),forKey:quotaObservationKey) }
            catch { storageError = error.localizedDescription; return false }
            return defaults.synchronize()
        }
    }
    func clearQuotaObservation() {
        _ = locked {
            guard load() else { return false }
            lastQuotaObservation = nil
            defaults.removeObject(forKey:quotaObservationKey)
            return defaults.synchronize()
        }
    }
}
