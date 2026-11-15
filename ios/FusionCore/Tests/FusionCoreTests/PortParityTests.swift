import XCTest
@testable import FusionCore

final class PortParityTests:XCTestCase {
    func engine(_ language:InputLanguage)->CompositionEngine {
        CompositionEngine(mode:.init(language:language),lexicon:try! Lexicon(url:EngineTests.dictionaryURL),nativeConfiguration:nil)
    }
    func testOriginalHanjaCandidateOrderAndUnlimitedInput() throws {
        struct Hit:Decodable { let text:String,score:Double,annotation:String }
        struct Fixture:Decodable { let input:String,phrase:Bool,expected:[Hit] }
        let url=try XCTUnwrap(Bundle.module.url(forResource:"hanja-upstream",withExtension:"json",subdirectory:"Fixtures"))
        let fixtures=try JSONDecoder().decode([Fixture].self,from:Data(contentsOf:url)),dictionary=try HanjaDictionary()
        for fixture in fixtures {
            let actual=dictionary.candidates(fixture.input,phrase:fixture.phrase)
            // Code units distinguish original compatibility ideographs from unified ones.
            XCTAssertEqual(actual.map{Array($0.text.utf16)},fixture.expected.map{Array($0.text.utf16)},"\(fixture.input), phrase=\(fixture.phrase)")
            XCTAssertEqual(actual.map(\.score),fixture.expected.map(\.score))
            XCTAssertEqual(actual.map(\.annotation),fixture.expected.map(\.annotation))
            XCTAssertEqual(Set(actual.map(\.id)).count,actual.count)
        }
        for language in [InputLanguage.korean,.jyutping,.english] {
            let e=engine(language),text=language == .korean ? String(repeating:"아",count:80):String(repeating:"a",count:80)
            XCTAssertNil(e.append(text));XCTAssertEqual(e.composition,text)
        }
    }
    func testCantoneseCompactSearchMatchesExhaustiveOriginalSegmenter() throws {
        let dictionary=try Lexicon(url:EngineTests.dictionaryURL),engine=CantoneseEngine(lexicon:dictionary)
        let aliases=ImportedCantoneseAliases.load()
        typealias Syllable=CantoneseEngine.Syllable
        func valid(_ scheme:[Syllable])->Bool {
            guard scheme.count>=2,scheme.dropLast().contains(where:{$0.origin.hasSuffix("a")}) else { return true }
            func count(_ text:String)->Int { text.components(separatedBy:"aam").count+text.components(separatedBy:"aang").count-2 }
            let origin=count(scheme.map(\.origin).joined())
            return origin==0 || origin==count(scheme.map(\.alias).joined())
        }
        func key(_ scheme:[Syllable])->String { scheme.map(\.origin).joined(separator:" ")+"|"+scheme.map(\.alias).joined() }
        let inputs=["neihou","mama","mami","aam","aang","aaam","aangaa","aaaaaaa","saanam","gwongdungwaa","hoenggong","janman","ngaaam","neihaam","maamaa","gaangam","neihouz","ngoih"]
            + aliases.keys.filter{$0.count>2}.sorted().prefix(100).flatMap{[$0+"aa",$0+"am",$0+"ng"]}
        for input in inputs where !["mama","mami"].contains(input) {
            let chars=Array(input);var paths=Array(repeating:[[Syllable]](),count:chars.count+1),all:[[Syllable]]=[];paths[0]=[[]]
            for start in chars.indices {
                for end in (start+1)...min(chars.count,start+6) {
                    let alias=String(chars[start..<end]);guard let origin=aliases[alias] else { continue }
                    for path in paths[start] { let next=path+[Syllable(alias:alias,origin:origin)];paths[end].append(next);all.append(next) }
                }
            }
            let schemes=all.enumerated().filter{valid($0.element)}.sorted { a,b in
                let x=a.element.map(\.alias).joined().count,y=b.element.map(\.alias).joined().count
                return x != y ? x>y:a.element.count != b.element.count ? a.element.count<b.element.count:a.offset<b.offset
            }.map(\.element)
            let full=schemes.filter{$0.map(\.alias).joined().count==input.count}
            let queries=full.isEmpty ? schemes:full.flatMap{scheme in (1...scheme.count).reversed().map{Array(scheme.prefix($0))}}
            let expected=Set(queries.filter{dictionary.hasCantonesePrefix($0.map(\.origin).joined())}.map(key))
            let actual=engine.segment(input)
            XCTAssertEqual(actual.hasFull,!full.isEmpty,input)
            XCTAssertEqual(actual.firstAliasLength,schemes.first?.first?.alias.count ?? 0,input)
            XCTAssertEqual(Set(actual.queries.map(key)),expected,input)
        }
    }
    private enum ImportedCantoneseAliases {
        static func load()->[String:String] {
            // Same source syllable import; the exhaustive traversal above is the original algorithm.
            let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            return try! JSONDecoder().decode([String:String].self,from:Data(contentsOf:root.appendingPathComponent("Sources/FusionCore/Resources/jyutping-syllables.json")))
        }
    }
    func testDeadKeySequencesMatchOriginalJava() throws {
        struct Event:Decodable { let dead:Bool,code:Int }
        struct Fixture:Decodable { let events:[Event],text:String,pending:String }
        let url=try XCTUnwrap(Bundle.module.url(forResource:"latin-dead-keys-upstream",withExtension:"json",subdirectory:"Fixtures"))
        for fixture in try JSONDecoder().decode([Fixture].self,from:Data(contentsOf:url)) {
            var combiner=LatinDeadKeys(),text=""
            for event in fixture.events {
                if event.code == -5 { if !combiner.backspace(),!text.isEmpty { text.removeLast() } }
                else if let output=combiner.input(LatinKeyValue.encoded(event.code | (event.dead ? 0x80000000:0))) { text+=output }
            }
            XCTAssertEqual(Array(text.utf16),Array(fixture.text.utf16))
            XCTAssertEqual(combiner.pending,fixture.pending)
        }
    }
    func testLatinSourceKeyMapsAltGrAndDeadAccents() {
        let french=InputMode(language:.french,layout:.azerty),german=InputMode(language:.german,layout:.deutsch)
        XCTAssertEqual(LayoutCatalog.latinKey(code:"Q",mode:french).label,"a")
        XCTAssertEqual(LayoutCatalog.latinKey(code:"1",mode:french).label,"&")
        XCTAssertEqual(LayoutCatalog.latinKey(code:"1",mode:french,hardware:false).label,"1")
        XCTAssertEqual(LayoutCatalog.latinKey(code:"Q",mode:german,altGraph:true).label,"@")
        XCTAssertEqual(LayoutCatalog.latinKey(code:"E",mode:german,altGraph:true).label,"€")
        XCTAssertEqual(LayoutCatalog.latinKey(code:"2",mode:french,capsLocked:true).label,"2")
        XCTAssertEqual(LayoutCatalog.latinKey(code:"1",mode:german,capsLocked:true).label,"1")
        XCTAssertTrue(LayoutCatalog.latinKey(code:"2",mode:french,hardware:false).values.contains(LatinKeyValue.encoded(0x8000007e)))
        let locked=LayoutCatalog.rows(for:.init(language:.english),shifted:true,numberRow:true,capsLocked:true)
        XCTAssertEqual(locked[0][0].label,"1");XCTAssertEqual(locked[1][0].label,"Q")
        XCTAssertEqual(LayoutCatalog.rows(for:french).last?.last?.label,"'")
        let key=LayoutCatalog.latinKey(code:"LEFT_BRACKET",mode:french)
        XCTAssertTrue(LatinKeyValue.isDead(key.values[0]))
        var dead=LatinDeadKeys()
        XCTAssertNil(dead.input(key.values[0]));XCTAssertEqual(dead.input("e"),"ê")
        XCTAssertNil(dead.input(LatinKeyValue.encoded(0x800000a8)));XCTAssertEqual(dead.input("u"),"ü")
        XCTAssertNil(dead.input(key.values[0]));XCTAssertEqual(dead.input(" "),"^")
        XCTAssertNil(dead.input(key.values[0]));XCTAssertTrue(dead.backspace());XCTAssertEqual(dead.input("e"),"e")
        for text in ["www.example","https://example","/path","example.org/path"] { XCTAssertTrue(LatinInputRules.looksLikeURL(text),text) }
        for text in ["hello","1/2","name@example"] { XCTAssertFalse(LatinInputRules.looksLikeURL(text),text) }
        XCTAssertTrue(LatinInputRules.insideQuoteOrAfterDigit("he said \"hello"))
        XCTAssertFalse(LatinInputRules.insideQuoteOrAfterDigit("he said \"hello\" today"))
    }
    func testImportedAndroidSettingsRemainPerMode() throws {
        let values:[String:String]=[
            "input_modes":"[\"type=cangjie;layout=Dayi3\",\"type=emoji\",\"type=latin;locale=de;layout=Deutsch\",\"type=mozc;candidate_view_height=3;flick_hint=false;flick_mode=ToggleOnly\",\"type=mozc;candidate_view_height=1;flick_hint=true\"]",
            "screen_mode":"Tablet","symbol_layout":"N2","touch_mode":"Flick","touch_correction":"false",
            "split_ratio_portrait":"15","split_ratio_landscape":"35","vibration_duration":"25","haptic_feedback":"false",
            "default_flick_action_up":"None","default_flick_action_down":"ShiftedSymbol","flick_sensitivity":"64"]
        let s=try SettingsImport.read(JSONSerialization.data(withJSONObject:values))
        XCTAssertEqual(s.modes.map(\.language),[.dayi,.emoji,.german,.japanese,.japanese])
        XCTAssertEqual(s.modes[2].layout,.deutsch)
        XCTAssertEqual(s.modes[3].candidateRows,3);XCTAssertEqual(s.modes[4].candidateRows,1)
        XCTAssertEqual(s.modes[3].flickHints,false);XCTAssertEqual(s.modes[4].flickHints,true)
        XCTAssertEqual(s.modes[3].kanaInputStyle,.toggle)
        XCTAssertEqual(s.screenMode,.tablet);XCTAssertEqual(s.symbolLayout,.n2)
        XCTAssertEqual(s.touchMode,.flick);XCTAssertFalse(s.touchCorrection)
        XCTAssertEqual(s.splitGap,0.15);XCTAssertEqual(s.splitGapLandscape,0.35)
        XCTAssertFalse(s.haptics);XCTAssertEqual(s.vibrationDuration,25)
        XCTAssertEqual(s.flickUp,.none);XCTAssertEqual(s.flickDown,.shiftedSymbol);XCTAssertEqual(s.flickSensitivity,64)
    }
    func testOldSettingsPreserveEffectiveGermanLayout() throws {
        var old=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(KeyboardSettings())) as? [String:Any])
        old.removeValue(forKey:"layoutDataVersion");old.removeValue(forKey:"touchMode");old.removeValue(forKey:"splitGapLandscape")
        old["splitGap"]=0.3
        var mode=InputMode(language:.german);mode.layout = .qwertz
        old["modes"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode([mode]))
        let s=try KeyboardSettings.decodeCompatible(JSONSerialization.data(withJSONObject:old))
        XCTAssertEqual(s.modes[0].layout,.deutsch);XCTAssertEqual(s.touchMode,.flick);XCTAssertEqual(s.splitGapLandscape,0.3)
    }
    func testKoreanPartialCommitKeepsSuffix() throws {
        let e=engine(.korean);e.append("ㅎㅏㄴㄱㅜㄱㅇㅓ")
        while !e.candidates.contains(where:{$0.text == "韓國" && $0.consumedUTF16 == 2}),e.hasMoreCandidates { e.loadMoreCandidates() }
        let c=try XCTUnwrap(e.candidates.first{$0.text == "韓國" && $0.consumedUTF16 == 2})
        XCTAssertEqual(e.commit(candidate:c),"韓國");XCTAssertEqual(e.composition,"어")
    }
    func testKoreanCursorFreezesPriorSyllablesAndDeletesOneNewJamo() {
        let e=engine(.korean);e.append("ㄱㅏㄷㅏ");e.moveCompositionCursor(-1)
        XCTAssertEqual(e.compositionCursorUTF16,1)
        e.append("ㄴ");XCTAssertEqual(e.composition,"가ㄴ다")
        e.append("ㅏ");XCTAssertEqual(e.composition,"가나다")
        e.backspace();XCTAssertEqual(e.composition,"가ㄴ다")
        e.backspace();e.backspace();XCTAssertEqual(e.composition,"다")
    }
    func testCantoneseTonesAliasesAnchorsAndPartialConsumption() throws {
        let e=engine(.jyutping)
        for input in ["neihou","nei5hou2","neihou2","neixxhoux","n'hou","nei'hou"] {
            e.reset();e.append(input)
            while !e.candidates.contains(where:{$0.text == "你好"}),e.hasMoreCandidates { e.loadMoreCandidates() }
            let c=try XCTUnwrap(e.candidates.first{$0.text == "你好"},input)
            XCTAssertEqual(c.annotation,"nei5 hou2",input)
            XCTAssertEqual(e.commit(candidate:c),"你好",input);XCTAssertEqual(e.composition,"",input)
        }
        e.append("neihouz");let first=try XCTUnwrap(e.candidates.first{$0.text == "你好"})
        XCTAssertEqual(e.commit(candidate:first),"你好");XCTAssertEqual(e.composition,"z")
    }
    func testLongAmbiguousCantoneseInputRemainsResponsive() {
        let e=engine(.jyutping),start=Date()
        e.append(String(repeating:"a",count:64))
        XCTAssertEqual(e.composition.count,64)
        print("Long Cantonese lookup seconds:",Date().timeIntervalSince(start))
        XCTAssertLessThan(Date().timeIntervalSince(start),1)
    }
    func testCandidatesContinueBeyondOldCap() {
        let e=engine(.cangjie);e.append("a")
        let first=e.candidates.map(\.id);XCTAssertTrue(e.hasMoreCandidates)
        e.loadMoreCandidates();XCTAssertGreaterThan(e.candidates.count,first.count)
        XCTAssertEqual(Array(e.candidates.prefix(first.count)).map(\.id),first)
        XCTAssertEqual(Set(e.candidates.map(\.id)).count,e.candidates.count)
    }
    func testKanaModifiersAndCompleteSyllableLayouts() {
        for (from,to) in [("は","ば"),("ば","ぱ"),("ぱ","は"),("う","ぅ"),("ぅ","ゔ"),("ゔ","う"),("つ","っ"),("っ","づ")] {
            XCTAssertEqual(KanaComposer.modified(from,action:"*"),to)
        }
        for layout in [KeyboardLayout.kanaSyllables,.kanaIroha] {
            for direction in ["horizontal","left","right"] {
                var mode=InputMode(language:.japanese,layout:layout);mode.syllablesDirection=direction
                let rows=LayoutCatalog.rows(for:mode),text=rows.flatMap{$0}.map(\.label).joined()
                XCTAssertEqual(rows.count,5);XCTAssertEqual(rows.flatMap{$0}.count,50)
                XCTAssertTrue(text.contains("ゐ"));XCTAssertTrue(text.contains("ゑ"));XCTAssertTrue(text.contains("　"))
            }
        }
    }
    func testDoublePinyinSeparatorAndSemicolonReachable() {
        for scheme in [DoublePinyin.microsoft,.sogou,.ziguang] {
            var mode=InputMode(language:.pinyin);mode.doublePinyin=scheme
            let e=engine(.pinyin);e.mode=mode
            XCTAssertTrue(LayoutCatalog.rows(for:mode).flatMap{$0}.contains{$0.values[0] == ";"})
            XCTAssertFalse(e.accepts(";"));e.append("p");XCTAssertTrue(e.accepts(";"))
        }
        XCTAssertEqual(DoublePinyin.ziranma.expand("ni'hk"),"ni'hao")
    }
    func testEmojiSourceAndLatinAlternatives() {
        XCTAssertEqual(EmojiCatalog.groups.count,9)
        XCTAssertEqual(EmojiCatalog.groups.flatMap(\.items).count,1749)
        XCTAssertGreaterThan(EmojiCatalog.variants(of:"👍").count,1)
        let german=LayoutCatalog.rows(for:.init(language:.german,layout:.deutsch),shifted:true).flatMap{$0}
        XCTAssertTrue(german.contains{$0.values.contains("ẞ")})
        XCTAssertFalse(german.contains{$0.values.contains("SS")})
        for symbol in SymbolLayout.allCases { XCTAssertFalse(LayoutCatalog.symbols(second:false,layout:symbol).isEmpty) }
    }
    func testTouchCorrectionLearnsOffsetWithoutChangingLiteralKeyCodes() {
        let correction=TouchCorrection(),frames=["a":CGRect(x:0,y:0,width:40,height:50),"b":CGRect(x:40,y:0,width:40,height:50)],codes=["a":"A","b":"B"]
        for _ in 0..<100 { _=correction.corrected(point:.init(x:36,y:25),frames:frames,codes:codes,learn:true) }
        XCTAssertEqual(correction.corrected(point:.init(x:43,y:25),frames:frames,codes:codes,learn:false),"a")
        XCTAssertNil(correction.corrected(point:.init(x:100,y:25),frames:frames,codes:codes,learn:false))
    }
}
