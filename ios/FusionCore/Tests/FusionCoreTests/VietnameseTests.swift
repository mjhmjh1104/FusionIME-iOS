import XCTest
@testable import FusionCore

final class VietnameseTests:XCTestCase {
    private func engine(_ layout:KeyboardLayout,nom:Bool) -> CompositionEngine {
        var mode=InputMode(language:.vietnamese,layout:layout);mode.hanNom=nom
        return CompositionEngine(mode:mode,lexicon:try! Lexicon(url:EngineTests.dictionaryURL),nativeConfiguration:nil)
    }
    func testUpstreamJavaRegressionCases() throws {
        struct Vector:Decodable { let mode:String;let keys:String;let expected:String }
        let url=try XCTUnwrap(Bundle.module.url(forResource:"VietnameseOracle",withExtension:"json",subdirectory:"Fixtures"))
        let vectors=try JSONDecoder().decode([Vector].self,from:Data(contentsOf:url))
        for vector in vectors {
            let layout:KeyboardLayout=vector.mode == "telex" ? .telex:.vni
            XCTAssertEqual(Array(VietnameseComposer.compose(vector.keys,layout:layout).utf16),Array(vector.expected.utf16),"\(vector.mode): \(vector.keys)")
            let e=engine(layout,nom:false)
            for key in vector.keys { e.append(String(key)) }
            XCTAssertEqual(Array(e.composition.utf16),Array(vector.expected.utf16))
            XCTAssertTrue(e.candidates.isEmpty,"Telex/VNI Quốc ngữ has no dictionary in the original")
        }
    }
    func testMultiwordPartialConversionForAllSixModes() throws {
        for layout in [KeyboardLayout.qwerty,.telex,.vni] {
            for nom in [false,true] {
                let e=engine(layout,nom:nom)
                let input=layout == .qwerty ? "tieng viet":layout == .telex ? "tieengs vieetj":"tie6ng1 vie6t5"
                e.append(input)
                XCTAssertEqual(e.composition,layout == .qwerty ? "tieng viet":"tiếng việt")
                if !nom && layout != .qwerty { XCTAssertTrue(e.candidates.isEmpty);continue }
                let partial=try XCTUnwrap(e.candidates.first{$0.text == (nom ? "㗂":"tiếng")},"\(layout), nom=\(nom)")
                XCTAssertEqual(partial.reading,layout == .qwerty ? "tieng ":"tiếng ")
                XCTAssertEqual(e.commit(candidate:partial),nom ? "㗂":"tiếng ")
                XCTAssertEqual(e.composition,layout == .qwerty ? "viet":"việt")
                XCTAssertEqual(e.compositionCursorUTF16,e.composition.utf16.count)
                let remaining=e.composition
                XCTAssertEqual(e.commit(candidate:partial),"")
                XCTAssertEqual(e.composition,remaining,"A stale candidate must not consume new input")
            }
        }
    }
    func testCursorEditingDeletesDisplayedCharacters() {
        let e=engine(.telex,nom:false)
        e.append("asb");XCTAssertEqual(e.composition,"áb")
        XCTAssertTrue(e.moveCompositionCursor(-1));XCTAssertEqual(e.compositionCursorUTF16,1)
        e.backspace();XCTAssertEqual(e.composition,"b");XCTAssertEqual(e.compositionCursorUTF16,0)
        e.backspace();XCTAssertEqual(e.composition,"b")
        e.append("dd");XCTAssertEqual(e.composition,"đb")
        e.moveCompositionCursor(99);e.append("z");XCTAssertEqual(e.composition,"đbz")
        e.reset();e.append("aw");e.backspace();XCTAssertTrue(e.composition.isEmpty)
        e.append("s");XCTAssertEqual(e.composition,"s","Deleted accents must not reappear")
    }
    func testDictionaryKeepsCaseAndDoesNotOfferCompletions() throws {
        let e=engine(.qwerty,nom:false)
        e.append("tieng")
        XCTAssertTrue(e.candidates.contains{$0.text=="tiếng"})
        XCTAssertFalse(e.candidates.contains{$0.reading.utf16.count>5})
        e.reset();e.append("TIENG");XCTAssertTrue(e.candidates.isEmpty)
        e.mode=InputMode(language:.vietnamese,layout:.telex)
        e.append("tieengs");XCTAssertTrue(e.candidates.contains{$0.text=="㗂"})
        e.reset();e.releaseNativeResources();e.append("tieengs")
        XCTAssertTrue(e.candidates.contains{$0.text=="㗂"})
    }
    func testNomPunctuationAndVNINumberRow() {
        XCTAssertEqual(InputMode(language:.vietnamese).layout,.qwerty)
        XCTAssertTrue(InputMode(language:.vietnamese).hanNom)
        for layout in [KeyboardLayout.qwerty,.telex,.vni] {
            var mode=InputMode(language:.vietnamese,layout:layout);mode.hanNom=true
            let normal=LayoutCatalog.rows(for:mode).flatMap{$0}.flatMap{$0.values}
            let shifted=LayoutCatalog.rows(for:mode,shifted:true).flatMap{$0}.flatMap{$0.values}
            XCTAssertTrue(normal.contains("、"));XCTAssertTrue(normal.contains("。"))
            XCTAssertTrue(shifted.contains("《"));XCTAssertTrue(shifted.contains("》"))
            if layout == .vni { XCTAssertTrue("0123456789".allSatisfy{normal.contains(String($0))}) }
        }
    }
}
