import Foundation

/// Reads the original dictionaries without collapsing vocabulary IDs or frequencies.
/// The traversal and stable ordering follow UnigramHanjaConverter/BigramHanjaConverter.
final class HanjaDictionary {
    private let index:Data,content:Data,bigrams:Data
    private var singleHanjaCache:[Int:String]=[:]
    init() throws {
        func read(_ name:String) throws -> Data {
            guard let url=Bundle.module.url(forResource:name,withExtension:"bin",subdirectory:"Resources/Korean") else { throw Lexicon.Failure.missingResource }
            return try Data(contentsOf:url,options:.mappedIfSafe)
        }
        index=try read("hanja_index");content=try read("hanja_content");bigrams=try read("hanja_bigram")
    }
    private struct Word { let id:Int,text:String,frequency:Float,extra:String,consumed:Int }
    private struct Path {
        var words:[Word]
        var text:String { words.map(\.text).joined() }
        var consumed:Int { words.reduce(0){$0+$1.consumed} }
        var score:Float { words.reduce(Float.zero){$0+$1.frequency}/Float(words.count) }
    }
    private func word(_ id:Int,consumed:Int) -> Word {
        var p=content.integer(id*4)
        _=content.string(&p)
        let text=content.string(&p),frequency=content.integer(p);p+=4
        return Word(id:id,text:text,frequency:Float(frequency),extra:content.string(&p),consumed:consumed)
    }
    private func following(_ id:Int) -> Set<Int> {
        let root=bigrams.integer(bigrams.count-4),count=bigrams.integer(root+4)
        var low=0,high=count-1
        while low<=high {
            let middle=(low+high)/2,p=root+8+middle*8,key=bigrams.integer(p)
            if key<id { low=middle+1 } else if key>id { high=middle-1 }
            else {
                let node=bigrams.integer(p+4),count=bigrams.integer(node+4)
                return Set((0..<count).map{bigrams.integer(node+8+$0*8)})
            }
        }
        return []
    }
    private func singleHanja(_ unit:Int)->String {
        if let cached=singleHanjaCache[unit] { return cached }
        let root=index.integer(index.count-4),count=index.short(root)
        var result=""
        for i in 0..<count {
            let p=root+2+i*6
            guard index.short(p)==unit else { continue }
            let node=index.integer(p+2),entries=node+2+index.short(node)*6
            for j in 0..<index.short(entries) {
                let text=word(index.integer(entries+2+j*4),consumed:1).text
                if text.count==1 { result+=text }
            }
            break
        }
        singleHanjaCache[unit]=result;return result
    }
    func candidates(_ text:String,phrase:Bool) -> [Candidate] {
        let input=Array(text.utf16)
        guard !input.isEmpty else { return [] }
        var wordsCache:[Int:[Word]]=[:],followingCache:[Int:Set<Int>]=[:]
        func words(at offset:Int)->[Word] {
            if let cached=wordsCache[offset] { return cached }
            struct Node { let offset:Int,constraints:[Int:String] }
            var nodes=[Node(offset:index.integer(index.count-4),constraints:[:])],result:[Word]=[]
            for end in offset..<input.count {
                var next:[Node]=[]
                for state in nodes {
                    let node=state.offset
                    for key in KoreanConversion.readingKeys(Int(input[end]),initial:end==offset,previous:end>0 ? Int(input[end-1]):nil) {
                        let count=index.short(node);var low=0,high=count-1
                        while low<=high {
                            let middle=(low+high)/2,p=node+2+middle*6,c=index.short(p)
                            if c<key.unit { low=middle+1 } else if c>key.unit { high=middle-1 }
                            else {
                                var constraints=state.constraints
                                // A sound-law alias must actually share a Hanzi
                                // with the original reading: 람 -> 남 must not
                                // turn 사람 into 四男 merely because 男 is 남.
                                if key.soundLaw { constraints[end-offset]=singleHanja(Int(input[end])) }
                                else if let hanja=key.hanja { constraints[end-offset]=hanja }
                                next.append(Node(offset:index.integer(p+2),constraints:constraints));break
                            }
                        }
                    }
                }
                guard !next.isEmpty else { break };nodes=next
                for state in nodes {
                    let node=state.offset
                    let p=node+2+index.short(node)*6,entryCount=index.short(p)
                    for i in 0..<entryCount {
                        let w=word(index.integer(p+2+i*4),consumed:end-offset+1)
                        if !state.constraints.isEmpty {
                            let characters=Array(w.text)
                            guard characters.count==w.consumed,state.constraints.allSatisfy({characters.indices.contains($0.key) && $0.value.contains(characters[$0.key])}) else { continue }
                        }
                        if phrase || w.text.count==end-offset+1 { result.append(w) }
                    }
                }
            }
            wordsCache[offset]=result;return result
        }
        struct State:Hashable { var offset:Int,previous:Int,depth:Int }
        var memo:[State:[Path]]=[:]
        func visit(_ offset:Int,_ previous:Int,_ depth:Int)->[Path] {
            // The original converter itself completes a candidate after five words.
            // No iOS beam, reading-length, vocabulary-count or result-count cap is used.
            guard offset<input.count,depth<=4 else { return [Path(words:[])] }
            let state=State(offset:offset,previous:previous,depth:depth)
            if let cached=memo[state] { return cached }
            if previous>=0,followingCache[previous]==nil { followingCache[previous]=following(previous) }
            let available=words(at:offset).filter{previous<0 || followingCache[previous]!.contains($0.id)}
            var result:[Path]=[]
            for w in available where !w.text.isEmpty {
                for suffix in visit(offset+w.consumed,w.id,depth+1) { result.append(Path(words:[w]+suffix.words)) }
            }
            result.append(Path(words:[]));memo[state]=result;return result
        }
        let paths=phrase ? visit(0,-1,0).filter{!$0.words.isEmpty}:words(at:0).map{Path(words:[$0])}
        // Kotlin's distinctBy(String) compares code units, including compatibility ideographs.
        var seen=Set<[UInt16]>()
        let unique=paths.enumerated().sorted {
            $0.element.score == $1.element.score ? $0.offset<$1.offset:$0.element.score>$1.element.score
        }.filter{seen.insert(Array($0.element.text.utf16)).inserted}
        let converted=unique.sorted { a,b in
            let x=a.element,y=b.element
            if x.consumed != y.consumed { return x.consumed>y.consumed }
            if phrase {
                if x.words.count != y.words.count { return x.words.count<y.words.count }
                let xc=x.text.utf16.filter{(0x4e00...0x9fff).contains($0)}.count,yc=y.text.utf16.filter{(0x4e00...0x9fff).contains($0)}.count
                if xc != yc { return xc>yc }
            }
            return x.score == y.score ? a.offset<b.offset:x.score>y.score
        }.map { item in
            let path=item.element,count=path.consumed
            return Candidate(path.text,reading:String(decoding:input.prefix(count),as:UTF16.self),score:Double(path.score),consumedUTF16:count,annotation:path.words.count==1 ? path.words[0].extra:"")
        }
        var extra=KoreanConversion.candidates(text)
        let digits=String(text.prefix{KoreanConversion.isDigit($0)})
        if !digits.isEmpty,digits.count<text.count {
            extra += candidates(String(text.dropFirst(digits.count)),phrase:phrase).map {
                Candidate(digits+$0.text,reading:digits+$0.reading,score:$0.score,consumedUTF16:digits.utf16.count+($0.consumedUTF16 ?? $0.reading.utf16.count),annotation:$0.annotation)
            }
        }
        return Candidate.unique(extra+converted)
    }
}

private extension Data {
    func short(_ p:Int)->Int { Int(self[p])<<8 | Int(self[p+1]) }
    func integer(_ p:Int)->Int { short(p)<<16 | short(p+2) }
    func string(_ p:inout Int)->String {
        var units:[UInt16]=[]
        while short(p) != 0 { units.append(UInt16(short(p)));p+=2 }
        p+=2;return String(decoding:units,as:UTF16.self)
    }
}
