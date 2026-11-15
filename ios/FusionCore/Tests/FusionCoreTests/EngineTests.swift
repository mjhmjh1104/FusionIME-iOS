import XCTest
@testable import FusionCore

final class EngineTests: XCTestCase {
    static var dictionaryURL:URL {
        if let path=ProcessInfo.processInfo.environment["FUSION_TEST_DICTIONARY"] { return URL(fileURLWithPath:path) }
        return URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/lexicon.sqlite")
    }
    func makeEngine(mode:InputMode = .init(language:.korean)) -> CompositionEngine {
        CompositionEngine(mode:mode,lexicon:try! Lexicon(url:Self.dictionaryURL))
    }
    func typeKorean(_ roman:String, layout:KeyboardLayout = .hangul2) -> String {
        let lower=LayoutCatalog.rows(for:InputMode(language:.korean,layout:layout)).flatMap{$0}
        let upper=LayoutCatalog.rows(for:InputMode(language:.korean,layout:layout),shifted:true).flatMap{$0}
        let physical=Array("qwertyuiopasdfghjklzxcvbnm")
        return HangulComposer.compose(roman.flatMap { c -> [Int] in
            let key=String(c).lowercased().first!
            guard let i=physical.firstIndex(of:key) else { return [Int(c.asciiValue ?? 0)] }
            return (c.isUppercase ? upper[i]:lower[i]).values[0].unicodeScalars.map{Int($0.value)}
        },layout:layout)
    }
    func testHangulCompositionAndResyllabification() {
        XCTAssertEqual(typeKorean("gksrmf"),"한글")
        XCTAssertEqual(typeKorean("dkssudgktpdy"),"안녕하세요")
        XCTAssertEqual(typeKorean("rkqt"),"값")
        XCTAssertEqual(typeKorean("rkqtdl"),"값이")
        XCTAssertEqual(typeKorean("rkqtk"),"갑사")
        XCTAssertEqual(typeKorean("rhk"),"과")
        XCTAssertEqual(typeKorean("Rk"),"까")
    }
    func testUndoDeletesOneJamo() {
        let engine=makeEngine()
        for c in "ㄱㅏㅂㅅ" { engine.append(String(c)) }
        XCTAssertEqual(engine.composition,"값")
        engine.backspace(); XCTAssertEqual(engine.composition,"갑")
        engine.backspace(); XCTAssertEqual(engine.composition,"가")
        engine.backspace(); XCTAssertEqual(engine.composition,"ㄱ")
        engine.backspace(); XCTAssertEqual(engine.composition,"")
        XCTAssertFalse(engine.backspace())
    }
    func testHanjaPhraseResyllabificationFromDaehToDaeha() {
        var mode=InputMode(language:.korean);mode.koreanConverter="phrase"
        let engine=makeEngine(mode:mode)
        for c in "ㄷㅐㅎ" { engine.append(String(c)) }
        XCTAssertEqual(engine.composition,"댛")
        engine.append("ㅏ")
        XCTAssertEqual(engine.composition,"대하")
        XCTAssertTrue(engine.candidates.contains{$0.text=="대하"})
        XCTAssertTrue(engine.candidates.contains{$0.text=="大河"})
        for _ in 0..<3 {
            XCTAssertTrue(engine.backspace());XCTAssertEqual(engine.composition,"댛")
            engine.append("ㅏ");XCTAssertEqual(engine.composition,"대하")
        }
    }
    func testThreeSetAndOldHangul() {
        XCTAssertEqual(HangulComposer.compose([0x1100,0x1161,0x11a8],layout:.hangul390),"각")
        XCTAssertEqual(HangulComposer.compose([0x1100,0x119e,0x11a8],layout:.hangul393),"ᄀᆞᆨ")
        XCTAssertEqual(HangulComposer.compose([0x1100,0x1103,0x119e],layout:.hangul393),"ᅚᆞ")
        XCTAssertEqual(HangulComposer.compose([0x314f,0x3131],layout:.hangul2),"ㅏㄱ")
        XCTAssertEqual(HangulComposer.compose([0x314f,0x3131],layout:.hangul2,correctOrders:true),"가")
        XCTAssertEqual(HangulComposer.compose([0x1100,0x1001169,0x1161],layout:.hangul391Strict),"과")
        XCTAssertEqual(HangulComposer.compose([0x1100,0x1169,0x1161],layout:.hangul391Strict),"고ㅏ")
    }
    func testKana() {
        XCTAssertEqual(KanaComposer.compose("nihongo"),"にほんご")
        XCTAssertEqual(KanaComposer.compose("konnichiha"),"こんにちは")
        XCTAssertEqual(KanaComposer.compose("gakkou"),"がっこう")
        XCTAssertEqual(KanaComposer.compose("kan",finalize:true),"かん")
        XCTAssertEqual(KanaComposer.compose("kan"),"かn")
        XCTAssertEqual(KanaComposer.compose("kya"),"きゃ")
        XCTAssertEqual(KanaComposer.katakana("にほんご"),"ニホンゴ")
    }
    func testTelex() {
        XCTAssertEqual(TelexComposer.compose("tieengs"),"tiếng")
        XCTAssertEqual(TelexComposer.compose("Vieetj"),"Việt")
        XCTAssertEqual(TelexComposer.compose("ddawng"),"đăng")
        XCTAssertEqual(TelexComposer.compose("dduwowngf"),"đường")
        XCTAssertEqual(TelexComposer.compose("hoaf"),"hoà")
        XCTAssertEqual(TelexComposer.compose("quas"),"quá")
        XCTAssertEqual(TelexComposer.compose("aaa"),"a")
        XCTAssertEqual(TelexComposer.compose("banana"),"bânna")
    }
    func testDoublePinyin() {
        XCTAssertEqual(DoublePinyin.ziranma.expand("nihk"),"ni'hao")
        XCTAssertEqual(DoublePinyin.xiaohe.expand("nihc"),"ni'hao")
        XCTAssertEqual(DoublePinyin.microsoft.expand("vsgo"),"zhong'guo")
        XCTAssertEqual(DoublePinyin.smartABC.expand("ashs"),"zhong'hong")
        XCTAssertEqual(DoublePinyin.jiajia.expand("nifd"),"ni'fao")
        XCTAssertEqual(DoublePinyin.ziguang.decode("o","p"),"ai")
        XCTAssertEqual(DoublePinyin.sogou.decode("b","d"),"biang")
    }
    func testActualBundledDictionaries() throws {
        let lex=try Lexicon(url:Self.dictionaryURL)
        for (mode,key,text) in [("hanja","한국","韓國"),("japanese","にほん","日本"),("pinyin","nihao","你好"),("zhuyin","ㄋㄧㄏㄠ","你好"),("cangjie","a","日"),("quick","a","日"),("dayi","a","人"),("jyutping","nei5","你"),("vietnamese","toi","tôi"),("nomTelex","a","丫")] {
            XCTAssertTrue(lex.lookup(key,mode:mode,prefix:false,limit:100).contains{$0.text==text},"\(mode) \(key)")
        }
        XCTAssertFalse(lex.lookup("a' OR 1=1 --",mode:"pinyin").contains{$0.text=="你好"})
        XCTAssertEqual(lex.lookup("",mode:"japanese"),[])
        XCTAssertTrue(lex.convertHanjaPhrase("한국정부").contains{$0.text=="韓國政府"})
        XCTAssertTrue(lex.lookup("ᄀᆑᆨ〮",mode:"jeongun",prefix:false).contains{$0.text=="湨"})
    }
    func testModeSwitchCommitAndCandidate() {
        let engine=makeEngine(mode:.init(language:.pinyin))
        engine.append("nihao")
        let candidate=engine.candidates.first{$0.text=="你好"}
        XCTAssertNotNil(candidate)
        XCTAssertEqual(engine.commit(candidate:candidate),"你好")
        XCTAssertEqual(engine.composition,"")
        engine.append("ni"); engine.mode=InputMode(language:.japanese)
        XCTAssertEqual(engine.raw,"")
        engine.append("nihon"); XCTAssertEqual(engine.commit(),"にほん")
    }
    func testEveryLayoutHasReachableKeys() {
        for language in InputLanguage.allCases {
            for layout in language.layouts {
                let keys=LayoutCatalog.rows(for:.init(language:language,layout:layout)).flatMap{$0}
                XCTAssertFalse(keys.isEmpty,layout.rawValue)
                XCTAssertEqual(Set(keys.map(\.id)).count,keys.count,layout.rawValue)
                XCTAssertTrue(keys.allSatisfy{!$0.values.isEmpty && !$0.values[0].isEmpty},layout.rawValue)
            }
        }
    }
    func testSettingsRoundTripAndRepair() throws {
        var settings=KeyboardSettings()
        settings.modes=[]; settings.height=999; settings.validate()
        XCTAssertFalse(settings.modes.isEmpty); XCTAssertEqual(settings.height,360)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardSettings.self,from:JSONEncoder().encode(settings)),settings)
    }
}
