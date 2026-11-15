import XCTest
import FusionCore
import Combine
import UIKit
import SwiftUI

@MainActor final class KeyboardIntegrationTests:XCTestCase {
    func testAppAndKeyboardIncludeMatchingLocalizations() throws {
        let keyboard=try XCTUnwrap(Bundle(url:Bundle.main.bundleURL.appendingPathComponent("PlugIns/FusionKeyboard.appex")))
        let languages=["en","ko","ja","zh-Hans","zh-Hant","vi"]
        var referenceKeys:Set<String>?
        for language in languages {
            var tables:[[String:String]]=[]
            for bundle in [Bundle.main,keyboard] {
                XCTAssertEqual(bundle.developmentLocalization,"en")
                let path=try XCTUnwrap(bundle.path(forResource:language,ofType:"lproj"))
                let localized=try XCTUnwrap(Bundle(path:path))
                let url=try XCTUnwrap(localized.url(forResource:"Localizable",withExtension:"strings"))
                let table=try XCTUnwrap(try PropertyListSerialization.propertyList(from:Data(contentsOf:url),format:nil) as? [String:String])
                XCTAssertGreaterThan(table.count,100)
                let keys=Set(table.keys)
                if let referenceKeys { XCTAssertEqual(keys,referenceKeys) } else { referenceKeys=keys }
                XCTAssertFalse(table.values.contains(where:{$0.isEmpty}))
                for key in ["입력 방식","키보드 설정","다음 키보드","언어 추가","학습 기록 지우기"] {
                    XCTAssertEqual(L10n.text(key,bundle:localized),table[key])
                    if language != "ko" { XCTAssertNotEqual(L10n.text(key,bundle:localized),key) }
                }
                tables.append(table)
            }
            XCTAssertEqual(tables[0],tables[1],"App and extension differ for \(language)")
        }
    }
    @MainActor final class NormalizingLanguageController:KeyboardViewController {
        var languageNotifications=0
        override var primaryLanguage:String? {
            get { "ko" }
            set { languageNotifications+=1 }
        }
    }
    @MainActor final class Document {
        var committed="",marked=""
        var text:String { committed+marked }
        func attach(_ model:KeyboardModel) {
            model.mark={self.marked=$0}
            model.unmark={self.committed+=self.marked;self.marked=""}
            model.insert={self.committed+=$0}
            model.before={self.text}
            model.erase={if !self.committed.isEmpty {self.committed.removeLast()}}
        }
    }
    /// Exercise UIKit's real selection/marked-range behavior instead of an
    /// append-only mock document. The proxy mirrors the keyboard host API.
    @MainActor final class TextViewDocument:NSObject,UITextDocumentProxy {
        let view=UITextView(frame:CGRect(x:0,y:0,width:320,height:200))
        let documentIdentifier=UUID()
        var documentInputMode:UITextInputMode? { view.textInputMode }
        var hasText:Bool { view.hasText }
        var documentContextBeforeInput:String? { (view.text as NSString).substring(to:view.selectedRange.location) }
        var documentContextAfterInput:String? { (view.text as NSString).substring(from:NSMaxRange(view.selectedRange)) }
        var selectedText:String? {
            view.selectedRange.length>0 ? (view.text as NSString).substring(with:view.selectedRange):nil
        }
        func insertText(_ text:String) { view.insertText(text) }
        func deleteBackward() { view.deleteBackward() }
        func setMarkedText(_ text:String,selectedRange:NSRange) { view.setMarkedText(text,selectedRange:selectedRange) }
        func unmarkText() { view.unmarkText() }
        func adjustTextPosition(byCharacterOffset offset:Int) {
            view.selectedRange=NSRange(location:max(0,min((view.text as NSString).length,view.selectedRange.location+offset)),length:0)
        }
        func attach(_ model:KeyboardModel) {
            model.mark={KeyboardDocumentEditor.setMarkedText($0,in:self,starting:self.view.markedTextRange == nil)}
            model.markAt={KeyboardDocumentEditor.setMarkedText($0,in:self,starting:self.view.markedTextRange == nil,selectedOffset:$1)}
            model.unmark={self.unmarkText()}
            model.insert={self.insertText($0)}
            model.erase={self.deleteBackward()}
            model.before={self.documentContextBeforeInput}
            model.after={self.documentContextAfterInput}
            model.selected={self.selectedText}
            model.move={self.adjustTextPosition(byCharacterOffset:$0)}
        }
    }
    @MainActor final class AddressDocument:NSObject,UITextDocumentProxy {
        let field=UITextField(frame:CGRect(x:0,y:0,width:320,height:44))
        var hidesSelection=false
        let documentIdentifier=UUID()
        var documentInputMode:UITextInputMode? { field.textInputMode }
        var keyboardType:UIKeyboardType { get { field.keyboardType } set { field.keyboardType=newValue } }
        var hasText:Bool { field.hasText }
        var documentContextBeforeInput:String? {
            guard let selection=field.selectedTextRange,let range=field.textRange(from:field.beginningOfDocument,to:selection.start) else { return nil }
            return field.text(in:range)
        }
        var documentContextAfterInput:String? {
            guard let selection=field.selectedTextRange,let range=field.textRange(from:selection.end,to:field.endOfDocument) else { return nil }
            return field.text(in:range)
        }
        var selectedText:String? { hidesSelection ? nil:field.selectedTextRange.flatMap{field.text(in:$0)} }
        func insertText(_ text:String) { field.insertText(text) }
        func deleteBackward() { field.deleteBackward() }
        func setMarkedText(_ text:String,selectedRange:NSRange) { field.setMarkedText(text,selectedRange:selectedRange) }
        func unmarkText() { field.unmarkText() }
        func adjustTextPosition(byCharacterOffset offset:Int) {
            guard let selection=field.selectedTextRange,let position=field.position(from:selection.end,offset:offset) else { return }
            field.selectedTextRange=field.textRange(from:position,to:position)
        }
    }
    func model(_ language:InputLanguage) throws -> KeyboardModel {
        let store=SettingsStore(allowShared:false,storage:UserDefaults(suiteName:"FusionTests."+UUID().uuidString)!)
        store.settings=KeyboardSettings();store.settings.modes=[.init(language:language)]
        let resources=Bundle.main.bundleURL.appendingPathComponent("PlugIns/FusionKeyboard.appex/Native")
        let model=KeyboardModel(store:store,lexicon:try Lexicon(url:resources.deletingLastPathComponent().appendingPathComponent("lexicon.sqlite")))
        XCTAssertTrue(FileManager.default.fileExists(atPath:resources.appendingPathComponent("mozc.data").path))
        model.engine.nativeConfiguration=NativeConfiguration(resources:resources,profile:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        return model
    }
    func testSettingsReloadKeepsIdentityAndDoesNotPublishChanges() {
        let defaults=UserDefaults(suiteName:"FusionReloadTests."+UUID().uuidString)!
        let store=SettingsStore(allowShared:false,storage:defaults)
        let original=store.settings
        var updates=0
        let token=store.$settings.dropFirst().sink { _ in updates+=1 }
        for _ in 0..<20 { store.reload(allowShared:false) }
        XCTAssertEqual(updates,0);XCTAssertEqual(store.settings,original)
        XCTAssertEqual(SettingsStore(allowShared:false,storage:defaults).settings,original)
        withExtendedLifetime(token) {}
    }
    func testReadOnlySharedSettingsPreserveDraftUntilAppChanges() throws {
        let local=UserDefaults(suiteName:"FusionLocal."+UUID().uuidString)!,shared=UserDefaults(suiteName:"FusionShared."+UUID().uuidString)!
        let original=Data("original".utf8),draft=Data("draft".utf8),updated=Data("updated".utf8)
        shared.set(original,forKey:"fusion.settings.v1")
        XCTAssertEqual(SettingsStore.settingsData(local:local,shared:shared),original)
        local.set(draft,forKey:"fusion.settings.v1");local.set(original,forKey:"fusion.settings.sharedBaseline.v1")
        XCTAssertEqual(SettingsStore.settingsData(local:local,shared:shared),draft)
        XCTAssertEqual(shared.data(forKey:"fusion.settings.v1"),original)
        shared.set(updated,forKey:"fusion.settings.v1")
        XCTAssertEqual(SettingsStore.settingsData(local:local,shared:shared),updated)
    }
    func testNormalizedPrimaryLanguageDoesNotRepeatHostNotifications() {
        let controller=NormalizingLanguageController()
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        XCTAssertEqual(controller.languageNotifications,0)
        controller.viewDidAppear(false)
        for _ in 0..<50 { controller.textDidChange(nil) }
        XCTAssertEqual(controller.languageNotifications,1)
    }
    func testSelectedLanguageAndLayoutSurviveKeyboardRecreation() {
        let suite="FusionSelectionTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let store=SettingsStore(allowShared:false,storage:defaults)
        store.settings.modes=[.init(language:.korean),.init(language:.japanese,layout:.romaji),.init(language:.japanese,layout:.kana12)]
        let selected=store.settings.modes[2]
        var updates=0
        let token=store.$settings.dropFirst().sink { _ in updates+=1 }
        let first=KeyboardModel(store:store)
        first.switchMode(2);first.suspend();first.releaseIdleResources()
        let restored=KeyboardModel(store:SettingsStore(allowShared:false,storage:UserDefaults(suiteName:suite)!))
        XCTAssertEqual(restored.mode,selected)
        XCTAssertEqual(restored.engine.mode,selected)
        XCTAssertTrue(restored.composition.isEmpty)
        XCTAssertFalse(restored.engine.hasLoadedNativeResources)
        XCTAssertEqual(updates,0,"Changing languages must not reload shared settings")
        withExtendedLifetime(token) {}
    }
    func testSelectedLanguageSurvivesReorderAndFallsBackWhenRemoved() {
        let suite="FusionSelectionTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let store=SettingsStore(allowShared:false,storage:defaults)
        store.settings.modes=[.init(language:.korean),.init(language:.english),.init(language:.japanese)]
        let model=KeyboardModel(store:store)
        model.switchMode(2)
        let selected=model.mode
        store.settings.modes.swapAt(0,2);model.changedSettings()
        XCTAssertEqual(model.modeIndex,0)
        XCTAssertEqual(model.mode,selected)
        XCTAssertEqual(model.engine.mode,selected)
        store.settings.modes.removeAll { $0.id == selected.id };model.changedSettings()
        XCTAssertEqual(model.modeIndex,0)
        XCTAssertEqual(model.mode.language,.english)
        let restored=KeyboardModel(store:SettingsStore(allowShared:false,storage:UserDefaults(suiteName:suite)!))
        XCTAssertEqual(restored.mode,model.mode)
    }
    func testReturningKeyboardRestoresLatestLanguageWithoutWritingOldComposition() throws {
        let suite="FusionSelectionTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let store=SettingsStore(allowShared:false,storage:defaults)
        store.settings.modes=[.init(language:.korean),.init(language:.english),.init(language:.japanese)]
        let returning=KeyboardModel(store:store),oldDocument=Document()
        returning.engine.nativeConfiguration=nil
        oldDocument.attach(returning)
        returning.text("ㄱ");returning.text("ㅏ")
        XCTAssertEqual(oldDocument.text,"가")
        let other=KeyboardModel(store:SettingsStore(allowShared:false,storage:UserDefaults(suiteName:suite)!))
        other.switchMode(2)
        let newDocument=Document();newDocument.committed="새 입력창 ";newDocument.attach(returning)
        store.reload(allowShared:false);returning.restoreSelectedMode()
        XCTAssertEqual(returning.mode,other.mode)
        XCTAssertEqual(returning.engine.mode,other.mode)
        XCTAssertTrue(returning.composition.isEmpty)
        XCTAssertTrue(returning.candidates.isEmpty)
        XCTAssertFalse(returning.engine.hasLoadedNativeResources)
        XCTAssertEqual(oldDocument.text,"가")
        XCTAssertEqual(newDocument.text,"새 입력창 ")
    }
    func testSuspendDoesNotWriteToDepartingDocument() async throws {
        let m=try model(.japanese),d=Document();d.attach(m)
        m.text("nihongo");XCTAssertEqual(d.marked,"にほんご")
        m.suspend()
        XCTAssertEqual(d.marked,"にほんご");XCTAssertEqual(d.committed,"")
        XCTAssertEqual(m.composition,"");XCTAssertTrue(m.candidates.isEmpty)
        m.releaseIdleResources();XCTAssertFalse(m.engine.hasLoadedNativeResources)
    }
    func testInputPreflightRejectsCandidateFromPreviousField() async throws {
        let m=try model(.japanese),first=Document();first.attach(m)
        m.text("nihongo")
        let oldCandidate=try XCTUnwrap(m.candidates.first{$0.text=="日本語"})
        let second=Document();second.committed="새 입력창 ";second.attach(m)
        var changed=true
        m.prepareInput={
            guard changed else { return false }
            changed=false;m.cancelForExternalChange();return true
        }
        m.commit(candidate:oldCandidate)
        XCTAssertEqual(second.text,"새 입력창 ")
        XCTAssertEqual(first.text,"にほんご")
        m.text("ka");m.enter()
        XCTAssertEqual(second.text,"새 입력창 か")
        XCTAssertEqual(first.text,"にほんご")
    }
    func testTypingReplacesSelectedTextAndPreservesBothSides() async throws {
        for (language,input,expected) in [(InputLanguage.korean,"ㄴㅏ","나"),(.japanese,"ka","か"),(.english,"hello","hello")] {
            let m=try model(language),d=TextViewDocument();d.attach(m)
            let selected="👨‍👩‍👧‍👦 선택\n영역"
            d.view.text="앞 "+selected+" 뒤"
            d.view.selectedRange=(d.view.text as NSString).range(of:selected)
            for c in input { m.text(String(c)) }
            m.commit(predictAfter:false)
            XCTAssertEqual(d.view.text,"앞 "+expected+" 뒤",language.rawValue)
            XCTAssertEqual(d.view.selectedRange,NSRange(location:("앞 "+expected).utf16.count,length:0))
        }
    }
    func testSelectionDuringCompositionReplacesOnlySelectedRange() async throws {
        let m=try model(.korean),d=TextViewDocument();d.attach(m)
        d.view.text="앞 ";d.view.selectedRange=NSRange(location:2,length:0)
        for c in "ㅎㅏㄴㄱㅡㄹ" { m.text(String(c)) }
        XCTAssertEqual(d.view.text,"앞 한글")
        d.view.selectedRange=(d.view.text as NSString).range(of:"한글")
        var changed=true
        m.prepareInput={
            guard changed else { return false }
            changed=false;m.cancelForExternalChange();return true
        }
        m.text("ㄴ");m.text("ㅏ");m.commit(predictAfter:false)
        XCTAssertEqual(d.view.text,"앞 나")
    }
    func testSelectionReplacementForDirectInputAndEmptySelection() async throws {
        let m=try model(.korean),d=TextViewDocument();d.attach(m)
        d.view.text="앞 선택 뒤";d.view.selectedRange=NSRange(location:2,length:2)
        m.text("😀")
        XCTAssertEqual(d.view.text,"앞 😀 뒤")
        m.text("ㄱ");m.text("ㅏ");m.commit(predictAfter:false)
        XCTAssertEqual(d.view.text,"앞 😀가 뒤")
    }
    func testAddressFieldClearsOnInsertionBeforeStartingComposition() {
        let d=AddressDocument()
        let window=UIWindow(frame:UIScreen.main.bounds)
        let controller=UIViewController();window.rootViewController=controller
        controller.view.addSubview(d.field);window.makeKeyAndVisible()
        defer { d.field.resignFirstResponder();window.isHidden=true }
        d.field.keyboardType = .webSearch
        d.field.text="https://example.com/old"
        XCTAssertTrue(d.field.becomeFirstResponder())
        d.field.selectedTextRange=d.field.textRange(from:d.field.endOfDocument,to:d.field.endOfDocument)
        d.field.clearsOnInsertion=true
        // Some host proxies omit the selection in the address pre-edit state.
        d.hidesSelection=true
        XCTAssertTrue(d.selectedText?.isEmpty ?? true)
        KeyboardDocumentEditor.setMarkedText("ㄴ",in:d,starting:true)
        XCTAssertEqual(d.field.text,"ㄴ")
        d.field.clearsOnInsertion=false
        KeyboardDocumentEditor.setMarkedText("나",in:d,starting:false)
        d.unmarkText()
        XCTAssertEqual(d.field.text,"나")
    }
    func testAddressFieldExplicitSelectionAndCaretInsertion() {
        let d=AddressDocument()
        d.field.keyboardType = .webSearch
        d.field.text="https://example.com/old"
        d.field.selectedTextRange=d.field.textRange(from:d.field.beginningOfDocument,to:d.field.endOfDocument)
        KeyboardDocumentEditor.setMarkedText("새 검색",in:d,starting:true);d.unmarkText()
        XCTAssertEqual(d.field.text,"새 검색")
        KeyboardDocumentEditor.setMarkedText("어",in:d,starting:true);d.unmarkText()
        XCTAssertEqual(d.field.text,"새 검색어")
    }
    func testCompactKeyboardGeometryAndLabels() {
        let settings=KeyboardSettings()
        XCTAssertEqual(KeyboardMetrics.height(settings:settings,rows:3,width:393,kanaPad:false),250)
        XCTAssertLessThanOrEqual(KeyboardMetrics.height(settings:settings,rows:3,width:852,kanaPad:false),185)
        XCTAssertLessThanOrEqual(KeyboardMetrics.height(settings:settings,rows:4,width:393,kanaPad:true),250)
        XCTAssertEqual(InputMode(language:.korean).displayName,"한국어 두벌식")
        let romaji=LayoutCatalog.rows(for:.init(language:.japanese,layout:.romaji))
        XCTAssertEqual(romaji[1].last?.values.first,"ー")
        XCTAssertEqual(romaji.map(\.count),[10,10,7])
        for shifted in [false,true] {
            let numbered=LayoutCatalog.rows(for:.init(language:.japanese,layout:.romaji),shifted:shifted,numberRow:true)
            XCTAssertEqual(numbered[2].last?.values.first,"ー")
            XCTAssertEqual(numbered.flatMap{$0}.filter{$0.values.first=="ー"}.count,1)
        }
    }
    private func keyboardWindow(_ model:KeyboardModel,touches:KeyboardTouchCoordinator)->UIWindow {
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:250))
        window.rootViewController=UIHostingController(rootView:KeyboardView(model:model,store:model.store,globe:AnyView(EmptyView()),touches:touches))
        window.makeKeyAndVisible()
        return window
    }
    private func renderKeyboard(_ window:UIWindow) async throws {
        window.layoutIfNeeded()
        // Let SwiftUI deliver row changes and geometry preferences to the same
        // coordinator used by KeyCap's touch-down and touch-up handlers.
        try await Task.sleep(nanoseconds:100_000_000)
        window.layoutIfNeeded()
    }
    func testShiftAndCapsLockRefreshTouchInputWithoutGeometryChanges() async throws {
        for correction in [false,true] {
            let m=try model(.english),d=Document(),touches=KeyboardTouchCoordinator();d.attach(m)
            m.store.settings.autoCapitalization=false
            let window=keyboardWindow(m,touches:touches)
            defer { window.isHidden=true }
            try await renderKeyboard(window)
            let key=try XCTUnwrap(m.rows.flatMap{$0}.first{$0.code=="Q"})
            let frame=try XCTUnwrap(touches.frames[key.id])
            let point=CGPoint(x:frame.midX,y:frame.midY),frames=touches.frames
            func input(_ expected:String) throws {
                let selected=try XCTUnwrap(touches.target(point,correct:correction,learn:true))
                XCTAssertEqual(selected.values[0],expected)
                m.text(selected.values[0])
            }
            m.shift();try await renderKeyboard(window)
            XCTAssertEqual(touches.frames,frames)
            try input("Q")
            XCTAssertFalse(m.shifted)
            try await renderKeyboard(window);try input("q")
            XCTAssertEqual(d.text,"Qq")
            m.shift();m.shift();try await renderKeyboard(window)
            XCTAssertTrue(m.capsLocked)
            try input("Q");try await renderKeyboard(window);try input("Q")
            XCTAssertEqual(d.text,"QqQQ")
            try await Task.sleep(nanoseconds:360_000_000)
            m.shift();try await renderKeyboard(window)
            XCTAssertFalse(m.capsLocked)
            try input("q")
            XCTAssertEqual(d.text,"QqQQq")
        }
    }
    func testAutomaticCapitalizationRefreshesTouchInputWithoutGeometryChanges() async throws {
        let m=try model(.english),d=Document(),touches=KeyboardTouchCoordinator();d.attach(m)
        m.store.settings.autoCapitalization=true;m.capitalization = .sentences
        let window=keyboardWindow(m,touches:touches)
        defer { window.isHidden=true }
        try await renderKeyboard(window)
        let key=try XCTUnwrap(m.rows.flatMap{$0}.first{$0.code=="Q"})
        let frame=try XCTUnwrap(touches.frames[key.id]),frames=touches.frames
        let point=CGPoint(x:frame.midX,y:frame.midY)
        m.updateCapitalization();try await renderKeyboard(window)
        XCTAssertTrue(m.shifted);XCTAssertEqual(touches.frames,frames)
        m.text(try XCTUnwrap(touches.target(point,correct:true,learn:true)).values[0])
        try await renderKeyboard(window)
        m.text(try XCTUnwrap(touches.target(point,correct:true,learn:true)).values[0])
        XCTAssertEqual(d.text,"Qq")
    }
    private func shiftControl(in view:UIView)->ShiftControl? {
        if let control=view as? ShiftControl { return control }
        return view.subviews.lazy.compactMap{self.shiftControl(in:$0)}.first
    }
    private func keyTouch(_ code:String,model:KeyboardModel,touches:KeyboardTouchCoordinator) throws -> (KeySpec,CGPoint) {
        let key=try XCTUnwrap(model.rows.flatMap{$0}.first{$0.code==code})
        let frame=try XCTUnwrap(touches.frames[key.id])
        return (key,CGPoint(x:frame.midX,y:frame.midY))
    }
    private func typeKey(_ code:String,expecting value:String,model:KeyboardModel,touches:KeyboardTouchCoordinator) throws {
        let (key,point)=try keyTouch(code,model:model,touches:touches)
        touches.updateKeys(model.rows)
        touches.begin(key.id,holdingShift:model.useHeldShift())
        defer { touches.end(key.id) }
        let selected=try XCTUnwrap(touches.target(point,correct:true,learn:true,start:key.id,preferCurrent:model.isShifted))
        XCTAssertEqual(selected.values[0],value)
        model.text(selected.values[0],holdingShift:touches.holdingShift(key.id))
    }
    func testFirstKeyUsesCurrentShiftInsteadOfUnshiftedTouchSnapshot() async throws {
        for (language,plain,shifted) in [(InputLanguage.english,"r","R"),(.korean,"ㄱ","ㄲ")] {
            for mode in [KeyboardTouchMode.seek,.flick] {
                for held in [false,true] {
                    let m=try model(language),d=Document(),touches=KeyboardTouchCoordinator();d.attach(m)
                    m.store.settings.autoCapitalization=false
                    let key=try XCTUnwrap(m.rows.flatMap{$0}.first{$0.code=="R"})
                    let point=CGPoint(x:20,y:20)
                    touches.frames=[key.id:CGRect(x:0,y:0,width:40,height:40)]
                    touches.updateKeys(m.rows);touches.begin(key.id,holdingShift:false)
                    XCTAssertEqual(touches.key(key.id,start:key.id)?.values[0],plain)
                    // Simulate a character touch captured before Shift's update,
                    // with no SwiftUI render between the modifier and dispatch.
                    if held { m.beginShift() } else { m.shift() }
                    touches.updateKeys(m.rows)
                    let selected=try XCTUnwrap(mode == .seek
                        ? touches.target(point,correct:true,learn:false,start:key.id,preferCurrent:m.isShifted)
                        : touches.key(key.id,start:key.id,preferCurrent:m.isShifted))
                    XCTAssertEqual(selected.values[0],shifted)
                    m.text(selected.values[0],holdingShift:touches.holdingShift(key.id))
                    touches.end(key.id)
                    if held { m.endShift() }
                    XCTAssertEqual(d.text,shifted)
                    XCTAssertFalse(m.isShifted);XCTAssertFalse(m.capsLocked)
                }
            }
        }
    }
    func testHeldShiftTypesMultipleUppercaseLettersUntilRelease() async throws {
        let m=try model(.english),d=Document(),touches=KeyboardTouchCoordinator();d.attach(m)
        m.store.settings.autoCapitalization=false
        let window=keyboardWindow(m,touches:touches)
        defer { window.isHidden=true }
        try await renderKeyboard(window)
        let shift=try XCTUnwrap(shiftControl(in:window))
        XCTAssertFalse(shift.isExclusiveTouch)
        let press=try XCTUnwrap(shift.gestureRecognizers?.compactMap{$0 as? UILongPressGestureRecognizer}.first)
        XCTAssertEqual(press.minimumPressDuration,0)
        XCTAssertFalse(press.cancelsTouchesInView)
        shift.handlePress(.began)
        XCTAssertTrue(m.isShifted)
        XCTAssertEqual(m.rows.flatMap{$0}.first{$0.code=="R"}?.label,"R")
        // A second finger can arrive before SwiftUI renders another frame.
        try typeKey("R",expecting:"R",model:m,touches:touches)
        try await renderKeyboard(window)
        try typeKey("T",expecting:"T",model:m,touches:touches)
        XCTAssertTrue(m.shiftHeld);XCTAssertFalse(m.capsLocked)
        shift.handlePress(.ended)
        XCTAssertFalse(m.isShifted)
        try typeKey("R",expecting:"r",model:m,touches:touches)
        XCTAssertEqual(d.text,"RTr")
        // A chord must not count as the first tap of a Caps Lock double tap.
        shift.handlePress(.began);shift.handlePress(.ended)
        XCTAssertTrue(m.shifted);XCTAssertFalse(m.capsLocked)
    }
    func testHeldShiftTypesKoreanDoubleConsonants() async throws {
        let m=try model(.korean),d=Document(),touches=KeyboardTouchCoordinator();d.attach(m)
        let window=keyboardWindow(m,touches:touches)
        defer { window.isHidden=true }
        try await renderKeyboard(window)
        let shift=try XCTUnwrap(shiftControl(in:window))
        shift.handlePress(.began)
        XCTAssertEqual(m.rows.flatMap{$0}.first{$0.code=="R"}?.label,"ㄲ")
        for (code,value) in [("R","ㄲ"),("K","ㅏ"),("T","ㅆ"),("K","ㅏ")] {
            try typeKey(code,expecting:value,model:m,touches:touches)
        }
        shift.handlePress(.ended)
        try typeKey("R",expecting:"ㄱ",model:m,touches:touches)
        try typeKey("K",expecting:"ㅏ",model:m,touches:touches)
        XCTAssertEqual(d.text,"까싸가")
        XCTAssertFalse(m.isShifted)
    }
    func testHeldShiftSurvivesShiftFingerReleasingBeforeLetter() async throws {
        for mode in [KeyboardTouchMode.seek,.flick] {
            let m=try model(.english),d=Document(),touches=KeyboardTouchCoordinator();d.attach(m)
            m.store.settings.autoCapitalization=false;m.store.settings.touchMode=mode
            let window=keyboardWindow(m,touches:touches)
            defer { window.isHidden=true }
            try await renderKeyboard(window)
            let shift=try XCTUnwrap(shiftControl(in:window))
            shift.handlePress(.began)
            let (key,point)=try keyTouch("R",model:m,touches:touches)
            touches.begin(key.id,holdingShift:m.useHeldShift())
            let startKey=try XCTUnwrap(touches.target(point,correct:true,learn:true,start:key.id))
            shift.handlePress(.ended)
            try await renderKeyboard(window)
            XCTAssertFalse(m.isShifted)
            XCTAssertEqual(touches.target(point,correct:true,learn:false)?.values[0],"r")
            let selected=mode == .seek ? try XCTUnwrap(touches.target(point,correct:true,learn:false,start:key.id)):startKey
            m.text(selected.values[0],holdingShift:touches.holdingShift(key.id));touches.end(key.id)
            try typeKey("T",expecting:"t",model:m,touches:touches)
            XCTAssertEqual(d.text,"Rt")
            XCTAssertFalse(touches.holdingShift(key.id))
        }
    }
    func testShiftControlPreservesTapCapsLockAndAccessibility() async throws {
        let m=try model(.english),d=Document(),touches=KeyboardTouchCoordinator();d.attach(m)
        m.store.settings.autoCapitalization=false
        let window=keyboardWindow(m,touches:touches)
        defer { window.isHidden=true }
        try await renderKeyboard(window)
        let shift=try XCTUnwrap(shiftControl(in:window))
        shift.handlePress(.began);shift.handlePress(.ended)
        XCTAssertTrue(m.shifted);XCTAssertFalse(m.shiftHeld);XCTAssertFalse(m.capsLocked)
        shift.handlePress(.began);shift.handlePress(.ended)
        XCTAssertTrue(m.capsLocked)
        shift.handlePress(.began)
        try typeKey("R",expecting:"R",model:m,touches:touches)
        shift.handlePress(.ended)
        XCTAssertTrue(m.capsLocked)
        try typeKey("T",expecting:"T",model:m,touches:touches)
        XCTAssertEqual(d.text,"RT")
        shift.handlePress(.began);shift.handlePress(.ended)
        XCTAssertFalse(m.isShifted);XCTAssertFalse(m.capsLocked)
        try await Task.sleep(nanoseconds:360_000_000)
        XCTAssertTrue(shift.accessibilityActivate())
        XCTAssertTrue(m.shifted);XCTAssertFalse(m.shiftHeld)
    }
    func testHeldShiftCancellationAndKeyboardDepartureDoNotLatch() async throws {
        let m=try model(.english),touches=KeyboardTouchCoordinator()
        m.store.settings.autoCapitalization=false
        let window=keyboardWindow(m,touches:touches)
        defer { window.isHidden=true }
        try await renderKeyboard(window)
        let shift=try XCTUnwrap(shiftControl(in:window))
        for state in [UIGestureRecognizer.State.cancelled,.ended] {
            shift.handlePress(.began);shift.handlePress(state,inside:false)
            XCTAssertFalse(m.isShifted);XCTAssertFalse(m.shiftHeld)
        }
        shift.handlePress(.began);m.suspend();shift.handlePress(.ended)
        XCTAssertFalse(m.isShifted);XCTAssertFalse(m.capsLocked)
        shift.handlePress(.began);m.cancelForExternalChange();shift.handlePress(.ended)
        XCTAssertFalse(m.isShifted);XCTAssertFalse(m.shiftHeld)
        shift.handlePress(.began)
        m.toggleSymbols();try await renderKeyboard(window)
        shift.handlePress(.ended)
        XCTAssertFalse(m.shiftHeld)
        XCTAssertFalse(m.isShifted)
    }
    func testWordSeparatorsAndPunctuationStayAfterComposition() async throws {
        let m=try model(.korean),d=Document();d.attach(m)
        for c in "ㅎㅏㄴㄱㅡㄹ" { m.text(String(c)) }
        m.space();XCTAssertEqual(d.text,"한글 ")
        m.text("ㄱㅏ");m.text("!");XCTAssertEqual(d.text,"한글 가!")
        let english=try model(.english),e=Document();e.attach(english)
        english.text("hello");english.enter();XCTAssertEqual(e.text,"hello\n")
    }
    func testLatinCorrectionUndoAndResumingEditedWord() throws {
        let m=try model(.english),d=TextViewDocument();d.attach(m)
        m.text("dont");m.space();XCTAssertEqual(d.view.text,"don't ")
        m.backspace();XCTAssertEqual(d.view.text,"dont");XCTAssertEqual(m.composition,"dont")
        m.space();XCTAssertEqual(d.view.text,"dont ")
        m.suspend();d.view.text="hello";d.view.selectedRange=NSRange(location:5,length:0)
        m.backspace();XCTAssertEqual(d.view.text,"hell");XCTAssertEqual(m.composition,"hell")
        m.text("o");m.space();XCTAssertEqual(d.view.text,"hello ")
    }
    func testLatinCorrectionHonorsHostAndUserPreference() throws {
        let m=try model(.english),d=TextViewDocument();d.attach(m)
        m.allowSpellChecking=false;m.text("dont");m.space();XCTAssertEqual(d.view.text,"dont ")
        m.allowSpellChecking=true;m.store.settings.autoCorrection=false
        m.text("dont");m.space();XCTAssertEqual(d.view.text,"dont dont ")
    }
    func testDoubleSpacePeriodCanBeUndone() throws {
        let m=try model(.english),d=TextViewDocument();d.attach(m)
        m.text("hello");m.space();m.space();XCTAssertEqual(d.view.text,"hello. ")
        m.backspace();XCTAssertEqual(d.view.text,"hello ")
    }
    func testLatinManualPickUsesPhantomSpaceAndPunctuationSwap() throws {
        let m=try model(.english),d=TextViewDocument();d.attach(m)
        m.store.settings.autoCorrection=false
        m.text("hello");m.commit(candidate:Candidate("hello"))
        XCTAssertEqual(d.view.text,"hello")
        m.text("w");XCTAssertEqual(d.view.text,"hello w")
        m.text("orld");m.space();m.commit(candidate:Candidate(","))
        XCTAssertEqual(d.view.text,"hello world, ")
        m.backspace();XCTAssertEqual(d.view.text,"hello world ,")
        m.text("!");XCTAssertEqual(d.view.text,"hello world ,!")
    }
    func testLatinPhantomSpaceBeforeBracketsAndAfterPunctuation() throws {
        let m=try model(.english),d=TextViewDocument();d.attach(m)
        m.store.settings.autoCorrection=false
        m.text("hello");m.commit(candidate:Candidate("hello"));m.text(".");m.text("w")
        XCTAssertEqual(d.view.text,"hello. w")
        m.commit(candidate:Candidate("world"));m.text("(");m.text("test")
        XCTAssertEqual(d.view.text,"hello. world (test")
    }
    func testLatinReconversionPreservesSurroundingTextAndCursor() throws {
        let m=try model(.english),d=TextViewDocument();d.attach(m)
        d.view.text="one hello two";d.view.selectedRange=NSRange(location:6,length:0)
        m.resumeLatinSuggestions()
        XCTAssertEqual(m.composition,"hello");XCTAssertEqual(d.view.text,"one hello two")
        m.text("x");XCTAssertEqual(d.view.text,"one hexllo two")
        m.space();XCTAssertEqual(d.view.text,"one hex llo two")
        XCTAssertEqual(d.view.selectedRange.location,8)
        m.suspend();d.view.selectedRange=NSRange(location:4,length:3);m.resumeLatinSuggestions()
        XCTAssertTrue(m.composition.isEmpty)
        m.text("new");XCTAssertEqual(d.view.text,"one new llo two")
    }
    func testLatinUppercaseReconversionKeepsSourceCandidateCase() throws {
        let m=try model(.english),d=TextViewDocument();d.attach(m)
        d.view.text="one HEL two";d.view.selectedRange=NSRange(location:6,length:0)
        m.resumeLatinSuggestions()
        XCTAssertEqual(d.view.text,"one HEL two")
        XCTAssertEqual(d.view.selectedRange,NSRange(location:6,length:0))
        XCTAssertEqual(m.composition,"HEL")
        XCTAssertFalse(m.candidates.contains{$0.text=="HELLO"})
        m.commit(candidate:try XCTUnwrap(m.candidates.first{$0.text=="hello"}))
        XCTAssertEqual(d.view.text,"one hello two")
        XCTAssertTrue(m.composition.isEmpty)
        m.suspend();d.view.text="Hel";d.view.selectedRange=NSRange(location:3,length:0)
        m.resumeLatinSuggestions()
        XCTAssertTrue(m.candidates.contains{$0.text=="Hello"})
    }
    func testLatinDeletedWordResumesCaseUntilFullyErased() throws {
        let m=try model(.english),d=TextViewDocument();d.attach(m)
        d.view.text="HELX";d.view.selectedRange=NSRange(location:4,length:0)
        m.backspace()
        XCTAssertEqual(d.view.text,"HEL")
        XCTAssertTrue(m.candidates.contains{$0.text=="hello"})
        XCTAssertFalse(m.candidates.contains{$0.text=="HELLO"})
        m.text("L");XCTAssertEqual(d.view.text,"HELL")
        XCTAssertTrue(m.candidates.contains{$0.text=="hello"})
        for _ in 0..<4 { m.backspace() }
        XCTAssertEqual(d.view.text,"")
        m.text("HEL")
        XCTAssertTrue(m.candidates.contains{$0.text=="HELLO"})
    }
    func testLatinDeadAccentPreviewDeleteAndCommit() throws {
        let m=try model(.french),d=TextViewDocument();d.attach(m)
        let dead=LatinKeyValue.encoded(0x80000000 | 0x5e)
        m.text(dead);XCTAssertEqual(d.view.text,"^")
        m.text("e");XCTAssertEqual(d.view.text,"ê")
        m.text(dead);m.backspace();XCTAssertEqual(d.view.text,"ê")
        m.text(dead);m.space();XCTAssertEqual(d.view.text,"ê^")
        m.text(dead);m.commit();XCTAssertEqual(d.view.text,"ê^^")
        m.text(dead);m.enter();XCTAssertEqual(d.view.text,"ê^^^")
        m.text(dead);m.cancelForExternalChange();XCTAssertTrue(m.composition.isEmpty)
    }
    func testLatinCorrectionUndoRetainsPunctuationAndSelectionDelete() throws {
        let m=try model(.english),d=TextViewDocument();d.attach(m)
        m.text("dont");m.text(".");XCTAssertEqual(d.view.text,"don't.")
        m.backspace();XCTAssertEqual(d.view.text,"dont.")
        m.suspend();d.view.text="first second";d.view.selectedRange=NSRange(location:6,length:6)
        m.backspace();XCTAssertEqual(d.view.text,"first ");XCTAssertTrue(m.composition.isEmpty)
    }
    func testKoreanPartialCommitAndCursorInUIKit() throws {
        let m=try model(.korean),d=TextViewDocument();d.attach(m)
        m.text("ㅎㅏㄴㄱㅜㄱㅇㅓ")
        while !m.candidates.contains(where:{$0.text == "韓國" && $0.consumedUTF16 == 2}),m.engine.hasMoreCandidates {
            m.loadMoreCandidates(after:try XCTUnwrap(m.candidates.last))
        }
        m.commit(candidate:try XCTUnwrap(m.candidates.first{$0.text == "韓國" && $0.consumedUTF16 == 2}))
        XCTAssertEqual(d.view.text,"韓國어");XCTAssertEqual(m.composition,"어")
        m.text("ㄴ");XCTAssertEqual(d.view.text,"韓國언")
        m.cursor(-1);m.text("ㄱㅏ");XCTAssertEqual(d.view.text,"韓國가언")
        m.backspace();XCTAssertEqual(d.view.text,"韓國ㄱ언")
    }
    func testFlickNoneAndShiftedSymbol() throws {
        let m=try model(.english),d=Document();d.attach(m)
        let key=try XCTUnwrap(m.rows.flatMap{$0}.first{$0.code == "Q"})
        m.flick(.none,key:key);XCTAssertEqual(d.text,"")
        m.store.settings.symbolLayout = .g
        m.flick(.shiftedSymbol,key:key)
        XCTAssertEqual(d.text,LayoutCatalog.symbol(code:"Q",shifted:true,layout:.g))
    }
    func testLearnedContextAndPerLanguageHistoryClear() throws {
        let store=try model(.english).store;store.settings.learnWords=true
        store.learn("world",language:.english,previous:"hello")
        store.learn("friend",language:.english,previous:"dear")
        store.learn("Welt",language:.german,previous:"Hallo")
        XCTAssertEqual(store.learned(language:.english,prefix:"",previous:"hello"),["world"])
        store.clearHistory(language:.english)
        XCTAssertTrue(store.learned(language:.english,prefix:"",previous:"hello").isEmpty)
        XCTAssertEqual(store.learned(language:.german,prefix:"W"),["Welt"])
    }
    func testKeyboardControllerBeforeHostDocumentConnects() async {
        let controller=KeyboardViewController()
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        controller.textDidChange(nil)
        controller.selectionDidChange(nil)
        controller.viewWillDisappear(false)
        XCTAssertFalse(controller.view.subviews.isEmpty)
    }
    func testJapanesePartialCandidateThenNextWord() async throws {
        let m=try model(.japanese),d=Document();d.attach(m)
        for c in "nihongowobenkyou" { m.text(String(c)) }
        m.commit(candidate:try XCTUnwrap(m.candidates.first{$0.text=="日本語"}))
        XCTAssertEqual(d.committed,"日本語");XCTAssertTrue(d.marked.hasPrefix("を"))
        m.enter();XCTAssertTrue(d.text.hasPrefix("日本語を"));XCTAssertEqual(d.marked,"")
        XCTAssertFalse(d.text.contains("日本語日本語"))
    }
    func testPinyinSelectionDoesNotDuplicateOrLoseSuffix() async throws {
        let m=try model(.pinyin),d=Document();d.attach(m)
        m.text("nihaoma")
        m.commit(candidate:try XCTUnwrap(m.candidates.first{$0.text=="你"}))
        XCTAssertEqual(d.committed,"");XCTAssertEqual(d.marked,m.engine.composition)
        m.space();XCTAssertFalse(d.text.contains("nihaoma"));XCTAssertTrue(d.text.hasPrefix("你"))
    }
    func testDeletingCompositionLeavesPreviousDocumentText() async throws {
        let m=try model(.korean),d=Document();d.committed="앞 문장 ";d.attach(m)
        m.text("ㄱ");m.text("ㅏ");m.text("ㄴ")
        m.backspace();XCTAssertEqual(d.text,"앞 문장 가")
        m.backspace();m.backspace();XCTAssertEqual(d.text,"앞 문장 ")
        m.backspace();XCTAssertEqual(d.text,"앞 문장")
    }
    func testChewingAndLanguageSwitchFinalizeMarkedText() async throws {
        let m=try model(.zhuyin),d=Document();d.attach(m)
        m.text("ㄋㄧˇㄏㄠˇ");XCTAssertEqual(d.marked,"你好")
        m.store.settings.modes.append(.init(language:.english))
        m.switchMode(1);XCTAssertEqual(d.text,"你好");XCTAssertEqual(d.marked,"")
        m.text("hello");m.space();XCTAssertEqual(d.text,"你好hello ")
    }
    func testGlobeTapCyclesLanguagesAndCommitsCompositionOnce() async throws {
        let m=try model(.japanese),d=Document();d.attach(m)
        m.store.settings.modes += [.init(language:.english),.init(language:.korean)]
        m.text("nihongo")
        let control=LanguageMenuButton(modes:m.store.settings.modes,selectedIndex:0,container:nil,select:m.switchMode)
        let button=control.makeControl()
        button.sendActions(for:.primaryActionTriggered)
        XCTAssertEqual(m.mode.language,.english)
        XCTAssertFalse(d.committed.isEmpty);XCTAssertEqual(d.marked,"")
        let committed=d.text
        // Consecutive taps must advance even before SwiftUI renders a new menu.
        button.sendActions(for:.primaryActionTriggered)
        XCTAssertEqual(m.mode.language,.korean)
        button.sendActions(for:.primaryActionTriggered)
        XCTAssertEqual(m.mode.language,.japanese)
        XCTAssertEqual(d.text,committed)
        // A menu selection chooses exactly that language, without advancing.
        button.choose(2)
        XCTAssertEqual(m.mode.language,.korean)
        button.sendActions(for:.primaryActionTriggered)
        XCTAssertEqual(m.mode.language,.japanese)
    }
    func testGlobeDragOpensImmediatelyAndSelectsOnlyOnRelease() throws {
        let container=UIView(frame:CGRect(x:0,y:0,width:393,height:250))
        let control=LanguageSwitchControl(frame:CGRect(x:4,y:3,width:30,height:36))
        container.addSubview(control);control.menuContainer=container
        var selections:[Int]=[]
        let modes=[InputMode(language:.korean),.init(language:.english),.init(language:.japanese)]
        control.configure(modes:modes,selectedIndex:0) { selections.append($0) }
        control.beginInteraction(at:CGPoint(x:19,y:21))
        XCTAssertNil(control.languageMenu)
        control.moveInteraction(to:CGPoint(x:24,y:21))
        let menu=try XCTUnwrap(control.languageMenu,"Dragging must open synchronously, without the long-press timer")
        let row=menu.rows[2]
        let point=row.convert(CGPoint(x:row.bounds.midX,y:row.bounds.midY),to:container)
        control.moveInteraction(to:point)
        // An unrelated SwiftUI update must not dismiss the menu mid-gesture.
        control.configure(modes:modes,selectedIndex:0) { selections.append($0) }
        XCTAssertTrue(control.languageMenu === menu);XCTAssertTrue(selections.isEmpty)
        control.endInteraction(at:point)
        XCTAssertEqual(selections,[2]);XCTAssertNil(control.languageMenu)
    }
    func testGlobeDragCancellationDoesNotAdvanceLanguage() {
        let container=UIView(frame:CGRect(x:0,y:0,width:393,height:250))
        let control=LanguageSwitchControl(frame:CGRect(x:4,y:3,width:30,height:36))
        container.addSubview(control);control.menuContainer=container
        var selections:[Int]=[]
        control.configure(modes:[.init(language:.korean),.init(language:.english)],selectedIndex:0) { selections.append($0) }
        control.beginInteraction(at:CGPoint(x:19,y:21))
        control.moveInteraction(to:CGPoint(x:26,y:21))
        control.endInteraction(at:CGPoint(x:390,y:245))
        XCTAssertTrue(selections.isEmpty);XCTAssertNil(control.languageMenu)
        control.beginInteraction(at:CGPoint(x:19,y:21))
        control.moveInteraction(to:CGPoint(x:26,y:21));control.cancelInteraction()
        control.endInteraction(at:CGPoint(x:19,y:21))
        XCTAssertTrue(selections.isEmpty)
        control.beginInteraction(at:CGPoint(x:19,y:21))
        control.moveInteraction(to:CGPoint(x:20,y:22))
        control.endInteraction(at:CGPoint(x:20,y:22))
        XCTAssertEqual(selections,[1],"Small tap jitter must still advance once")
    }
    func testGlobeFastDragUsesReleaseLocationWithoutIntermediateEvents() {
        let container=UIView(frame:CGRect(x:0,y:0,width:393,height:250))
        let control=LanguageSwitchControl(frame:CGRect(x:4,y:3,width:30,height:36))
        container.addSubview(control);control.menuContainer=container
        var selections:[Int]=[]
        control.configure(modes:[.init(language:.korean),.init(language:.english),.init(language:.japanese)],selectedIndex:0) { selections.append($0) }
        control.beginInteraction(at:CGPoint(x:19,y:21))
        // Menu starts at y=41, and its third 44pt row contains y=151.
        control.endInteraction(at:CGPoint(x:150,y:151))
        XCTAssertEqual(selections,[2]);XCTAssertNil(control.languageMenu)
        control.endInteraction(at:CGPoint(x:150,y:151))
        XCTAssertEqual(selections,[2],"A release must never select twice")
    }
    func testExpandedCandidatesCloseOnSelectionAndDocumentChange() async throws {
        let m=try model(.japanese),d=Document();d.attach(m)
        m.text("nihongo");m.candidatesExpanded=true
        m.commit(candidate:try XCTUnwrap(m.candidates.first{$0.text=="日本語"}))
        XCTAssertEqual(d.text,"日本語");XCTAssertFalse(m.candidatesExpanded)
        m.text("ka");m.candidatesExpanded=true;m.cancelForExternalChange()
        XCTAssertTrue(m.candidates.isEmpty);XCTAssertFalse(m.candidatesExpanded)
        m.text("ka");m.candidatesExpanded=true;m.suspend()
        XCTAssertFalse(m.candidatesExpanded)
    }
    func testHanjaPhraseResyllabificationOnIOS() throws {
        let bundle=Bundle.main.bundleURL.appendingPathComponent("PlugIns/FusionKeyboard.appex")
        var mode=InputMode(language:.korean);mode.koreanConverter="phrase"
        let engine=CompositionEngine(mode:mode,lexicon:try Lexicon(url:bundle.appendingPathComponent("lexicon.sqlite")),nativeConfiguration:NativeConfiguration(resources:bundle.appendingPathComponent("Native"),profile:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        for c in "ㄷㅐㅎ" { engine.append(String(c)) }
        XCTAssertEqual(engine.composition,"댛")
        engine.append("ㅏ")
        XCTAssertEqual(engine.composition,"대하")
        XCTAssertTrue(engine.candidates.contains{$0.text=="大河"})
        XCTAssertNil(engine.dictionaryError)
        XCTAssertEqual(engine.commit(),"대하")
    }
    func testVietnameseMultiwordSpaceAndReturnInUIKit() throws {
        let m=try model(.vietnamese),d=TextViewDocument();d.attach(m)
        m.store.settings.modes[0].layout = .telex;m.store.settings.modes[0].hanNom=false;m.changedSettings()
        m.text("tieengs");m.space();m.text("Vieetj")
        XCTAssertEqual(d.view.text,"tiếng Việt")
        XCTAssertNotNil(d.view.markedTextRange)
        XCTAssertTrue(m.candidates.isEmpty)
        m.enter();XCTAssertEqual(d.view.text,"tiếng Việt");XCTAssertNil(d.view.markedTextRange)
        m.enter();XCTAssertEqual(d.view.text,"tiếng Việt\n")
        m.text("aass");m.backspace();XCTAssertEqual(d.view.text,"tiếng Việt\n")
        m.text("s");XCTAssertEqual(d.view.text,"tiếng Việt\ns")
    }
    func testVietnamesePartialCandidateKeepsRemainingMarkedText() throws {
        let m=try model(.vietnamese),d=TextViewDocument();d.attach(m)
        m.store.settings.modes[0].layout = .qwerty;m.store.settings.modes[0].hanNom=false;m.changedSettings()
        m.text("tieng");m.space();m.text("viet")
        m.commit(candidate:try XCTUnwrap(m.candidates.first{$0.text=="tiếng"}))
        XCTAssertEqual(d.view.text,"tiếng viet");XCTAssertEqual(m.composition,"viet")
        XCTAssertNotNil(d.view.markedTextRange)
        m.enter();XCTAssertEqual(d.view.text,"tiếng viet");XCTAssertNil(d.view.markedTextRange)
    }
    func testVietnameseSecondSpaceSelectsNomPhrase() throws {
        let m=try model(.vietnamese),d=TextViewDocument();d.attach(m)
        m.store.settings.modes[0].layout = .qwerty;m.store.settings.modes[0].hanNom=true;m.changedSettings()
        m.text("tieng");m.space();m.text("viet");m.space()
        XCTAssertEqual(d.view.text,"tieng viet ");XCTAssertNotNil(d.view.markedTextRange)
        XCTAssertEqual(m.candidates.first?.text,"㗂越")
        m.space();XCTAssertEqual(d.view.text,"㗂越");XCTAssertTrue(m.composition.isEmpty)
        XCTAssertNil(d.view.markedTextRange)
    }
    func testVietnameseCursorEditingAfterReplacingSelection() throws {
        let m=try model(.vietnamese),d=TextViewDocument();d.attach(m)
        m.store.settings.modes[0].layout = .telex;m.store.settings.modes[0].hanNom=false;m.changedSettings()
        d.view.text="before OLD after";d.view.selectedRange=NSRange(location:7,length:3)
        m.text("asb");m.cursor(-1)
        XCTAssertEqual(d.view.text,"before áb after");XCTAssertEqual(d.view.selectedRange.location,8)
        m.backspace();XCTAssertEqual(d.view.text,"before b after")
        XCTAssertEqual(d.view.selectedRange.location,7)
        m.text("dd");XCTAssertEqual(d.view.text,"before đb after")
        XCTAssertEqual(d.view.selectedRange.location,8)
        m.enter();XCTAssertEqual(d.view.text,"before đb after");XCTAssertNil(d.view.markedTextRange)
    }
    func testVietnameseSymbolPageKeepsComposition() throws {
        let m=try model(.vietnamese),d=TextViewDocument();d.attach(m)
        m.store.settings.modes[0].layout = .vni;m.store.settings.modes[0].hanNom=false;m.changedSettings()
        m.text("a6");m.toggleSymbols();m.text("1");m.text(",")
        XCTAssertEqual(d.view.text,"ấ,");XCTAssertEqual(m.composition,"ấ,")
        m.toggleSymbols();m.backspace();m.backspace()
        XCTAssertEqual(d.view.text,"");XCTAssertTrue(m.composition.isEmpty)
    }
}
