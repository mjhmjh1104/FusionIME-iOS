import Foundation

/// All seven schemes from Android's DoublePinyinScheme.kt.
public enum DoublePinyin: String, Codable, CaseIterable, Identifiable, Sendable {
    case full, ziranma, microsoft, smartABC, jiajia, xiaohe, sogou, ziguang
    public var id:String { rawValue }
    public var name:String { self == .full ? "全拼" : rawValue }
    public var usesSemicolon:Bool { [.microsoft,.sogou,.ziguang].contains(self) }
    public func expand(_ input:String) -> String {
        guard self != .full else { return input }
        let chars=Array(input.lowercased()); var result=""; var i=0
        while i<chars.count {
            if chars[i]=="'" { result.append("'");i+=1; continue }
            guard chars[i].isASCII && chars[i].isLetter else { result.append(chars[i]); i+=1; continue }
            if i+1<chars.count && (chars[i+1].isLetter || chars[i+1]==";") {
                result += decode(chars[i],chars[i+1]); i+=2
                if i<chars.count && chars[i] != "'" { result.append("'") }
            } else { result += initial(chars[i]); i+=1 }
        }
        return result
    }
    private func initial(_ c:Character) -> String {
        let map:[Character:String]
        switch self {
        case .smartABC: map=["a":"zh","e":"ch","v":"sh"]
        case .jiajia: map=["u":"ch","i":"sh","v":"zh"]
        case .ziguang: map=["u":"zh","a":"ch","i":"sh"]
        default: map=["i":"ch","u":"sh","v":"zh"]
        }
        return map[c] ?? String(c)
    }
    public func decode(_ a:Character,_ b:Character) -> String {
        let zeroKeys:String
        switch self {
        case .smartABC: zeroKeys="ljhkqfgrb"
        case .jiajia: zeroKeys="sfgdwrtqp"
        case .xiaohe: zeroKeys="djhcwfgrz"
        case .ziguang: zeroKeys="prsqkwtjz"
        default: zeroKeys="ljhkzfgrb"
        }
        let syllables=["ai","an","ang","ao","ei","en","eng","er","ou"]
        var zeros:[String:String]=[:]
        let prefixed=[DoublePinyin.microsoft,.smartABC,.jiajia,.sogou,.ziguang].contains(self)
        let split = ![DoublePinyin.smartABC,.ziguang].contains(self)
        if split { zeros=["aa":"a","ee":"e","oo":"o"] }
        if prefixed { zeros.merge(["oa":"a","oe":"e","oo":"o"]) { _,new in new } }
        for (key,value) in zip(zeroKeys,syllables) {
            if split { zeros[String(value.first!)+String(key)]=value }
            if prefixed { zeros["o"+String(key)]=value }
        }
        if let zero=zeros[String(a)+String(b)] { return zero }
        let first=initial(a)
        var final=final(a,b)
        if "jqxy".contains(first) && first.count==1 && final.hasPrefix("v") { final="u"+final.dropFirst() }
        return first+final
    }
    private func final(_ a:Character,_ b:Character) -> String {
        func inside(_ chars:String) -> Bool { chars.contains(a) }
        let pairs:String
        switch self {
        case .ziranma: pairs="b:ou c:iao f:en g:eng h:ang j:an k:ao l:ai m:ian p:un q:iu r:uan t:ve x:ie z:ei"
        case .microsoft,.sogou: pairs="g:eng q:iu r:uan t:ve p:un f:en h:ang j:an k:ao l:ai z:ei x:ie c:iao b:ou m:ian ;:ing"
        case .smartABC: pairs="q:ei n:un g:eng w:ian y:ing p:uan f:en h:ang j:an k:ao l:ai z:iao x:ie b:ou"
        case .jiajia: pairs="t:eng n:iu c:uan z:un r:en g:ang f:an d:ao s:ai w:ei m:ie k:iao p:ou j:ian q:ing"
        case .xiaohe: pairs="g:eng q:iu w:ei r:uan t:ve y:un p:ie d:ai f:en h:ang j:an z:ou c:ao b:in m:ian"
        case .ziguang: pairs="w:en r:an t:eng q:ao p:ai s:ang d:ie f:ian k:ei l:uan z:ou ;:ing b:iao m:un"
        case .full: return String(b)
        }
        let map=Dictionary(uniqueKeysWithValues:pairs.split(separator:" ").map { item -> (Character,String) in
            let p=item.split(separator:":"); return (p[0].first!,String(p[1]))
        })
        if let value=map[b] { return value }
        switch self {
        case .ziranma:
            switch b {
            case "d": return inside("jqxnl") ? "iang":"uang"
            case "n": return inside("bpmnljqxy") ? "in":"n"
            case "o": return inside("dtnlgkhvuirzcs") ? "uo":"o"
            case "s": return inside("jqx") ? "iong":"ong"
            case "v": return inside("dtgkhvuirzcs") ? "ui":"v"
            case "w": return inside("gkhvuirzcs") ? "ua":"ia"
            case "y": return inside("gkhvuirzcs") ? "uai":"ing"
            default: break
            }
        case .microsoft,.sogou:
            switch b {
            case "n": return inside("bpmnljqxy") ? "in":"n"
            case "w": return inside("gkhvuirzcs") ? "ua":"ia"
            case "v": return inside("dtgkhvuirzcs") ? "ui":"ve"
            case "y": return inside("gkhvuirzcs") ? "uai":"v"
            case "o": return inside("dtnlgkhvuirzcs") ? "uo":"o"
            case "s": return inside("jqx") ? "iong":"ong"
            case "d": return inside(self == .sogou ? "jqxnlb":"jqxnl") ? "iang":"uang"
            default: break
            }
        case .smartABC:
            switch b {
            case "r": return inside("dtnljqx") ? "iu":"r"
            case "t": return inside("nljqx") ? "iang":"uang"
            case "o": return inside("dtnlgkhaevrzcs") ? "uo":"o"
            case "s": return inside("jqx") ? "iong":"ong"
            case "d": return inside("gkhaevrzcs") ? "ua":"ia"
            case "c": return inside("gkhaev") ? "uai":"in"
            case "m": return inside("nl") ? "ve":inside("jqxy") ? "ue":"ui"
            default: break
            }
        case .jiajia:
            switch b {
            case "l": return inside("bpmnljqxy") ? "in":"l"
            case "b": return inside("gkhvuirzcs") ? "ua":"ia"
            case "v": return inside("dtgkhvuirzcs") ? "ui":"v"
            case "x": return inside("gkhvuirzcs") ? "uai":"ve"
            case "o": return inside("dtnlgkhvuirzcs") ? "uo":"o"
            case "y": return inside("jqx") ? "iong":"ong"
            case "h": return inside("jqxnlb") ? "iang":"uang"
            default: break
            }
        case .xiaohe:
            switch b {
            case "n": return inside("bpmfdtnljqx") ? "iao":"n"
            case "o": return inside("dtnlgkhvuirzcs") ? "uo":"o"
            case "s": return inside("jqx") ? "iong":"ong"
            case "k": return inside("gkhvuirzcs") ? "uai":"ing"
            case "l": return inside("jqxnl") ? "iang":"uang"
            case "x": return inside("gkhvuirzcs") ? "ua":"ia"
            case "v": return inside("dtgkhvuirzcs") ? "ui":"v"
            default: break
            }
        case .ziguang:
            switch b {
            case "n": return inside("jqxy") ? "ue":inside("nl") ? "ve":inside("dtgkhrzcsuai") ? "ui":"n"
            case "g": return inside("nljqxb") ? "iang":inside("gkhuai") ? "uang":"g"
            case "y": return inside("jqxylmnbp") ? "in":"uai"
            case "o": return inside("dtnlgkhrzcsuai") ? "uo":"o"
            case "h": return inside("jqx") ? "iong":"ong"
            case "j": return inside("dnlmjqx") ? "iu":"j"
            case "x": return inside("jqxl") ? "ia":inside("gkhuai") ? "ua":"x"
            default: break
            }
        default: break
        }
        return String(b)
    }
}
