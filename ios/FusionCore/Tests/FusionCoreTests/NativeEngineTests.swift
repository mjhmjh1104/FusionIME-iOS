import XCTest
import Darwin
@testable import FusionCore

final class NativeEngineTests:XCTestCase {
    func engine(_ language:InputLanguage,mode:InputMode? = nil) -> CompositionEngine {
        let resources=EngineTests.dictionaryURL.deletingLastPathComponent().appendingPathComponent("Native")
        return CompositionEngine(mode:mode ?? .init(language:language),lexicon:try! Lexicon(url:EngineTests.dictionaryURL),nativeConfiguration:.init(resources:resources,profile:FileManager.default.temporaryDirectory.appendingPathComponent("fusion-tests")))
    }
    func testLatinOriginalHistoryPersistsForgetsAndHonorsLearningSwitch() throws {
        let resources=EngineTests.dictionaryURL.deletingLastPathComponent().appendingPathComponent("Native")
        let profile=FileManager.default.temporaryDirectory.appendingPathComponent("latin-history-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:profile) }
        var config=NativeConfiguration(resources:resources,profile:profile,learning:true)
        var predictor:NativePredictor?=try XCTUnwrap(NativePredictor(language:.english,configuration:config))
        for _ in 0..<12 { predictor!.learn("fusiontestword",previous:"hello") }
        XCTAssertTrue(predictor!.suggest("fusiontest",previous:"hello").contains{$0.text=="fusiontestword"})
        predictor!.flush();predictor=nil
        predictor=try XCTUnwrap(NativePredictor(language:.english,configuration:config))
        XCTAssertTrue(predictor!.suggest("fusiontest",previous:"hello").contains{$0.text=="fusiontestword"})
        config.learning=false
        let privatePredictor=try XCTUnwrap(NativePredictor(language:.english,configuration:config))
        XCTAssertFalse(privatePredictor.suggest("fusiontest",previous:"hello").contains{$0.text=="fusiontestword"})
        predictor!.forget("fusiontestword")
        XCTAssertFalse(predictor!.suggest("fusiontest",previous:"hello").contains{$0.text=="fusiontestword"})
    }
    func testLatinCaseQuotesAndMultiwordContext() {
        let e=engine(.english)
        e.append("HEL");XCTAssertTrue(e.candidates.contains{$0.text=="HELLO"});XCTAssertNil(e.autoCorrection)
        e.reset();e.append("Hel");XCTAssertTrue(e.candidates.contains{$0.text=="Hello"})
        e.reset();e.append("hel'");XCTAssertTrue(e.candidates.contains{$0.text=="hello'"})
        e.reset();e.previousWord="the rest of";e.append("th");XCTAssertFalse(e.candidates.isEmpty)
    }
    func testResumedLatinSuggestionsKeepDictionaryCaseAndResetForNewWords() {
        let e=engine(.english)
        e.isResumedWord=true;e.append("HEL")
        XCTAssertEqual(e.composition,"HEL")
        XCTAssertTrue(e.candidates.contains{$0.text=="hello"})
        XCTAssertFalse(e.candidates.contains{$0.text=="HELLO"})
        e.append("L");XCTAssertTrue(e.isResumedWord)
        XCTAssertTrue(e.candidates.contains{$0.text=="hello"})
        while !e.raw.isEmpty { e.backspace() }
        XCTAssertFalse(e.isResumedWord)
        e.append("HEL");XCTAssertTrue(e.candidates.contains{$0.text=="HELLO"})
        e.reset();e.isResumedWord=true;e.append("Hel")
        XCTAssertTrue(e.candidates.contains{$0.text=="Hello"})
        e.reset();e.isResumedWord=true;e.append("dont")
        XCTAssertNil(e.autoCorrection)
        _=e.commit();XCTAssertFalse(e.isResumedWord)
        e.append("dont");XCTAssertEqual(e.autoCorrection?.text,"don't")
    }
    func testIdlePresentationDoesNotLoadNativeDictionaries() {
        let e=engine(.japanese)
        XCTAssertFalse(e.hasLoadedNativeResources)
        for language in [InputLanguage.pinyin,.korean,.english,.japanese] {
            e.mode=InputMode(language:language);e.predictNext(after:"")
            XCTAssertFalse(e.hasLoadedNativeResources)
        }
        e.append("koーhiー")
        XCTAssertTrue(e.usesNativeSession)
        XCTAssertEqual(e.composition,"こーひー")
        XCTAssertTrue(e.candidates.contains{$0.text=="コーヒー"})
        e.reset();e.releaseNativeResources()
        XCTAssertFalse(e.hasLoadedNativeResources)
        e.append("nihongo");XCTAssertTrue(e.candidates.contains{$0.text=="日本語"})
    }
    func testNativeEditingPredictionAndGodanFlickCodes() throws {
        let p=engine(.pinyin);p.append("niha");p.moveCompositionCursor(-1);p.append("o")
        XCTAssertEqual(p.raw,"nihoa");p.backspace();XCTAssertEqual(p.raw,"niha")
        p.moveCompositionCursor(1);p.append("o")
        let c=try XCTUnwrap(p.candidates.first{$0.text == "你好" && $0.nativeID != nil})
        XCTAssertEqual(p.commit(candidate:c),"你好")
        p.predictNext(after:"你好");XCTAssertFalse(p.candidates.isEmpty)
        p.reset();p.releaseNativeResources()
        let j=engine(.japanese,mode:.init(language:.japanese,layout:.godan))
        j.append("k$");XCTAssertEqual(j.composition,"かっ")
        j.reset();j.append("nihongo");_ = j.convertSpace()
        XCTAssertTrue(j.candidates.contains(where:{$0.focused}))
        j.reset();j.mode=InputMode(language:.japanese,layout:.kanaSyllables)
        j.append("は");j.append("*");XCTAssertEqual(j.composition,"ば")
        j.append("*");XCTAssertEqual(j.composition,"ぱ")
    }
    func testLatinCorrectionRequiresDictionaryConfidence() throws {
        let e=engine(.english)
        e.append("dont");XCTAssertEqual(e.autoCorrection?.text,"don't")
        for word in ["hello","URL","abc123"] { e.reset();e.append(word);XCTAssertNil(e.autoCorrection,word) }
    }
    func testLongLatinContextAndRepeatedLanguageSwitches() {
        let e=engine(.english)
        e.previousWord=String(repeating:"x",count:20000)
        e.append("hel");XCTAssertTrue(e.candidates.contains{$0.text.lowercased()=="hello"})
        var baseline:UInt64=0
        for round in 0..<12 {
            for (language,input,result) in [(InputLanguage.korean,"ㅎㅏㄴ","한"),(.japanese,"nihongo","日本語"),(.pinyin,"nihao","你好"),(.zhuyin,"ㄋㄧˇㄏㄠˇ","你好")] {
                e.mode=InputMode(language:language)
                XCTAssertFalse(e.hasLoadedNativeResources)
                e.append(input)
                XCTAssertTrue(e.candidates.contains{$0.text==result},"\(language): \(e.candidates.map(\.text))")
                e.reset();e.releaseNativeResources()
                XCTAssertFalse(e.hasLoadedNativeResources)
            }
            if round==0 { baseline=footprint() }
        }
        let final=footprint()
        print("Repeated engine switch footprint: baseline=\(baseline), final=\(final)")
        XCTAssertLessThan(final,baseline+16*1024*1024,"Native resources accumulate across switches")
    }
    private func footprint()->UInt64 {
        var info=task_vm_info_data_t()
        var count=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride/MemoryLayout<integer_t>.stride)
        let result=withUnsafeMutablePointer(to:&info) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {
                task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count)
            }
        }
        XCTAssertEqual(result,KERN_SUCCESS)
        return info.phys_footprint
    }
    func testLifecycleTiming() {
        let start=Date()
        let e=engine(.korean)
        let opened=Date()
        e.mode=InputMode(language:.japanese)
        let switched=Date()
        e.append("nihongo")
        let typed=Date()
        e.mode=InputMode(language:.english)
        let left=Date()
        print("Lifecycle ms: open=\(opened.timeIntervalSince(start)*1000), switch=\(switched.timeIntervalSince(opened)*1000), firstInput=\(typed.timeIntervalSince(switched)*1000), leave=\(left.timeIntervalSince(typed)*1000)")
    }
    func testPinyinRealDecoderAndSelection() throws {
        let e=engine(.pinyin)
        e.append("nihao")
        XCTAssertTrue(e.usesNativeSession,"\(String(describing:e.dictionaryError))")
        let candidate=try XCTUnwrap(e.candidates.first{$0.text=="你好" && $0.nativeID != nil})
        XCTAssertEqual(e.commit(candidate:candidate),"你好")
        XCTAssertEqual(e.composition,"")
        e.append("zhongguo");XCTAssertTrue(e.candidates.contains{$0.text=="中国"})
        XCTAssertEqual(e.convertSpace(),"中国")
    }
    func testPinyinPartialSelectionAndStaleCandidate() throws {
        let e=engine(.pinyin);e.append("nihaoma")
        let first=try XCTUnwrap(e.candidates.first{$0.text=="你"})
        XCTAssertEqual(e.commit(candidate:first),"")
        XCTAssertTrue(e.composition.hasPrefix("你"));XCTAssertFalse(e.raw.isEmpty)
        let before=e.composition
        XCTAssertEqual(e.commit(candidate:first),"");XCTAssertEqual(e.composition,before)
        XCTAssertTrue(e.backspace());XCTAssertFalse(e.composition.hasPrefix("你"))
    }
    func testTraditionalAndDoublePinyin() {
        var mode=InputMode(language:.pinyin);mode.traditional=true;mode.doublePinyin = .xiaohe
        let e=engine(.pinyin,mode:mode);e.append("vsgo")
        XCTAssertTrue(e.candidates.contains{$0.text=="中國"},e.candidates.map(\.text).joined(separator:","))
    }
    func testChewingTonesAndPhrase() throws {
        for engine in 0...2 {
            var mode=InputMode(language:.zhuyin);mode.zhuyinEngine=engine
            let e=self.engine(.zhuyin,mode:mode)
            if engine==0 {
                e.append("ㄋㄧˇ")
                let ni=try XCTUnwrap(e.candidates.first{$0.text=="你"})
                e.commit(candidate:ni);e.append("ㄏㄠˇ")
                let hao=try XCTUnwrap(e.candidates.first{$0.text=="好"})
                e.commit(candidate:hao)
            } else { e.append("ㄋㄧˇㄏㄠˇ") }
            XCTAssertEqual(e.composition,"你好")
            XCTAssertEqual(e.commit(),"你好")
            e.append("ㄇㄚˇ")
            XCTAssertTrue(e.candidates.contains{$0.text=="馬"})
            XCTAssertFalse(e.candidates.contains{$0.text=="媽"})
        }
    }
    func testOriginalLatinAndKoreanPrediction() {
        let en=engine(.english);en.append("hel")
        XCTAssertTrue(en.candidates.contains{$0.text.lowercased()=="hello"},en.candidates.map(\.text).joined(separator:","))
        let ko=engine(.korean);ko.append("ㅎㅏㄴㄱㅜㄱ")
        XCTAssertTrue(ko.candidates.contains{$0.text=="한국"})
    }
    func testUserDictionaryAndLearningDisabled() throws {
        let resources=EngineTests.dictionaryURL.deletingLastPathComponent().appendingPathComponent("Native")
        let profile=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var config=NativeConfiguration(resources:resources,profile:profile)
        config.userDictionary=[UserEntry(language:.english,reading:"ff",text:"FusionIME")]
        let e=CompositionEngine(mode:.init(language:.english),lexicon:try Lexicon(url:EngineTests.dictionaryURL),nativeConfiguration:config)
        e.append("ff");XCTAssertTrue(e.candidates.contains{$0.text=="FusionIME"})
        let p=CompositionEngine(mode:.init(language:.pinyin),lexicon:try Lexicon(url:EngineTests.dictionaryURL),nativeConfiguration:config)
        p.append("nihao");_ = p.convertSpace()
        XCTAssertFalse(FileManager.default.fileExists(atPath:profile.path))
    }
    func testSettingsMigrationAndDictionaryImport() throws {
        let old=Data("{\"modes\":[{\"language\":\"pinyin\",\"traditional\":true}]}".utf8)
        let settings=try KeyboardSettings.decodeCompatible(old)
        XCTAssertTrue(settings.modes[0].traditional);XCTAssertEqual(settings.modes[0].layout,.qwerty)
        XCTAssertEqual(settings.flickSensitivity,18)
        let android=Data("<map><string name=\"input_modes\">[\"type=korean;layout=Set3391Strict;converter=Phrase\",\"type=pinyin;chinese_traditional=true;pinyin_spelling=Xiaohe\",\"type=viet;layout=VNIQuocNgu\"]</string><boolean name=\"split_keyboard_landscape\" value=\"true\"/></map>".utf8)
        let migrated=try SettingsImport.read(android)
        XCTAssertEqual(migrated.modes.map(\.layout),[.hangul391Strict,.qwerty,.vni])
        XCTAssertEqual(migrated.modes[0].koreanConverter,"phrase")
        XCTAssertEqual(migrated.modes[1].doublePinyin,.xiaohe)
        XCTAssertTrue(migrated.splitLandscape)
        let entries=try UserDictionaryFile.read(Data("ふゅーじょん\tFusionIME\t名詞\nhello\tHello\tenglish".utf8),defaultLanguage:.japanese)
        XCTAssertEqual(entries.map(\.language),[.japanese,.english])
        XCTAssertEqual(try UserDictionaryFile.read(UserDictionaryFile.write(entries),defaultLanguage:.korean).map(\.text),entries.map(\.text))
        XCTAssertThrowsError(try KeyboardSettings.decodeCompatible(Data("[]".utf8)))
    }
    func testVNICompositionAndVisibleCharacterDeletion() {
        XCTAssertEqual(VNIComposer.compose("tie6ng1"),"tiếng")
        XCTAssertEqual(VNIComposer.compose("Vie6t5"),"Việt")
        XCTAssertEqual(VNIComposer.compose("d9u7o7ng2"),"đường")
        XCTAssertEqual(VNIComposer.compose("a11"),"a")
        let e=engine(.vietnamese,mode:.init(language:.vietnamese,layout:.vni))
        e.append("a61");XCTAssertEqual(e.composition,"ấ")
        e.backspace();XCTAssertEqual(e.composition,"")
    }
    #if canImport(CMozc)
    func testMozcSentenceAndLiteralKana() throws {
        let e=engine(.japanese)
        e.append("nihongo");XCTAssertEqual(e.composition,"にほんご")
        let c=try XCTUnwrap(e.candidates.first{$0.text=="日本語"})
        XCTAssertEqual(e.commit(candidate:c),"日本語")
        XCTAssertEqual(e.composition,"")
        e.append("は");e.append("゛");XCTAssertEqual(e.composition,"ば")
        e.reset();e.append("watashihanihongowobenkyoushiteimasu")
        XCTAssertTrue(e.candidates.contains{$0.text.contains("日本語")})
    }
    func testMozcPartialCommitPreservesRemainder() throws {
        let e=engine(.japanese);e.append("nihongowobenkyou")
        let candidate=try XCTUnwrap(e.candidates.first{$0.text=="日本語"})
        XCTAssertEqual(e.commit(candidate:candidate),"日本語")
        XCTAssertFalse(e.composition.isEmpty)
        XCTAssertTrue(e.composition.contains("を"))
    }
    #endif
}
