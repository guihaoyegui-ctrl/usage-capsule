import SwiftUI
import AppKit

typealias ViewState<Value> = SwiftUI.State<Value>

enum Forge {
    static let orange = Color(red:0.78,green:0.36,blue:0.14)
    static let amber = Color(red:1.0,green:0.69,blue:0.35)
    static let text = Color(red:0.94,green:0.91,blue:0.85)
    static let muted = Color(red:0.66,green:0.68,blue:0.67)
    static let background = Color(red:0.16,green:0.18,blue:0.19)
    static let screen = Color(red:0.085,green:0.095,blue:0.10)
    static let line = Color.white.opacity(0.11)
}

private extension QuotaColorTier {
    var lampTop:Color {
        switch self {
        case .paleGold: return Color(red:1,green:0.85,blue:0.57)
        case .amber: return Color(red:1,green:0.75,blue:0.40)
        case .orange: return Color(red:1,green:0.65,blue:0.31)
        case .vermilion: return Color(red:1,green:0.52,blue:0.28)
        case .coralRed: return Color(red:1,green:0.43,blue:0.45)
        }
    }
    var lampBottom:Color {
        switch self {
        case .paleGold: return Color(red:1,green:0.69,blue:0.33)
        case .amber: return Color(red:1,green:0.60,blue:0.24)
        case .orange: return Color(red:1,green:0.48,blue:0.18)
        case .vermilion: return Color(red:0.98,green:0.35,blue:0.17)
        case .coralRed: return Color(red:1,green:0.25,blue:0.30)
        }
    }
}

struct BatteryBar: View {
    var remaining: Double?
    var count = 10
    var height: CGFloat = 5
    var scale:CGFloat = 1
    var body: some View {
        let tier=quotaColorTier(remaining:remaining)
        let level=tier == nil ? 0 : min(100,remaining ?? 0)
        let compact=height <= 4*scale
        return HStack(spacing:(compact ? 1.5 : 2.5)*scale) {
            ForEach(0..<count,id:\.self) { i in
                GeometryReader { geo in
                    let fill = max(0,min(1,(level/100)*Double(count)-Double(i)))
                    ZStack(alignment:.leading) {
                        RoundedRectangle(cornerRadius:1.2*scale).fill(Color(white:0.11))
                            .overlay(RoundedRectangle(cornerRadius:1.2*scale).strokeBorder(.white.opacity(0.055),lineWidth:0.35*scale))
                        if fill > 0, let tier {
                            RoundedRectangle(cornerRadius:1.2*scale)
                                .fill(LinearGradient(colors:[tier.lampTop,tier.lampBottom],startPoint:.top,endPoint:.bottom))
                                .opacity(glowStrength(remaining:remaining))
                                .frame(width:geo.size.width*fill)
                                .overlay(RoundedRectangle(cornerRadius:1.2*scale).strokeBorder(.white.opacity(0.42),lineWidth:0.4*scale))
                                .shadow(color:tier.lampTop.opacity(0.48),radius:(compact ? 2.1 : 3.5)*scale)
                        }
                    }
                }
            }
        }.frame(height:height)
        .accessibilityLabel(L10n.format("可用 %@", String(describing: (percentLabel(remaining)))))
    }
}

struct CompactView: View {
    @ObservedObject var store: QuotaStore
    var hover: (Bool)->Void
    var click: ()->Void
    var dragChanged:(Bool)->Void
    var menu:()->NSMenu
    var body: some View {
        CapsuleInteraction(
            content:AnyView(CapsuleFace(primary:store.displayedPrimary?.remaining,weekly:store.secondary?.remaining,scale:CGFloat(store.scale),primaryUnlimited:store.primaryUnlimited,primaryLabel:store.displayedPrimaryLabel)
                .overlay(alignment:.topTrailing) {
                    if store.resumeNeedsDot {
                        Circle().fill(store.resumeOverviewStage == .review ? Forge.amber : Forge.text.opacity(0.8))
                            .frame(width:4*store.scale,height:4*store.scale).padding(.top,11*store.scale).padding(.trailing,25*store.scale)
                            .allowsHitTesting(false)
                    }
                }.accessibilityHidden(true).padding(8)),
            label:L10n.format("%@ %@，周额 %@",store.displayedPrimaryLabel,store.primaryUnlimited ? "∞" : percentLabel(store.displayedPrimary?.remaining),percentLabel(store.secondary?.remaining)),
            hover:hover,press:click,dragChanged:dragChanged,menu:menu)
            .frame(width:184*store.scale+16,height:60*store.scale+16)
    }
}

