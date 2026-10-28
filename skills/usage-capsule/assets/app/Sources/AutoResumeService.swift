import Foundation
import AppKit

@MainActor extension QuotaStore {
    var selectedResumeTasks: [ResumeSelection] {
        resumeLedger.selections.filter { $0.accountID == limits?.accountId }
    }
    func isAutoResumeSelected(_ id:String) -> Bool {
        selectedResumeTasks.contains { $0.threadID == id }
    }
    func toggleAutoResume(_ thread:ResumeThreadChoice) {
        guard !demo else { return }
        if isAutoResumeSelected(thread.id) {
            removeAutoResume(thread.id)
        } else if let accountID = limits?.accountId, error == nil {
            objectWillChange.send()
            resumeLedger.remove(threadID:thread.id)
            resumeLedger.select(threadID:thread.id,accountID:accountID,title:thread.title)
            resumeStatuses[thread.id] = L10n.text("已选中，等待额度中断")
        }
    }
    func removeAutoResume(_ id:String) {
        objectWillChange.send()
        resumeLedger.remove(threadID:id)
        resumeStatuses.removeValue(forKey:id)
        Task { await cancelResumeSelection(id) }
    }
    func cancelResumeSelection(_ id:String) async {
        objectWillChange.send()
        resumeLedger.remove(threadID:id)
        guard handoffLedger.refresh() else { resumeNotice = L10n.text("续跑记录无法读取，请检查本机存储"); return }
        for record in handoffLedger.visibleRecords where record.threadID == id && record.state.unresolved {
            await cancelHandoff(record)
        }
        objectWillChange.send()
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
                return ResumeThreadChoice(id:id,title:name.isEmpty ? String(id.prefix(12)) : String(name.prefix(120)),folder:row["cwd"] as? String ?? "")
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
        guard let account = limits?.accountId, let sampleTime = lastSync, let p = primary, let w = secondary,
              let pDuration=p.windowDurationMins, let wDuration=w.windowDurationMins else { return nil }
        return ResumeQuotaObservation(accountID:account,observedAt:sampleTime.timeIntervalSince1970,
            primary:ResumeQuotaWindowObservation(durationMinutes:pDuration,resetsAt:p.resetsAt,remaining:p.remaining),
            weekly:ResumeQuotaWindowObservation(durationMinutes:wDuration,resetsAt:w.resetsAt,remaining:w.remaining))
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
    private func historyContains(_ record:HandoffRecord) async throws -> Bool {
        var cursor:String?
        for _ in 0..<5 {
            var params:[String:Any] = ["threadId":record.threadID,"limit":100,"sortDirection":"desc"]
            if let cursor { params["cursor"] = cursor }
            let data = try await taskConnection.request("thread/items/list",params:params)
            guard let result = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let rows = result["data"] as? [[String:Any]] else { throw ServiceError(message:"Invalid history response") }
            if rows.contains(where: { row in
                let item = row["item"] as? [String:Any]
                return item?["type"] as? String == "userMessage" && item?["clientId"] as? String == record.clientMessageID
            }) { return true }
            cursor = result["nextCursor"] as? String
            if cursor == nil { break }
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
        guard handoffLedger.refresh() else { resumeNotice = L10n.text("续跑记录无法读取，请检查本机存储"); return }
        for record in handoffLedger.visibleRecords where record.state.unresolved && record.accountID == limits?.accountId {
            do {
                let entries = try await queueEntries(record.threadID)
                if let entry = entries.first(where: { $0["clientUserMessageId"] as? String == record.clientMessageID }),
                   let id = entry["id"] as? String {
                    guard handoffLedger.markQueued(clientMessageID:record.clientMessageID,queueID:id) else { continue }
                    if !isAutoResumeSelected(record.threadID) { await cancelHandoff(record) }
                    else if entries.first?["id"] as? String == id {
                        guard let currentTurn = try await latestResumeTurn(record.threadID) else {
                            resumeStatuses[record.threadID] = L10n.text("暂无法检查，请刷新或在 Codex 查看")
                            continue
                        }
                        let stillFailed = currentTurn.id == record.failedTurnID && (currentTurn.status == "failed" || currentTurn.status == "interrupted") && (currentTurn.errorCode == "usageLimitExceeded" || currentTurn.errorCode == "rateLimitExceeded")
                        if !stillFailed {
                            await cancelHandoff(record)
                            resumeStatuses[record.threadID] = L10n.text("任务状态已变化，请在 Codex 查看")
                        } else if let daily = primary?.remaining, daily > 0, let weekly = secondary?.remaining, weekly > 0, error == nil {
                            resumeStatuses[record.threadID] = wakeThread(record.threadID) ? L10n.text("已排队，等待 Codex 处理") : L10n.text("已排队，请打开 Codex")
                        } else { resumeStatuses[record.threadID] = L10n.text("等待额度恢复") }
                    } else { resumeStatuses[record.threadID] = L10n.text("任务已有排队消息，请在 Codex 查看") }
                } else if try await historyContains(record) {
                    _ = handoffLedger.markHandedOff(clientMessageID:record.clientMessageID)
                    resumeStatuses[record.threadID] = L10n.text("已交给 Codex，请在原任务查看")
                } else {
                    _ = handoffLedger.markUncertain(clientMessageID:record.clientMessageID)
                    resumeStatuses[record.threadID] = L10n.text("提交结果待核实，请在 Codex 查看")
                }
            } catch {
                resumeStatuses[record.threadID] = L10n.text("提交结果待核实，请在 Codex 查看")
            }
        }
        objectWillChange.send()
    }
    func scanAutoResume() async {
        guard !demo, !resumeScanning, error == nil,
              !resumeLedger.selections.isEmpty || !handoffLedger.visibleRecords.isEmpty else { return }
        resumeScanning = true
        defer { resumeScanning = false }
        let previous = resumeLedger.lastQuotaObservation
        let current = quotaObservation()
        defer { if let current { resumeLedger.recordQuotaObservation(current) } }
        do { try await taskConnection.connect() } catch { resumeNotice = L10n.text("暂无法检查，请刷新或在 Codex 查看"); return }
        await reconcileHandoffs()
        var candidates:[(ResumeSelection,ResumeTurn)] = []
        // Inspect all selected tasks before updating the shared quota snapshot.
        for original in selectedResumeTasks {
            do {
                guard let turn = try await latestResumeTurn(original.threadID) else { continue }
                let quotaFailure = (turn.status == "failed" || turn.status == "interrupted") && (turn.errorCode == "usageLimitExceeded" || turn.errorCode == "rateLimitExceeded")
                let observedZero = primary?.remaining == 0 || secondary?.remaining == 0
                let missedReset = current.map { !missedQuotaResetWindows(selection:original,turn:turn,previous:previous,current:$0).isEmpty } ?? false
                if quotaFailure && (observedZero || missedReset) { resumeLedger.waitForReset(threadID:original.threadID,turnID:turn.id) }
                guard let selection = resumeLedger.selections.first(where: { $0.threadID == original.threadID }) else { continue }
                if resumeEligible(selection,accountID:limits?.accountId,turn:turn,primaryRemaining:primary?.remaining,weeklyRemaining:secondary?.remaining) {
                    candidates.append((selection,turn))
                } else if selection.dispatchedTurnID != turn.id {
                    resumeStatuses[selection.threadID] = quotaFailure && selection.waitingTurnID == turn.id ? L10n.text("等待额度恢复") : L10n.text("已选中，等待额度中断")
                }
            } catch { resumeStatuses[original.threadID] = L10n.text("暂无法检查，请刷新或在 Codex 查看") }
        }
        guard handoffLedger.refresh(), !handoffLedger.hasUnresolved else { return }
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
                guard resumeEligible(selection,accountID:quota.accountId,turn:turn,primaryRemaining:quota.bucket?.primary?.remaining,weeklyRemaining:quota.bucket?.secondary?.remaining),
                      (try await queueEntries(selection.threadID)).isEmpty else { continue }
                let loadedData = try await taskConnection.request("thread/loaded/list")
                guard let loaded = try JSONSerialization.jsonObject(with:loadedData) as? [String:Any],
                      let ids = loaded["data"] as? [String], loaded["nextCursor"] as? String == nil,
                      !ids.contains(selection.threadID) else { continue }
                let latest = try await latestResumeTurn(selection.threadID)
                guard latest == turn, isAutoResumeSelected(selection.threadID),
                      let selected = resumeLedger.selections.first(where: { $0.threadID == selection.threadID }),
                      resumeEligible(selected,accountID:limits?.accountId,turn:latest,primaryRemaining:primary?.remaining,weeklyRemaining:secondary?.remaining),
                      let record = handoffLedger.begin(threadID:selection.threadID,accountID:selection.accountID,title:selection.title,failedTurnID:turn.id) else { continue }
                resumeLedger.markDispatched(threadID:selection.threadID,turnID:turn.id)
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
