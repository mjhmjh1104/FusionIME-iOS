import Foundation

struct CantoneseEntry {
    var number:Int
    var text:String
    var romanization:String
    var input=""
    var syllables:[String] { romanization.filter{!$0.isNumber}.split(separator:" ").map(String.init) }
    var letters:String { syllables.joined() }
    var key:String { text+"\0"+romanization }
    func consuming(_ input:String) -> Self { var copy=self;copy.input=input;return copy }
}

/// Researcher/Segmenter search paths from the original Jyutping module. SQLite
/// replaces the three Android binary indices; source order is retained as number.
final class CantoneseEngine {
    private let lexicon:Lexicon
    private var cache:[String:[CantoneseEntry]]=[:]
    private var searchCache:[String:[CantoneseEntry]]=[:]
    struct Syllable { let alias:String,origin:String }
    typealias Scheme=[Syllable]
    private static let aliases:[String:String] = {
        let url=Bundle.module.url(forResource:"jyutping-syllables",withExtension:"json",subdirectory:"Resources")!
        return try! JSONDecoder().decode([String:String].self,from:Data(contentsOf:url))
    }()
    init(lexicon:Lexicon) { self.lexicon=lexicon }
    private func unique(_ values:[CantoneseEntry]) -> [CantoneseEntry] {
        var seen=Set<String>();return values.filter{seen.insert($0.key).inserted}
    }
    private func ranked(_ values:[CantoneseEntry]) -> [CantoneseEntry] {
        values.sorted { $0.input.count == $1.input.count ? $0.number<$1.number:$0.input.count>$1.input.count }
    }
    private func spell(_ value:String,input:String? = nil) -> [CantoneseEntry] {
        let key="s"+value
        if cache[key] == nil { cache[key]=lexicon.cantonese(spell:value,limit:Int(Int32.max)) }
        return cache[key]!.map{$0.consuming(input ?? value)}
    }
    private func anchors(_ value:String,input:String? = nil) -> [CantoneseEntry] {
        let normalized=value.replacingOccurrences(of:"y",with:"j"),key="a"+normalized
        if cache[key] == nil { cache[key]=lexicon.cantonese(anchors:normalized,limit:Int(Int32.max)) }
        return cache[key]!.map{$0.consuming(input ?? value)}
    }
    struct Segmentation {
        var schemes:[Scheme],queries:[Scheme],firstAliasLength:Int,hasFull:Bool
    }
    /// Compact state for Scheme.isValid; equivalent histories share suffix searches.
    private struct LongAState:Hashable {
        var tail="",count=0,priorA=false,lastA=false
        func adding(_ syllable:Syllable)->Self {
            var next=self
            next.priorA = priorA || lastA
            for c in syllable.origin {
                if (tailSuffix(next.tail,2)=="aa" && c=="m") || (next.tail=="aan" && c=="g") { next.count+=1 }
                next.tail=String((next.tail+String(c)).suffix(3))
            }
            next.lastA=syllable.origin.hasSuffix("a")
            return next
        }
        private func tailSuffix(_ text:String,_ n:Int)->String { String(text.suffix(n)) }
        func valid(aliasCount:Int)->Bool { !priorA || count==0 || count==aliasCount }
    }
    private struct FinishState:Hashable { var offset:Int,state:LongAState }
    func segment(_ value:String) -> Segmentation {
        func explicit(_ scheme:Scheme)->Segmentation {
            Segmentation(schemes:[scheme],queries:(1...scheme.count).reversed().map{Array(scheme.prefix($0))},firstAliasLength:scheme.first?.alias.count ?? 0,hasFull:true)
        }
        if value == "a" { return explicit([.init(alias:"a",origin:"aa")]) }
        if value == "m" || value == "o" { return explicit([.init(alias:value,origin:value)]) }
        if value == "mama" { return explicit([.init(alias:"ma",origin:"maa"),.init(alias:"ma",origin:"maa")]) }
        if value == "mami" { return explicit([.init(alias:"ma",origin:"maa"),.init(alias:"mi",origin:"mi")]) }
        let chars=Array(value),n=chars.count
        guard n>0 else { return Segmentation(schemes:[],queries:[],firstAliasLength:0,hasFull:false) }
        var edges=Array(repeating:[Syllable](),count:n)
        for start in chars.indices {
            for end in (start+1)...min(n,start+6) {
                let alias=String(chars[start..<end])
                if let origin=Self.aliases[alias] { edges[start].append(Syllable(alias:alias,origin:origin)) }
            }
        }
        func longA(_ text:String)->Int { text.components(separatedBy:"aam").count+text.components(separatedBy:"aang").count-2 }
        let counts=(0...n).map{longA(String(chars.prefix($0)))}
        // Determine full coverage and the original longest/fewest-syllables first scheme
        // without materializing the exponentially many equivalent a/aa segmentations.
        struct Best { var state:LongAState,count:Int,first:Int }
        var best=Array(repeating:[Best](),count:n+1),indices=Array(repeating:[LongAState:Int](),count:n+1)
        best[0]=[Best(state:LongAState(),count:0,first:0)];indices[0][LongAState()]=0
        for start in chars.indices {
            for syllable in edges[start] {
                let end=start+syllable.alias.count
                for path in best[start] {
                    let next=Best(state:path.state.adding(syllable),count:path.count+1,first:start==0 ? syllable.alias.count:path.first)
                    if let i=indices[end][next.state] {
                        if next.count<best[end][i].count { best[end][i]=next }
                    } else { indices[end][next.state]=best[end].count;best[end].append(next) }
                }
            }
        }
        let hasFull=best[n].contains{$0.state.valid(aliasCount:counts[n])}
        let first=(1...n).reversed().lazy.compactMap { end in best[end].filter{$0.state.valid(aliasCount:counts[end])}.min{$0.count<$1.count} }.first?.first ?? 0
        var finishCache:[FinishState:Bool]=[:]
        func finishes(_ offset:Int,_ state:LongAState)->Bool {
            if offset==n { return state.valid(aliasCount:counts[n]) }
            let key=FinishState(offset:offset,state:state)
            if let cached=finishCache[key] { return cached }
            let result=edges[offset].contains { finishes(offset+$0.alias.count,state.adding($0)) }
            finishCache[key]=result;return result
        }
        struct Prefix { var scheme:Scheme,state:LongAState,spell:String,anchors:String }
        var prefixes=Array(repeating:[Prefix](),count:n+1),seen=Array(repeating:Set<String>(),count:n+1),exists:[String:Bool]=[:]
        prefixes[0]=[Prefix(scheme:[],state:LongAState(),spell:"",anchors:"")]
        var relevant:[Scheme]=[],queries:[Scheme]=[]
        for start in chars.indices {
            for syllable in edges[start] {
                let end=start+syllable.alias.count
                for prefix in prefixes[start] {
                    let spell=prefix.spell+syllable.origin
                    if exists[spell]==nil { exists[spell]=lexicon.hasCantonesePrefix(spell) }
                    // This is an exact index exclusion, not a search quota: no entry can
                    // have this spelling or any longer spelling beginning with it.
                    guard exists[spell]==true else { continue }
                    let scheme=prefix.scheme+[syllable],anchors=prefix.anchors+String(syllable.alias.first!)
                    let key=scheme.map(\.origin).joined(separator:" ")+"|"+anchors
                    guard seen[end].insert(key).inserted else { continue }
                    let state=prefix.state.adding(syllable)
                    prefixes[end].append(Prefix(scheme:scheme,state:state,spell:spell,anchors:anchors))
                    if state.valid(aliasCount:counts[end]) { relevant.append(scheme) }
                    if hasFull ? finishes(end,state):state.valid(aliasCount:counts[end]) { queries.append(scheme) }
                }
            }
        }
        func ordered(_ schemes:[Scheme])->[Scheme] {
            schemes.enumerated().sorted { a,b in
                let al=a.element.reduce(0){$0+$1.alias.count},bl=b.element.reduce(0){$0+$1.alias.count}
                if al != bl { return al>bl }
                if a.element.count != b.element.count { return a.element.count<b.element.count }
                return a.offset<b.offset
            }.map(\.element)
        }
        return Segmentation(schemes:ordered(relevant),queries:ordered(queries),firstAliasLength:first,hasFull:hasFull)
    }
    private func query(_ segmentation:Segmentation,length:Int) -> [CantoneseEntry] {
        segmentation.queries.flatMap { scheme in
            let key=scheme.map(\.origin).joined(),input=scheme.map(\.alias).joined(),a=scheme.compactMap{$0.origin.first}.map(String.init).joined()
            let allowed=Set(anchors(a).map(\.number))
            return spell(key,input:input).filter{allowed.contains($0.number)}
        }
    }
    private func modify(_ item:CantoneseEntry,text:String) -> CantoneseEntry {
        guard text.count>1,item.input.count != text.count else { return item }
        if item.letters.hasPrefix(text) { return item.consuming(text) }
        let tail=String(text.dropFirst(max(0,item.input.count-1)))
        guard tail.count<=6,let last=item.syllables.last else { return item }
        if let origin=Self.aliases[tail] { return last == origin ? item.consuming(text):item }
        return last.hasPrefix(tail) ? item.consuming(text):item
    }
    private func slices(_ text:String) -> [CantoneseEntry] {
        guard !text.isEmpty else { return [] }
        let hits=(1...text.count).reversed().flatMap { count -> [CantoneseEntry] in
            let prefix=String(text.prefix(count))
            return spell(prefix).map{modify($0,text:text)}+Array(ranked(anchors(prefix).map{modify($0,text:text)}).prefix(72))
        }
        return unique(ranked(hits))
    }
    private func search(_ text:String,schemes:Segmentation) -> [CantoneseEntry] {
        if let existing=searchCache[text] { return existing }
        let result=searchUncached(text,schemes:schemes);searchCache[text]=result;return result
    }
    private func searchUncached(_ text:String,schemes:Segmentation) -> [CantoneseEntry] {
        guard !text.isEmpty else { return [] }
        let spelled=spell(text),anchored=anchors(text),queried=query(schemes,length:text.count)
        let prefixes=(3..<25).contains(text.count) && (text.first == "m" || text.last == "m" || (spelled.isEmpty && !queried.contains{$0.input.count == text.count} && !schemes.hasFull))
        var partial:[CantoneseEntry]=[]
        if prefixes {
            for scheme in schemes.schemes {
                let leading=scheme.map(\.alias).joined(),tail=String(text.dropFirst(leading.count))
                guard let first=tail.first else { continue }
                let a=scheme.compactMap{$0.alias.first}.map(String.init).joined(),syllables=scheme.map(\.origin).joined(separator:" ")
                partial += anchors(a+tail).filter { item in
                    let reading=item.syllables.joined(separator:" ")
                    return reading.hasPrefix(syllables) && reading.dropFirst(syllables.count).split(separator:" ").compactMap(\.first).map(String.init).joined() == tail.replacingOccurrences(of:"y",with:"j")
                }.map{$0.consuming(text)}
                let suffix=tail.hasPrefix("y") ? "j"+tail.dropFirst():tail
                partial += anchors(a+String(first)).filter{$0.syllables.joined(separator:" ").hasPrefix(syllables+" "+suffix)}.map{$0.consuming(text)}
            }
            for count in (1..<text.count).reversed() {
                partial += anchors(String(text.prefix(count))).compactMap { item in
                    let tail=String(text.dropFirst(max(0,item.input.count-1)))
                    guard tail.count<=6,let last=item.syllables.last else { return nil }
                    if item.letters.hasPrefix(text) { return item.consuming(text) }
                    if let syllable=Self.aliases[tail] { return last == syllable ? item.consuming(text):nil }
                    return last.hasPrefix(tail) ? item.consuming(text):nil
                }
            }
        }
        let ideal=unique(queried.filter{$0.input.count == text.count}).sorted{$0.number<$1.number}
        let other=ranked(unique(queried.filter{$0.input.count<text.count}))
        let full=unique(spelled+ideal+anchored+partial)
        let fetched=unique(Array(full.prefix(10))+Array(ranked(full).prefix(10))+Array(other.prefix(10))+Array(other.sorted{$0.number<$1.number}.prefix(10))+full+other)
        guard let first=fetched.first else { return slices(text) }
        if first.input.count == text.count { return fetched }
        let lengths=Set(fetched.map{$0.input.count}).filter{$0>0 && $0<text.count}.sorted(by:>)
        var combined:[CantoneseEntry]=[]
        for length in lengths {
            let tail=String(text.dropFirst(length))
            guard let head=fetched.first(where:{$0.input.count == length}),let rest=search(tail,schemes:segment(tail)).first else { continue }
            combined.append(.init(number:head.number+rest.number+2_000_000,text:head.text+rest.text,romanization:head.romanization+" "+rest.romanization,input:head.input+rest.input))
        }
        return Array(ranked(combined).prefix(1))+fetched
    }
    private func toned(_ input:String) -> String {
        let chars=Array(input),marks:[Character:(String,String)]=["v":("1","4"),"x":("2","5"),"q":("3","6")]
        var result="",i=0
        while i<chars.count {
            if let mark=marks[chars[i]] { let twice=i+1<chars.count && chars[i+1] == chars[i];result += twice ? mark.1:mark.0;i += twice ? 2:1 }
            else { result.append(chars[i]);i+=1 }
        }
        return result
    }
    private func isSyllableLetter(_ c:Character)->Bool { c.isASCII && c.isLetter && !"vxq".contains(c) }
    private func withTones(_ input:String,hits:[CantoneseEntry])->[CantoneseEntry] {
        let text=toned(input),toneInput=input.filter{!isSyllableLetter($0)},textTones=text.filter{"123456".contains($0)}
        let qualified=hits.compactMap { item -> CantoneseEntry? in
            let reading=item.romanization.replacingOccurrences(of:" ",with:"")
            if reading.hasPrefix(text) { return item.consuming(input) }
            let tones=reading.filter{"123456".contains($0)}
            let correctPosition=text.dropFirst(item.input.count).first.map{"123456".contains($0)} ?? false
            let toneLast=text.last.map{"123456".contains($0)} ?? false
            switch (textTones.count,tones.count) {
            case (1,1): return textTones == tones && correctPosition ? item.consuming(item.input+toneInput):nil
            case (1,2):
                if toneLast { return tones.hasSuffix(textTones) && correctPosition ? item.consuming(input):nil }
                return tones.hasPrefix(textTones) ? item.consuming(item.input+toneInput):nil
            case (2,1):
                guard textTones.hasPrefix(tones),correctPosition else { return nil }
                let leading=input.prefix(while:isSyllableLetter)
                return item.consuming(String(leading)+input.dropFirst(leading.count).prefix{!isSyllableLetter($0)})
            case (2,2):
                guard textTones == tones else { return nil }
                if toneLast { return item.input.count == text.count-2 ? item.consuming(input):nil }
                return text.dropFirst(item.input.count+1).first == textTones.last ? item.consuming(item.input+toneInput):nil
            default:return input.hasPrefix(reading) ? item.consuming(reading):nil
            }
        }
        return qualified.sorted{$0.input.count>$1.input.count}
    }
    private func withSeparators(_ text:String,hits:[CantoneseEntry])->[CantoneseEntry] {
        guard text.first != "'" else { return [] }
        let trailing=text.last == "'",count=text.filter{$0 == "'"}.count,parts=text.split(separator:"'").map(String.init)
        let qualified=hits.compactMap { item -> CantoneseEntry? in
            let syllables=item.syllables
            if syllables == parts { return item.consuming(text) }
            func pairMatches(trailing:Bool)->Bool {
                if text.count == (trailing ? 4:3) || syllables.first == parts.first { return true }
                guard parts.first?.count == 1,parts.first?.first == syllables.first?.first else { return false }
                return trailing ? parts.last == syllables.last:(parts.last?.hasPrefix(syllables.last ?? "") ?? false)
            }
            if count == 1 && trailing {
                return syllables.count == 1 && item.input.count == text.count-1 ? item.consuming(text):nil
            }
            if count == 1 {
                if syllables.count == 1 { return item.input.count == parts.first?.count ? item.consuming(item.input+"'"):nil }
                return syllables.count == 2 && pairMatches(trailing:false) ? item.consuming(item.input+"'"):nil
            }
            if count == 2 && trailing {
                if syllables.count == 1 { return item.input.count == parts.first?.count ? item.consuming(item.input+"'"):nil }
                return syllables.count == 2 && item.input.count == text.count-2 && pairMatches(trailing:true) ? item.consuming(text):nil
            }
            if (count == 2 && text.count == 5 && parts.count == 3) || (count == 3 && text.count == 6 && parts.count == 3) {
                switch syllables.count {
                case 1:return item.input.count == 1 ? item.consuming(item.input+"'"):nil
                case 2:return item.input.count == 2 ? item.consuming(item.input+"''"):nil
                case 3:return item.consuming(text)
                default:return nil
                }
            }
            guard syllables.count<parts.count,zip(syllables,parts).allSatisfy({$0 == $1}) else { return nil }
            return item.consuming(item.input+String(repeating:"'",count:max(0,syllables.count-1)))
        }
        if !qualified.isEmpty { return qualified.sorted{$0.input.count>$1.input.count} }
        return anchors(parts.compactMap(\.first).map(String.init).joined()).filter { item in
            item.syllables.count == parts.count && zip(parts,item.syllables).allSatisfy{$0.count == 1 ? $1.hasPrefix($0):$0 == $1}
        }.map{$0.consuming(text)}
    }
    func candidates(_ input:String) -> [Candidate] {
        cache=[:];searchCache=[:];defer { cache=[:];searchCache=[:] }
        let text=input.lowercased(),letters=text.filter{$0.isASCII && $0.isLetter && !"vxq".contains($0)},schemes=segment(letters)
        var hits:[CantoneseEntry]
        if text.count == 1 {
            hits=text == "a" ? spell("a")+spell("aa",input:"a")+anchors(text):["m","o"].contains(text) ? spell(text)+anchors(text):anchors(text)
        } else {
            let first=schemes.firstAliasLength
            hits=first == 0 ? slices(letters):search(letters,schemes:schemes)
            if first != 0 && (first == 1 || letters != text) { hits += slices(letters) }
        }
        let separators=text.contains("'"),tones=text.contains{!isSyllableLetter($0) && $0 != "'"}
        if separators && tones { hits=hits.filter{toned(text).hasPrefix($0.romanization)}.map{$0.consuming(text)} }
        else if tones { hits=withTones(text,hits:hits) }
        else if separators { hits=withSeparators(text,hits:hits) }
        return unique(hits).map{Candidate($0.text,reading:$0.romanization,score:-Double($0.number),consumedUTF16:$0.input.utf16.count,annotation:$0.romanization)}
    }
}
