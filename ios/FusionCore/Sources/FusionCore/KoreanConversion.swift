import Foundation

enum KoreanConversion {
    static func acceptsLiteral(_ text:String)->Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy{(48...57).contains($0.value) || $0.value==46}
    }
    static func candidates(_ input:String)->[Candidate] {
        var result:[Candidate]=[]
        func add(_ text:String,reading:String) {
            result.append(Candidate(text,reading:reading,consumedUTF16:reading.utf16.count))
        }
        let digits=String(input.prefix{isDigit($0)})
        if !digits.isEmpty {
            for value in numberForms(digits) { add(value,reading:digits) }
        }
        if input.hasPrefix(".") {
            let dots=String(input.prefix{$0=="."})
            for value in ["…","⋯","‥","。","．","·"] { add(value,reading:dots) }
        }
        // Numbered clauses retain the Arabic number unless the user chooses
        // the separately offered Han-numeral form.
        if input.hasPrefix("제") {
            let rest=input.dropFirst(),number=String(rest.prefix{isDigit($0)})
            let suffix=rest.dropFirst(number.count)
            let units:[Character:String]=["조":"條","항":"項","호":"號","장":"章","절":"節","편":"編","권":"卷","회":"回","차":"次"]
            if !number.isEmpty,let first=suffix.first,let unit=units[first] {
                let reading="제"+number+String(first)
                add("第"+number+unit,reading:reading)
                if let han=numberForms(number).first { add("第"+han+unit,reading:reading) }
            }
        }
        return Candidate.unique(result)
    }
    static func isDigit(_ c:Character)->Bool { c.unicodeScalars.count==1 && c.asciiValue.map{(48...57).contains($0)} == true }
    static func numberForms(_ digits:String)->[String] {
        let ordinary=Array("零一二三四五六七八九"),financial=Array("零壹貳參肆伍陸柒捌玖")
        let values=digits.compactMap(\.wholeNumberValue)
        guard values.count==digits.count,!values.isEmpty else { return [] }
        var result:[String]=[]
        if let number=Int(digits),number<10_000,!(digits.count>1 && digits.first=="0") {
            if number==0 { result.append("零") }
            else {
                let places=[1000,100,10,1],units=["千","百","十",""]
                var text="",zero=false
                for (place,unit) in zip(places,units) {
                    let digit=number/place%10
                    if digit==0 { if !text.isEmpty { zero=true };continue }
                    if zero { text+="零";zero=false }
                    if !(place==10 && digit==1 && text.isEmpty) { text+=String(ordinary[digit]) }
                    text+=unit
                }
                result.append(text)
            }
        }
        result += [String(values.map{ordinary[$0]}),String(values.map{financial[$0]})]
        if let n=Int(digits),String(n)==digits {
            let circle:UInt32?=n==0 ? 0x24ea:(1...20).contains(n) ? 0x2460+UInt32(n-1):(21...35).contains(n) ? 0x3251+UInt32(n-21):(36...50).contains(n) ? 0x32b1+UInt32(n-36):nil
            if let circle { result.append(String(UnicodeScalar(circle)!)) }
            if (1...20).contains(n) {
                result += [String(UnicodeScalar(0x2474+UInt32(n-1))!),String(UnicodeScalar(0x2488+UInt32(n-1))!)]
            }
            if (1...10).contains(n) { result.append(String(UnicodeScalar(0x2776+UInt32(n-1))!)) }
        }
        result.append(String(String.UnicodeScalarView(digits.unicodeScalars.map{UnicodeScalar($0.value+0xfee0)!})))
        var seen=Set<String>();return result.filter{seen.insert($0).inserted}
    }
    struct ReadingKey {
        let unit:Int
        // Individual reading changes must only admit the corresponding Hanzi,
        // not every homophone of the replacement syllable.
        let hanja:String?
        let soundLaw:Bool
        init(_ unit:Int,_ hanja:String?=nil,soundLaw:Bool=false) { self.unit=unit;self.hanja=hanja;self.soundLaw=soundLaw }
    }
    static func readingKeys(_ unit:Int,initial:Bool,previous:Int?=nil)->[ReadingKey] {
        var result=[ReadingKey(unit)]
        // Alternate Northern readings supplement, rather than replace, the
        // dictionary's existing readings, including those within compound words.
        if unit==0xd788 { result.append(ReadingKey(0xd76c)) } // 히 -> 희
        if unit==0xd398 { result.append(ReadingKey(0xd3d0)) } // 페 -> 폐
        if unit==0xba54 { result.append(ReadingKey(0xba8c)) } // 메 -> 몌
        // NIKL: https://www.korean.go.kr/nkview/nklife/1988_4/15_3.html
        // Internal 렬/률 lose ㄹ after a vowel or ㄴ in Southern spellings.
        let previousTail=previous.flatMap { (0xac00...0xd7a3).contains($0) ? ($0-0xac00)%28:nil }
        let internalRieul=[0xb82c,0xb960].contains(unit) && (previousTail==0 || previousTail==4)
        if initial || internalRieul,(0xac00...0xd7a3).contains(unit) {
            let syllable=unit-0xac00,lead=syllable/588,vowel=syllable%588/28,tail=syllable%28
            let yVowels:Set<Int>=[2,6,7,12,17,20]
            if lead==5 { result.append(ReadingKey(0xac00+(yVowels.contains(vowel) ? 11:2)*588+vowel*28+tail,soundLaw:true)) }
            else if lead==2,[6,12,17,20].contains(vowel) { result.append(ReadingKey(0xac00+11*588+vowel*28+tail,soundLaw:true)) }
        }
        // NIKL: https://www.korean.go.kr/nkview/nklife/1995_4/5_7.html
        // AKS: https://encykorea.aks.ac.kr/Article/E0066411
        // 憩: NIKL, 한글 맞춤법 영향 평가 (2014), p.161, report_seq=764.
        // 醵: https://korean.go.kr/front/mcfaq/mcfaqView.do?mcfaq_seq=8928
        let specific:[Int:(String,String)]=[
            0xc678:("왜","歪"), 0xac70:("갹","醵"), 0xacc4:("게","憩"),
            0xcd09:("주","嗾"), 0xd64d:("항","肛"), 0xc2dd:("지","識識"),
            0xb860:("논","論論")
        ]
        if let (reading,hanja)=specific[unit] { result.append(ReadingKey(Int(reading.utf16.first!),hanja)) }
        // DLIFLC: https://ankdm.dliflc.edu/ANKDM/ankdc/pdfs/Grammar_Index.pdf
        if unit==0xc5fc,[0xd398,0xd3d0].contains(previous) { result.append(ReadingKey(0xb834,"炎")) } // 페염/폐염 -> 肺炎
        if unit==0xc464,previous==0xc6d0 { result.append(ReadingKey(0xc218,"讐")) } // 원쑤 only, not 元帥
        if unit==0xb0e5,previous==0xad81 { result.append(ReadingKey(0xb7c9,"量")) } // 궁냥
        return result
    }
}
