import Foundation

public struct KeySpec: Identifiable, Equatable {
    public var id:String
    public var label:String
    /// Center, left, up, right, down. Non-flick keys may expose accent alternatives.
    public var values:[String]
    public var flick:Bool
    public var code:String?
    public var hints:[String]?
    public var isSpacer:Bool { label == "　" }
    public init(_ label:String, values:[String]? = nil, id:String? = nil, flick:Bool = false,code:String? = nil) {
        self.id=id ?? label; self.label=label; self.values=values ?? [label]; self.flick=flick
        self.code=code
    }
}
public enum LayoutCatalog {
    private static let punctuation:[Character:String] = [";":"SEMICOLON","'":"APOSTROPHE",",":"COMMA",".":"PERIOD","/":"SLASH","-":"MINUS","=":"EQUALS","[":"LEFT_BRACKET","]":"RIGHT_BRACKET","\\":"BACKSLASH","`":"GRAVE"]
    public static func rows(for mode:InputMode, shifted:Bool = false, numberRow:Bool = false,tablet:Bool = false,capsLocked:Bool = false) -> [[KeySpec]] {
        let layout=mode.layout
        if mode.language.isLatin { return LatinLayouts.rows(mode:mode,shifted:shifted,numberRow:numberRow,tablet:tablet,capsLocked:capsLocked) }
        if layout == .kana12 {
            let groups=["あいうえお","かきくけこ","さしすせそ","たちつてと","なにぬねの","はひふへほ","まみむめも","や（ゆ）よ","らりるれろ","゛゜小゛゜","わをんー〜","。、？！…"]
            return stride(from:0,to:12,by:3).map { start in groups[start..<start+3].enumerated().map { offset,s in
                var key=KeySpec(String(s.first!),values:s.map(String.init),id:"kana\(start+offset)",flick:mode.kanaFlick)
                if start+offset == 9 { key.label="小゛゜";key.hints=key.values;key.hints?[0]="小゛゜";key.values[0]="*" }
                return key
            } }
        }
        if layout == .godan {
            let groups:[[(String,[String])]] = [
                [("A",["a","あっ","あん","ゃ","1"]),("K",["k","k","q","g","2"]),("H",["h","p","f","b","3"])],
                [("I",["i","いっ","いん","ぃ","4"]),("S",["s","s","j","z","5"]),("M",["m","/","l","ー","6"])],
                [("U",["u","うっ","うん","ゅ","7"]),("T",["t","t","c","d","8"]),("Y",["y","（","x","）","9"])],
                [("E",["e","えっ","えん","ぇ","e"]),("N",["n",":","n","・","0"]),("R",["r","。","?","!","、"])],
                [("O",["o","おっ","おん","ょ","o"]),("W",["w","「","v","」","w"])]]
            let table=ImportedTables.shared.layouts["LayoutGodan.TABLE"]!
            return groups.enumerated().map { row,items in items.map { label,hints in
                let codes=table[label]!,order=[0,3,1,4,2]
                var key=KeySpec(label,values:order.map{codes[$0] == 0 ? "":scalar(codes[$0])},flick:true,code:label)
                key.hints=hints;return key
            } }
        }
        if layout == .kanaSyllables || layout == .kanaIroha {
            let text = LayoutExtras.shared.kana[layout == .kanaSyllables ? "KEYS_AIUEO":"KEYS_IROHA"]!
            let chars=Array(text)
            if mode.syllablesDirection != "horizontal" {
                var columns=stride(from:0,to:chars.count,by:5).map { Array(chars[$0..<min($0+5,chars.count)]) }
                if mode.syllablesDirection=="right" { columns.reverse() }
                return (0..<5).map { row in columns.enumerated().compactMap { column,characters in
                    guard row<characters.count else { return nil }
                    return KeySpec(String(characters[row]),id:"\(column)-\(row)")
                } }
            }
            return stride(from:0,to:chars.count,by:10).map { start in chars[start..<min(start+10,chars.count)].enumerated().map { i,c in KeySpec(String(c),id:"\(start+i)") } }
        }
        var rows:[String]
        switch layout {
        case .qwertz,.deutsch: rows=["qwertzuiop","asdfghjkl","yxcvbnm"]
        case .azerty: rows=["azertyuiop","qsdfghjklm","wxcvbn"]
        case .dvorak: rows=["',.pyfgcrl","aoeuidhtns",";qjkxbmwvz"]
        case .colemak: rows=["qwfpgjluy;","arstdhneio","zxcvbkm"]
        default: rows=["qwertyuiop","asdfghjkl","zxcvbnm"]
        }
        if layout == .deutsch { rows=["qwertzuiopü","asdfghjklöä","yxcvbnmß"] }
        if mode.language == .spanish && layout == .qwerty { rows[1]+="ñ" }
        let extended:[KeyboardLayout]=[.hangul390,.hangul391,.hangul391Strict,.hangul393,.kanaJIS,.zhuyin,.dayi]
        if extended.contains(layout) {
            rows=["1234567890-=","qwertyuiop[]","asdfghjkl;'","zxcvbnm,./"]
            if [.hangul390,.hangul391,.hangul391Strict,.hangul393,.kanaJIS].contains(layout) { rows[3]+="`\\" }
            if layout == .dayi { rows[3]+="`\\" }
        } else if numberRow || layout == .vni { rows.insert("1234567890",at:0) }
        if mode.language == .pinyin && mode.doublePinyin.usesSemicolon { rows[rows.count-2]+=";" }
        if tablet && !extended.contains(layout) {
            for char in ",." where !rows.joined().contains(char) { rows[rows.count-1].append(char) }
        }
        if [.pinyin,.zhuyin,.cangjie,.quick,.jyutping].contains(mode.language) && !extended.contains(layout) {
            for char in ",." where !rows.joined().contains(char) { rows[rows.count-1].append(char) }
        }
        if mode.language == .japanese && layout == .romaji { rows[rows.count-2]+="ー" }
        if mode.language == .vietnamese && mode.hanNom { for char in ",." where !rows[rows.count-1].contains(char) { rows[rows.count-1].append(char) } }
        let tableID:String?
        switch layout {
        case .hangul2: tableID="Hangul2Set.TABLE_KS"
        case .hangul390: tableID="Hangul3Set.TABLE_390"
        case .hangul391,.hangul391Strict: tableID="Hangul3Set.TABLE_391"
        case .hangulOld2: tableID="HangulOld.TABLE_OLD_2SET"
        case .hangul393: tableID="HangulOld.TABLE_OLD_393"
        case .kanaJIS: tableID="LayoutKana.TABLE_JIS"
        case .zhuyin: tableID="LayoutZhuyin.TABLE"
        default: tableID=nil
        }
        let table=tableID.flatMap { ImportedTables.shared.layouts[$0] } ?? [:]
        return rows.enumerated().map { rowIndex,row in
            row.enumerated().map { index,char in
                let code=punctuation[char] ?? String(char).uppercased()
                if layout == .cangjie || layout == .dayi,
                   let root=ImportedTables.shared.layouts[layout == .dayi ? "LayoutCangjie.TABLE_DAYI3":"LayoutCangjie.TABLE_QWERTY"]?[code] {
                    let label=scalar(root[min(shifted ? 1:0,root.count-1)])
                    return KeySpec(label,values:[shifted ? label:String(char)],id:"\(rowIndex)-\(index)",code:code)
                }
                if [.pinyin,.zhuyin,.cangjie,.quick,.jyutping].contains(mode.language),let values=ImportedTables.shared.layouts["LayoutExt.TABLE_CHINESE"]?[code] {
                    return KeySpec(scalar(values[min(shifted ? 1:0,values.count-1)]),id:"\(rowIndex)-\(index)",code:code)
                }
                if mode.language == .vietnamese && mode.hanNom && (char == "," || char == ".") {
                    return KeySpec(char == "," ? (shifted ? "《":"、"):(shifted ? "》":"。"),id:"\(rowIndex)-\(index)",code:code)
                }
                if let values=table[code], !values.isEmpty {
                    let output=scalar(values[min(shifted ? 1:0,values.count-1)])
                    if layout == .hangul391Strict && !shifted && (code == "9" || code == "SLASH") {
                        // Preserve Android's strict-vowel tag in a private-use input token.
                        let tagged=String(UnicodeScalar(0xf0000 | (values[0] & 0xffff))!)
                        return KeySpec(output,values:[tagged],id:"\(rowIndex)-\(index)",code:code)
                    }
                    return KeySpec(output,id:"\(rowIndex)-\(index)",code:code)
                }
                let shiftedSymbols:[Character:String] = ["1":"!","2":"@","3":"#","4":"$","5":"%","6":"^","7":"&","8":"*","9":"(","0":")","-":"_","=":"+","[":"{","]":"}",";":":","'":"\"",",":"<",".":">","/":"?","`":"~","\\":"|"]
                let output=shifted ? shiftedSymbols[char] ?? (char == "ß" ? "ẞ":String(char).uppercased()):String(char)
                let alternatives=accentAlternatives(char,shifted:shifted)
                return KeySpec(output,values:[output]+alternatives,id:"\(rowIndex)-\(index)",code:code)
            }
        }
    }
    public static func latinKey(code:String,mode:InputMode,shifted:Bool=false,altGraph:Bool=false,hardware:Bool=true,capsLocked:Bool=false)->KeySpec {
        LatinLayouts.key(code:code,mode:mode,shifted:shifted,altGraph:altGraph,hardware:hardware,capsLocked:capsLocked)
    }
    public static func symbols(second:Bool = false,layout:SymbolLayout = .system) -> [[KeySpec]] {
        if layout == .system {
            return (second ? ["[]{}#%^*+=", "_\\|~<>€£¥•", "…、。！？「」"] : ["1234567890","-/:;()$&@\"",".,?!'[]"]).enumerated().map { row,text in text.enumerated().map { column,char in
                KeySpec(String(char),values:[String(char)]+(LayoutExtras.shared.symbol[String(char)] ?? []),id:"symbol-\(row)-\(column)",code:punctuation[char] ?? String(char).uppercased())
            } }
        }
        var rows=["qwertyuiop",layout == .g || layout == .n1 || layout == .n2 ? "asdfghjkl;":"asdfghjkl","zxcvbnm,."]
        if layout == .n2 || layout == .o2 { rows.insert("1234567890",at:0) }
        return rows.enumerated().map { row,text in text.enumerated().map { column,char in
            let code=punctuation[char] ?? String(char).uppercased()
            let value=symbol(code:code,shifted:second,layout:layout) ?? String(char)
            return KeySpec(value,values:[value]+(LayoutExtras.shared.symbol[value] ?? []),id:"symbol-\(row)-\(column)",code:code)
        } }
    }
    public static func symbol(code:String,shifted:Bool,layout:SymbolLayout) -> String? {
        let table=ImportedTables.shared.layouts["LayoutSymbol.TABLE_\(layout == .system ? "G":layout.rawValue)"] ?? [:]
        guard let values=table[code] ?? ImportedTables.shared.layouts["LayoutQwerty.TABLE_QWERTY"]?[code],!values.isEmpty else { return nil }
        return scalar(values[min(shifted ? 1:0,values.count-1)])
    }
    public static var numbers:[[KeySpec]] {
        ["+-123=","*/456#","()789$",",0.%"].enumerated().map { row,text in text.enumerated().map { column,char in KeySpec(String(char),id:"number-\(row)-\(column)") } }
    }
    public static var emoji:[String] { EmojiCatalog.groups.flatMap(\.items).compactMap(\.first) }
    static func accentAlternatives(_ c:Character,shifted:Bool) -> [String] {
        let added:[Character:[String]]=["a":["ă","ą"],"o":["ơ"],"u":["ư"],"d":["đ"],"y":["ý"]]
        return ((LayoutExtras.shared.latin[String(c)] ?? [])+(added[c] ?? [])).map { shifted ? ($0 == "ß" ? "ẞ":$0.uppercased()):$0 }
    }
}

private struct LayoutExtras:Decodable {
    let latin:[String:[String]],symbol:[String:[String]],kana:[String:String]
    enum CodingKeys:String,CodingKey { case latin="LatinMoreKeysTable",symbol="SymbolMoreKeysTable",kana }
    static let shared:Self = {
        let url=Bundle.module.url(forResource:"layout-extras",withExtension:"json",subdirectory:"Resources")!
        return try! JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
    }()
}
