import Foundation

public enum UserDictionaryFile {
    public static func read(_ data:Data,defaultLanguage:InputLanguage) throws -> [UserEntry] {
        guard data.count<8_000_000,let text=String(data:data,encoding:.utf8) else { throw CocoaError(.fileReadCorruptFile) }
        var entries:[UserEntry]=[]
        for line in text.split(whereSeparator:{$0.isNewline}) where !line.hasPrefix("#") {
            let fields=line.split(separator:"\t",omittingEmptySubsequences:false).map { $0.trimmingCharacters(in:.whitespaces) }
            guard fields.count>=2,!fields[0].isEmpty,!fields[1].isEmpty,fields[0].count<128,fields[1].count<128 else { continue }
            let language=fields.count>=3 ? InputLanguage(rawValue:fields[2]) ?? defaultLanguage:defaultLanguage
            entries.append(UserEntry(language:language,reading:fields[0],text:fields[1]))
            if entries.count>=10000 { break }
        }
        guard !entries.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return entries
    }
    public static func write(_ entries:[UserEntry]) -> Data {
        let clean:(String)->String = { $0.replacingOccurrences(of:"\t",with:" ").replacingOccurrences(of:"\n",with:" ").replacingOccurrences(of:"\r",with:" ") }
        return Data(entries.map{"\(clean($0.reading))\t\(clean($0.text))\t\($0.language.rawValue)"}.joined(separator:"\n").utf8)
    }
}
