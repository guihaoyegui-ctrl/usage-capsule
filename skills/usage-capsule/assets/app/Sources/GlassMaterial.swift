import SwiftUI
import ImageIO

/// The crop is the material plate's viewport; the original alpha PNG is untouched.
private enum GlassPlate {
    static let capsule=load("CapsuleGlass",crop:CGRect(x:48,y:41,width:2076,height:621))
    static let overview=load("OverviewGlass",crop:CGRect(x:57,y:91,width:984,height:1256))
    private static func load(_ name:String,crop:CGRect) -> CGImage? {
        guard let url=Bundle.main.url(forResource:name,withExtension:"png"),
              let source=CGImageSourceCreateWithURL(url as CFURL,nil),
              let image=CGImageSourceCreateImageAtIndex(source,0,nil) else { return nil }
        return image.cropping(to:crop)
    }
}

struct PolishedShell:View {
    var radius:CGFloat
    var body:some View {
        GeometryReader { geo in
            let capsule=geo.size.width > geo.size.height*2
            if let plate=capsule ? GlassPlate.capsule : GlassPlate.overview {
                Image(decorative:plate,scale:CGFloat(plate.width)/(capsule ? 184 : 248))
                    .resizable(capInsets:capsule ? EdgeInsets() : EdgeInsets(top:24,leading:24,bottom:24,trailing:24))
                    .interpolation(.high)
                    .frame(width:geo.size.width,height:geo.size.height)
            } else {
                RoundedRectangle(cornerRadius:radius,style:.continuous)
                    .fill(LinearGradient(colors:[Color(white:0.21),Color(white:0.045)],startPoint:.topLeading,endPoint:.bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).strokeBorder(Forge.muted,lineWidth:1))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
