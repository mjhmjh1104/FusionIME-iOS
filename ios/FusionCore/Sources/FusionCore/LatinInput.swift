import Foundation

/// Android COMBINING_ACCENT is retained as an input token, never as visible text.
public enum LatinKeyValue {
    public static func encoded(_ code:Int)->String {
        let value=scalar(code)
        return code & 0x80000000 == 0 ? value:"\u{f1000}"+value
    }
    public static func display(_ text:String)->String { text.hasPrefix("\u{f1000}") ? String(text.dropFirst()):text }
    public static func isDead(_ text:String)->Bool { text.hasPrefix("\u{f1000}") }
}

/// Event order and normalization from AOSP DeadKeyCombiner.
public struct LatinDeadKeys {
    public private(set) var pending=""
    public init() {}
    public mutating func reset() { pending="" }
    public mutating func backspace()->Bool { guard !pending.isEmpty else { return false };pending.removeLast();return true }
    public mutating func input(_ token:String)->String? {
        let text=LatinKeyValue.display(token),dead=LatinKeyValue.isDead(token)
        if pending.isEmpty { if dead { pending=text;return nil };return text }
        if text.first?.isWhitespace == true || text==pending.last.map(String.init) {
            let result=pending;pending="";return result
        }
        if dead { pending+=text;return nil }
        let marks:[Character:String] = ["`":"\u{300}","ˋ":"\u{300}","´":"\u{301}","^":"\u{302}","ˆ":"\u{302}","~":"\u{303}","˜":"\u{303}","¯":"\u{304}","˘":"\u{306}","˙":"\u{307}","¨":"\u{308}","ˀ":"\u{309}","˚":"\u{30a}","˝":"\u{30b}","ˇ":"\u{30c}","ˈ":"\u{30d}","ʻ":"\u{312}","᾽":"\u{313}","ʽ":"\u{314}","ʼ":"\u{315}","'":"\u{31b}",".":"\u{323}","¸":"\u{327}","˛":"\u{328}","ˌ":"\u{329}","ˍ":"\u{331}","-":"\u{335}"]
        let strokes=Dictionary(uniqueKeysWithValues:zip(Array("DGHILOTdghilot"),Array("ĐǤĦƗŁØŦđǥħɨłøŧ")))
        var base=text.first.map(String.init) ?? "",suffix=""
        for accent in pending {
            if accent=="-",let first=text.first,let replacement=strokes[first] { base=String(replacement) }
            else { suffix+=marks[accent] ?? String(accent) }
        }
        pending="";return (base+suffix).precomposedStringWithCanonicalMapping+text.dropFirst()
    }
}

public enum LatinInputRules {
    // Source: LatinIME/donottranslate-config-spacing-and-punctuations.xml.
    public static let punctuation=["!","?",",",":",";","\"","(",")","'","-","/","@","_"]
    public static func separator(_ c:Character)->Bool { c.isWhitespace || "\"()[]{}*&<>+=|.,;:!?/_\\".contains(c) }
    public static func connector(_ c:Character)->Bool { "'-".contains(c) }
    public static func word(_ c:Character)->Bool { c.isLetter || connector(c) || c.unicodeScalars.allSatisfy{CharacterSet.nonBaseCharacters.contains($0)} }
    public static func precededBySpace(_ c:Character)->Bool { "([{&".contains(c) }
    public static func followedBySpace(_ c:Character)->Bool { ".,;:!?)]}&".contains(c) }
    public static func allowsDoubleSpace(after c:Character)->Bool {
        c.isLetter || c.isNumber || "'\")]}>+%".contains(c) || c.unicodeScalars.contains{$0.properties.generalCategory == .otherSymbol}
    }
    public static func insideQuoteOrAfterDigit(_ text:String)->Bool {
        if text.last?.isNumber==true { return true }
        var previous:Character?=nil,last:Character?=nil
        for c in text.reversed() {
            if c == "\"",previous?.isWhitespace==true { return false }
            if c.isWhitespace,previous == "\"" { return true }
            previous=c;last=c
        }
        return last == "\""
    }
    public static func looksLikeURL(_ text:String)->Bool {
        // StringUtils.lastPartLooksLikeURL, including its ASCII-run boundary.
        let units=Array(text.unicodeScalars);var index=units.count,w=0,slashes=0,hasSlash=false,hasPeriod=false,code:UInt32=0
        while index>0 {
            code=units[index-1].value
            if code<46 || code>122 { break }
            if code==46 { hasPeriod=true }
            if code==47 { hasSlash=true;slashes+=1;if slashes==2 { return true } } else { slashes=0 }
            w=code==119 ? w+1:0;index-=1
        }
        return (w>=3 && hasPeriod) || (slashes==1 && (index==0 || UnicodeScalar(code).map{CharacterSet.whitespacesAndNewlines.contains($0)} == true)) || (hasPeriod && hasSlash)
    }
}

