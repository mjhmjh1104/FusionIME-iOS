import SwiftUI
import FusionCore

struct KeyFramesPreference:PreferenceKey {
    static var defaultValue:[String:CGRect]=[:]
    static func reduce(value:inout [String:CGRect],nextValue:()->[String:CGRect]) { value.merge(nextValue(),uniquingKeysWith:{$1}) }
}
@MainActor final class KeyboardTouchCoordinator:ObservableObject {
    var frames:[String:CGRect]=[:]
    private var keys:[String:KeySpec]=[:]
    private var pressedKeys:[String:[String:KeySpec]]=[:]
    private var heldShiftTouches=Set<String>()
    private let correction=TouchCorrection()
    @Published private(set) var active:[String:String]=[:]
    func updateKeys(_ rows:[[KeySpec]]) {
        keys=Dictionary(rows.flatMap{$0}.filter{!$0.isSpacer}.map{($0.id,$0)},uniquingKeysWith:{$1})
    }
    func begin(_ start:String,holdingShift:Bool) {
        // Preserve the modifier for a key whose finger lifts after Shift's.
        pressedKeys[start]=keys
        if holdingShift { heldShiftTouches.insert(start) } else { heldShiftTouches.remove(start) }
    }
    func holdingShift(_ start:String)->Bool { heldShiftTouches.contains(start) }
    private func keys(start:String?,preferCurrent:Bool)->[String:KeySpec] {
        preferCurrent ? keys:start.flatMap{pressedKeys[$0]} ?? keys
    }
    func key(_ id:String,start:String?=nil,preferCurrent:Bool=false)->KeySpec? {
        keys(start:start,preferCurrent:preferCurrent)[id]
    }
    func target(_ point:CGPoint,correct:Bool,learn:Bool,start:String?=nil,preferCurrent:Bool=false) -> KeySpec? {
        let keys=keys(start:start,preferCurrent:preferCurrent)
        let codes=keys.compactMapValues { key -> String? in
            guard let code=key.code,code.count==1 || ["SEMICOLON","APOSTROPHE","PERIOD","COMMA","SLASH"].contains(code) else { return nil }
            return code
        }
        let id=correct ? correction.corrected(point:point,frames:frames,codes:codes,learn:learn):frames.first(where:{$0.value.contains(point)})?.key
        return id.flatMap { keys[$0] }
    }
    func highlight(start:String,key:KeySpec?) { active[start]=key?.id }
    func end(_ start:String) { active.removeValue(forKey:start);pressedKeys.removeValue(forKey:start);heldShiftTouches.remove(start) }
    func reset() { active=[:] }
}
