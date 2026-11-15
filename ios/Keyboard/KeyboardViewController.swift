import UIKit
import SwiftUI
import Combine
import FusionCore

class KeyboardViewController:UIInputViewController {
    private var store:SettingsStore!
    private var model:KeyboardModel!
    private var host:UIHostingController<KeyboardView>?
    private var heightConstraint:NSLayoutConstraint?
    private var subscriptions=Set<AnyCancellable>()
    private var writing=false
    private var documentID:UUID?
    private var expectedBefore:String?
    private var expectedAfter:String?
    private var expectedSelection:String?
    private var hasMarkedText=false
    private var reportedLanguage:String?
    private var isVisible=false

    override func viewDidLoad() {
        super.viewDidLoad()
        store=SettingsStore(allowShared:hasFullAccess)
        model=KeyboardModel(store:store)
        model.fullAccess=hasFullAccess
        model.prepareInput={ [weak self] in self?.reconcileContext() ?? false }
        model.insert={ [weak self] text in self?.mutate { $0.insertText(text) } }
        model.mark={ [weak self] text in
            guard let self else { return }
            self.mutate { proxy in KeyboardDocumentEditor.setMarkedText(text,in:proxy,starting:!self.hasMarkedText) }
            self.hasMarkedText = !text.isEmpty
        }
        model.markAt={ [weak self] text,offset in
            guard let self else { return }
            self.mutate { proxy in KeyboardDocumentEditor.setMarkedText(text,in:proxy,starting:!self.hasMarkedText,selectedOffset:offset) }
            self.hasMarkedText = !text.isEmpty
        }
        model.unmark={ [weak self] in
            self?.mutate { $0.unmarkText() }; self?.hasMarkedText=false
        }
        model.erase={ [weak self] in self?.mutate { $0.deleteBackward() } }
        model.move={ [weak self] offset in self?.mutate { $0.adjustTextPosition(byCharacterOffset:offset) } }
        model.before={ [weak self] in self?.textDocumentProxy.documentContextBeforeInput }
        model.after={ [weak self] in self?.textDocumentProxy.documentContextAfterInput }
        model.selected={ [weak self] in self?.textDocumentProxy.selectedText }
        model.dismiss={ [weak self] in self?.dismissKeyboard() }
        model.nextKeyboard={ [weak self] in self?.advanceToNextInputMode() }
        let root=KeyboardView(model:model,store:store,globe:AnyView(GlobeButton(controller:self)),menuContainer:view)
        let host=UIHostingController(rootView:root)
        self.host=host; addChild(host)
        host.view.backgroundColor = .clear; host.view.translatesAutoresizingMaskIntoConstraints=false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo:view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo:view.bottomAnchor)
        ])
        host.didMove(toParent:self)
        let height=view.heightAnchor.constraint(equalToConstant:250)
        height.priority = .required; height.isActive=true; heightConstraint=height
        store.$settings.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.model.changedSettings(); self?.updateHeight() }
        }.store(in:&subscriptions)
        model.$modeIndex.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.updateHeight(); self?.updateTraits() } }.store(in:&subscriptions)
        model.$settingsVisible.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.updateHeight() } }.store(in:&subscriptions)
        model.$symbols.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.updateHeight() } }.store(in:&subscriptions)
        model.$numberPad.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.updateHeight() } }.store(in:&subscriptions)
        snapshot(); updateTraits()
    }
    override func viewWillAppear(_ animated:Bool) {
        super.viewWillAppear(animated)
        reportedLanguage=nil
        store.reload(allowShared:hasFullAccess)
        model.fullAccess=hasFullAccess
        reconcileContext(); model.restoreSelectedMode(); updateTraits(); updateHeight()
        model.refreshClipboard()
    }
    override func viewDidAppear(_ animated:Bool) {
        super.viewDidAppear(animated)
        isVisible=true; updateTraits();model?.resumeLatinSuggestions()
    }
    override func viewWillDisappear(_ animated:Bool) {
        isVisible=false
        for menu in view.subviews.compactMap({$0 as? LanguageSelectionOverlay}) { menu.onDismiss?() }
        // WebKit discards an outstanding marked range when switching keyboards.
        // Finalize only the existing range in the same document: never submit a
        // new candidate or reinsert text into a departing/new input connection.
        if hasMarkedText, let documentID, documentID == currentDocumentID,
           expectedBefore == textDocumentProxy.documentContextBeforeInput,
           expectedAfter == textDocumentProxy.documentContextAfterInput,
           expectedSelection == textDocumentProxy.selectedText {
            writing=true; textDocumentProxy.unmarkText(); writing=false
        }
        hasMarkedText=false; model?.suspend()
        super.viewWillDisappear(animated)
    }
    override func viewDidDisappear(_ animated:Bool) {
        super.viewDidDisappear(animated)
        model?.releaseIdleResources()
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning(); model?.releaseIdleResources()
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); updateHeight() }
    override func textDidChange(_ textInput:UITextInput?) { let changed=reconcileContext(); updateTraits();if changed { model?.resumeLatinSuggestions() } }
    override func selectionDidChange(_ textInput:UITextInput?) { if reconcileContext() { updateTraits();model?.resumeLatinSuggestions() } }
    private func mutate(_ change:(UITextDocumentProxy)->Void) {
        guard let currentDocumentID, documentID == nil || documentID == currentDocumentID else {
            hasMarkedText=false; model.cancelForExternalChange(); snapshot(); return
        }
        writing=true; change(textDocumentProxy); snapshot(); writing=false
    }
    /// UIKit can return nil before the host connects, despite the nonnull Swift API.
    /// Read the Objective-C property without its unconditional NSUUID -> UUID bridge.
    private var currentDocumentID:UUID? {
        (textDocumentProxy as? NSObject)?.value(forKey:"documentIdentifier") as? UUID
    }
    private func snapshot() {
        documentID=currentDocumentID
        expectedBefore=textDocumentProxy.documentContextBeforeInput
        expectedAfter=textDocumentProxy.documentContextAfterInput
        expectedSelection=textDocumentProxy.selectedText
    }
    @discardableResult private func reconcileContext()->Bool {
        guard model != nil, !writing else { return false }
        let proxy=textDocumentProxy
        if documentID != currentDocumentID || expectedBefore != proxy.documentContextBeforeInput || expectedAfter != proxy.documentContextAfterInput || expectedSelection != proxy.selectedText {
            // The host already changed focus/selection. A WebKit document ID may
            // span multiple fields, so even unmarkText could target the old field.
            // Discard our state without sending any edit into the changed context.
            hasMarkedText=false; model.cancelForExternalChange(); snapshot()
            return true
        }
        return false
    }
    private func updateTraits() {
        guard model != nil else { return }
        model.needsGlobe=needsInputModeSwitchKey
        if hasDictationKey == store.settings.showVoiceInputButton { hasDictationKey = !store.settings.showVoiceInputButton }
        model.fullAccess=hasFullAccess
        model.numericField=[UIKeyboardType.numberPad,.decimalPad,.asciiCapableNumberPad].contains(textDocumentProxy.keyboardType ?? .default)
        model.capitalization=textDocumentProxy.autocapitalizationType ?? .sentences
        model.allowSpellChecking=textDocumentProxy.autocorrectionType != .no
        model.automaticSpaces = ![UIKeyboardType.emailAddress,.URL].contains(textDocumentProxy.keyboardType ?? .default)
        if [UIKeyboardType.emailAddress,.URL].contains(textDocumentProxy.keyboardType ?? .default) {
            model.capitalization = .none; model.allowSpellChecking=false
        }
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: model.returnLabel="이동"
        case .search: model.returnLabel="검색"
        case .send: model.returnLabel="전송"
        case .done: model.returnLabel="완료"
        case .next: model.returnLabel="다음"
        default: model.returnLabel="줄바꿈"
        }
        // UIKit may normalize the language returned by its getter. Track what we
        // sent ourselves so textDidChange cannot repeatedly notify the host.
        let language=model.mode.language.locale
        if isVisible && reportedLanguage != language {
            reportedLanguage=language
            primaryLanguage=language
        }
        model.updateCapitalization()
    }
    private func updateHeight() {
        guard model != nil else { return }
        if model.layoutWidth != view.bounds.width { model.layoutWidth=view.bounds.width }
        let kanaPad=model.mode.layout == .kana12 && !model.symbols && !model.emoji && !model.numericField
        var target=KeyboardMetrics.height(settings:model.effectiveSettings,rows:model.rows.count,width:view.bounds.width,kanaPad:kanaPad)
        if model.settingsVisible { target=max(target,view.bounds.width>550 ? 250:380) }
        if heightConstraint?.constant != target { heightConstraint?.constant=target }
    }
}

enum KeyboardDocumentEditor {
    static func setMarkedText(_ text:String,in proxy:UITextDocumentProxy,starting:Bool,selectedOffset:Int? = nil) {
        // Use the host's insertion path to replace a selection. Backspace can
        // perform smart deletion and remove adjacent whitespace in WebKit.
        // Search/address fields may display a pre-edit selection without exposing
        // selectedText; insertion also lets those hosts clear it before marking.
        let searchField=[UIKeyboardType.URL,.webSearch].contains(proxy.keyboardType ?? .default)
        if proxy.selectedText?.isEmpty == false || (starting && searchField && !text.isEmpty) {
            proxy.insertText("")
        }
        proxy.setMarkedText(text,selectedRange:NSRange(location:max(0,min(text.utf16.count,selectedOffset ?? text.utf16.count)),length:0))
    }
}
