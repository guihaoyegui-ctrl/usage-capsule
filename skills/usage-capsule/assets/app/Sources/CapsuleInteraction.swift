import AppKit
import SwiftUI

/// Owns the whole window rectangle, including the rim and shadow margins.
/// The visual is a passive child, so text and lamp layers cannot steal input.
struct CapsuleInteraction:NSViewRepresentable {
    var content:AnyView
    var label:String
    var hover:(Bool)->Void
    var press:()->Void
    var dragChanged:(Bool)->Void
    var menu:()->NSMenu
    func makeNSView(context:Context) -> Surface { Surface() }
    func updateNSView(_ view:Surface,context:Context) {
        view.visual.rootView=content
        view.hover=hover; view.press=press; view.dragChanged=dragChanged; view.makeMenu=menu
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp(L10n.text("按住胶囊任意位置拖动；悬停查看；点击固定概览；右键退出"))
        view.toolTip=L10n.text("日额为 5 小时窗口 · 按住任意位置拖动 · 点击固定 · 右键退出")
    }
    final class Surface:NSView {
        private final class ClearHostingView:NSHostingView<AnyView> {
            override var isOpaque:Bool { false }
        }
        fileprivate let visual:NSHostingView<AnyView>
        var hover:((Bool)->Void)?
        var press:(()->Void)?
        var dragChanged:((Bool)->Void)?
        var makeMenu:(()->NSMenu)?
        private var pointer=CapsulePointerGesture()
        private var windowOrigin=CGPoint.zero
        private var dragging=false
        private var tracking:NSTrackingArea?
        override init(frame:NSRect) {
            visual=ClearHostingView(rootView:AnyView(EmptyView()))
            super.init(frame:frame)
            visual.frame=bounds
            visual.autoresizingMask=[.width,.height]
            visual.wantsLayer=true
            visual.layer?.backgroundColor=NSColor.clear.cgColor
            visual.layer?.isOpaque=false
            addSubview(visual)
        }
        required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
        override var isOpaque:Bool { false }
        override var mouseDownCanMoveWindow:Bool { false }
        override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
        override func hitTest(_ point:NSPoint) -> NSView? {
            let local=convert(point,from:superview)
            return bounds.contains(local) ? self : nil
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area=NSTrackingArea(rect:.zero,options:[.activeAlways,.mouseEnteredAndExited,.inVisibleRect],owner:self,userInfo:nil)
            addTrackingArea(area); tracking=area
        }
        override func resetCursorRects() { addCursorRect(bounds,cursor:dragging ? .closedHand : .openHand) }
        override func mouseEntered(with event:NSEvent) { if !dragging { hover?(true) } }
        override func mouseExited(with event:NSEvent) { if !dragging { hover?(false) } }
        override func mouseDown(with event:NSEvent) {
            guard let window else { return }
            pointer.begin(at:window.convertPoint(toScreen:event.locationInWindow))
            windowOrigin=window.frame.origin
        }
        override func mouseDragged(with event:NSEvent) {
            guard let window, let delta=pointer.move(to:window.convertPoint(toScreen:event.locationInWindow)) else { return }
            if !dragging { dragging=true; dragChanged?(true); NSCursor.closedHand.set() }
            window.setFrameOrigin(CGPoint(x:windowOrigin.x+delta.x,y:windowOrigin.y+delta.y))
        }
        override func mouseUp(with event:NSEvent) {
            let result=pointer.end()
            if dragging { dragging=false; dragChanged?(false); NSCursor.openHand.set() }
            if result == .click { press?() }
        }
        override func viewWillMove(toWindow newWindow:NSWindow?) {
            if newWindow == nil {
                pointer.cancel()
                if dragging { dragging=false; dragChanged?(false) }
            }
            super.viewWillMove(toWindow:newWindow)
        }
        override func rightMouseDown(with event:NSEvent) {
            guard let menu=makeMenu?() else { return }
            NSMenu.popUpContextMenu(menu,with:event,for:self)
        }
        override func accessibilityPerformPress() -> Bool { press?(); return true }
    }
}
