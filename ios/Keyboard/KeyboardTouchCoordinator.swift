import SwiftUI
import FusionCore

struct KeyFramesPreference:PreferenceKey {
    static var defaultValue:[String:CGRect]=[:]
    static func reduce(value:inout [String:CGRect],nextValue:()->[String:CGRect]) { value.merge(nextValue(),uniquingKeysWith:{$1}) }
}
@MainActor final class KeyboardTouchCoordinator:ObservableObject {
    var frames:[String:CGRect]=[:]
    var keys:[String:KeySpec]=[:]
    private let correction=TouchCorrection()
    @Published private(set) var active:[String:String]=[:]
    func target(_ point:CGPoint,correct:Bool,learn:Bool) -> KeySpec? {
        let codes=keys.compactMapValues { key -> String? in
            guard let code=key.code,code.count==1 || ["SEMICOLON","APOSTROPHE","PERIOD","COMMA","SLASH"].contains(code) else { return nil }
            return code
        }
        let id=correct ? correction.corrected(point:point,frames:frames,codes:codes,learn:learn):frames.first(where:{$0.value.contains(point)})?.key
        return id.flatMap { keys[$0] }
    }
    func highlight(start:String,key:KeySpec?) { active[start]=key?.id }
    func end(_ start:String) { active.removeValue(forKey:start) }
    func reset() { active=[:] }
}
