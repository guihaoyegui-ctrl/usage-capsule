import Foundation

enum ResumeStage {
    case armed, monitoring, waiting, queued, running, ended, review, consent, used, account, reserved, paused, unknown
    var label:String {
        switch self {
        case .armed: return L10n.text("已授权一次，等待额度中断")
        case .monitoring: return L10n.text("持续监测，等待下次额度中断")
        case .waiting: return L10n.text("等待额度恢复")
        case .queued: return L10n.text("已排队，等待 Codex 处理")
        case .running: return L10n.text("正在执行")
        case .ended: return L10n.text("本轮已结束")
        case .review: return L10n.text("需要你核实，请打开原对话")
        case .consent: return L10n.text("旧版选择，请确认单次授权")
        case .used: return L10n.text("本次授权已使用")
        case .account: return L10n.text("等待原账号登录")
        case .reserved: return L10n.text("等待额度高于保留值")
        case .paused: return L10n.text("自动续跑已暂停")
        case .unknown: return L10n.text("进展暂无法核实，请查看原对话")
        }
    }
    var symbol:String {
        switch self {
        case .armed, .monitoring, .consent: return "checkmark.shield"
        case .waiting, .reserved: return "clock"
        case .queued: return "tray.and.arrow.down"
        case .running: return "play.fill"
        case .ended: return "checkmark.circle"
        case .review, .unknown, .account: return "exclamationmark.circle"
        case .used: return "checkmark"
        case .paused: return "pause.circle"
        }
    }
}

@MainActor extension QuotaStore {
    var currentResumeRecords:[HandoffRecord] { handoffLedger.visibleRecords.filter { $0.accountID == limits?.accountId } }
    var activeResumeSelections:[ResumeSelection] { selectedResumeTasks.filter { $0.canAwaitFailure && handoffLedger.authorizationState($0.authorizationID) == "active" } }
    var resumeIsPaused:Bool { handoffLedger.paused }
    var resumeReserve:ResumeReserve { handoffLedger.reserve(accountID:limits?.accountId ?? "") }
    func stage(for record:HandoffRecord) -> ResumeStage {
        guard record.accountID == limits?.accountId else { return .account }
        if resumeTrackingUnavailable.contains(record.id) || error != nil || !accountSnapshotVerified { return .unknown }
        switch record.state {
        case .queued: return .queued
        case .submitting, .uncertain: return .review
        case .cancelled, .acknowledged: return .used
        case .handedOff:
            if record.turnStatus == "completed" { return .ended }
            if record.turnStatus == "inProgress" { return .running }
            if record.turnStatus == "failed" { return record.quotaFailureConfirmed == true ? .waiting : .review }
            return .unknown
        }
    }
    func stage(for item:ResumeSelection) -> ResumeStage {
        guard item.accountID == limits?.accountId else { return .account }
        let continuous = item.effectiveMode == .continuous && handoffLedger.authorizationState(item.authorizationID) == "active"
        if let record = currentResumeRecords.last(where: { $0.threadID == item.threadID && $0.failedTurnID == item.dispatchedTurnID }) {
            if !continuous || record.blocksDispatch { return stage(for:record) }
        }
        if !continuous && item.dispatchedTurnID != nil { return .used }
        if item.authorizationVersion != 2 || item.authorizationID == nil { return .consent }
        if handoffLedger.authorizationState(item.authorizationID) != "active" { return .used }
        if error != nil || !accountSnapshotVerified || limits?.ordinaryUsageAllowed == nil { return .unknown }
        if resumeIsPaused { return .paused }
        if item.waitingTurnID != nil {
            if let profile = limits?.quotaProfile, profile.allowsResume(),
               !handoffLedger.permitsDispatch(accountID:item.accountID,primary:primary?.remaining,weekly:secondary?.remaining,quotaProfile:profile) { return .reserved }
            return .waiting
        }
        return continuous ? .monitoring : .armed
    }
    func detail(for record:HandoffRecord) -> String {
        switch record.state {
        case .cancelled: return L10n.text("已确认撤回排队指令")
        case .acknowledged: return L10n.text("已核实，保留防重复记录")
        case .handedOff:
            if record.releasedAfterInspection == true { return L10n.text("已由你核实并放行；任务进展请看原对话") }
            if record.turnStatus == "completed" { return L10n.text("仅表示本轮结束，请在原对话核对任务结果") }
            if record.quotaFailureConfirmed == true { return L10n.text("额度中断已确认；持续监测等待恢复") }
            if record.turnStatus == "failed" { return L10n.text("本轮遇到错误，后续自动交接已暂停") }
            return L10n.text("已交给 Codex；需要停止时请在原对话操作")
        default: return stage(for:record).label
        }
    }
    var resumeOverviewStage:ResumeStage {
        if handoffLedger.storageCorrupted { return .review }
        if handoffLedger.visibleRecords.contains(where: { $0.blocksDispatch && $0.accountID != limits?.accountId }) { return .account }
        if currentResumeRecords.contains(where: { stage(for:$0) == .review || stage(for:$0) == .unknown && $0.blocksDispatch }) { return .review }
        if currentResumeRecords.contains(where: { stage(for:$0) == .running }) { return .running }
        if currentResumeRecords.contains(where: { $0.state == .queued }) { return .queued }
        if resumeIsPaused { return .paused }
        if activeResumeSelections.contains(where: { $0.waitingTurnID != nil }) { return .waiting }
        return .armed
    }
    var resumeSummary:String {
        if resumeIsPaused { return L10n.text("自动续跑已暂停") }
        if resumeOverviewStage == .review { return ResumeStage.review.label }
        if resumeOverviewStage == .account { return ResumeStage.account.label }
        if error != nil && resumeNeedsDot { return ResumeStage.unknown.label }
        let waiting = activeResumeSelections.filter { $0.waitingTurnID != nil }.count
        let queued = currentResumeRecords.filter { $0.state == .queued }.count
        let running = currentResumeRecords.filter { stage(for:$0) == .running }.count
        let counts = L10n.format("等待 %@ · 排队 %@ · 执行 %@",String(waiting),String(queued),String(running))
        let continuous = activeResumeSelections.filter { $0.effectiveMode == .continuous }.count
        return continuous > 0 ? L10n.format("持续监测 %@ 项 · %@",String(continuous),counts) : counts
    }
    var resumeNeedsDot:Bool {
        !activeResumeSelections.isEmpty || handoffLedger.visibleRecords.contains { $0.blocksDispatch } || handoffLedger.storageCorrupted
    }
    func filteredResumeChoices(_ query:String) -> [ResumeThreadChoice] {
        let term = query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !term.isEmpty else { return recentThreads }
        return recentThreads.filter { $0.title.localizedCaseInsensitiveContains(term) || $0.folder.localizedCaseInsensitiveContains(term) }
    }
}
