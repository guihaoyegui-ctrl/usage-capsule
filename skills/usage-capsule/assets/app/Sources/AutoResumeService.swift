import Foundation
import AppKit

@MainActor extension QuotaStore {
    var selectedResumeTasks: [ResumeSelection] {
        resumeLedger.selections.filter { $0.accountID == limits?.accountId }
    }
    func isAutoResumeSelected(_ id:String) -> Bool {
        selectedResumeTasks.contains { item in
            guard item.threadID == id, item.authorizationVersion == 2, let authorization = item.authorizationID else { return false }
            let state = handoffLedger.authorizationState(authorization)
            return (state == "active" && item.canAwaitFailure) || (state == "consumed" && handoffLedger.records.contains { $0.authorizationID == authorization && $0.blocksDispatch })
        }
    }
    func setResumePaused(_ paused:Bool) {
        guard !demo else { return }
        objectWillChange.send()
        if !handoffLedger.setPaused(paused) { resumeNotice = L10n.text("续跑记录无法读取，请检查本机存储") }
    }
    func moveResumeTask(_ id:String,offset:Int) {
        guard !demo else { return }
        objectWillChange.send(); resumeLedger.move(threadID:id,offset:offset)
    }
    func renewResumeAuthorization(_ item:ResumeSelection,mode:ResumeMode = .once) {
        guard !demo, error == nil, item.accountID == limits?.accountId,
              handoffLedger.refresh(), !handoffLedger.records.contains(where: { $0.threadID == item.threadID && $0.blocksDispatch }) else { return }
        objectWillChange.send()
        resumeLedger.remove(threadID:item.threadID)
        resumeLedger.select(threadID:item.threadID,accountID:item.accountID,title:item.title,mode:mode)
        registerResumeAuthorization(item.threadID)
        resumeStatuses[item.threadID] = L10n.text("已选中，等待额度中断")
    }
    func releaseResumeHandoff(_ item:HandoffRecord) {
        guard !demo, item.accountID == limits?.accountId else { return }
        objectWillChange.send()
        _ = handoffLedger.releaseAfterInspection(clientMessageID:item.id)
    }
    func setResumeReserve(primary:Double,weekly:Double) {
        guard !demo, let account = limits?.accountId else { return }
        objectWillChange.send()
        if !handoffLedger.setReserve(accountID:account,primary:primary,weekly:weekly) { resumeNotice = L10n.text("续跑记录无法读取，请检查本机存储") }
    }
    func toggleAutoResume(_ thread:ResumeThreadChoice,mode:ResumeMode = .once) {
        guard !demo else { return }
        if isAutoResumeSelected(thread.id) {
            removeAutoResume(thread.id)
        } else if let accountID = limits?.accountId, error == nil {
            objectWillChange.send()
            resumeLedger.remove(threadID:thread.id)
            resumeLedger.select(threadID:thread.id,accountID:accountID,title:thread.title,mode:mode)
            registerResumeAuthorization(thread.id)
            resumeStatuses[thread.id] = L10n.text("已选中，等待额度中断")
        }
    }
    func removeAutoResume(_ id:String) {
        objectWillChange.send()
        _ = handoffLedger.revokeAuthorizations(threadID:id)
        resumeLedger.remove(threadID:id)
        resumeStatuses.removeValue(forKey:id)
        Task { await cancelResumeSelection(id) }
    }
    func cancelResumeSelection(_ id:String) async {
        objectWillChange.send()
        _ = handoffLedger.revokeAuthorizations(threadID:id)
        resumeLedger.remove(threadID:id)
        guard handoffLedger.refresh() else { resumeNotice = L10n.text("续跑记录无法读取，请检查本机存储"); return }
        for record in handoffLedger.visibleRecords where record.threadID == id && record.state.unresolved {
            await cancelHandoff(record)
        }
        objectWillChange.send()
    }
    private func registerResumeAuthorization(_ id:String) {
        guard let item = resumeLedger.selections.first(where: { $0.threadID == id }), let authorization = item.authorizationID,
              handoffLedger.authorize(id:authorization,threadID:id,accountID:item.accountID,mode:item.effectiveMode,grantedAt:item.selectedAt ?? 0) else {
            resumeNotice = L10n.text("续跑记录无法读取，请检查本机存储")
            return
        }
    }
    func clearHandoff(_ id:String,acknowledge:Bool = false) {
        guard activeHandoffSubmissionID != id else { return }
        objectWillChange.send()
        if acknowledge { _ = handoffLedger.acknowledgeUncertain(clientMessageID:id) }
        _ = handoffLedger.dismissResolved(clientMessageID:id)
    }
    func loadRecentThreads(more:Bool = false) async {
        guard !demo, !loadingThreads else { return }
        loadingThreads = true
        defer { loadingThreads = false }
        do {
            try await taskConnection.connect()
            var params: [String:Any] = ["limit":30,"sortKey":"updated_at","sortDirection":"desc","archived":false]
            if more, let cursor = resumeListCursor { params["cursor"] = cursor }
            let data = try await taskConnection.request("thread/list",params:params)
            let result = try JSONSerialization.jsonObject(with:data) as? [String:Any]
            let rows = result?["data"] as? [[String:Any]] ?? []
            let choices = rows.compactMap { row -> ResumeThreadChoice? in
                guard let id = row["id"] as? String, row["parentThreadId"] as? String == nil else { return nil }
                let name = [row["name"] as? String,row["preview"] as? String].compactMap { $0?.trimmingCharacters(in:.whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
                return ResumeThreadChoice(id:id,title:name.isEmpty ? String(id.prefix(12)) : name,folder:row["cwd"] as? String ?? "")
            }
            recentThreads = more ? recentThreads + choices.filter { choice in !recentThreads.contains { $0.id == choice.id } } : choices
            resumeListCursor = result?["nextCursor"] as? String
            resumeNotice = nil
        } catch { resumeNotice = L10n.format("任务列表暂无法读取：%@",error.localizedDescription) }
    }
    func latestResumeTurn(_ id:String) async throws -> ResumeTurn? {
        let data = try await taskConnection.request("thread/turns/list",params:["threadId":id,"limit":1,"sortDirection":"desc"])
        let result = try JSONSerialization.jsonObject(with:data) as? [String:Any]
        guard let turn = (result?["data"] as? [[String:Any]])?.first,
              let turnID = turn["id"] as? String, let status = turn["status"] as? String else { return nil }
        let error = turn["error"] as? [String:Any]
        return ResumeTurn(id:turnID,status:status,errorCode:error?["codexErrorInfo"] as? String,completedAt:(turn["completedAt"] as? NSNumber)?.doubleValue)
    }
    func quotaObservation() -> ResumeQuotaObservation? {
        guard let snapshot = limits, let account = snapshot.accountId, let sampleTime = lastSync else { return nil }
        let profile = snapshot.quotaProfile
        guard !profile.ambiguous, profile.otherWindows.isEmpty else { return nil }
        func observation(_ window:QuotaWindow?) -> ResumeQuotaWindowObservation? {
            guard let window, let duration = window.windowDurationMins else { return nil }
            return ResumeQuotaWindowObservation(durationMinutes:duration,resetsAt:window.resetsAt,remaining:window.remaining)
        }
        return ResumeQuotaObservation(accountID:account,observedAt:sampleTime.timeIntervalSince1970,
            primary:observation(profile.fiveHour),weekly:observation(profile.weekly),planType:profile.planType,ordinaryUsageAllowed:snapshot.ordinaryUsageAllowed)
    }
    private func queueEntries(_ threadID:String) async throws -> [[String:Any]] {
        var all:[[String:Any]] = []
        var cursor:String?
        for _ in 0..<10 {
            var params:[String:Any] = ["threadId":threadID,"limit":100]
            if let cursor { params["cursor"] = cursor }
            let data = try await taskConnection.request("thread/queue/list",params:params)
            guard let result = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let rows = result["data"] as? [[String:Any]] else { throw ServiceError(message:"Invalid queue response") }
            all += rows
            cursor = result["nextCursor"] as? String
            if cursor == nil { return all }
        }
        throw ServiceError(message:"Queue is too large to verify")
    }
    private func handoffHistory(_ record:HandoffRecord) async throws -> (String,[[String:Any]])? {
        var cursor:String?
        var all:[[String:Any]] = []
        for _ in 0..<5 {
            var params:[String:Any] = ["threadId":record.threadID,"limit":100,"sortDirection":"desc"]
            if let cursor { params["cursor"] = cursor }
            let data = try await taskConnection.request("thread/items/list",params:params)
            guard let result = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let rows = result["data"] as? [[String:Any]] else { throw ServiceError(message:"Invalid history response") }
            all += rows
            if let match = rows.first(where: { row in
                let item = row["item"] as? [String:Any]
                return item?["type"] as? String == "userMessage" && item?["clientId"] as? String == record.clientMessageID
            }), let turnID = match["turnId"] as? String { return (turnID,all) }
            cursor = result["nextCursor"] as? String
            if cursor == nil { break }
        }
        return nil
    }
    private func historyContains(_ record:HandoffRecord) async throws -> Bool {
        try await handoffHistory(record) != nil
    }
    private func trackHandoff(_ record:HandoffRecord) async throws -> Bool {
        guard let (turnID,entries) = try await handoffHistory(record) else { return false }
        _ = handoffLedger.markHandedOff(clientMessageID:record.id)
        var cursor:String?
        for _ in 0..<5 {
            var params:[String:Any] = ["threadId":record.threadID,"limit":100,"sortDirection":"desc"]
            if let cursor { params["cursor"] = cursor }
            let data = try await taskConnection.request("thread/turns/list",params:params)
            guard let result = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let turns = result["data"] as? [[String:Any]] else { throw ServiceError(message:"Invalid turns response") }
            if let turn = turns.first(where: { $0["id"] as? String == turnID }), let status = turn["status"] as? String {
                let messages = entries.filter { $0["turnId"] as? String == turnID }.compactMap { $0["item"] as? [String:Any] }
                let final = messages.first { $0["type"] as? String == "agentMessage" && $0["phase"] as? String != "commentary" && ($0["text"] as? String)?.isEmpty == false }
                let ended = (turn["completedAt"] as? NSNumber)?.doubleValue
                // Independent readers can report an interrupted live desktop turn.
                // Such a status cannot free the barrier or claim it has stopped.
                if status == "completed" && (final == nil || ended == nil) { return false }
                if status == "failed" && (turn["error"] as? [String:Any]) == nil { return false }
                guard status != "interrupted" else { return false }
                let code = (turn["error"] as? [String:Any])?["codexErrorInfo"] as? String
                let quotaFailure = status == "failed" && (code == "usageLimitExceeded" || code == "rateLimitExceeded")
                return handoffLedger.updateProgress(clientMessageID:record.id,turnID:turnID,status:status,excerpt:final?["text"] as? String,endedAt:ended,quotaFailureConfirmed:quotaFailure)
            }
            cursor = result["nextCursor"] as? String
            if cursor == nil { return false }
        }
        return false
    }
    private func cancelHandoff(_ record:HandoffRecord) async {
        do {
            try await taskConnection.connect()
            let entries = try await queueEntries(record.threadID)
            if let entry = entries.first(where: { $0["clientUserMessageId"] as? String == record.clientMessageID }),
               let queueID = entry["id"] as? String {
                guard handoffLedger.markQueued(clientMessageID:record.clientMessageID,queueID:queueID) else { throw ServiceError(message:"Cannot persist queue state") }
                let data = try await taskConnection.request("thread/queue/delete",params:["threadId":record.threadID,"queuedSubmissionId":queueID])
                let result = try JSONSerialization.jsonObject(with:data) as? [String:Any]
                if result?["deleted"] as? Bool == true {
                    _ = handoffLedger.markCancelled(clientMessageID:record.clientMessageID)
                    return
                }
            }
            if try await historyContains(record) { _ = handoffLedger.markHandedOff(clientMessageID:record.clientMessageID) }
            else { _ = handoffLedger.markUncertain(clientMessageID:record.clientMessageID) }
        } catch {
            _ = handoffLedger.markUncertain(clientMessageID:record.clientMessageID)
            resumeNotice = L10n.text("取消结果待核实，请在 Codex 查看")
        }
    }
    private func reconcileHandoffs() async {
        let reconciliationRevision = accountSnapshotRevision
        guard handoffLedger.refresh() else { resumeNotice = L10n.text("续跑记录无法读取，请检查本机存储"); return }
        for record in handoffLedger.visibleRecords where (record.state.unresolved || record.state == .handedOff) && record.accountID == limits?.accountId {
            do {
                if record.state == .handedOff {
                    let confirmed:Bool
                    if record.turnStatus == "completed" { confirmed = true }
                    else { confirmed = try await trackHandoff(record) }
                    if confirmed { resumeTrackingUnavailable.remove(record.id) }
                    else { resumeTrackingUnavailable.insert(record.id) }
                    continue
                }
                let entries = try await queueEntries(record.threadID)
                if let entry = entries.first(where: { $0["clientUserMessageId"] as? String == record.clientMessageID }),
                   let id = entry["id"] as? String {
                    guard handoffLedger.markQueued(clientMessageID:record.clientMessageID,queueID:id) else { continue }
                    if handoffLedger.authorizationState(record.authorizationID) == "revoked" { await cancelHandoff(record) }
                    else if isAutoResumeSelected(record.threadID), entries.first?["id"] as? String == id {
                        guard let currentTurn = try await latestResumeTurn(record.threadID) else {
                            resumeStatuses[record.threadID] = L10n.text("暂无法检查，请刷新或在 Codex 查看")
                            continue
                        }
                        let stillFailed = currentTurn.id == record.failedTurnID && (currentTurn.status == "failed" || currentTurn.status == "interrupted") && (currentTurn.errorCode == "usageLimitExceeded" || currentTurn.errorCode == "rateLimitExceeded")
                        if !stillFailed {
                            await cancelHandoff(record)
                            resumeStatuses[record.threadID] = L10n.text("任务状态已变化，请在 Codex 查看")
                        } else if handoffLedger.refresh(), isAutoResumeSelected(record.threadID), record.accountID == limits?.accountId,
                                  accountSnapshotVerified, reconciliationRevision == accountSnapshotRevision,
                                  handoffLedger.records.contains(where: { $0.id == record.id && $0.state == .queued }),
                                  handoffLedger.authorizationState(record.authorizationID) != "revoked",
                                  handoffLedger.permitsDispatch(accountID:record.accountID,primary:primary?.remaining,weekly:secondary?.remaining,quotaProfile:limits?.quotaProfile), error == nil {
                            resumeStatuses[record.threadID] = wakeThread(record.threadID) ? L10n.text("已排队，等待 Codex 处理") : L10n.text("已排队，请打开 Codex")
                        } else { resumeStatuses[record.threadID] = L10n.text("等待额度恢复") }
                    } else { resumeStatuses[record.threadID] = L10n.text("任务已有排队消息，请在 Codex 查看") }
                } else if try await historyContains(record) {
                    _ = handoffLedger.markHandedOff(clientMessageID:record.clientMessageID)
                    if try await trackHandoff(record) { resumeTrackingUnavailable.remove(record.id) }
                    else { resumeTrackingUnavailable.insert(record.id) }
                    resumeStatuses[record.threadID] = L10n.text("已交给 Codex，请在原任务查看")
                } else {
                    _ = handoffLedger.markUncertain(clientMessageID:record.clientMessageID)
                    resumeStatuses[record.threadID] = L10n.text("提交结果待核实，请在 Codex 查看")
                }
            } catch {
                resumeTrackingUnavailable.insert(record.id)
                resumeStatuses[record.threadID] = L10n.text("提交结果待核实，请在 Codex 查看")
            }
        }
        if accountSnapshotVerified, reconciliationRevision == accountSnapshotRevision, resumeNotificationsEnabled, let deliverResumeNotification {
            for record in handoffLedger.visibleRecords where record.accountID == limits?.accountId && ["completed","failed"].contains(record.turnStatus ?? "") {
                if handoffLedger.claimNotification(clientMessageID:record.id) { deliverResumeNotification(record) }
            }
        }
        objectWillChange.send()
    }
    func scanAutoResume() async {
        guard resumeLedger.refresh() else { resumeNotice = L10n.text("续跑记录无法读取，请检查本机存储"); return }
        guard !demo, !resumeScanning, error == nil, accountSnapshotVerified,
              !resumeLedger.selections.isEmpty || !handoffLedger.visibleRecords.isEmpty else { return }
        resumeScanning = true
        defer { resumeScanning = false }
        let previous = resumeLedger.lastQuotaObservation
        let current = quotaObservation()
        let scanRevision = accountSnapshotRevision
        defer {
            if let current, accountSnapshotVerified, scanRevision == accountSnapshotRevision { resumeLedger.recordQuotaObservation(current) }
            else { resumeLedger.clearQuotaObservation() }
        }
        do { try await taskConnection.connect() } catch { resumeNotice = L10n.text("暂无法检查，请刷新或在 Codex 查看"); return }
        await reconcileHandoffs()
        guard accountSnapshotVerified, scanRevision == accountSnapshotRevision else { return }
        var candidates:[(ResumeSelection,ResumeTurn)] = []
        // Inspect all selected tasks before updating the shared quota snapshot.
        for original in selectedResumeTasks {
            do {
                guard let turn = try await latestResumeTurn(original.threadID) else { continue }
                guard original.canAwaitFailure, original.dispatchedTurnID != turn.id,
                      handoffLedger.authorizationState(original.authorizationID) == "active" else { continue }
                // Never pick up quota failures that predate the user's choice.
                guard let selectedAt = original.selectedAt, let completed = turn.completedAt,
                      completed >= selectedAt, completed <= Date().timeIntervalSince1970 + 5 else { continue }
                let quotaFailure = (turn.status == "failed" || turn.status == "interrupted") && (turn.errorCode == "usageLimitExceeded" || turn.errorCode == "rateLimitExceeded")
                let observedZero = limits?.ordinaryUsageAllowed == false || primary?.remaining == 0 || secondary?.remaining == 0 || limits?.quotaProfile.otherWindows.contains(where: { $0.remaining == 0 }) == true
                let missedReset = current.map { !missedQuotaResetWindows(selection:original,turn:turn,previous:previous,current:$0).isEmpty } ?? false
                if quotaFailure && (observedZero || missedReset) { resumeLedger.waitForReset(threadID:original.threadID,turnID:turn.id,authorizationID:original.authorizationID) }
                guard let selection = resumeLedger.selections.first(where: { $0.threadID == original.threadID }) else { continue }
                if resumeEligible(selection,accountID:limits?.accountId,turn:turn,primaryRemaining:primary?.remaining,weeklyRemaining:secondary?.remaining,quotaProfile:limits?.quotaProfile) {
                    candidates.append((selection,turn))
                } else if selection.dispatchedTurnID != turn.id {
                    resumeStatuses[selection.threadID] = quotaFailure && selection.waitingTurnID == turn.id ? L10n.text("等待额度恢复") : L10n.text("已选中，等待额度中断")
                }
            } catch { resumeStatuses[original.threadID] = L10n.text("暂无法检查，请刷新或在 Codex 查看") }
        }
        guard handoffLedger.refresh(), !handoffLedger.hasDispatchBlocker, !handoffLedger.paused else { return }
        for (selection,turn) in candidates {
            do {
                let quotaData: Data
                do { quotaData = try await taskConnection.request("account/rateLimits/read") }
                catch {
                    guard expiredAuthentication(error) else { throw error }
                    taskConnection.disconnect(); try await taskConnection.connect()
                    quotaData = try await taskConnection.request("account/rateLimits/read")
                }
                let quota = try JSONDecoder().decode(LimitsResponse.self,from:quotaData)
                guard handoffLedger.refresh(), handoffLedger.permitsDispatch(accountID:selection.accountID,primary:quota.quotaProfile.fiveHour?.remaining,weekly:quota.quotaProfile.weekly?.remaining,quotaProfile:quota.quotaProfile) else { continue }
                guard resumeEligible(selection,accountID:quota.accountId,turn:turn,primaryRemaining:quota.quotaProfile.fiveHour?.remaining,weeklyRemaining:quota.quotaProfile.weekly?.remaining,quotaProfile:quota.quotaProfile),
                      (try await queueEntries(selection.threadID)).isEmpty else { continue }
                let loadedData = try await taskConnection.request("thread/loaded/list")
                guard let loaded = try JSONSerialization.jsonObject(with:loadedData) as? [String:Any],
                      let ids = loaded["data"] as? [String], loaded["nextCursor"] as? String == nil,
                      !ids.contains(selection.threadID) else { continue }
                let latest = try await latestResumeTurn(selection.threadID)
                guard latest == turn, isAutoResumeSelected(selection.threadID),
                      let selected = resumeLedger.selections.first(where: { $0.threadID == selection.threadID }),
                      resumeEligible(selected,accountID:limits?.accountId,turn:latest,primaryRemaining:primary?.remaining,weeklyRemaining:secondary?.remaining,quotaProfile:limits?.quotaProfile),
                      error == nil, accountSnapshotVerified, scanRevision == accountSnapshotRevision,
                      quota.quotaProfile.configurationID == limits?.quotaProfile.configurationID,
                      let authorizationID = selected.authorizationID,
                      let record = handoffLedger.begin(threadID:selection.threadID,accountID:selection.accountID,title:selection.title,failedTurnID:turn.id,primaryRemaining:quota.quotaProfile.fiveHour?.remaining,weeklyRemaining:quota.quotaProfile.weekly?.remaining,authorizationID:authorizationID,quotaProfile:quota.quotaProfile) else { continue }
                resumeLedger.markDispatched(threadID:selection.threadID,turnID:turn.id,authorizationID:authorizationID)
                activeHandoffSubmissionID = record.clientMessageID
                resumeStatuses[selection.threadID] = L10n.text("正在加入 Codex 队列…")
                do {
                    let resultData = try await taskConnection.request("thread/queue/add",params:[
                        "threadId":selection.threadID,"clientUserMessageId":record.clientMessageID,
                        "input":[["type":"text","text":"Continue the unfinished task that stopped because of the usage limit. First inspect existing files and completed actions so work is not repeated. Preserve the user's instructions and scope. If user input or approval is required, stop and ask. This continuation was enabled by the user in Usage Capsule."]]
                    ])
                    let result = try JSONSerialization.jsonObject(with:resultData) as? [String:Any]
                    let queued = result?["queuedSubmission"] as? [String:Any]
                    guard queued?["clientUserMessageId"] as? String == record.clientMessageID,
                          let queueID = queued?["id"] as? String,
                          handoffLedger.markQueued(clientMessageID:record.clientMessageID,queueID:queueID) else { throw ServiceError(message:"Queue response not confirmed") }
                    if !isAutoResumeSelected(selection.threadID) { await cancelHandoff(record) }
                    else { await reconcileHandoffs() }
                } catch {
                    _ = handoffLedger.markUncertain(clientMessageID:record.clientMessageID)
                    resumeStatuses[selection.threadID] = L10n.text("提交结果待核实，请在 Codex 查看")
                }
                _ = handoffLedger.finishSubmission(clientMessageID:record.clientMessageID)
                activeHandoffSubmissionID = nil
                objectWillChange.send()
                break
            } catch { resumeStatuses[selection.threadID] = L10n.text("暂无法检查，请刷新或在 Codex 查看") }
        }
    }
    func openResumeThread(_ id:String) {
        guard UUID(uuidString:id) != nil, let url = URL(string:"codex://threads/\(id)") else { return }
        NSWorkspace.shared.open(url)
    }
}