enum LatinLayouts {
    private static let maps:[String:[String:String]] = {
        let url=Bundle.module.url(forResource:"latin-keymaps",withExtension:"json",subdirectory:"Resources")!
        return try! JSONDecoder().decode([String:[String:String]].self,from:Data(contentsOf:url))
    }()
    static func key(code:String,mode:InputMode,shifted:Bool,altGraph:Bool=false,hardware:Bool=false,tablet:Bool=false,capsLocked:Bool=false)->KeySpec {
        let layout=mode.layout
        let mapName=layout == .azerty ? "AZERTY":[KeyboardLayout.qwertz,.deutsch].contains(layout) ? "QWERTZ":layout == .dvorak ? "DVORAK":layout == .colemak ? "COLEMAK":""
        var mapping=maps["KEYCODE_MAP_"+mapName] ?? [:]
        if hardware && [.dvorak,.colemak].contains(layout) { mapping=[:] }
        if !hardware {
            if layout == .azerty {
                mapping.merge(maps["SOFT_KEYCODE_MAP_AZERTY_NUMBERS"] ?? [:],uniquingKeysWith:{$1})
                if !tablet { mapping.merge(maps["SOFT_KEYCODE_MAP_AZERTY_MOBILE"] ?? [:],uniquingKeysWith:{$1}) }
            } else if layout == .deutsch { mapping.merge(maps["SOFT_KEYCODE_MAP_DEUTSCH_QWERTZ"] ?? [:],uniquingKeysWith:{$1}) }
        }
        let mapped=mapping[code] ?? code
        var table=ImportedTables.shared.layouts["LayoutQwerty.TABLE_QWERTY"] ?? [:]
        table.merge(ImportedTables.shared.layouts["LayoutExt.TABLE"] ?? [:],uniquingKeysWith:{$1})
        let tableName=layout == .azerty ? "AZERTY":[KeyboardLayout.qwertz,.deutsch].contains(layout) ? "GERMAN_QWERTZ":mode.language == .spanish && layout == .qwerty ? "SPANISH_QWERTY":""
        table.merge(ImportedTables.shared.layouts["LayoutLatin.TABLE_"+tableName] ?? [:],uniquingKeysWith:{$1})
        let altTable=ImportedTables.shared.layouts["LayoutLatin.TABLE_"+tableName+"_ALTGR"]
        let alternate=altTable?[mapped] ?? altTable?[code]
        let codes=(altGraph ? alternate:nil) ?? table[mapped] ?? []
        let codePoint=codes.isEmpty ? 0:codes[min(capsLocked ? 2:(shifted ? 1:0),codes.count-1)]
        let value=LatinKeyValue.encoded(codePoint),label=LatinKeyValue.display(value)
        var alternatives=label.first.map { LayoutCatalog.accentAlternatives(Character(String($0).lowercased()),shifted:shifted) } ?? []
        alternatives += LayoutCatalog.symbolAlternatives(label)
        alternatives += (alternate ?? []).map(LatinKeyValue.encoded)
        var seen=Set([value]);alternatives=alternatives.filter{seen.insert($0).inserted}
        return KeySpec(label,values:[value]+alternatives,code:mapped)
    }
    static func rows(mode:InputMode,shifted:Bool,numberRow:Bool,tablet:Bool,capsLocked:Bool=false)->[[KeySpec]] {
        let layout=mode.layout
        var physical=["qwertyuiop","asdfghjkl","zxcvbnm"]
        if layout == .azerty || layout == .colemak || (mode.language == .spanish && layout == .qwerty) { physical[1]+=";" }
        if layout == .deutsch { physical=["qwertyuiop[","asdfghjkl;'","zxcvbnm."] }
        if layout == .dvorak { physical=["qwertyuiop","asdfghjkl;","xcvbnm,./"] }
        if tablet { for c in ",." where !physical[2].contains(c) { physical[2].append(c) } }
        if numberRow { physical.insert("1234567890",at:0) }
        let punctuation:[Character:String]=[";":"SEMICOLON","'":"APOSTROPHE",",":"COMMA",".":"PERIOD","/":"SLASH","[":"LEFT_BRACKET"]
        return physical.enumerated().map { row,text in text.enumerated().map { column,c in
            var result=key(code:punctuation[c] ?? String(c).uppercased(),mode:mode,shifted:shifted,tablet:tablet,capsLocked:capsLocked)
            result.id="\(row)-\(column)";return result
        } }
    }
}
