import Foundation

/// Swift port of the bundled VietPad TelexIM/VniIM/VietKeyInput, called in the
/// same order as Android's VietIMEMode.keyTyped. Original algorithm: Au D. Xuong,
/// Quan Nguyen and Quang D. Le. See the bundled VietPad license/attribution.
/// Keep UTF-16 comparisons: Java distinguishes composed and decomposed strings.
public enum VietnameseComposer {
    private static let table = [
        "âaăêeiôoơuưyÂAĂÊEIÔOƠUƯYdD",
        "ấáắếéíốóớúứýẤÁẮẾÉÍỐÓỚÚỨÝđĐ",
        "ầàằềèìồòờùừỳẦÀẰỀÈÌỒÒỜÙỪỲ",
        "ẩảẳểẻỉổỏởủửỷẨẢẲỂẺỈỔỎỞỦỬỶ",
        "ẫãẵễẽĩỗõỡũữỹẪÃẴỄẼĨỖÕỠŨỮỸ",
        "ậạặệẹịộọợụựỵẬẠẶỆẸỊỘỌỢỤỰỴ"
    ].map { Array($0.utf16) }
    private static func string(_ units:[UInt16]) -> String { String(decoding:units,as:UTF16.self) }
    private static func contains(_ set:String,_ unit:UInt16) -> Bool { set.utf16.contains(unit) }
    private static func lower(_ unit:UInt16) -> UInt16 { string([unit]).lowercased().utf16.first! }
    private static func base(_ unit:UInt16) -> UInt16 { string([unit]).decomposedStringWithCanonicalMapping.utf16.first! }

