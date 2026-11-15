import Foundation
import CSQLite

/// One connection per engine. Calls are serialized by the owning actor/UI queue.
/// SQLite's bounded page cache avoids loading the multilingual lexicon into RAM.
public final class Lexicon {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public enum Failure: Error { case missingResource, open(String) }
    public init(url: URL? = nil) throws {
        guard let url = url ?? Bundle.main.url(forResource:"lexicon",withExtension:"sqlite") else { throw Failure.missingResource }
        guard sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,nil) == SQLITE_OK else {
            let message = db.map { String(cString:sqlite3_errmsg($0)) } ?? "Cannot open lexicon"
            sqlite3_close(db); db=nil; throw Failure.open(message)
        }
        sqlite3_exec(db,"PRAGMA cache_size=-1024; PRAGMA mmap_size=0; PRAGMA query_only=ON",nil,nil,nil)
    }
    deinit { sqlite3_close(db) }
    public func lookup(_ reading:String, mode:String, prefix:Bool = true, limit:Int = 30) -> [Candidate] {
        let key=Self.normalize(reading)
        guard !key.isEmpty else { return [] }
        var result = query("SELECT text,reading,score FROM entries WHERE mode=? AND reading=? ORDER BY score DESC LIMIT ?", values:[mode,key], limit:limit)
        if prefix && result.count < limit {
            // Walk the indexed range incrementally; later pages can reach every entry.
            result += query("SELECT text,reading,score FROM entries WHERE mode=? AND reading>? AND reading<? ORDER BY reading,text LIMIT ?", values:[mode,key,key+"\u{10ffff}"],limit:limit-result.count)
        }
        var seen=Set<String>()
        return result.filter { seen.insert($0.text).inserted }.map { candidate in
            guard mode == "hanja" else { return candidate }
            let note=query("SELECT extra,reading,0 FROM annotations WHERE mode=? AND reading=? AND text=? LIMIT ?",values:[mode,candidate.reading,candidate.text],limit:1).first?.text ?? ""
            return Candidate(candidate.text,reading:candidate.reading,score:candidate.score,annotation:note)
        }
    }
    private func query(_ sql:String, values:[String], limit:Int) -> [Candidate] {
        var stmt:OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&stmt,nil)==SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i,value) in values.enumerated() { sqlite3_bind_text(stmt,Int32(i+1),value,-1,transient) }
        sqlite3_bind_int(stmt,Int32(values.count+1),Int32(max(1,min(Int(Int32.max),limit))))
        var result:[Candidate]=[]
        while sqlite3_step(stmt)==SQLITE_ROW {
            guard let text=sqlite3_column_text(stmt,0), let reading=sqlite3_column_text(stmt,1) else { continue }
            result.append(Candidate(String(cString:text),reading:String(cString:reading),score:sqlite3_column_double(stmt,2)))
        }
        return result
    }
    func cantonese(spell:String? = nil,anchors:String? = nil,limit:Int = 1000) -> [CantoneseEntry] {
        let column=spell != nil ? "spell":"anchors",key=spell ?? anchors ?? ""
        var stmt:OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT number,text,romanization FROM cantonese WHERE \(column)=? ORDER BY number LIMIT ?",-1,&stmt,nil)==SQLITE_OK,let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt,1,key,-1,transient);sqlite3_bind_int(stmt,2,Int32(min(Int(Int32.max),limit)))
        var entries:[CantoneseEntry]=[]
        while sqlite3_step(stmt)==SQLITE_ROW {
            entries.append(CantoneseEntry(number:Int(sqlite3_column_int(stmt,0)),text:String(cString:sqlite3_column_text(stmt,1)),romanization:String(cString:sqlite3_column_text(stmt,2))))
        }
        return entries
    }
    public static func normalize(_ text:String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased().filter { $0 != " " && $0 != "'" }
    }
    private var hanjaDictionary:HanjaDictionary?
    public func hanjaCandidates(_ input:String,phrase:Bool) -> [Candidate] {
        if hanjaDictionary == nil { hanjaDictionary=try? HanjaDictionary() }
        return hanjaDictionary?.candidates(input,phrase:phrase) ?? []
    }
    public func convertHanjaPhrase(_ input:String) -> [Candidate] { hanjaCandidates(input,phrase:true) }
    func hasCantonesePrefix(_ prefix:String)->Bool {
        var statement:OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT 1 FROM cantonese WHERE spell>=? AND spell<? LIMIT 1",-1,&statement,nil)==SQLITE_OK,let statement else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement,1,prefix,-1,transient);sqlite3_bind_text(statement,2,prefix+"{",-1,transient)
        return sqlite3_step(statement)==SQLITE_ROW
    }
    /// Unigram dynamic programming fallback for phrases absent from the dictionary.
    /// This deliberately does not claim Mozc's context model or Chewing's tone model.
    public func convertPhrase(_ input:String, mode:String) -> String? {
        let chars=Array(Self.normalize(input))
        guard chars.count>1 else { return nil }
        var costs=Array(repeating:Double.infinity,count:chars.count+1)
        var texts=Array(repeating:"",count:chars.count+1)
        costs[0]=0
        for start in chars.indices where costs[start].isFinite {
            let end=chars.count
            for stop in (start+1)...end {
                let key=String(chars[start..<stop])
                guard let hit=lookup(key,mode:mode,prefix:false,limit:1).first else { continue }
                let cost=costs[start] + (mode == "japanese" ? max(0.1, -hit.score)+3 : max(0.1,18-hit.score))
                if cost < costs[stop] { costs[stop]=cost; texts[stop]=texts[start]+hit.text }
            }
        }
        return costs[chars.count].isFinite ? texts[chars.count] : nil
    }
}
