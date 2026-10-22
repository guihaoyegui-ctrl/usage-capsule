import SwiftUI
import AppKit
import Combine

final class FloatingPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
}
final class TransparentHostingView<Content:View>: NSHostingView<Content> {
    override var isOpaque:Bool { false }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = QuotaStore()
    var compact: FloatingPanel!
    var overview: FloatingPanel!
    var statusItem: NSStatusItem!
    var hideTask: Task<Void,Never>?
    var subscription: AnyCancellable?
    var settingsWindow: NSWindow?
    var presentation = OverviewPresentation()
    let motion = OverviewMotion()
    var motionTask:Task<Void,Never>?
    var keyMonitor: Any?
    var clickMonitor: Any?
    private var draggingCapsule = false
    private var terminating = false
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.arguments.contains("--render-preview") { renderPreview(); return }
        if ProcessInfo.processInfo.arguments.contains("--render-motion") { renderMotionPreview(); return }
        let saved = UserDefaults.standard.double(forKey:"widgetScale")
        store.scale = saved > 0 ? min(1.5,max(1,saved)) : 1
        store.alwaysOnTop = UserDefaults.standard.object(forKey:"onTop") as? Bool ?? true
        compact = makePanel(size:compactSize)
        compact.delegate = self; compact.isMovableByWindowBackground = false
        compact.title = L10n.text("用量胶囊")
        overview = makePanel(size:NSSize(width:264,height:340)); overview.delegate = self
        overview.title = L10n.text("用量概览")
        overview.dismiss = { [weak self] in self?.closeOverview(animated:false) }
        compact.dismiss = { [weak self] in self?.closeOverview(animated:false) }
        installCompact()
        installOverview()
        placeCompact()
        updateLevel()
        compact.orderFrontRegardless()
        installMenu()
        installDismissEvents()
        store.start()
        subscription = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.resizeOverview(); self?.updateMenuTitle() }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-overview") { presentation.togglePin(); applyPresentation() }
        if ProcessInfo.processInfo.arguments.contains("--smoke") { runSmoke() }
    }
    var compactSize:NSSize { NSSize(width:184*store.scale+16,height:60*store.scale+16) }
    func hosting<V:View>(_ view:V) -> NSHostingView<V> {
        let host = TransparentHostingView(rootView:view)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layer?.isOpaque = false
        return host
    }
    func installCompact() {
        let view = CompactView(store:store,
            hover:{ [weak self] in self?.hoverChanged($0) },
            click:{ [weak self] in self?.togglePin() },
            dragChanged:{ [weak self] in self?.capsuleDragChanged($0) },
            menu:{ [weak self] in self?.capsuleMenu() ?? NSMenu() })
        compact.contentView = hosting(view)
        compact.setContentSize(compactSize)
    }
    func runSmoke() {
            Task { @MainActor in
                for _ in 0..<60 {
                    try? await Task.sleep(nanoseconds:500_000_000)
                    if self.store.lastSync != nil && !self.store.refreshing { break }
                }
                self.showOverview()
                try? await Task.sleep(nanoseconds:300_000_000)
                let wasVisible = self.overview.isVisible
                self.closeOverview()
                try? await Task.sleep(nanoseconds:180_000_000)
                self.presentation.hoverBegan(); self.applyPresentation()
                let staysClosed = !self.overview.isVisible
                self.presentation.pointerLeftSurfaces(); self.presentation.hoverBegan(); self.applyPresentation()
                try? await Task.sleep(nanoseconds:300_000_000)
                let reopens = self.overview.isVisible
                self.closeOverview()
                try? await Task.sleep(nanoseconds:30_000_000)
                self.showOverview()
                try? await Task.sleep(nanoseconds:350_000_000)
                let interruptedClose = self.overview.isVisible && self.motion.progress == 1
                self.closeOverview(animated:false)
                let escapeCloses = !self.overview.isVisible
                let report:[String:Any] = ["connected":self.store.lastSync != nil,"accountIdentityAvailable":self.store.limits?.accountId != nil,"primaryRemaining":self.store.primary?.remaining as Any? ?? NSNull(),"weeklyRemaining":self.store.secondary?.remaining as Any? ?? NSNull(),"dailyCells":self.store.days.count,"knownDailyCells":self.store.days.filter { $0.tokens != nil }.count,"resetCardCount":self.store.resetCount as Any? ?? NSNull(),"error":self.store.error as Any? ?? NSNull(),"overviewOpens":wasVisible,"dismissSuppressesHover":staysClosed,"overviewReenters":reopens,"interruptedCloseStaysOpen":interruptedClose,"escapeImmediateClose":escapeCloses,"reducedMotion":self.motion.reduced,"capsuleWidth":184*self.store.scale,"capsuleHeight":60*self.store.scale,"overviewContentHeight":self.overview.frame.height-16]
                if let data = try? JSONSerialization.data(withJSONObject:report,options:.prettyPrinted), let dest = ProcessInfo.processInfo.environment["CARTRIDGE_SMOKE_FILE"] {
                    try? data.write(to:URL(fileURLWithPath:dest))
                }
                NSApp.terminate(nil)
            }
    }
    func makePanel(size:NSSize) -> FloatingPanel {
        let p = FloatingPanel(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.hidesOnDeactivate = false; p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        p.animationBehavior = .utilityWindow
        return p
    }
    func installOverview() {
        overview.contentView = hosting(OverviewSurface(store:store,motion:motion,hover:{ [weak self] in self?.hoverChanged($0) },pin:{ [weak self] in self?.togglePin() },close:{ [weak self] in self?.closeOverview() }).padding(8).fixedSize())
        resizeOverview()
    }
    func resizeOverview() {
        guard let overview, let host = overview.contentView else { return }
        host.layoutSubtreeIfNeeded()
        let fitted = host.fittingSize
        if fitted.height > 100, abs(overview.frame.height-fitted.height) > 0.5 { overview.setContentSize(NSSize(width:264,height:fitted.height)) }
        if overview.isVisible { positionOverview() }
    }
    func placeCompact() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        let x = (UserDefaults.standard.object(forKey:"widgetX") as? Double).map { CGFloat($0) }
        let y = (UserDefaults.standard.object(forKey:"widgetY") as? Double).map { CGFloat($0) }
        let origin = CGPoint(x:x ?? (screen.maxX-compact.frame.width-24),y:y ?? (screen.minY+28))
        compact.setFrameOrigin(clamped(origin,in:screen,size:compact.frame.size))
    }
    func clamped(_ point:CGPoint,in screen:NSRect,size:NSSize) -> CGPoint {
        CGPoint(x:max(screen.minX,min(point.x,screen.maxX-size.width)),y:max(screen.minY,min(point.y,screen.maxY-size.height)))
    }
    func positionOverview() {
        guard let compact, let overview else { return }
        let screen = compact.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let right = compact.frame.maxX
        let x = right+overview.frame.width <= screen.maxX ? right : compact.frame.minX-overview.frame.width
        let y = compact.frame.maxY-overview.frame.height
        overview.setFrameOrigin(clamped(CGPoint(x:x,y:y),in:screen,size:overview.frame.size))
    }
    func hoverChanged(_ inside:Bool) {
        hideTask?.cancel()
        guard !draggingCapsule else { return }
        if inside {
            hideTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds:180_000_000)
                if !Task.isCancelled { self.presentation.hoverBegan(); self.applyPresentation() }
            }
        } else if !store.pinned {
            hideTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds:450_000_000)
                guard !Task.isCancelled else { return }
                let mouse = NSEvent.mouseLocation
                if !self.compact.frame.contains(mouse) && (!self.overview.isVisible || !self.overview.frame.contains(mouse)) {
                    self.presentation.pointerLeftSurfaces(); self.applyPresentation()
                }
            }
        }
    }
    func capsuleDragChanged(_ dragging:Bool) {
        draggingCapsule=dragging; hideTask?.cancel()
        if dragging {
            if !presentation.isPinned { closeOverview(animated:false) }
        } else {
            let screen=compact.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
            compact.setFrameOrigin(clamped(compact.frame.origin,in:screen,size:compact.frame.size))
            presentation.pointerLeftSurfaces()
        }
    }
    func capsuleMenu() -> NSMenu {
        hideTask?.cancel()
        let menu=NSMenu()
        for (title,selector) in [(L10n.text("查看 / 固定概览"),#selector(pinMenu)),(L10n.text("关闭概览"),#selector(closeMenu)),(L10n.text("刷新用量"),#selector(refreshMenu)),(L10n.text("设置"),#selector(settingsMenu)),(L10n.text("隐藏胶囊"),#selector(hideMenu))] {
            let item=NSMenuItem(title:title,action:selector,keyEquivalent:""); item.target=self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit=NSMenuItem(title:L10n.text("退出用量胶囊"),action:#selector(quitMenu),keyEquivalent:""); quit.target=self; menu.addItem(quit)
        return menu
    }
    func applyPresentation(animated:Bool = true) {
        if store.pinned != presentation.isPinned { store.pinned = presentation.isPinned }
        motionTask?.cancel()
        motion.reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || ProcessInfo.processInfo.arguments.contains("--reduced-motion")
        if presentation.isVisible {
            resizeOverview(); positionOverview()
            let starting = !overview.isVisible
            if starting {
                let point=popupAnchor(panel:overview.frame,trigger:compact.frame)
                motion.origin=UnitPoint(x:point.x,y:point.y)
                motion.progress=0
                overview.orderFrontRegardless()
            }
            guard motion.progress != 1 else { return }
            if !animated { setMotion(1,animated:false); return }
            if starting {
                motionTask=Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled, self.presentation.isVisible else { return }
                    self.setMotion(1,animated:true)
                }
            } else { setMotion(1,animated:true) }
        } else {
            guard overview.isVisible else { motion.progress=0; return }
            if !animated { setMotion(0,animated:false); overview.orderOut(nil); return }
            setMotion(0,animated:true)
            let duration=motion.reduced ? OverviewMotion.gentle : OverviewMotion.exit
            motionTask=Task { @MainActor in
                try? await Task.sleep(nanoseconds:UInt64((duration+0.02)*1_000_000_000))
                guard !Task.isCancelled, !self.presentation.isVisible else { return }
                self.overview.orderOut(nil)
            }
        }
    }
    func setMotion(_ value:CGFloat,animated:Bool) {
        if animated {
            withAnimation(OverviewMotion.animation(entering:value > 0,reduced:motion.reduced)) { motion.progress=value }
        } else {
            var transaction=Transaction(); transaction.disablesAnimations=true
            withTransaction(transaction) { motion.progress=value }
        }
    }
    func showOverview() { hideTask?.cancel(); presentation.open(); applyPresentation() }
    func closeOverview(animated:Bool = true) { hideTask?.cancel(); presentation.close(); applyPresentation(animated:animated) }
    func togglePin() {
        hideTask?.cancel(); presentation.togglePin(); applyPresentation()
        overview.makeKeyAndOrderFront(nil)
    }
    func hideWidget() { closeOverview(animated:false); compact.orderOut(nil) }
    func installDismissEvents() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if OverviewKeyboardDismissal.shouldClose(for:event,modalWindow:NSApplication.shared.modalWindow) {
                self?.closeOverview(animated:false); return nil
            }
            return event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.presentation.isPinned else { return }
                self.closeOverview(); self.presentation.pointerLeftSurfaces()
            }
        }
    }
    func updateLevel() { compact.level = store.alwaysOnTop ? .floating : .normal; overview.level = compact.level }
    func windowDidMove(_ notification:Notification) {
        guard let window = notification.object as? NSWindow, window === compact else { return }
        UserDefaults.standard.set(compact.frame.minX,forKey:"widgetX"); UserDefaults.standard.set(compact.frame.minY,forKey:"widgetY")
        if overview.isVisible { positionOverview() }
    }
    func windowDidResignKey(_ notification:Notification) { }
    func installMenu() {
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength) }
        statusItem.button?.image = NSImage(systemSymbolName:"chart.bar.xaxis",accessibilityDescription:L10n.text("用量胶囊"))
        let menu = NSMenu()
        for (title,selector) in [(L10n.text("显示胶囊"),#selector(showWidget)),(L10n.text("固定概览"),#selector(pinMenu)),(L10n.text("关闭概览"),#selector(closeMenu)),(L10n.text("隐藏胶囊"),#selector(hideMenu)),(L10n.text("刷新用量"),#selector(refreshMenu)),(L10n.text("设置"),#selector(settingsMenu))] {
            let item = NSMenuItem(title:title,action:selector,keyEquivalent:""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title:L10n.text("退出用量胶囊"),action:#selector(quitMenu),keyEquivalent:"q"); quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
    }
    func updateMenuTitle() { statusItem?.button?.toolTip = L10n.format("用量胶囊 · 日额 %@ · 周额 %@", String(describing: (percentLabel(store.primary?.remaining))), String(describing: (percentLabel(store.secondary?.remaining)))) }
    @objc func showWidget() { compact.orderFrontRegardless() }
    @objc func pinMenu() { togglePin() }
    @objc func closeMenu() { closeOverview() }
    @objc func hideMenu() { hideWidget() }
    @objc func refreshMenu() { Task { await store.refresh() } }
    @objc func settingsMenu() { showSettings() }
    @objc func quitMenu() { NSApp.terminate(nil) }
    func applySettings() {
        UserDefaults.standard.set(store.language,forKey:"interfaceLanguage")
        UserDefaults.standard.set(store.scale,forKey:"widgetScale"); UserDefaults.standard.set(store.alwaysOnTop,forKey:"onTop")
        installCompact(); placeCompact(); updateLevel()
        installOverview(); installMenu()
        compact.title=L10n.text("用量胶囊"); overview.title=L10n.text("用量概览")
        settingsWindow?.title=L10n.text("用量胶囊设置")
        DispatchQueue.main.async { [weak self] in
            guard let window=self?.settingsWindow, let content=window.contentView else { return }
            window.setContentSize(content.fittingSize)
        }
    }
    func showSettings() {
        if settingsWindow == nil {
            let root = SettingsView(store:store,apply:{ [weak self] in self?.applySettings() },login:{ Task { await self.store.login() } })
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:380,height:300),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            let hosting=NSHostingView(rootView:root)
            window.title = L10n.text("用量胶囊设置"); window.contentView = hosting; window.setContentSize(hosting.fittingSize); window.isReleasedWhenClosed = false; window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps:true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationWillTerminate(_ notification:Notification) {
        terminating = true; motionTask?.cancel(); hideTask?.cancel(); store.stop()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }
    func renderPreview() {
        store.loadDemo()
        store.scale = 1
        let dark=ProcessInfo.processInfo.arguments.contains("--dark-preview")
        let hero=ProcessInfo.processInfo.arguments.contains("--reference-preview")
        let five=ProcessInfo.processInfo.arguments.contains("--five-tier-preview")
        let view = HStack(alignment:.top,spacing:24) {
            VStack(spacing:14) {
                ForEach(hero ? [68] : (five ? [90,70,50,30,10] : [100,60,20]),id:\.self) { level in
                    VStack(spacing:6) {
                        CapsuleFace(primary:Double(level),weekly:hero || five ? 42 : Double(level))
                        Text(hero ? L10n.text("常驻 184 × 60 pt · 3× 展示") : L10n.format("日额 %@%%", String(describing: (level)))).font(.system(size:11)).foregroundStyle(dark ? Forge.muted : Color(white:0.29))
                    }
                }
            }.padding(.top,10)
            OverviewView(store:store,hover:{_ in},onPin:{},onClose:{})
        }.padding(24).background(dark ? Forge.background : Color(red:0.85,green:0.86,blue:0.87))
        let renderer = ImageRenderer(content:view)
        renderer.scale = 3
        if let image = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage:image)
            let path = ProcessInfo.processInfo.arguments.last!
            if let data = rep.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:path)) }
        }
        NSApp.terminate(nil)
    }
}
struct SettingsView: View {
    @ObservedObject var store:QuotaStore
    var apply:()->Void
    var login:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text(L10n.text("用量胶囊")).font(.title2.weight(.medium))
            Picker(L10n.text("界面语言"),selection:Binding(get:{store.language},set:{store.language=$0;apply()})) {
                ForEach(CapsuleLanguage.allCases,id:\.rawValue) { language in Text(language.title).tag(language.rawValue) }
            }
            Toggle(L10n.text("保持在其他窗口上方"),isOn:Binding(get:{store.alwaysOnTop},set:{store.alwaysOnTop = $0;apply()}))
            HStack { Text(L10n.text("常驻尺寸")); Slider(value:Binding(get:{store.scale},set:{store.scale = $0;apply()}),in:1...1.5,step:0.05); Text("\(Int(store.scale*100))%").monospacedDigit() }
            Text(L10n.text("按住胶囊任意位置拖动；悬停查看，点击固定。概览右上角 × 或 Escape 关闭；右键或菜单栏可退出。每分钟更新用量。")).font(.caption).foregroundStyle(.secondary)
            HStack { Button(L10n.text("登录 Codex"),action:login); Button(L10n.text("立即刷新")) { Task { await store.refresh() } } }
            Text(L10n.text("重置卡仅在长按按钮后兑换。程序使用本机 Codex 登录，不需要 API Key。")).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width:380)
    }
}
@main struct CartridgeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
