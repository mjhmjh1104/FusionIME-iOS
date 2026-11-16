import Foundation

public enum InputLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case korean, english, german, spanish, french, italian, portuguese
    case japanese, pinyin, zhuyin, cangjie, quick, dayi, jyutping, vietnamese, emoji
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .french: return "Français"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .japanese: return "日本語"
        case .pinyin: return "拼音"
        case .zhuyin: return "注音"
        case .cangjie: return "倉頡"
        case .quick: return "速成"
        case .dayi: return "大易"
        case .jyutping: return "粵拼"
        case .vietnamese: return "Tiếng Việt"
        case .emoji: return "이모지"
        }
    }
    public var isLatin: Bool { [.english,.german,.spanish,.french,.italian,.portuguese].contains(self) }
    public var locale: String {
        switch self {
        case .korean: return "ko-KR"
        case .english: return "en-US"
        case .german: return "de-DE"
        case .spanish: return "es-ES"
        case .french: return "fr-FR"
        case .italian: return "it-IT"
        case .portuguese: return "pt-BR"
        case .japanese: return "ja-JP"
        case .pinyin: return "zh-Hans"
        case .jyutping: return "yue-Hant"
        case .vietnamese: return "vi-VN"
        default: return "zh-Hant"
        }
    }
    public var layouts: [KeyboardLayout] {
        if isLatin { return [.qwerty,.qwertz,.deutsch,.azerty,.dvorak,.colemak] }
        switch self {
        case .korean: return [.hangul2,.hangul390,.hangul391,.hangul391Strict,.hangulOld2,.hangul393]
        case .japanese: return [.romaji,.kana12,.kanaJIS,.kanaSyllables,.kanaIroha,.godan]
        case .vietnamese: return [.telex,.vni,.qwerty]
        case .zhuyin: return [.zhuyin]
        case .cangjie,.quick: return [.cangjie]
        case .dayi: return [.dayi]
        case .emoji: return [.emoji]
        default: return [.qwerty,.qwertz,.azerty,.dvorak,.colemak]
        }
    }
}

public enum KeyboardLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case qwerty, qwertz, deutsch, azerty, dvorak, colemak, emoji
    case hangul2, hangul390, hangul391, hangul391Strict, hangulOld2, hangul393
    case romaji, kana12, kanaJIS, kanaSyllables, kanaIroha, godan, telex, vni, zhuyin, cangjie, dayi
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .hangul2: return "두벌식"
        case .hangul390: return "세벌식 390"
        case .hangul391: return "세벌식 최종"
        case .hangul391Strict: return "세벌식 최종 엄격 조합"
        case .hangulOld2: return "옛한글 두벌식"
        case .hangul393: return "옛한글 세벌식 393"
        case .kana12: return "かな 12キー Flick"
        case .kanaJIS: return "かな JIS"
        case .kanaSyllables: return "五十音"
        case .kanaIroha: return "いろは"
        case .deutsch: return "Deutsch"
        case .emoji: return "이모지"
        default: return rawValue.uppercased()
        }
    }
}

public struct InputMode: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var language: InputLanguage
    public var layout: KeyboardLayout
    public var traditional = false
    public var hanja = true
    public var correctHangulOrder = false
    public var kanaTapCycle = false
    public var hanNom = true
    public var doublePinyin: DoublePinyin = .full
    public var zhuyinEngine = 1
    public var fullWidth = false
    public var numberRow:Bool?
    public var cursorKeys:Bool?
    public var koreanConverter="word"
    public var kanaFlick=true
    public var syllablesDirection="horizontal"
    public var autoCapitalization:Bool?
    public var doubleSpacePeriod:Bool?
    public var candidateRows:Int?
    public var flickHints:Bool?
    public var kanaInputStyle:KanaInputStyle {
        get { !kanaFlick ? .toggle:kanaTapCycle ? .both:.flick }
        set { kanaFlick=newValue != .toggle;kanaTapCycle=newValue != .flick }
    }
    public init(language: InputLanguage, layout: KeyboardLayout? = nil) {
        id = UUID(); self.language = language
        self.layout = layout ?? (language == .german ? .deutsch : language == .french ? .azerty : language == .vietnamese ? .qwerty : language.layouts[0])
    }
    public var title: String { language.name }
    public var displayName:String { title+" "+layout.name }
}

