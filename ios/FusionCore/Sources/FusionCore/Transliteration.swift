import Foundation

public enum VNIComposer {
    public static func compose(_ input:String) -> String { VietnameseComposer.compose(input,layout:.vni) }
}

public enum KanaComposer {
    private static let cycles:[String:String] = {
        let url=Bundle.module.url(forResource:"kana-modifiers",withExtension:"json",subdirectory:"Resources")!
        return try! JSONDecoder().decode([String:String].self,from:Data(contentsOf:url))
    }()
    public static func modified(_ text:String,action:String) -> String {
        guard let last=text.last else { return text }
        let normal=Array("あいうえおやゆよつわかけ"),small=Array("ぁぃぅぇぉゃゅょっゎゕゖ")
        var replacement=String(last)
        if action=="*" { replacement=cycles[String(last)] ?? String(last) }
        else if action=="小" {
            if let i=normal.firstIndex(of:last) { replacement=String(small[i]) }
            else if let i=small.firstIndex(of:last) { replacement=String(normal[i]) }
        } else {
            let decomposed=replacement.decomposedStringWithCanonicalMapping
            let base=decomposed.unicodeScalars.first.map(String.init) ?? replacement
            let mark=action=="゜" ? "\u{309a}":"\u{3099}"
            replacement=(decomposed.contains(mark) ? base:base+mark).precomposedStringWithCanonicalMapping
        }
        return String(text.dropLast())+replacement
    }
    static let table: [String:String] = {
        var result:[String:String]=[:]
        let rows = ["a i u e o|あいうえお", "ka ki ku ke ko|かきくけこ", "sa shi su se so|さしすせそ", "ta chi tsu te to|たちつてと", "na ni nu ne no|なにぬねの", "ha hi fu he ho|はひふへほ", "ma mi mu me mo|まみむめも", "ya yu yo|やゆよ", "ra ri ru re ro|らりるれろ", "wa wi we wo|わゐゑを", "ga gi gu ge go|がぎぐげご", "za ji zu ze zo|ざじずぜぞ", "da di du de do|だぢづでど", "ba bi bu be bo|ばびぶべぼ", "pa pi pu pe po|ぱぴぷぺぽ", "va vi vu ve vo|ゔゔゔゔゔ"]
        for row in rows {
            let parts=row.split(separator:"|")
            for (key,value) in zip(parts[0].split(separator:" "),parts[1]) { result[String(key)]=String(value) }
        }
        for (prefix,kana) in [("ky","き"),("gy","ぎ"),("sh","し"),("sy","し"),("jy","じ"),("j","じ"),("ch","ち"),("ty","ち"),("ny","に"),("hy","ひ"),("by","び"),("py","ぴ"),("my","み"),("ry","り")] {
            for (vowel,small) in [("a","ゃ"),("u","ゅ"),("o","ょ")] { result[prefix+vowel]=kana+small }
        }
        for (key,value) in ["si":"し","ti":"ち","tu":"つ","hu":"ふ","zi":"じ","n'":"ん","nn":"ん","xtu":"っ","ltu":"っ","xtsu":"っ","ltsu":"っ","fa":"ふぁ","fi":"ふぃ","fe":"ふぇ","fo":"ふぉ","va":"ゔぁ","vi":"ゔぃ","ve":"ゔぇ","vo":"ゔぉ","she":"しぇ","je":"じぇ","che":"ちぇ","thi":"てぃ","dhi":"でぃ","tsa":"つぁ","tsi":"つぃ","tse":"つぇ","tso":"つぉ","wu":"う","ye":"いぇ"] { result[key]=value }
        for prefix in ["x","l"] { for (key,value) in ["a":"ぁ","i":"ぃ","u":"ぅ","e":"ぇ","o":"ぉ","ya":"ゃ","yu":"ゅ","yo":"ょ","wa":"ゎ","ka":"ゕ","ke":"ゖ"] { result[prefix+key]=value } }
        return result
    }()
    public static func compose(_ input:String, finalize:Bool = false) -> String {
        let chars=Array(input.lowercased()); var i=0; var output=""
        while i<chars.count {
            let c=chars[i]
            if i+1<chars.count && c==chars[i+1] && "bcdfghjklmpqrstvwxyz".contains(c) { output+="っ"; i+=1; continue }
            if c=="n" {
                if i+1==chars.count { output += finalize ? "ん" : "n"; i+=1; continue }
                if chars[i+1]=="n" && i+2<chars.count && "aiueoy".contains(chars[i+2]) { output+="ん"; i+=1; continue }
                if !"aiueoyn'".contains(chars[i+1]) { output+="ん"; i+=1; continue }
            }
            var matched=false
            for length in stride(from:min(4,chars.count-i),through:1,by:-1) {
                if let kana=table[String(chars[i..<i+length])] { output+=kana; i+=length; matched=true; break }
            }
            if matched { continue }
            if c=="゛" || c=="゜", let last=output.last {
                output.removeLast(); output += (String(last)+(c=="゛" ? "\u{3099}" : "\u{309a}")).precomposedStringWithCanonicalMapping
            } else { output += c=="-" ? "ー" : String(c) }
            i+=1
        }
        return output
    }
    public static func katakana(_ input:String) -> String {
        String(String.UnicodeScalarView(input.unicodeScalars.map { s in
            (0x3041...0x3096).contains(s.value) ? UnicodeScalar(s.value+0x60)! : s
        }))
    }
}

public enum TelexComposer {
    public static func compose(_ input:String) -> String { VietnameseComposer.compose(input,layout:.telex) }
}