struct CapsuleFace:View {
    var primary:Double?
    var weekly:Double?
    var scale:CGFloat = 1
    var primaryUnlimited = false
    var primaryLabel:String? = nil
    var body:some View {
        HStack(spacing:11*scale) {
            reading(primary,label:primaryLabel ?? L10n.text("日额"),unlimited:primaryUnlimited)
            Rectangle().fill(LinearGradient(colors:[.clear,.white.opacity(0.23),.clear],startPoint:.top,endPoint:.bottom)).frame(width:0.5,height:34*scale)
            reading(weekly,label:L10n.text("周额"))
        }
        .padding(.horizontal,25*scale).padding(.vertical,9*scale)
        .frame(width:184*scale,height:60*scale)
        .background(PolishedShell(radius:30*scale))
        .shadow(color:.black.opacity(0.23),radius:3,y:3)
        .foregroundStyle(Forge.text)
    }
    private func reading(_ remaining:Double?,label:String,unlimited:Bool = false) -> some View {
        VStack(alignment:.leading,spacing:2.5*scale) {
            Text(label).font(.system(size:8*scale,weight:.medium)).foregroundStyle(Forge.text.opacity(0.73))
            HStack(alignment:.firstTextBaseline,spacing:1*scale) {
                Text(unlimited ? "∞" : (remaining.map { String(format:"%.0f",$0) } ?? "—"))
                    .font(.system(size:(unlimited ? 28 : 23)*scale,weight:.semibold)).monospacedDigit().tracking(-0.6*scale)
                if remaining != nil && !unlimited { Text("%").font(.system(size:11*scale,weight:.medium)).foregroundStyle(Forge.text.opacity(0.90)) }
            }.frame(height:23*scale,alignment:.leading)
            if unlimited {
                Capsule().fill(LinearGradient(colors:[Forge.amber,Forge.orange.opacity(0.2)],startPoint:.leading,endPoint:.trailing)).frame(width:40*scale,height:1.5*scale).frame(height:3.7*scale)
            } else { BatteryBar(remaining:remaining,height:3.7*scale,scale:scale) }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

struct OverviewView: View {
    @ObservedObject var store: QuotaStore
    var hover: (Bool)->Void
    var onPin: ()->Void
    var onClose: ()->Void
    var body: some View {
        TimelineView(.periodic(from:Date(),by:1)) { context in
            VStack(alignment:.leading,spacing:7) {
                header
                Text(L10n.format("会员与用量 · 每 %@ 秒检查",String(Int(QuotaStore.refreshInterval))))
                    .font(.system(size:8.5)).foregroundStyle(Forge.muted)
                    .help(L10n.text("也会在手动刷新、收到账号更新通知或电脑唤醒时检查；并非实时监控，不调用模型。"))
                if let error = store.error {
                    HStack(alignment:.top,spacing:5) {
                        Image(systemName:"wifi.exclamationmark")
                        Text(store.lastSync == nil ? error : L10n.text("更新失败，显示上次数据")).lineLimit(2)
                        Spacer(minLength:0)
                        Button(L10n.text("登录")) { Task { await store.login() } }.buttonStyle(.plain).foregroundStyle(Forge.amber)
                    }.font(.system(size:10)).foregroundStyle(Forge.muted).help(error)
                }
                if store.primaryUnlimited { unlimitedSection }
                else { quotaSection(store.displayedPrimary,label:store.displayedPrimaryLabel,now:context.date) }
                quotaSection(store.secondary,label:L10n.text("周额"),now:context.date)
                ForEach(Array((store.limits?.quotaProfile.otherWindows ?? []).dropFirst(store.primary == nil && !store.primaryUnlimited ? 1 : 0).enumerated()),id:\.offset) { _,window in
                    quotaSection(window,label:window.title,now:context.date)
                }
                dailySection
                resetSection
                VStack(alignment:.leading,spacing:5) {
                  Button { store.openResumeSettings?() } label: {
                    HStack(spacing:5) {
                        Image(systemName:store.resumeOverviewStage.symbol)
                        Text(L10n.text("自动续跑"))
                        Spacer()
                        Text(L10n.format("%@ 个任务",String(store.activeResumeSelections.count)))
                        Image(systemName:"chevron.right").font(.system(size:8))
                    }.font(.system(size:10)).foregroundStyle(Forge.muted).padding(.vertical,3)
                  }.buttonStyle(.plain).disabled(store.demo)
                  if store.resumeNeedsDot || store.resumeIsPaused {
                    HStack(spacing:4) {
                        Text(store.resumeOverviewStage == .review ? L10n.text("需要你核实，请打开原对话") : store.resumeSummary).lineLimit(1)
                        Spacer(minLength:0)
                        Button(store.resumeIsPaused ? L10n.text("恢复") : L10n.text("暂停")) { store.setResumePaused(!store.resumeIsPaused) }
                            .buttonStyle(.plain).foregroundStyle(Forge.amber)
                    }.font(.system(size:9)).foregroundStyle(Forge.muted)
                    if let next = store.activeResumeSelections.first {
                        Text(next.title).font(.system(size:9)).lineLimit(1).foregroundStyle(Forge.muted).help(next.title)
                    }
                  }
                }
                footer
            }
            .padding(.horizontal,16).padding(.vertical,14).frame(width:248).frame(minHeight:324,alignment:.top)
            .background(PolishedShell(radius:21))
            .shadow(color:.black.opacity(0.20),radius:5,y:3)
            .foregroundStyle(Forge.text).onHover(perform:hover)
        }
    }
    private var header:some View {
        HStack(spacing:4) {
            Text(L10n.text("概览")).font(.system(size:14,weight:.medium))
            Text(store.membershipLabel).font(.system(size:9,weight:.medium)).lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(Forge.amber).padding(.horizontal,6).padding(.vertical,3)
                .background(Forge.amber.opacity(0.10),in:Capsule())
                .help(L10n.text("会员等级来自本次账号用量读取；检测失败时保留上次确认标记，不猜测会员等级。"))
            Spacer()
            icon(store.pinned ? "pin.fill" : "pin",label:store.pinned ? L10n.text("取消固定") : L10n.text("固定概览"),action:onPin)
                .foregroundStyle(store.pinned ? Forge.amber : Forge.muted)
            icon("arrow.clockwise",label:L10n.text("刷新用量"),action:{Task { await store.refresh() }})
                .disabled(store.refreshing || store.redeeming)
            icon("xmark",label:L10n.text("关闭概览"),action:onClose)
        }.frame(height:20)
    }
    private func icon(_ name:String,label:String,action:@escaping ()->Void) -> some View {
        Button(action:action) {
            Image(systemName:name).font(.system(size:10,weight:.medium)).frame(width:21,height:22).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Forge.muted).help(label).accessibilityLabel(label)
    }
    private var unlimitedSection:some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(alignment:.firstTextBaseline) {
                Text(L10n.text("日额")).font(.system(size:12,weight:.medium))
                Spacer()
                Text("∞").font(.system(size:25,weight:.medium)).foregroundStyle(Forge.text)
            }
            Text(L10n.text("五小时不限额")).font(.system(size:9)).foregroundStyle(Forge.muted)
        }.help(L10n.text("仅表示没有五小时额度上限；周额度和其他实际限制仍然适用。"))
    }
    private func quotaSection(_ window:QuotaWindow?,label:String,now:Date) -> some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(alignment:.firstTextBaseline) {
                Text(label).font(.system(size:12,weight:.medium))
                Spacer()
                Text(percentLabel(window?.remaining)).font(.system(size:20,weight:.medium)).monospacedDigit()
            }
            BatteryBar(remaining:window?.remaining,height:5)
            HStack(spacing:4) {
                Text(L10n.format("重置 %@", String(describing: (shortResetTime(window)))))
                Spacer(minLength:0)
                Text(L10n.format("已用 %@", String(describing: (percentLabel(window?.usedPercent)))))
            }.font(.system(size:9)).monospacedDigit().foregroundStyle(Forge.muted)
            if window?.windowDurationMins == 300 {
                Text(L10n.format("5 小时窗口 · 距重置 %@", String(describing: (countdown(window,now:now)))))
                    .font(.system(size:9)).monospacedDigit().foregroundStyle(Forge.muted)
            }
        }.help(L10n.format("%@可用 %@；下次重置 %@", String(describing: (label)), String(describing: (percentLabel(window?.remaining))), String(describing: (resetTime(window)))))
    }
    private var dailySection:some View {
        VStack(alignment:.leading,spacing:6) {
            Rectangle().fill(Forge.line).frame(height:0.5)
            HStack {
                Text(L10n.text("近 7 天 Token")).font(.system(size:11,weight:.medium))
                Spacer(minLength:2)
                if store.usageError != nil { Image(systemName:"exclamationmark.circle").foregroundStyle(Forge.amber).help(store.usageError!) }
            }
            HStack(spacing:5) { ForEach(store.days) { day in dayCell(day) } }
            HStack(spacing:3) {
                Text(store.selected?.shortDate ?? "—")
                Text("·")
                Text(fullTokens(store.selected?.tokens))
                if store.selected?.tokens != nil { Text("token") }
            }.font(.system(size:10)).monospacedDigit().lineLimit(1)
            .help("\(store.days.allSatisfy { $0.tokens != nil } ? L10n.text("7 天合计") : L10n.text("已知数据合计"))：\(fullTokens(knownTokenTotal(store.days))) token")
        }
    }
    private func dayCell(_ day:DayUsage) -> some View {
        let peak = max(1,store.days.compactMap(\.tokens).max() ?? 1)
        let intensity = day.tokens.map { $0 == 0 ? 0.04 : 0.20 + 0.72*Double($0)/Double(peak) } ?? 0
        return Button { store.selectedDay = day.date } label: {
            VStack(spacing:4) {
                ZStack {
                    RoundedRectangle(cornerRadius:3).fill(Color.white.opacity(0.055))
                    RoundedRectangle(cornerRadius:3).fill(Forge.orange.opacity(intensity))
                    if day.tokens == nil { Text("—").font(.system(size:10)).foregroundStyle(Forge.muted) }
                }.frame(height:26)
                .overlay(RoundedRectangle(cornerRadius:3).strokeBorder(store.selectedDay == day.date ? Forge.amber.opacity(0.8) : .clear,lineWidth:0.7))
                Text(day.shortDate.replacingOccurrences(of:"-",with:"/"))
                    .font(.system(size:8)).monospacedDigit().foregroundStyle(Forge.muted)
            }.frame(maxWidth:.infinity)
        }.buttonStyle(.plain).onHover { if $0 { store.selectedDay = day.date } }
        .help("\(day.date)：\(fullTokens(day.tokens))\(day.tokens == nil ? "" : " token")")
        .accessibilityLabel(L10n.format("%@ Token 消耗 %@", String(describing: (day.date)), String(describing: (fullTokens(day.tokens)))))
    }
    private var resetSection:some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(spacing:6) {
                Image(systemName:"ticket").font(.system(size:12)).foregroundStyle(Forge.amber.opacity(0.8))
                Text(L10n.format("重置卡 %@", String(describing: (store.resetCount.map { "× \($0)" } ?? L10n.text("待查询"))))).font(.system(size:11,weight:.medium)).lineLimit(1).minimumScaleFactor(0.72)
                Spacer(minLength:2)
                HoldToReset(enabled:store.canRedeem,busy:store.redeeming,label:resetLabel) { Task { await store.redeem() } }
                    .frame(width:94).help(store.redemptionLabel)
            }
            .background {
                RoundedRectangle(cornerRadius:12,style:.continuous).fill(.white.opacity(0.025))
                    .overlay(RoundedRectangle(cornerRadius:12,style:.continuous).strokeBorder(.white.opacity(0.10),lineWidth:0.5))
                    .padding(-6)
            }
            if let notice=store.notice {
                Text(notice).font(.system(size:10)).foregroundStyle(Forge.muted).fixedSize(horizontal:false,vertical:true)
            }
        }.padding(.top,1)
    }
    private var resetLabel:String {
        if store.demo { return L10n.text("演示模式") }
        if store.redeeming { return L10n.text("正在核实…") }
        if store.pendingRedemption { return L10n.text("长按核实") }
        if !store.canRedeem { return store.resetCount == 0 ? L10n.text("暂无卡片") : L10n.text("暂不可用") }
        return L10n.text("长按确认")
    }
    private var footer:some View {
        HStack(spacing:4) {
            Circle().fill(store.error == nil && store.lastSync != nil ? Color(red:0.48,green:0.68,blue:0.60) : Forge.muted).frame(width:3,height:3)
            Text(store.refreshing ? L10n.text("更新中…") : L10n.format("更新于 %@", String(describing: (store.lastSync.map { $0.formatted(date:.omitted,time:.shortened) } ?? L10n.text("尚未同步")))))
            Spacer(minLength:0)
            Text(store.demo ? L10n.text("示例数据") : L10n.text("实时"))
        }.font(.system(size:9)).monospacedDigit().foregroundStyle(Forge.muted)
    }
    private func shortResetTime(_ window:QuotaWindow?) -> String {
        guard let timestamp=window?.resetsAt else { return "—" }
        let date=Date(timeIntervalSince1970:timestamp), formatter=DateFormatter()
        formatter.dateFormat=Calendar.current.isDateInToday(date) ? "HH:mm" : "MM/dd HH:mm"
        return formatter.string(from:date)
    }
}