public enum KeyboardTheme: String, Codable, CaseIterable { case system, light, dark }
public enum SymbolLayout:String,Codable,CaseIterable,Identifiable {
    case system, g="G", n1="N1", n2="N2", o1="O1", o2="O2"
    public var id:String { rawValue }
}
public enum KeyboardScreenMode:String,Codable,CaseIterable { case automatic,mobile,tablet }
public enum KeyboardTouchMode:String,Codable,CaseIterable { case seek,flick }
public enum KanaInputStyle:String,CaseIterable { case both,flick,toggle }
public enum FlickAction:String,Codable,CaseIterable,Identifiable {
    case none, standard, shift, symbol, shiftedSymbol, space, backspace, enter, nextLanguage
    public var id:String { rawValue }
    public var name:String {
        switch self {
        case .none:return "없음"
        case .standard:return "기본 문자"
        case .shift:return "Shift 문자"
        case .symbol:return "대응 기호"
        case .shiftedSymbol:return "Shift 기호"
        case .space:return "공백"
        case .backspace:return "삭제"
        case .enter:return "확정 / 줄바꿈"
        case .nextLanguage:return "다음 언어"
        }
    }
}
public struct UserEntry:Codable,Equatable,Identifiable {
    public var id=UUID()
    public var language:InputLanguage
    public var reading:String
    public var text:String
    public init(language:InputLanguage,reading:String,text:String) { self.language=language;self.reading=reading;self.text=text }
}
public struct KeyboardSettings: Codable, Equatable {
    public var modes: [InputMode] = [.init(language:.korean),.init(language:.english),.init(language:.japanese),.init(language:.pinyin),.init(language:.vietnamese)]
    public var theme: KeyboardTheme = .system
    public var screenMode:KeyboardScreenMode = .automatic
    public var symbolLayout:SymbolLayout = .system
    public var touchMode:KeyboardTouchMode = .seek
    public var touchCorrection = true
    public var vibrationDuration = 10.0
    public var showVoiceInputButton = true
    public var clipboardCandidates = false
    public var numberRow = false
    public var cursorKeys = false
    public var haptics = false
    public var sound = false
    public var autoCapitalization = true
    public var autoCorrection = true
    public var doubleSpacePeriod = true
    public var suggestions = true
    public var learnWords = false
    public var height = 250.0
    public var heightLayoutVersion = 2
    public var layoutDataVersion = 1
    public var landscapeHeight = 180.0
    public var splitPortrait = false
    public var splitLandscape = false
    public var splitGap = 0.2
    public var splitGapLandscape = 0.2
    public var flickSensitivity = 18.0
    public var flickUp:FlickAction = .shift
    public var flickDown:FlickAction = .symbol
    public var keyPreview = true
    public var flickHints = true
    public var candidateRows = 1
    public var userDictionary:[UserEntry] = []
    public var historyGeneration = "v1"
    public var latinHistoryGenerations:[String:String]=[:]
    public init() {}
    public mutating func validate() {
        if modes.isEmpty { modes = [.init(language:.korean)] }
        // Repair stale/corrupt preferences without trapping in UI indexing.
        var seen = Set<UUID>()
        modes = modes.filter { seen.insert($0.id).inserted }
        for i in modes.indices where !modes[i].language.layouts.contains(modes[i].layout) {
            modes[i].layout = modes[i].language.layouts[0]
        }
        height = height.isFinite ? min(360,max(210,height)) : 250
        landscapeHeight = landscapeHeight.isFinite ? min(280,max(170,landscapeHeight)) : 180
        splitGap = splitGap.isFinite ? min(0.5,max(0.1,splitGap)):0.2
        splitGapLandscape = splitGapLandscape.isFinite ? min(0.5,max(0.1,splitGapLandscape)):0.2
        vibrationDuration = vibrationDuration.isFinite ? min(50,max(5,vibrationDuration)):10
        flickSensitivity = flickSensitivity.isFinite ? min(150,max(8,flickSensitivity)):18
        candidateRows = min(3,max(1,candidateRows))
        for i in modes.indices {
            if let rows=modes[i].candidateRows { modes[i].candidateRows=min(3,max(1,rows)) }
            if !modes[i].kanaTapCycle && !modes[i].kanaFlick { modes[i].kanaFlick=true }
            modes[i].zhuyinEngine=min(2,max(0,modes[i].zhuyinEngine))
            if !["word","phrase","jeongun","hangul"].contains(modes[i].koreanConverter) { modes[i].koreanConverter="word" }
        }
        userDictionary=Array(userDictionary.filter{!$0.reading.isEmpty && !$0.text.isEmpty && $0.reading.count<128 && $0.text.count<128}.prefix(10000))
        var entryIDs=Set<UUID>();userDictionary=userDictionary.filter{entryIDs.insert($0.id).inserted}
        latinHistoryGenerations=latinHistoryGenerations.filter{UUID(uuidString:$0.value) != nil}
        if historyGeneration != "v1" && UUID(uuidString:historyGeneration)==nil { historyGeneration="v1" }
    }
    /// Merge defaults before decoding so additions do not discard saved languages/settings.
    public static func decodeCompatible(_ data:Data) throws -> Self {
        let encoder=JSONEncoder()
        var merged=try JSONSerialization.jsonObject(with:encoder.encode(Self())) as! [String:Any]
        guard let saved=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw CocoaError(.fileReadCorruptFile) }
        merged.merge(saved){_,new in new}
        if saved["splitGapLandscape"] == nil { merged["splitGapLandscape"]=saved["splitGap"] ?? 0.2 }
        if saved["touchMode"] == nil { merged["touchMode"]="flick" }
        if saved["heightLayoutVersion"] == nil {
            // Retain custom sizes, while moving the old defaults to the compact layout.
            if saved["height"] as? Double == 260 { merged["height"]=250.0 }
            if saved["landscapeHeight"] as? Double == 210 { merged["landscapeHeight"]=180.0 }
        }
        if let modes=saved["modes"] as? [[String:Any]] {
            merged["modes"]=try modes.compactMap { old -> [String:Any]? in
                guard let name=old["language"] as? String,let language=InputLanguage(rawValue:name) else { return nil }
                var mode=try JSONSerialization.jsonObject(with:encoder.encode(InputMode(language:language))) as! [String:Any]
                mode.merge(old){_,new in new}
                if saved["layoutDataVersion"] == nil && language == .german && old["layout"] as? String == "qwertz" { mode["layout"]="deutsch" }
                return mode
            }
        }
        var result=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:merged))
        result.validate();return result
    }
}

