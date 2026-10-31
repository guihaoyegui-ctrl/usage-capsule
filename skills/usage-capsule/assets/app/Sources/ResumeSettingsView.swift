import SwiftUI

struct ResumeSettingsView: View {
    @ObservedObject var store: QuotaStore
    @ViewState private var tab = 0
    @ViewState private var search = ""
    @ViewState private var rules = false
    @ViewState private var selectionMode:ResumeMode = .once
    @ViewState private var releaseCandidate:HandoffRecord?
    private let warm = Color(red:1,green:0.70,blue:0.42)
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            header
            if let notice = store.resumeNotice ?? store.error ?? (store.handoffLedger.storageCorrupted ? L10n.text("续跑记录无法读取，请检查本机存储") : nil) {
                Text(notice).font(.caption).foregroundStyle(warm).fixedSize(horizontal:false,vertical:true)
            }
            Picker(L10n.text("续跑管理"),selection:$tab) {
                Text(L10n.text("已授权任务")).tag(0)
                Text(L10n.text("选择任务")).tag(1)
                Text(L10n.text("续跑记录")).tag(2)
            }.pickerStyle(.segmented)
            if tab == 0 { selectedList } else if tab == 1 { choices } else { records }
            Divider()
            rulesSection
            Text(L10n.text("续跑会消耗额度；仅在胶囊运行且电脑唤醒时检查。重置卡每次仍需你确认。"))
                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
        .padding(22).frame(width:480,height:650)
        .background(LinearGradient(colors:[Color(white:0.13),Color(white:0.075)],startPoint:.topLeading,endPoint:.bottomTrailing))
        .foregroundStyle(Color(white:0.93))
        .preferredColorScheme(.dark).tint(warm)
        .onAppear { if store.resumeLedger.selections.isEmpty { tab = 1 } }
        .alert(L10n.text("确认放行下一项？"),isPresented:Binding(get:{releaseCandidate != nil},set:{if !$0 { releaseCandidate = nil }})) {
            Button(L10n.text("取消"),role:.cancel) { releaseCandidate = nil }
            Button(L10n.text("已核实，放行下一项")) {
                if let candidate = releaseCandidate { store.releaseResumeHandoff(candidate) }
                releaseCandidate = nil
            }
        } message: { Text(L10n.text("请先在原对话核实当前任务；放行不会停止它，下一项可能与它同时消耗额度。")) }
    }
    private var header:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:5) {
                    HStack(spacing:7) {
                        Image(systemName:"waveform.path").foregroundStyle(warm)
                        Text(L10n.text("自动续跑")).font(.system(size:21,weight:.semibold))
                        Text(L10n.text("预览")).font(.system(size:10)).foregroundStyle(warm).padding(4).background(warm.opacity(0.10),in:Capsule())
                    }
                    Text(L10n.text("选择单次或持续模式；额度恢复后接续原任务。")).font(.system(size:12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.setResumePaused(!store.resumeIsPaused) } label: {
                    Label(store.resumeIsPaused ? L10n.text("恢复监测") : L10n.text("暂停续跑"),systemImage:store.resumeIsPaused ? "play.fill" : "pause.fill")
                }.disabled(store.demo)
            }
            HStack {
                Label(store.resumeSummary,systemImage:store.resumeOverviewStage.symbol).font(.system(size:12)).foregroundStyle(warm)
                Spacer()
                if store.refreshing { ProgressView().controlSize(.small) }
                Button { Task { await store.refresh() } } label: { Image(systemName:"arrow.clockwise") }
                    .buttonStyle(.plain).help(L10n.text("刷新用量")).disabled(store.refreshing || store.demo)
            }.padding(11).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:10))
            if store.resumeIsPaused {
                Text(L10n.text("已停止新增交接；排队和正在执行的任务请分别取消或在原对话停止。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    private var selectedList:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(L10n.format("%@ 项有效授权",String(store.activeResumeSelections.count))).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("取消全部授权")) { for item in store.resumeLedger.selections { store.removeAutoResume(item.threadID) } }
                    .buttonStyle(.plain).disabled(store.resumeLedger.selections.isEmpty || store.demo)
            }
            ScrollView {
                LazyVStack(spacing:9) {
                    if store.resumeLedger.selections.isEmpty { empty(L10n.text("还没有授权任务"),symbol:"checkmark.shield") }
                    ForEach(Array(store.resumeLedger.selections.enumerated()),id:\.element.id) { index,item in
                        VStack(alignment:.leading,spacing:9) {
                            HStack(alignment:.top,spacing:10) {
                                Text(String(index+1)).font(.system(size:12,design:.monospaced)).foregroundStyle(warm).frame(width:20)
                                VStack(alignment:.leading,spacing:6) {
                                    Text(item.title).font(.system(size:13,weight:.medium)).lineLimit(2).help(item.title)
                                    Label(store.stage(for:item).label,systemImage:store.stage(for:item).symbol).font(.caption).foregroundStyle(.secondary)
                                    if item.authorizationVersion == 2 { Text(item.effectiveMode.label).font(.caption2).foregroundStyle(warm) }
                                    if let status = store.resumeStatuses[item.threadID], item.canAwaitFailure { Text(status).font(.caption2).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength:0)
                                openButton(item.threadID)
                            }
                            HStack(spacing:10) {
                                Button { store.moveResumeTask(item.threadID,offset:-1) } label: { Image(systemName:"arrow.up") }.help(L10n.text("提高优先级")).disabled(index == 0)
                                Button { store.moveResumeTask(item.threadID,offset:1) } label: { Image(systemName:"arrow.down") }.help(L10n.text("降低优先级")).disabled(index == store.resumeLedger.selections.count-1)
                                Spacer()
                                Menu(L10n.text("续跑模式")) {
                                    Button(L10n.text("授权：仅续跑一次")) { store.renewResumeAuthorization(item,mode:.once) }
                                    Button(L10n.text("授权：持续续跑（不限次数）")) { store.renewResumeAuthorization(item,mode:.continuous) }
                                }.disabled(item.accountID != store.limits?.accountId || store.error != nil || store.handoffLedger.records.contains { $0.threadID == item.threadID && $0.blocksDispatch })
                                Button(L10n.text("取消授权")) { store.removeAutoResume(item.threadID) }
                            }.font(.system(size:11)).buttonStyle(.borderless).disabled(store.demo)
                        }.padding(12).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
                    }
                }
            }
        }.frame(maxHeight:.infinity)
    }
    private var choices:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                TextField(L10n.text("搜索已加载的任务或项目"),text:$search).textFieldStyle(.roundedBorder)
                if store.loadingThreads { ProgressView().controlSize(.small) }
                Button(L10n.text("刷新列表")) { Task { await store.loadRecentThreads() } }.disabled(store.loadingThreads || store.demo)
            }
            Picker(L10n.text("新增任务的续跑模式"),selection:$selectionMode) {
                ForEach(ResumeMode.allCases,id:\.self) { mode in Text(mode.label).tag(mode) }
            }.pickerStyle(.segmented)
            Text(L10n.text("勾选即授权所选模式；仅接续授权后发生的额度中断，随时取消。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:0) {
                    if store.filteredResumeChoices(search).isEmpty { empty(L10n.text("当前已加载列表中没有匹配任务"),symbol:"magnifyingglass") }
                    ForEach(store.filteredResumeChoices(search)) { thread in
                        Toggle(isOn:Binding(get:{store.isAutoResumeSelected(thread.id)},set:{_ in store.toggleAutoResume(thread,mode:selectionMode)})) {
                            VStack(alignment:.leading,spacing:4) {
                                Text(thread.title).font(.system(size:13)).lineLimit(2).help(thread.title)
                                if !thread.folder.isEmpty { Text(URL(fileURLWithPath:thread.folder).lastPathComponent).font(.caption).foregroundStyle(.secondary).help(thread.folder) }
                            }.padding(.vertical,9)
                        }.toggleStyle(.checkbox).disabled(store.demo || store.limits?.accountId == nil || store.error != nil)
                        Divider().opacity(0.5)
                    }
                    if store.resumeListCursor != nil { Button(L10n.text("加载更多")) { Task { await store.loadRecentThreads(more:true) } }.padding(.top,10).disabled(store.loadingThreads) }
                }
            }
            Text(L10n.format("已加载 %@ 项；搜索仅包含已加载的列表。",String(store.recentThreads.count))).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxHeight:.infinity)
    }
    private var records:some View {
        ScrollView {
            LazyVStack(spacing:10) {
                if store.handoffLedger.visibleRecords.isEmpty { empty(L10n.text("还没有续跑记录"),symbol:"tray") }
                ForEach(store.handoffLedger.visibleRecords.reversed()) { item in
                    VStack(alignment:.leading,spacing:9) {
                        HStack(alignment:.top) {
                            VStack(alignment:.leading,spacing:5) {
                                Text(item.title).font(.system(size:13,weight:.medium)).lineLimit(2).help(item.title)
                                Label(store.stage(for:item).label,systemImage:store.stage(for:item).symbol).font(.caption).foregroundStyle(warm)
                            }
                            Spacer(minLength:0)
                            openButton(item.threadID)
                        }
                        Text(store.detail(for:item)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        if let excerpt = item.excerpt, !excerpt.isEmpty {
                            Text(excerpt).font(.system(size:12)).lineLimit(4).textSelection(.enabled).padding(9).frame(maxWidth:.infinity,alignment:.leading).background(.black.opacity(0.15),in:RoundedRectangle(cornerRadius:7))
                        }
                        HStack {
                            if let time = item.endedAt ?? item.createdAt { Text(Date(timeIntervalSince1970:time),format:.dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                            if item.state == .queued { Button(L10n.text("取消排队")) { Task { await store.cancelResumeSelection(item.threadID) } } }
                            else if item.state == .uncertain || item.state == .submitting {
                                Button(L10n.text("已核实，清除")) { store.clearHandoff(item.id,acknowledge:true) }
                                    .disabled(store.activeHandoffSubmissionID == item.id || !store.handoffLedger.canAcknowledge(item)).help(L10n.text("请先在 Codex 确认任务状态"))
                            } else if item.blocksDispatch {
                                Button(L10n.text("核实后放行下一项")) { releaseCandidate = item }
                                    .disabled(item.accountID != store.limits?.accountId || store.activeHandoffSubmissionID == item.id)
                            } else { Button(L10n.text("清除记录")) { store.clearHandoff(item.id) } }
                        }.font(.system(size:11)).buttonStyle(.borderless).disabled(store.demo)
                    }.padding(12).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
                }
            }
        }.frame(maxHeight:.infinity)
    }
    private var rulesSection:some View {
        DisclosureGroup(L10n.text("续跑规则与通知"),isExpanded:$rules) {
            VStack(alignment:.leading,spacing:9) {
                HStack {
                    if !store.primaryUnlimited { Text(L10n.text("保留日额")); reservePicker(primary:true) }
                    Text(L10n.text("保留周额")); reservePicker(primary:false)
                }
                Text(L10n.text("持续模式会在每次额度恢复后续跑；正常回复结束、等待你处理或其他错误不会自动开始新一轮。")).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text(L10n.text("低于保留值时不再派发；无法限制已运行任务的实际消耗。")).font(.caption2).foregroundStyle(.secondary)
                Toggle(L10n.text("本轮结束或出错时通知"),isOn:Binding(get:{store.resumeNotificationsEnabled},set:{store.configureResumeNotifications?($0)}))
                    .disabled(store.configureResumeNotifications == nil || store.demo)
                if let notice = store.resumeNotificationNotice { Text(notice).font(.caption2).foregroundStyle(.secondary) }
                if let sync = store.lastSync { HStack { Text(L10n.text("最近额度更新")); Text(sync,style:.time).monospacedDigit() }.font(.caption2).foregroundStyle(.secondary) }
            }.font(.system(size:11)).padding(.top,8)
        }.font(.system(size:12)).disabled(store.demo)
    }
    private func reservePicker(primary:Bool) -> some View {
        Picker(primary ? L10n.text("保留日额") : L10n.text("保留周额"),selection:Binding(get:{primary ? store.resumeReserve.primary : store.resumeReserve.weekly},set:{ value in
            store.setResumeReserve(primary:primary ? value : store.resumeReserve.primary,weekly:primary ? store.resumeReserve.weekly : value)
        })) { ForEach([0,10,20,30,50,70,90],id:\.self) { level in Text("\(level)%").tag(Double(level)) } }
            .labelsHidden().frame(width:68).disabled(store.limits?.accountId == nil || store.error != nil)
    }
    private func openButton(_ id:String) -> some View {
        Button { store.openResumeThread(id) } label: { Image(systemName:"arrow.up.right.square").frame(width:24,height:24) }
            .buttonStyle(.plain).help(L10n.text("在 Codex 查看")).accessibilityLabel(L10n.text("在 Codex 查看"))
    }
    private func empty(_ text:String,symbol:String) -> some View {
        VStack(spacing:10) { Image(systemName:symbol).font(.system(size:25,weight:.light)).foregroundStyle(warm.opacity(0.7)); Text(text).font(.system(size:13)).foregroundStyle(.secondary) }
            .frame(maxWidth:.infinity).padding(.vertical,46)
    }
}