struct HoldToReset: View {
    var enabled:Bool
    var busy:Bool
    var label:String
    var action:()->Void
    @ViewState private var progress:CGFloat = 0
    var body:some View {
        ZStack(alignment:.leading) {
            Capsule().fill(Forge.orange.opacity(enabled ? 0.14 : 0.04))
            GeometryReader { geo in
                Rectangle().fill(Forge.orange.opacity(0.5)).frame(width:geo.size.width*progress)
            }.clipShape(Capsule())
            Text(label).font(.system(size:10,weight:.medium)).foregroundStyle(enabled || busy ? Forge.amber : Forge.muted).frame(maxWidth:.infinity)
        }.frame(height:28)
        .overlay(Capsule().strokeBorder(Forge.orange.opacity(enabled ? 0.65 : 0.18),lineWidth:0.7))
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration:0.8,maximumDistance:10,perform:{
            progress=0
            if enabled { action() }
        },onPressingChanged:{ down in
            guard enabled else { progress=0; return }
            withAnimation(down ? .linear(duration:0.8) : .easeOut(duration:0.1)) { progress=down ? 1 : 0 }
        })
        .accessibilityLabel(label).accessibilityHint(L10n.text("打开重置确认，确认后才会使用重置卡"))
        .accessibilityAction { if enabled { action() } }
    }
}
