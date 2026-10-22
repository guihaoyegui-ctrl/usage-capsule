import AppKit
import SwiftUI

@main struct InteractionCoverage {
    @MainActor static func main() {
        _ = NSApplication.shared
        var failures=0
        for scale in [1.0,1.5] {
            let store=QuotaStore(); store.scale=scale
            var clicks=0
            let size=NSSize(width:184*scale+16,height:60*scale+16)
            let content=CompactView(store:store,hover:{_ in},click:{clicks += 1},dragChanged:{_ in},menu:{NSMenu()})
                .frame(width:size.width,height:size.height)
            let host=NSHostingView(rootView:content)
            let panel=NSPanel(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isReleasedWhenClosed=false
            panel.contentView=host
            panel.setContentSize(size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until:Date(timeIntervalSinceNow:0.1))
            host.layoutSubtreeIfNeeded()

            var uncovered=0
            var examples:[String]=[]
            for y in 0..<Int(size.height) {
                for x in 0..<Int(size.width) {
                    let hit=host.hitTest(CGPoint(x:Double(x)+0.5,y:Double(y)+0.5))
                    if !(hit is CapsuleInteraction.Surface) {
                        uncovered += 1
                        if examples.count < 4 { examples.append("(\(x),\(y)): \(hit.map { String(describing:type(of:$0)) } ?? "nil")") }
                    }
                }
            }
            if uncovered == 0 {
                print("PASS: entire \(Int(size.width))×\(Int(size.height)) window routes to the capsule input surface at \(Int(scale*100))%")
            } else {
                failures += 1
                print("FAIL: \(uncovered) points cannot drag at \(Int(scale*100))% — \(examples.joined(separator:"; "))")
            }
            // Text, lamp rows, the divider, rims, and all four frame corners.
            let points=[CGPoint(x:1,y:1),CGPoint(x:size.width-1,y:1),CGPoint(x:1,y:size.height-1),CGPoint(x:size.width-1,y:size.height-1),CGPoint(x:40*scale+8,y:37*scale+8),CGPoint(x:130*scale+8,y:12*scale+8),CGPoint(x:size.width/2,y:size.height/2)]
            for point in points {
                if let input=host.hitTest(point) as? CapsuleInteraction.Surface {
                    let before=clicks
                    _ = input.accessibilityPerformPress()
                    if clicks != before+1 { failures += 1; print("FAIL: full-area input lost its click action") }
                } else {
                    failures += 1; print("FAIL: no input surface at \(point)")
                }
            }
            panel.close()
        }
        print("Interaction coverage: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
