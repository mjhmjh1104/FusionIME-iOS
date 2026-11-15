import CoreGraphics
import FusionCore

/// The preference is the complete extension height, without iOS's globe/home area.
enum KeyboardMetrics {
    static func height(settings:KeyboardSettings,rows:Int,width:CGFloat,kanaPad:Bool)->CGFloat {
        let wide=width>550
        let toolbar=CGFloat(wide ? 28:36)*CGFloat(settings.candidateRows)
        let keyRows=rows+(kanaPad ? 0:1)
        let minimum=CGFloat(keyRows)*(wide ? 28:43)+CGFloat(max(0,keyRows-1))*(wide ? 5:7)+toolbar+13
        let preference=wide ? settings.landscapeHeight:settings.height
        return max(CGFloat(preference)+CGFloat(settings.candidateRows-1)*(wide ? 28:36),minimum)
    }
}
