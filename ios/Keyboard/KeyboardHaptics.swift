import CoreHaptics
import UIKit

@MainActor final class KeyboardHaptics {
    private var engine:CHHapticEngine?
    func play(milliseconds:Double) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil {
                let engine=try CHHapticEngine();engine.playsHapticsOnly=true;engine.isAutoShutdownEnabled=true
                self.engine=engine
            }
            guard let engine else { return }
            try engine.start()
            let event=CHHapticEvent(eventType:.hapticContinuous,parameters:[.init(parameterID:.hapticIntensity,value:0.45),.init(parameterID:.hapticSharpness,value:0.5)],relativeTime:0,duration:min(50,max(5,milliseconds))/1000)
            try engine.makePlayer(with:CHHapticPattern(events:[event],parameters:[])).start(atTime:CHHapticTimeImmediate)
        } catch { UIImpactFeedbackGenerator(style:.light).impactOccurred() }
    }
    func stop() { engine?.stop(completionHandler:nil);engine=nil }
}
