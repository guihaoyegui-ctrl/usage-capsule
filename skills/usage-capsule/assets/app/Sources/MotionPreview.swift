import SwiftUI
import AppKit
import ImageIO

/// An export of the same native views and transition, using example data only.
struct MotionPreviewScene:View {
    @ObservedObject var store:QuotaStore
    var progress:CGFloat
    var body:some View {
        HStack(alignment:.top,spacing:24) {
            VStack(alignment:.center,spacing:12) {
                Spacer()
                CapsuleFace(primary:store.primary?.remaining,weekly:store.secondary?.remaining)
                Text("184 × 60 pt").font(.system(size:10)).foregroundStyle(Forge.muted)
            }.frame(width:184,height:324)
            OverviewView(store:store,hover:{_ in},onPin:{},onClose:{})
                .modifier(PopupReveal(progress:progress,origin:UnitPoint(x:0,y:0.91),reduced:false))
        }.padding(24).background(Forge.background)
    }
}

@MainActor extension AppDelegate {
    func renderMotionPreview() {
        store.loadDemo(); store.scale=1
        let destinationURL=URL(fileURLWithPath:ProcessInfo.processInfo.arguments.last!)
        let fps=30, count=75
        guard let destination=CGImageDestinationCreateWithURL(destinationURL as CFURL,"com.compuserve.gif" as CFString,count,nil) else { NSApp.terminate(nil); return }
        CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        for frame in 0..<count {
            let time=Double(frame)/Double(fps)
            let progress:Double
            if time < 0.18 { progress=0 }
            else if time < 0.18+OverviewMotion.enter { progress=exportEase((time-0.18)/OverviewMotion.enter) }
            else if time < 1.78 { progress=1 }
            else if time < 1.78+OverviewMotion.exit { progress=1-exportEase((time-1.78)/OverviewMotion.exit) }
            else { progress=0 }
            let renderer=ImageRenderer(content:MotionPreviewScene(store:store,progress:CGFloat(progress)))
            renderer.scale=2
            if let image=renderer.cgImage {
                CGImageDestinationAddImage(destination,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/Double(fps)]] as CFDictionary)
            }
        }
        if !CGImageDestinationFinalize(destination) { fputs("Could not export motion preview\n",stderr) }
        NSApp.terminate(nil)
    }
    private func exportEase(_ fraction:Double) -> Double {
        let value=max(0,min(1,fraction))
        var low=0.0,high=1.0
        for _ in 0..<18 {
            let t=(low+high)/2, inverse=1-t
            let x=3*inverse*inverse*t*0.23+3*inverse*t*t*0.32+t*t*t
            if x < value { low=t } else { high=t }
        }
        return 1-pow(1-(low+high)/2,3)
    }
}