    public static func compose(_ input:String,layout:KeyboardLayout) -> String {
        appending(input,to:"",layout:layout)
    }
    /// Apply keys to the displayed text, rather than replaying a keystroke history.
    public static func appending(_ input:String,to text:String,layout:KeyboardLayout) -> String {
        guard layout == .telex || layout == .vni else { return text+input }
        var units=Array(text.utf16)
        for key in input.utf16 {
            let start=(units.lastIndex(of:32).map { $0+1 }) ?? 0
            let word=Array(units[start...])
            if !word.isEmpty,let accent=accent(for:key,word:word,layout:layout) {
                let converted=convert(word,accent:accent)
                if converted != word { units.replaceSubrange(start...,with:converted);continue }
            }
            units.append(key)
        }
        return string(units)
    }
    private static func accent(for key:UInt16,word:[UInt16],layout:KeyboardLayout) -> Int? {
        if layout == .vni { return (48...57).contains(key) ? Int(key-48):nil }
        let key=lower(key)
        let marks:[UInt16:Int]=[115:1,102:2,114:3,120:4,106:5,97:6,101:6,111:6,119:7,100:9,122:0]
        guard let mark=marks[key] else { return nil }
        guard mark == 6 || mark == 7 else { return mark }
        for unit in word {
            for row in table {
                let columns = mark == 7 || key == 97 ? 0..<3 : key == 111 ? 6..<9 : 3..<5
                if columns.contains(where:{unit == row[$0] || unit == row[$0+12]}) { return mark == 7 ? 8:6 }
            }
        }
        return mark == 7 ? 7:nil
    }
    private static func convertChar(_ unit:UInt16,_ accent:Int) -> UInt16 {
        for (tone,row) in table.enumerated() {
            guard let column=row.firstIndex(of:unit) else { continue }
            if contains("DdĐđ",unit) && accent != 0 && accent != 9 { return unit }
            var composed:UInt16
            if accent < 6 { composed=table[accent][column] }
            else if accent == 9 && column > 23 { composed=table[1][column] }
            else {
                var position=column
                if accent == 6 {
                    if [1,4,7,13,16,19].contains(column) { position-=1 }
                    else if [2,8,14,20].contains(column) { position-=2 }
                } else if accent == 7 {
                    if [7,9,19,21].contains(column) { position+=1 }
                    else if [6,18].contains(column) { position+=2 }
                } else if accent == 8 {
                    if [1,13].contains(column) { position+=1 }
                    else if [0,12].contains(column) { position+=2 }
                }
                composed=table[tone][position]
            }
            if composed == unit {
                if accent < 6 || (accent == 9 && column > 23) { composed=table[0][column] }
                else {
                    var position=column
                    if accent == 6 && [0,3,6,12,15,18].contains(column) { position+=1 }
                    else if accent == 7 && [8,10,20,22].contains(column) { position-=1 }
                    else if accent == 8 && [2,14].contains(column) { position-=1 }
                    composed=table[tone][position]
                }
                if composed == unit && accent == 0 { composed=base(unit) }
            }
            return composed
        }
        return unit
    }
    private static func fixUO(_ distance:Int,_ accent:Int,_ units:inout [UInt16]) {
        let first=units.count-distance,second=first+1
        if accent == 7 && lower(base(units[first])) == 117 {
            units[second]=convertChar(units[second],accent)
            units[first]=convertChar(units[first],accent)
            for row in table {
                if units[second] == row[7] || units[second] == row[19] {
                    if contains("ưƯ",units[first]) { units[second]=convertChar(units[second],accent);break }
                } else if units[second] == row[8] || units[second] == row[20] {
                    if lower(units[first]) == 117 { units[first]=convertChar(units[first],accent);break }
                }
            }
        } else if accent == 6 {
            units[second]=convertChar(units[second],6)
            if contains("ưƯ",units[first]) { units[first]=convertChar(units[first],7) }
        } else {
            if accent == 0 && contains("ơo",lower(units[second])) { units[first]=convertChar(units[first],accent) }
            units[second]=convertChar(units[second],accent)
        }
    }
    /// VietIMEMode only calls shiftAccent with the numeric shape keys 6 and 8.
    private static func shiftAccent(_ word:[UInt16]) -> [UInt16] {
        var units=word
        let last=word.count-1,previous=last-1
        let first=lower(word[last]),second=lower(word[previous])
        let decomposed=string(word).decomposedStringWithCanonicalMapping.lowercased()
        let columns:[Int]
        if word.count == 3 && (decomposed.hasPrefix("qu") || decomposed.hasPrefix("gi")) { columns=[5,9] }
        else if contains("aeoy",first) { columns=[5,7,9,11] }
        else { return word }
        for tone in 1..<table.count where columns.contains(where:{second == table[tone][$0]}) {
            units[previous]=convertChar(word[previous],0)
            units[last]=convertChar(word[last],tone)
            break
        }
        return units
    }
    private static func convert(_ word:[UInt16],accent:Int) -> [UInt16] {
        let count=word.count,last=count-1
        var units=word
        if accent == 9 && contains("DdĐđ",word[0]) {
            units[0]=convertChar(word[0],accent);return units
        }
        guard count < 8,let scalar=UnicodeScalar(word[last]),
              [.uppercaseLetter,.lowercaseLetter,.titlecaseLetter,.modifierLetter,.otherLetter,.decimalNumber].contains(scalar.properties.generalCategory) else { return word }
        let lowered=word.map(lower)
        func finish(_ converted:[UInt16]) -> [UInt16] {
            if accent == 0 && converted == word {
                return Array(string(word).decomposedStringWithCanonicalMapping.replacingOccurrences(of:"đ",with:"d").replacingOccurrences(of:"Đ",with:"D").utf16)
            }
            return converted
        }
        if count > 2 && contains("hg",lowered[last]) {
            if count > 3 { fixUO(4,accent,&units) }
            else { units[0]=convertChar(units[0],accent) }
            return finish(units)
        } else if count >= 3 && (contains("cmnpt",lowered[last]) || (contains("iu",lowered[last]) && contains("uư",lowered[count-3]))) {
            fixUO(3,accent,&units);return finish(units)
        } else if count == 3 && (lowered.starts(with:Array("qu".utf16)) || lowered.starts(with:Array("gi".utf16))) {
            units[last]=convertChar(units[last],accent);return finish(units)
        } else if count > 1 && accent == 6 && contains("uiy",lower(base(units[last-1]))) {
            units=shiftAccent(word);units[last]=convertChar(units[last],accent);return finish(units)
        }
        if count > 1 {
            for tone in table.indices {
                if [9,10,21,22].contains(where:{units[last-1] == table[tone][$0]}) && lower(units[last]) == 111 {
                    units[last]=convertChar(units[last],accent)
                    if tone != 0 { units[last]=convertChar(units[last],tone) }
                    return units
                }
            }
        }
        let consonants="bcdfghjklmnpqrstvwxyz0123456789"
        if count > 1 && !contains("Đđ",units[last-1]) && !contains(consonants,lower(units[last-1])) && contains("abcdefghijklmnopqrstuvwxyz",lower(units[last])) {
            if count > 2 && accent == 7 && lower(units[last-2]) == 117 {
                units[last-2]=convertChar(units[last-2],accent);units[last-1]=convertChar(units[last-1],accent)
            } else if count > 2 && accent == 6 && lower(base(units[last-2])) == 117 {
                if units[last-2] == 0x1b0 { units[last-2]=117 }
                if units[last-2] == 0x1af { units[last-2]=85 }
                units[last-1]=convertChar(units[last-1],accent)
            } else if (accent == 6 || accent == 7) && contains("iy",lower(units[last-1])) {
                units[last]=convertChar(units[last],accent)
            } else if accent == 8 && !contains(consonants,lower(units[last])) {
                if contains("iuo",lower(base(units[last-1]))) { units=shiftAccent(word) }
                units[last]=convertChar(units[last],accent)
            } else {
                let plain=String(String.UnicodeScalarView(string(word).decomposedStringWithCanonicalMapping.unicodeScalars.filter { !(0x300...0x36f).contains($0.value) })).lowercased()
                let modernEnding=["oa","oe","uy"].contains(where:plain.hasSuffix)
                if count > 2 && (count > 3 || !contains("DdĐđ",units[0])) { units[last-2]=convertChar(units[last-2],0) }
                let target=modernEnding ? last:last-1
                units[target]=convertChar(units[target],accent)
            }
            return finish(units)
        } else if !contains("bcfghjklmnpqrstvwxz0123456789",lower(units[last])) {
            units[last]=convertChar(units[last],accent);return finish(units)
        }
        return word
    }
}
