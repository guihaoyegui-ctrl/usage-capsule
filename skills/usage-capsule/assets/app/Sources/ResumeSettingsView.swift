import SwiftUI

struct ResumeSettingsView: View {
    @ObservedObject var store: QuotaStore
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(L10n.text("自动续跑")).font(.title2.weight(.medium))
                Spacer()
                if !store.resumeLedger.selections.isEmpty {
                    Button(L10n.text("全部取消")) {
                        for item in store.resumeLedger.selections { store.removeAutoResume(item.threadID) }
                    }
                }
            }
            Text(L10n.text("只续跑你选中的任务。额度恢复后，任务会逐个交给 Codex 在原对话继续。"))
                .font(.callout).foregroundStyle(.secondary)
            if !store.resumeLedger.selections.isEmpty {
                Text(L10n.text("已选任务")).font(.headline)
                ScrollView {
                    VStack(alignment:.leading,spacing:9) {
                        ForEach(store.resumeLedger.selections) { item in
                            HStack(alignment:.top,spacing:8) {
                                VStack(alignment:.leading,spacing:3) {
                                    Text(item.title).lineLimit(1)
                                    Text(item.accountID == store.limits?.accountId
                                         ? (store.resumeStatuses[item.threadID] ?? L10n.text("已选中，等待额度中断"))
                                         : L10n.text("等待原账号登录"))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength:0)
                                Button { store.openResumeThread(item.threadID) } label: { Image(systemName:"arrow.up.right.square") }
                                    .help(L10n.text("在 Codex 查看"))
                                Button { store.removeAutoResume(item.threadID) } label: { Image(systemName:"xmark") }
                                    .help(L10n.text("取消选择"))
                            }.buttonStyle(.borderless)
                        }
                    }
                }.frame(maxHeight:80)
                Divider()
            }
            if !store.handoffLedger.visibleRecords.isEmpty {
                Text(L10n.text("续跑记录")).font(.headline)
                ScrollView {
                    VStack(alignment:.leading,spacing:8) {
                        ForEach(store.handoffLedger.visibleRecords) { item in
                            HStack(alignment:.top,spacing:8) {
                                VStack(alignment:.leading,spacing:3) {
                                    Text(item.title).lineLimit(1)
                                    Text(handoffLabel(item)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength:0)
                                Button { store.openResumeThread(item.threadID) } label: { Image(systemName:"arrow.up.right.square") }.help(L10n.text("在 Codex 查看"))
                                if item.state == .queued {
                                    Button(L10n.text("取消排队")) { Task { await store.cancelResumeSelection(item.threadID) } }
                                } else if item.state == .uncertain || item.state == .submitting {
                                    Button(L10n.text("已核实，清除")) { store.clearHandoff(item.id,acknowledge:true) }
                                        .disabled(store.activeHandoffSubmissionID == item.id || !store.handoffLedger.canAcknowledge(item))
                                        .help(L10n.text("请先在 Codex 确认任务状态"))
                                } else {
                                    Button { store.clearHandoff(item.id) } label: { Image(systemName:"xmark") }.help(L10n.text("清除记录"))
                                }
                            }.buttonStyle(.borderless)
                        }
                    }
                }.frame(maxHeight:110)
                Divider()
            }
            HStack {
                Text(L10n.text("选择任务")).font(.headline)
                Spacer()
                if store.loadingThreads { ProgressView().controlSize(.small) }
                Button(L10n.text("刷新列表")) { Task { await store.loadRecentThreads() } }
                    .disabled(store.loadingThreads || store.demo)
            }
            if let notice = store.resumeNotice { Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    if store.recentThreads.isEmpty && !store.loadingThreads {
                        Text(L10n.text("暂无可选任务，请登录 Codex 后刷新列表")).foregroundStyle(.secondary)
                    }
                    ForEach(store.recentThreads) { thread in
                        Toggle(isOn:Binding(get:{store.isAutoResumeSelected(thread.id)},set:{_ in store.toggleAutoResume(thread)})) {
                            VStack(alignment:.leading,spacing:2) {
                                Text(thread.title).lineLimit(2)
                                if !thread.folder.isEmpty {
                                    Text(URL(fileURLWithPath:thread.folder).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.toggleStyle(.checkbox)
                            .disabled(store.demo || store.limits?.accountId == nil || store.error != nil)
                    }
                    if store.resumeListCursor != nil {
                        Button(L10n.text("加载更多")) { Task { await store.loadRecentThreads(more:true) } }.disabled(store.loadingThreads)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,4)
            }.frame(maxHeight:.infinity)
            Divider()
            Text(L10n.text("续跑会消耗额度。请保持胶囊运行；无法确认中断原因时不会自动继续。已开始的任务可在 Codex 中停止，审批仍由你决定。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width:430,height:520)
    }
    private func handoffLabel(_ item:HandoffRecord) -> String {
        switch item.state {
        case .submitting, .uncertain: return L10n.text("提交结果待核实，请在 Codex 查看")
        case .queued: return L10n.text("已排队，等待 Codex 处理")
        case .handedOff: return L10n.text("已交给 Codex，请在原任务查看")
        case .cancelled: return L10n.text("已取消排队")
        case .acknowledged: return L10n.text("已核实")
        }
    }
}