public struct Candidate: Equatable, Identifiable, Sendable {
    public let text: String
    public let reading: String
    public let score: Double
    public let nativeID:Int?
    public let nativeGeneration:UUID?
    public let consumedUTF16:Int?
    public let annotation:String
    public let focused:Bool
    public var id: String { Data(text.utf8).base64EncodedString() + "\u{0}" + Data(reading.utf8).base64EncodedString() + (nativeID.map(String.init) ?? "") }
    public init(_ text: String, reading: String = "", score: Double = 0, nativeID:Int? = nil, nativeGeneration:UUID? = nil,consumedUTF16:Int? = nil,annotation:String = "",focused:Bool = false) {
        self.text = text; self.reading = reading; self.score = score
        self.nativeID=nativeID; self.nativeGeneration=nativeGeneration
        self.consumedUTF16=consumedUTF16
        self.annotation=annotation;self.focused=focused
    }
    public func consuming(_ count:Int) -> Self { Self(text,reading:reading,score:score,nativeID:nativeID,nativeGeneration:nativeGeneration,consumedUTF16:count,annotation:annotation,focused:focused) }
    static func unique(_ candidates:[Self])->[Self] {
        var positions:[Data:Int]=[:],result:[Self]=[]
        for candidate in candidates {
            guard !candidate.text.isEmpty else { continue }
            // Keep distinct compatibility Han glyphs; normalize combining Kana/Hangul.
            let compatibility=candidate.text.unicodeScalars.contains { (0xf900...0xfaff).contains($0.value) || (0x2f800...0x2fa1f).contains($0.value) }
            let text=compatibility ? candidate.text:candidate.text.precomposedStringWithCanonicalMapping
            let key=Data(text.utf8)
            if let index=positions[key] {
                // Keep the native selection token and focus when a literal has
                // the same visible text. Losing them breaks segmented conversion.
                let old=result[index]
                if candidate.focused && !old.focused || candidate.nativeID != nil && old.nativeID == nil {
                    result[index]=candidate
                }
            } else { positions[key]=result.count;result.append(candidate) }
        }
        return result
    }
}

struct ImportedTables: Decodable {
    let layouts: [String: [String: [Int]]]
    let combinations: [String: [String: Int]]
    let hangul: [String: [Int]]
    static let shared: ImportedTables = {
        guard let url = Bundle.module.url(forResource:"tables",withExtension:"json",subdirectory:"Resources"),
              let data = try? Data(contentsOf:url), let tables = try? JSONDecoder().decode(Self.self,from:data) else {
            preconditionFailure("Missing imported keyboard tables. Run Scripts/build_resources.py.")
        }
        return tables
    }()
}
func scalar(_ value: Int) -> String { UnicodeScalar(value & 0xffff).map(String.init) ?? "" }
