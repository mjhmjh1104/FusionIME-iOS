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
    struct Alternatives {
        let start:String,values:[String],frame:CGRect,anchor:CGRect
        var selected:Int?
        var cellWidth:CGFloat { frame.width/CGFloat(values.count) }
    }
    var width:CGFloat=390
    @Published private(set) var alternatives:Alternatives?
    func showAlternatives(start:String,key:KeySpec) {
        guard key.values.count>1,let anchor=frames[key.id] ?? frames[start] else { return }
        let available=max(1,width-8),popupWidth=min(available,CGFloat(key.values.count)*40)
        let x=max(4,min(width-4-popupWidth,anchor.midX-popupWidth/2))
        let cellWidth=popupWidth/CGFloat(key.values.count)
        let base=max(0,min(key.values.count-1,Int((anchor.midX-x)/cellWidth)))
        var values=Array(key.values.dropFirst());values.insert(key.values[0],at:base)
        alternatives=Alternatives(start:start,values:values,frame:CGRect(x:x,y:max(2,anchor.minY-54),width:popupWidth,height:50),anchor:anchor,selected:base)
        active[start]=key.id
    }
    func trackAlternatives(start:String,point:CGPoint) {
        guard var popup=alternatives,popup.start==start else { return }
        let bounds=CGRect(x:popup.frame.minX-16,y:popup.frame.minY-30,width:popup.frame.width+32,height:popup.anchor.maxY-popup.frame.minY+60)
        popup.selected=bounds.contains(point) ? max(0,min(popup.values.count-1,Int((point.x-popup.frame.minX)/popup.cellWidth))):nil
        alternatives=popup
    }
    func selectedAlternative(start:String,point:CGPoint)->String? {
        trackAlternatives(start:start,point:point)
        guard let popup=alternatives,popup.start==start,let index=popup.selected else { return nil }
        return popup.values[index]
    }
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
    func end(_ start:String) {
        active.removeValue(forKey:start);pressedKeys.removeValue(forKey:start);heldShiftTouches.remove(start)
        if alternatives?.start==start { alternatives=nil }
    }
    func reset() { active=[:];alternatives=nil }
}
