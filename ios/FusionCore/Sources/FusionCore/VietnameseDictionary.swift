import Foundation

/// Reads the exact dictionary shipped by the Android app. Preserve case,
/// Unicode spelling, frequencies and tie order instead of normalizing through
/// the general-purpose SQLite lexicon.
public final class VietnameseDictionary {
    private let data:Data
    public init(name:String) throws {
        guard ["nom_qwerty","nom_quoc_ngu","quoc_ngu_qwerty"].contains(name),
              let url=Bundle.module.url(forResource:name,withExtension:"bin",subdirectory:"Resources/Vietnamese") else { throw Lexicon.Failure.missingResource }
        data=try Data(contentsOf:url,options:.mappedIfSafe)
    }
    private func short(_ offset:Int) -> Int { Int(data[offset])<<8 | Int(data[offset+1]) }
    private func int(_ offset:Int) -> Int { short(offset)<<16 | short(offset+2) }
    private func string(_ offset:inout Int) -> String {
        var units:[UInt16]=[]
        while offset+1<data.count {
            let unit=UInt16(short(offset));offset+=2
            if unit == 0 { break }
            units.append(unit)
        }
        return String(decoding:units,as:UTF16.self)
    }
    /// Visit the trie once. Every matching input prefix remains selectable,
    /// including spaces consumed by Android's VietnameseConverter.
    public func candidates(beforeCursor text:String) -> [Candidate] {
        guard data.count>=4 else { return [] }
        var node=int(data.count-4)
        var hits:[Candidate]=[]
        let units=Array(text.utf16)
        for (index,unit) in units.enumerated() {
            guard node>=0,node+2<=data.count else { break }
            if unit != 32 {
                let count=short(node)
                guard node+2+count*6<=data.count else { break }
                guard let edge=(0..<count).first(where:{short(node+2+$0*6)==Int(unit)}) else { break }
                node=int(node+4+edge*6)
            }
            guard node>=0,node+2<=data.count else { break }
            var offset=node+2+short(node)*6
            guard offset+2<=data.count else { break }
            let count=short(offset);offset+=2
            let reading=String(decoding:units.prefix(index+1),as:UTF16.self)
            for _ in 0..<count {
                let result=string(&offset)
                _=string(&offset) // Extra field is not displayed by VietIMEMode.
                guard offset+2<=data.count else { break }
                let score=Int16(bitPattern:UInt16(short(offset)));offset+=2
                hits.append(Candidate(result,reading:reading,score:Double(score),consumedUTF16:index+1))
            }
        }
        // Explicit index tie-break preserves the source dictionary's order.
        let sorted=hits.enumerated().sorted { a,b in
            if a.element.consumedUTF16 != b.element.consumedUTF16 { return a.element.consumedUTF16! > b.element.consumedUTF16! }
            if a.element.score != b.element.score { return a.element.score > b.element.score }
            return a.offset < b.offset
        }
        var seen=Set<[UInt16]>()
        return sorted.compactMap { seen.insert(Array($0.element.text.utf16)).inserted ? $0.element:nil }
    }
}
