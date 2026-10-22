import SwiftUI
import AppKit

@MainActor final class OverviewMotion:ObservableObject {
    @Published var progress:CGFloat = 0
    @Published var origin:UnitPoint = .trailing
    @Published var reduced = false
    static let enter:Double = 0.26
    static let exit:Double = 0.12
    static let gentle:Double = 0.10
    static func animation(entering:Bool,reduced:Bool) -> Animation {
        .timingCurve(0.23,1,0.32,1,duration:reduced ? gentle : (entering ? enter : exit))
    }
}

/// Only compositing properties change. Panel bounds and text layout stay fixed.
struct PopupReveal:AnimatableModifier {
    var progress:CGFloat
    var origin:UnitPoint
    var reduced:Bool
    var animatableData:CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content:Content) -> some View {
        let p = max(0,min(1,progress))
        content
            .overlay {
                if !reduced {
                    GeometryReader { geo in
                        let glint = LinearGradient(colors:[.clear,Forge.amber.opacity(0.72),.white.opacity(0.80),.clear],startPoint:.leading,endPoint:.trailing)
                        ZStack(alignment:.leading) {
                            Rectangle().fill(glint).frame(width:26)
                                .offset(x:(geo.size.width+52)*p-26)
                                .opacity(0.055)
                            RoundedRectangle(cornerRadius:21,style:.continuous)
                                .strokeBorder(Forge.amber,lineWidth:1)
                                .mask(alignment:.leading) { Rectangle().fill(glint).frame(width:45).offset(x:(geo.size.width+90)*p-45) }
                                .opacity(0.8)
                        }.opacity(4*p*(1-p)).clipShape(RoundedRectangle(cornerRadius:21,style:.continuous))
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .scaleEffect(reduced ? 1 : 0.96+0.04*p,anchor:origin)
            .offset(x:reduced ? 0 : (1-p)*(origin.x-0.5)*20,
                    y:reduced ? 0 : (1-p)*(origin.y-0.5)*8)
            .opacity(p)
    }
}

struct OverviewSurface:View {
    @ObservedObject var store:QuotaStore
    @ObservedObject var motion:OverviewMotion
    @Environment(\.accessibilityReduceMotion) private var reduced
    var hover:(Bool)->Void
    var pin:()->Void
    var close:()->Void
    var body:some View {
        OverviewView(store:store,hover:hover,onPin:pin,onClose:close)
            .modifier(PopupReveal(progress:motion.progress,origin:motion.origin,reduced:motion.reduced || reduced))
    }
}
