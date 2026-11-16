import XCTest
@testable import FusionCore

final class KoreanConversionTests:XCTestCase {
    private func engine(_ text:String,phrase:Bool=false) throws -> CompositionEngine {
        var mode=InputMode(language:.korean);mode.koreanConverter=phrase ? "phrase":"word"
        let engine=CompositionEngine(mode:mode,lexicon:try Lexicon(url:EngineTests.dictionaryURL),nativeConfiguration:nil)
        XCTAssertTrue(engine.accepts(text));engine.append(text)
        while engine.hasMoreCandidates { engine.loadMoreCandidates() }
        return engine
    }
    func testPartialHanjaCommitKeepsUnconvertedSuffix() throws {
        for phrase in [false,true] {
            let e=try engine("ㅂㅏㄴㅇㅣㅂㄱㅡㅁㅈㅣ",phrase:phrase)
            XCTAssertEqual(e.composition,"반입금지")
            let candidate=try XCTUnwrap(e.candidates.first{$0.text=="搬入"})
            XCTAssertEqual(candidate.consumedUTF16,2)
            XCTAssertEqual(e.commit(candidate:candidate),"搬入")
            XCTAssertEqual(e.composition,"금지")
            e.append("ㄴ");XCTAssertEqual(e.composition,"금진")
        }
    }
    func testNumbersPunctuationAndMixedClausesAreConvertible() throws {
        for phrase in [false,true] {
            for (reading,text) in [("제1조","第1條"),("제12항","第12項"),("1조","1條"),("1","一"),("12","十二"),(".","…"),("...","…")] {
                let e=try engine(reading,phrase:phrase)
                let candidate=try XCTUnwrap(e.candidates.first{$0.text==text},reading)
                XCTAssertEqual(e.commit(candidate:candidate),text)
                XCTAssertEqual(e.composition,"")
            }
        }
    }
    func testCircledNumbersAndLeadingZeroes() throws {
        for (reading,text) in [("0","⓪"),("1","①"),("10","⑩"),("20","⑳"),("21","㉑"),("35","㉟"),("36","㊱"),("50","㊿")] {
            let e=try engine(reading)
            XCTAssertTrue(e.candidates.contains{$0.text==text},reading)
        }
        XCTAssertTrue(KoreanConversion.numberForms("01").contains("零一"))
        XCTAssertFalse(KoreanConversion.numberForms("01").contains("①"))
        XCTAssertTrue(KoreanConversion.numberForms(String(repeating:"1",count:80)).contains(String(repeating:"一",count:80)))
    }
    func testNorthernReadingsSupplementExistingReadings() throws {
        for phrase in [false,true] {
            for (reading,text) in [("히","姬"),("페","肺"),("페렴","肺炎"),("페염","肺炎"),("은페","隱蔽"),("유히","遊戲"),("리익","利益"),("희","姬"),("폐","肺"),
                                   ("메별","袂別"),("련메","連袂"),("녀성","女性"),("력사","歷史"),("로동","勞動"),("랭동","冷凍"),
                                   ("규률","規律"),("분렬","分裂"),("비률","比率"),("외곡","歪曲"),("거출","醵出"),("휴계","休憩"),
                                   ("사촉","使嗾"),("홍문","肛門"),("표식","標識"),("원쑤","怨讐"),("곤난","困難"),("의론","議論")] {
                let e=try engine(reading,phrase:phrase)
                let candidate=try XCTUnwrap(e.candidates.first{$0.text==text},reading)
                XCTAssertEqual(candidate.consumedUTF16,reading.utf16.count)
                XCTAssertEqual(e.commit(candidate:candidate),text)
            }
        }
        let enemy=try engine("원쑤")
        XCTAssertFalse(enemy.candidates.contains{$0.text=="元帥"})
        let rest=try engine("휴계")
        XCTAssertFalse(rest.candidates.contains{$0.text=="休揭"})
    }
    func testLongPressAlternativesOnLettersAndAllNumberLayouts() throws {
        let english=InputMode(language:.english)
        XCTAssertTrue(LayoutCatalog.latinKey(code:"A",mode:english).values.contains("á"))
        XCTAssertTrue(LayoutCatalog.latinKey(code:"A",mode:english,shifted:true).values.contains("Á"))
        for keys in [LayoutCatalog.numbers.flatMap{$0},LayoutCatalog.symbols().flatMap{$0},LayoutCatalog.rows(for:english,numberRow:true).flatMap{$0},LayoutCatalog.rows(for:.init(language:.korean),numberRow:true).flatMap{$0}] {
            XCTAssertTrue(try XCTUnwrap(keys.first{$0.label=="1"}).values.contains("½"))
            XCTAssertTrue(try XCTUnwrap(keys.first{$0.label=="3"}).values.contains("¾"))
        }
    }
    func testSupplementaryHanjaConsumesReadingLength() throws {
        for phrase in [false,true] {
            let e=try engine("조",phrase:phrase)
            let candidate=try XCTUnwrap(e.candidates.first{$0.text=="𠄬"})
            XCTAssertEqual(candidate.text.utf16.count,2)
            XCTAssertEqual(candidate.consumedUTF16,1)
            XCTAssertEqual(e.commit(candidate:candidate),"𠄬")
            XCTAssertTrue(e.composition.isEmpty)
        }
    }
    func testCandidateDeduplicationPreservesHanGlyphVariants() throws {
        let e=try engine("버스")
        XCTAssertEqual(e.candidates.filter{$0.text=="버스"}.count,1)
        let kana=Candidate.unique([Candidate("が"),Candidate("か\u{3099}",nativeID:2),Candidate("ガ")])
        XCTAssertEqual(kana.map(\.text),["が","ガ"])
        XCTAssertEqual(Candidate.unique([Candidate("神"),Candidate("神")]).count,2)
        let native=NativeEngineTests().engine(.japanese)
        native.append("nihon")
        XCTAssertEqual(native.candidates.filter{$0.text==native.composition}.count,1)
        XCTAssertEqual(Set(native.candidates.map{Data($0.text.utf8)}).count,native.candidates.count)
    }
}
