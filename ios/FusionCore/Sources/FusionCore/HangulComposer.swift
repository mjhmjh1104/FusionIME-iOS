import Foundation

/// Port of FusionIME's HangulCombiner. Input history is replayed for exact jamo undo.
public enum HangulComposer {
    public static func compose(_ input: [Int], layout: KeyboardLayout, correctOrders:Bool = false) -> String {
        let imported = ImportedTables.shared
        let old = layout == .hangulOld2 || layout == .hangul393
        let tableName = old ? "HangulOld.COMB_FULL" : layout == .hangul2 ? "Hangul2Set.COMB_KS" : layout == .hangul391Strict ? "Hangul3Set.COMBINATION_391_STRICT" : "Hangul3Set.COMBINATION_390_391"
        let combinations = imported.combinations[tableName] ?? [:]
        let choMap = imported.hangul["CONVERT_CHO"] ?? []
        let jongMap = imported.hangul["CONVERT_JONG"] ?? []
        let oldVowels = imported.hangul["CONVERT_OLDHANGUL_JUNG"] ?? []
        func mapped(_ map:[Int], _ index:Int) -> Int? { map.indices.contains(index) && map[index] != 0 ? map[index] : nil }
        func isCho(_ c:Int) -> Bool { (0x1100...0x115f).contains(c) || (0xa960...0xa97c).contains(c) }
        func isJung(_ c:Int) -> Bool { (0x1160...0x11a7).contains(c) || (0xd7b0...0xd7ca).contains(c) }
        func isJong(_ c:Int) -> Bool { (0x11a8...0x11ff).contains(c) || (0xd7cb...0xd7ff).contains(c) }
        func combine(_ a:Int?, _ b:Int?) -> Int? {
            guard let a, let b else { return nil }
            return combinations["\(a),\(b)"]
        }
        func compat(_ code:Int, _ map:[Int]) -> String { map.firstIndex(of:code).map { scalar($0+0x3131) } ?? scalar(code) }
        var cho:Int?, jung:Int?, jong:Int?, split:(Int,Int)?, last:Int?
        var output = ""
        func current() -> String {
            if cho == nil && jung == nil && jong == nil { return "" }
            if let c=cho, jung == nil && jong == nil, (0x1100...0x1112).contains(c & 0xffff) { return compat(c & 0xffff,choMap) }
            if let v=jung, cho == nil && jong == nil, (0x1161...0x1175).contains(v) { return scalar(v-0x1161+0x314f) }
            if let t=jong, cho == nil && jung == nil, (0x11a8...0x11c2).contains(t & 0xffff) { return compat(t & 0xffff,jongMap) }
            let c=cho.map {$0 & 0xffff}, v=jung.map {$0 & 0xffff}, t=jong.map {$0 & 0xffff}
            if let c, let v, (0x1100...0x1112).contains(c), (0x1161...0x1175).contains(v) {
                if t == nil || (0x11a8...0x11c2).contains(t!) {
                    return scalar(0xac00 + (c-0x1100)*588 + (v-0x1161)*28 + (t.map {$0-0x11a7} ?? 0))
                }
                return scalar(0xac00+(c-0x1100)*588+(v-0x1161)*28) + scalar(t!)
            }
            return scalar(c ?? 0x115f) + scalar(v ?? 0x1160) + (t.map(scalar) ?? "")
        }
        func flush() { output += current(); cho=nil; jung=nil; jong=nil; split=nil }
        for full in input {
            let c = full & 0xffff
            if isCho(c) {
                if cho != nil {
                    if let merged=combine(cho,full), last.map({isCho($0) || (0x3131...0x3186).contains($0)}) ?? true { cho=merged }
                    else { flush(); cho=full }
                } else if correctOrders { cho=full }
                else { flush(); cho=full }
            } else if isJung(c) {
                if jung != nil {
                    if let merged=combine(jung,full) { jung=merged }
                    else { flush(); jung=full }
                } else if correctOrders || last == nil || last.map({isCho($0) || (0x3131...0x314e).contains($0) || (0x3165...0x3186).contains($0)}) == true { jung=full }
                else { flush(); jung=full }
            } else if isJong(c) {
                if let prior=jong {
                    if let merged=combine(prior,full) { jong=merged; split=(prior,full) }
                    else { flush(); jong=full }
                } else if correctOrders || last == nil || (last.map(isJung) == true && cho != nil) { jong=full }
                else { flush(); jong=full }
            } else if (0x3131...0x314e).contains(c) || (0x3165...0x3186).contains(c) {
                let start=mapped(choMap,c-0x3131), end=mapped(jongMap,c-0x3131)
                if cho != nil && jung != nil {
                    if let prior=jong {
                        if let merged=combine(prior,end), let end { jong=merged; split=(prior,end) }
                        else { flush(); cho=start }
                    } else if let end { jong=end }
                    else { flush(); cho=start }
                } else if cho != nil {
                    if let merged=combine(cho,start) { cho=merged }
                    else { flush(); cho=start }
                } else if correctOrders { cho=start }
                else { flush(); cho=start }
            } else if (0x314f...0x3163).contains(c) || (0x3187...0x318e).contains(c) {
                let vowel = c <= 0x3163 ? c-0x314f+0x1161 : (mapped(oldVowels,c-0x3187) ?? c)
                if let end=jong {
                    let promoted=split?.1 ?? end
                    let next=jongMap.firstIndex(of:promoted).flatMap { mapped(choMap,$0) }
                    jong=split?.0; flush(); cho=next; jung=vowel
                } else if jung != nil {
                    if let merged=combine(jung,vowel) { jung=merged }
                    else { flush(); jung=vowel }
                } else { jung=vowel }
            } else if c == 0x3164 {
                if cho != nil && jung == nil && jong == nil { jung=0x1160 }
                else if cho == nil && jong == nil { cho=0x115f }
                else { flush(); cho=0x115f }
            } else { flush(); output += scalar(c) }
            last=c
        }
        return output+current()
    }
}
