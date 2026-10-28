import Foundation

struct ResumeSelection: Codable, Equatable, Identifiable {
    let threadID: String
    let accountID: String
    var title: String
    var dispatchedTurnID: String?
    var waitingTurnID: String?
    var selectedAt: Double? = nil
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
    let primary: ResumeQuotaWindowObservation
    let weekly: ResumeQuotaWindowObservation
}

/// Infers a reset missed between two nearby successful reads. The caller must
/// retain the previous observation until every selected task has been checked.
/// A missing timestamp, changed account/window, stale read, or ambiguous order
/// produces no result. Generic rate limits are not enough evidence unless zero
/// quota was observed separately by the caller.
func missedQuotaResetWindows(selection:ResumeSelection,turn:ResumeTurn,previous:ResumeQuotaObservation?,current:ResumeQuotaObservation) -> Set<ResumeResetWindow> {
    guard let previous, !selection.accountID.isEmpty,
          previous.accountID == selection.accountID, current.accountID == selection.accountID,
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
    guard valid(previous.primary,current.primary,300), valid(previous.weekly,current.weekly,10080) else { return [] }
    var windows: Set<ResumeResetWindow> = []
    func crossed(_ old:ResumeQuotaWindowObservation,_ new:ResumeQuotaWindowObservation) -> Bool {
        guard let oldReset = old.resetsAt, let newReset = new.resetsAt else { return false }
        return finished > oldReset - Double(old.durationMinutes) * 60 && finished < oldReset && oldReset <= current.observedAt && newReset > oldReset
    }
    if crossed(previous.primary,current.primary) { windows.insert(.fiveHour) }
    if crossed(previous.weekly,current.weekly) { windows.insert(.weekly) }
    return windows
}

struct ResumeThreadChoice: Identifiable {
    let id: String
    let title: String
    let folder: String
}

func resumeEligible(_ selection: ResumeSelection, accountID: String?, turn: ResumeTurn?, primaryRemaining: Double?, weeklyRemaining: Double?) -> Bool {
    guard let accountID, accountID == selection.accountID,
          let primaryRemaining, primaryRemaining.isFinite, primaryRemaining > 0,
          let weeklyRemaining, weeklyRemaining.isFinite, weeklyRemaining > 0,
          let turn, turn.status == "failed" || turn.status == "interrupted",
          turn.errorCode == "usageLimitExceeded" || turn.errorCode == "rateLimitExceeded",
          selection.waitingTurnID == turn.id, selection.dispatchedTurnID != turn.id else { return false }
    return true
}

final class ResumeLedger {
    private let defaults: UserDefaults
    private let key = "selectedAutoResume.v1"
    private let quotaObservationKey = "selectedAutoResumeQuotaObservation.v1"
    private(set) var selections: [ResumeSelection]
    private(set) var lastQuotaObservation: ResumeQuotaObservation?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selections = defaults.data(forKey:key).flatMap { try? JSONDecoder().decode([ResumeSelection].self,from:$0) } ?? []
        lastQuotaObservation = defaults.data(forKey:quotaObservationKey).flatMap { try? JSONDecoder().decode(ResumeQuotaObservation.self,from:$0) }
    }
    func select(threadID:String,accountID:String,title:String,selectedAt:Double = Date().timeIntervalSince1970) {
        guard !threadID.isEmpty, !accountID.isEmpty else { return }
        if let index = selections.firstIndex(where: { $0.threadID == threadID }) {
            selections[index].title = title
        } else {
            selections.append(ResumeSelection(threadID:threadID,accountID:accountID,title:title,dispatchedTurnID:nil,waitingTurnID:nil,selectedAt:selectedAt))
        }
        persist()
    }
    func remove(threadID:String) {
        selections.removeAll { $0.threadID == threadID }
        persist()
    }
    func markDispatched(threadID:String,turnID:String) {
        guard let index = selections.firstIndex(where: { $0.threadID == threadID }) else { return }
        selections[index].dispatchedTurnID = turnID
        selections[index].waitingTurnID = nil
        persist()
    }
    func waitForReset(threadID:String,turnID:String) {
        guard let index = selections.firstIndex(where: { $0.threadID == threadID }),
              selections[index].dispatchedTurnID != turnID,
              selections[index].waitingTurnID != turnID else { return }
        selections[index].waitingTurnID = turnID
        persist()
    }
    func recordQuotaObservation(_ observation:ResumeQuotaObservation) {
        lastQuotaObservation = observation
        defaults.set(try? JSONEncoder().encode(observation),forKey:quotaObservationKey)
        defaults.synchronize()
    }
    private func persist() {
        defaults.set(try? JSONEncoder().encode(selections),forKey:key)
        defaults.synchronize()
    }
}
