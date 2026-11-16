import SwiftUI
import UIKit
import FusionCore
import AudioToolbox

@MainActor final class KeyboardModel:ObservableObject {
    let store:SettingsStore
    let engine:CompositionEngine
    @Published private(set) var modeIndex:Int
    @Published var composition=""
    @Published var candidates:[Candidate]=[]
    @Published var candidatesExpanded=false
    @Published var shifted=false
    @Published var capsLocked=false
    @Published private(set) var shiftHeld=false
    @Published var symbols=false
    @Published var symbolsSecond=false
    @Published var emoji=false
    @Published var settingsVisible=false
    @Published var fullAccess=false
    @Published var needsGlobe=true
    @Published var returnLabel="줄바꿈"
    @Published var message:String?
    @Published var numericField=false
    @Published var numberPad=false
    @Published var layoutWidth:CGFloat=390
    @Published var clipboardText:String?
    var capitalization:UITextAutocapitalizationType = .sentences
    var allowSpellChecking=true
    var insert:((String)->Void)?
    var mark:((String)->Void)?
    var markAt:((String,Int)->Void)?
    var unmark:(()->Void)?
    var erase:(()->Void)?
    var move:((Int)->Void)?
    var dismiss:(()->Void)?
    var before:(()->String?)?
    var after:(()->String?)?
    var selected:(()->String?)?
    var automaticSpaces=true
    var nextKeyboard:(()->Void)?
    var prepareInput:(()->Bool)?
    // Keep a partially converted prefix in the same host marked range.
    // Restarting marked text immediately after unmarking is not reliable across
    // the extension's asynchronous document proxy.
    private var convertedPrefix=""
    private var lastSpace:Date?
    private var lastShift:Date?
    private var heldShiftUsed=false
    private var kanaTap:(base:String,index:Int,time:Date)?
    private lazy var checker=UITextChecker()
    private var pendingEmoji:String?
    private var lastCorrection:(typed:String,committed:String,separator:String)?
    private enum LatinSpace { case none,weak,phantom,swapped }
    private var latinSpace:LatinSpace = .none
    private var deadKeys=LatinDeadKeys()
    private var reconversion:(word:String,before:String,after:String,suffixCount:Int)?
    private var automaticShift=false,wordAutoCapitalized=false
    private var doubleSpacePeriodInserted=false
    private let haptics=KeyboardHaptics()
    init(store:SettingsStore,lexicon:Lexicon? = nil) {
        self.store=store
        let index=store.selectedModeIndex
        modeIndex=index
        engine=CompositionEngine(mode:store.settings.modes[index],lexicon:lexicon,nativeConfiguration:store.nativeConfiguration)
        store.rememberSelectedMode(engine.mode)
        emoji=engine.mode.language == .emoji
        message=engine.dictionaryError == nil ? nil:L10n.text("변환 사전을 읽지 못했습니다. 앱을 다시 설치해 주세요.")
    }
    var mode:InputMode { store.settings.modes[min(modeIndex,store.settings.modes.count-1)] }
    var effectiveSettings:KeyboardSettings {
        var settings=store.settings
        if mode.language == .japanese {
            settings.candidateRows=mode.candidateRows ?? settings.candidateRows
            settings.flickHints=mode.flickHints ?? settings.flickHints
        }
        return settings
    }
    var tabletLayout:Bool { store.settings.screenMode == .tablet || (store.settings.screenMode == .automatic && layoutWidth>=600) }
    var isNumberPad:Bool { numericField || numberPad }
    private var koreanConversion:Bool { mode.language == .korean && mode.hanja && mode.koreanConverter != "hangul" && !numericField }
    private var convertsSymbols:Bool { koreanConversion || (mode.language == .japanese && !numericField) }
    var isShifted:Bool { shifted || shiftHeld }
    var rows:[[KeySpec]] {
        if isNumberPad { return LayoutCatalog.numbers }
        return symbols ? LayoutCatalog.symbols(second:symbolsSecond,layout:store.settings.symbolLayout):LayoutCatalog.rows(for:mode,shifted:isShifted,numberRow:mode.numberRow ?? store.settings.numberRow,tablet:tabletLayout,capsLocked:capsLocked || (automaticShift && shifted && !shiftHeld))
    }
    func changedSettings() {
        candidatesExpanded=false
        commit(predictAfter:false)
        engine.nativeConfiguration=store.nativeConfiguration
        activateMode(store.selectedModeIndex)
        refreshClipboard()
    }
    func switchMode(_ index:Int) {
        guard store.settings.modes.indices.contains(index), index != modeIndex else { return }
        candidatesExpanded=false
        commit(predictAfter:false); activateMode(index)
    }
    func restoreSelectedMode() {
        let index=store.selectedModeIndex
        guard index != modeIndex || engine.mode != store.settings.modes[index] else { return }
        // Another keyboard instance may have changed the last language. Never
        // commit a departing field's composition into the newly focused field.
        suspend(); activateMode(index)
    }
    private func activateMode(_ index:Int) {
        endShift(cancelled:true)
        modeIndex=index; engine.mode=mode; store.rememberSelectedMode(mode)
        latinSpace = .none;deadKeys.reset();reconversion=nil
        shifted=false; capsLocked=false; symbols=false; emoji=mode.language == .emoji; numberPad=false; sync(); updateCapitalization()
    }
    func text(_ value:String,holdingShift:Bool=false) {
        let manualShift=useHeldShift() || holdingShift
        _ = prepareInput?()
        feedback(); lastSpace=nil;lastCorrection=nil;doubleSpacePeriodInserted=false
        materializeLatinReconversion()
        let priorMarkedPrefix=engine.textBeforeCompositionCursor+deadKeys.pending
        if engine.raw.isEmpty { wordAutoCapitalized = !manualShift && automaticShift && shifted && value.first?.isUppercase==true }
        guard let value=mode.language.isLatin ? deadKeys.input(value):value else { markComposition();sync();return }
        if mode.language.isLatin {
            if let first=value.first,LatinInputRules.word(first),!engine.raw.isEmpty || !LatinInputRules.connector(first) {
                if latinSpace == .phantom && !LatinInputRules.connector(first) { insertLatinAutomaticSpace() }
                latinSpace = .none
            } else if !engine.accepts(value) || engine.raw.isEmpty {
                latinSeparator(value);return
            }
        }
        if emoji || mode.language == .emoji { chooseEmoji(value);return }
        var context=before?() ?? ""
        if !priorMarkedPrefix.isEmpty && context.hasSuffix(priorMarkedPrefix) { context=String(context.dropLast(priorMarkedPrefix.count)) }
        engine.previousWord=mode.language.isLatin ? context:context.split(whereSeparator:{$0.isWhitespace}).last.map(String.init) ?? ""
        let shiftedRoots=(isShifted || manualShift) && [.cangjie,.quick,.dayi].contains(mode.language)
        let compositionLayout=convertsSymbols || ((!symbols || mode.language == .vietnamese || (mode.language == .pinyin && value == "'")) && !isNumberPad)
        if compositionLayout && !shiftedRoots && engine.accepts(value) {
            var input=value
            let groups=["あ":"あいうえお","か":"かきくけこ","さ":"さしすせそ","た":"たちつてと","な":"なにぬねの","は":"はひふへほ","ま":"まみむめも","や":"やゆよ","ら":"らりるれろ","わ":"わをんー"]
            if mode.layout == .kana12 && mode.kanaTapCycle, let group=groups[value] {
                let chars=Array(group)
                if let previous=kanaTap, previous.base==value, Date().timeIntervalSince(previous.time)<0.7, !engine.raw.isEmpty {
                    engine.backspace()
                    let index=(previous.index+1)%chars.count
                    input=String(chars[index]); kanaTap=(value,index,Date())
                } else { kanaTap=(value,0,Date()) }
            } else { kanaTap=nil }
            let previous=engine.append(input)
            updateMarkedComposition(committing:previous ?? "")
            sync()
        } else { commitWithCorrection(suffix:output(value)) }
        if shifted && !capsLocked { shifted=false }
    }
    func backspace() {
        _ = useHeldShift()
        _ = prepareInput?()
        feedback(); lastSpace=nil; kanaTap=nil
        materializeLatinReconversion()
        if deadKeys.backspace() { markComposition();sync();return }
        if mode.language.isLatin,latinSpace == .swapped,let context=before?(),context.hasSuffix(" "),context.count>=2 {
            let punctuation=String(context.dropLast().suffix(1));erase?();erase?();insert?(" "+punctuation);latinSpace = .none;sync();return
        }
        latinSpace = .none
        if doubleSpacePeriodInserted,engine.raw.isEmpty,(before?() ?? "").hasSuffix(". ") {
            erase?();erase?();insert?(" ");doubleSpacePeriodInserted=false;lastCorrection=nil;updateCapitalization();return
        }
        doubleSpacePeriodInserted=false
        if let correction=lastCorrection,engine.raw.isEmpty,(before?() ?? "").hasSuffix(correction.committed) {
            for _ in correction.committed { erase?() }
            lastCorrection=nil;engine.isResumedWord=true
            if correction.separator == " " {
                engine.append(correction.typed);markComposition();sync()
            } else { insert?(correction.typed+correction.separator);sync(predictions:true) }
            return
        }
        lastCorrection=nil
        if pendingEmoji != nil { pendingEmoji=nil;mark?("");unmark?();sync();return }
        if engine.backspace() {
            updateMarkedComposition()
            sync()
        } else {
            let context=before?() ?? "",hadSelection = !(selected?() ?? "").isEmpty
            erase?()
            if mode.language.isLatin,!hadSelection,context.last.map(LatinInputRules.word) == true {
                let word=String(context.dropLast().reversed().prefix{LatinInputRules.word($0)}.reversed())
                if !word.isEmpty,word.count<48 {
                    for _ in word { erase?() };engine.isResumedWord=true;engine.append(word);markComposition();sync()
                }
            }
            updateCapitalization()
        }
    }
    func space() {
        _ = useHeldShift()
        _ = prepareInput?()
        feedback()
        materializeLatinReconversion()
        if mode.language.isLatin,!deadKeys.pending.isEmpty { if let value=deadKeys.input(" ") { text(value) };return }
        if insertLatinSeparatorInsideWord(" ") { return }
        if mode.language == .vietnamese {
            let prefix=engine.textBeforeCompositionCursor
            if prefix.hasSuffix(" ") { commit(candidate:candidates.first);return }
            if !prefix.isEmpty { engine.append(" ");markComposition();sync();return }
            commit(suffix:" ");return
        }
        if let committed=engine.convertSpace() { applyNativeCommit(committed); return }
        let converts=[InputLanguage.japanese,.pinyin,.zhuyin,.cangjie,.quick,.dayi,.jyutping].contains(mode.language)
        if !engine.raw.isEmpty {
            if converts { commit(candidate:candidates.dropFirst().first); return }
            // A single marked-text replacement keeps the separator after the word
            // even when the host processes proxy requests asynchronously.
            commitWithCorrection(suffix:output(" ")); lastSpace=Date();latinSpace = .weak;updateCapitalization();return
        }
        if mode.doubleSpacePeriod ?? store.settings.doubleSpacePeriod, mode.language.isLatin, let lastSpace, Date().timeIntervalSince(lastSpace)<1.1,
           let context=before?(),context.hasSuffix(" "), context.dropLast().last.map(LatinInputRules.allowsDoubleSpace(after:)) == true {
            erase?(); insert?(". "); self.lastSpace=nil;doubleSpacePeriodInserted=true;lastCorrection=nil;updateCapitalization()
        } else { insert?(output(" ")); lastSpace=Date();latinSpace = .weak;updateCapitalization() }
    }
    func enter() {
        _ = useHeldShift()
        _ = prepareInput?()
        feedback();materializeLatinReconversion()
        if mode.language.isLatin { if !deadKeys.pending.isEmpty { text("\n") } else { latinSeparator("\n") };return }
        let composing = !engine.raw.isEmpty
        // First Return confirms CJK composition; the next Return is sent to the host.
        commitWithCorrection(suffix:!composing || mode.language.isLatin ? "\n":"")
        updateCapitalization()
    }
    func shift() {
        automaticShift=false
        if let lastShift, Date().timeIntervalSince(lastShift)<0.35 { capsLocked=true; shifted=true }
        else { capsLocked=false; shifted.toggle() }
        lastShift=Date()
    }
    func beginShift() {
        guard !shiftHeld else { return }
        heldShiftUsed=false;shiftHeld=true
    }
    func useHeldShift()->Bool {
        guard shiftHeld else { return false }
        heldShiftUsed=true;lastShift=nil
        return true
    }
    func endShift(cancelled:Bool=false) {
        guard shiftHeld else { return }
        let used=heldShiftUsed
        shiftHeld=false;heldShiftUsed=false
        if !cancelled && !used { shift() }
    }
    func output(_ text:String) -> String {
        guard mode.fullWidth && symbols else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            scalar.value==32 ? UnicodeScalar(0x3000)! : (33...126).contains(scalar.value) ? UnicodeScalar(scalar.value+0xfee0)!:scalar
        }))
    }
    func flick(_ action:FlickAction,key:KeySpec,holdingShift:Bool=false) {
        let shifted=isShifted || holdingShift
        switch action {
        case .none:break
        case .standard:text(key.values[0],holdingShift:holdingShift)
        case .shift:
            let alternate=LayoutCatalog.rows(for:mode,shifted:!shifted,numberRow:mode.numberRow ?? store.settings.numberRow,tablet:tabletLayout).flatMap{$0}.first{$0.id==key.id}
            text(alternate?.values[0] ?? key.values[0].uppercased(),holdingShift:holdingShift)
        case .symbol,.shiftedSymbol:
            if let code=key.code,let value=LayoutCatalog.symbol(code:code,shifted:action == .shiftedSymbol || shifted,layout:store.settings.symbolLayout) {
                if convertsSymbols || mode.language == .vietnamese || mode.language.isLatin { text(value,holdingShift:holdingShift) } else { commit(suffix:output(value)) }
            }
            else { text(key.values[0],holdingShift:holdingShift) }
        case .space:space()
        case .backspace:backspace()
        case .enter:enter()
        case .nextLanguage:switchMode((modeIndex+1)%store.settings.modes.count)
        }
    }
    func commit(candidate:Candidate? = nil,suffix:String = "",predictAfter:Bool = true,manual:Bool = true) {
        engine.isResumedWord=false
        candidatesExpanded=false
        let documentChanged=prepareInput?() ?? false
        if documentChanged && candidate != nil { return }
        materializeLatinReconversion()
        if mode.language.isLatin,manual,let candidate {
            if engine.raw.isEmpty,candidate.text.count==1,let c=candidate.text.first,!LatinInputRules.word(c) {
                latinSeparator(candidate.text,fromCandidate:true);return
            }
            if latinSpace == .phantom { insertLatinAutomaticSpace() }
            latinSpace = .phantom
        }
        if let pendingEmoji {
            mark?(candidate?.text ?? pendingEmoji);unmark?();self.pendingEmoji=nil
            if !suffix.isEmpty { insert?(suffix) };sync();return
        }
        kanaTap=nil
        guard !engine.raw.isEmpty else {
            if !deadKeys.pending.isEmpty { mark?(deadKeys.pending);unmark?();deadKeys.reset();sync() }
            if let candidate { insert?(candidate.text); learn(candidate.text); sync(predictions:predictAfter) }
            if !suffix.isEmpty { insert?(suffix) }
            return
        }
        let result=engine.commit(candidate:candidate)+deadKeys.pending
        deadKeys.reset()
        updateMarkedComposition(committing:output(result)+suffix)
        learn(result)
        sync(predictions:predictAfter)
    }
    private func commitWithCorrection(suffix:String) {
        let typed=engine.composition
        let candidate=allowSpellChecking && store.settings.autoCorrection && !engine.isResumedWord ? engine.autoCorrection:nil
        commit(candidate:candidate,suffix:suffix,manual:false)
        if let candidate { lastCorrection=(typed,candidate.text+suffix,suffix) }
    }
    private func applyNativeCommit(_ result:String) {
        updateMarkedComposition(committing:result)
        if !result.isEmpty { store.learn(result,language:mode.language) }
        sync()
    }
    private func updateMarkedComposition(committing text:String="") {
        // Candidate selection, Space and typing during Mozc conversion can all
        // return a committed prefix alongside a new preedit. Publish them in one
        // replacement until the entire composition ends, regardless of language.
        convertedPrefix+=text
        if !engine.composition.isEmpty { markComposition() }
        else { mark?(convertedPrefix);unmark?();convertedPrefix="" }
    }
    func suspend() {
        convertedPrefix=""
        endShift(cancelled:true)
        // The controller finalizes any connected marked range before suspending.
        // Do not submit candidates or run next-word prediction while switching keyboards.
        engine.flushLearning()
        engine.reset(); pendingEmoji=nil; composition=""; candidates=[]; candidatesExpanded=false; lastSpace=nil; kanaTap=nil;clipboardText=nil
        haptics.stop()
        lastCorrection=nil;engine.isResumedWord=false;doubleSpacePeriodInserted=false;latinSpace = .none;deadKeys.reset();reconversion=nil
    }
    func releaseIdleResources() {
        if engine.raw.isEmpty { engine.releaseNativeResources(); candidates=[]; candidatesExpanded=false }
    }
    func cancelForExternalChange() {
        convertedPrefix=""
        endShift(cancelled:true)
        candidatesExpanded=false
        lastCorrection=nil;engine.isResumedWord=false;doubleSpacePeriodInserted=false;latinSpace = .none;deadKeys.reset();reconversion=nil
        engine.reset(); pendingEmoji=nil;sync(); lastSpace=nil; kanaTap=nil; updateCapitalization()
    }
    private func markComposition() {
        let source=engine.composition,offset=engine.compositionCursorUTF16
        let text=convertedPrefix+String(decoding:source.utf16.prefix(offset),as:UTF16.self)+deadKeys.pending+String(decoding:source.utf16.dropFirst(offset),as:UTF16.self)
        if let markAt { markAt(text,convertedPrefix.utf16.count+engine.compositionCursorUTF16+deadKeys.pending.utf16.count) }
        else { mark?(text) }
    }
    func cursor(_ offset:Int) {
        _ = useHeldShift()
        lastCorrection=nil;engine.isResumedWord=true;doubleSpacePeriodInserted=false
        _ = prepareInput?()
        materializeLatinReconversion()
        if engine.moveCompositionCursor(offset) { markComposition();sync();return }
        commit(); move?(offset); updateCapitalization()
    }
    func toggleSymbols() { endShift(cancelled:true);if mode.language != .vietnamese && !convertsSymbols { commit() }; symbols.toggle(); emoji=false;numberPad=false }
    func toggleEmoji() { endShift(cancelled:true);commit(); emoji.toggle(); symbols=false;numberPad=false }
    func toggleNumbers() { endShift(cancelled:true);if !convertsSymbols { commit() }; numberPad.toggle(); symbols=false;emoji=false }
    func chooseEmoji(_ text:String) {
        commit(predictAfter:false);pendingEmoji=text;mark?(text);composition=text
        candidates=EmojiCatalog.variants(of:text).map { Candidate($0) }
    }
    func refreshClipboard() {
        guard fullAccess,store.settings.clipboardCandidates,UIPasteboard.general.hasStrings else { clipboardText=nil;return }
        clipboardText=UIPasteboard.general.string
    }
    func useClipboard() { if let text=clipboardText { commit(suffix:text);clipboardText=nil } }
    func clearClipboard() { if fullAccess { UIPasteboard.general.items=[] };clipboardText=nil }
    func paste() {
        guard fullAccess else { message=L10n.text("붙여넣기는 설정에서 전체 접근 허용을 켜면 사용할 수 있습니다."); return }
        if let text=UIPasteboard.general.string { commit(suffix:text) }
    }
    func updateCapitalization() {
        guard mode.language.isLatin,mode.autoCapitalization ?? store.settings.autoCapitalization,!capsLocked else { return }
        let context=before?() ?? ""
        automaticShift=true
        switch capitalization {
        case .none: shifted=false
        case .allCharacters: shifted=true
        case .words: shifted=context.isEmpty || context.last?.isWhitespace == true
        default: shifted=context.isEmpty || context.hasSuffix("\n") || [". ","! ","? "].contains(where:context.hasSuffix)
        }
    }
    private func sync(predictions:Bool=false) {
        if engine.dictionaryError != nil { message=L10n.text("변환 엔진이나 사전을 읽지 못했습니다. 앱을 다시 설치해 주세요.") }
        if !engine.raw.isEmpty { store.migrateLatinHistory(to:engine) }
        if predictions && engine.raw.isEmpty { engine.predictNext(after:before?() ?? "") }
        composition=engine.composition+deadKeys.pending
        candidates=engine.candidates
        if mode.language.isLatin,engine.nativeConfiguration == nil,store.settings.learnWords,allowSpellChecking {
            let context=engine.raw.isEmpty ? (before?() ?? "").split(whereSeparator:{$0.isWhitespace}).last.map(String.init) ?? "":engine.previousWord
            let learned=store.learned(language:mode.language,prefix:composition,previous:context).filter{$0 != composition}
            var seen=Set(learned)
            candidates=learned.map{Candidate($0)}+candidates.filter{seen.insert($0.text).inserted}
        }
        if mode.language.isLatin,engine.raw.isEmpty,predictions,candidates.isEmpty { candidates=LatinInputRules.punctuation.map{Candidate($0)} }
        if candidates.isEmpty { candidatesExpanded=false }
        if mode.language.isLatin && !composition.isEmpty && allowSpellChecking {
            let language=mode.language.locale.replacingOccurrences(of:"-",with:"_")
            let range=NSRange(location:0,length:composition.utf16.count)
            let suggestions=engine.nativeConfiguration == nil ? (checker.completions(forPartialWordRange:range,in:composition,language:language) ?? []) + (checker.guesses(forWordRange:range,in:composition,language:language) ?? []):[]
            let learned=engine.nativeConfiguration == nil ? store.learned(language:mode.language,prefix:composition):[]
            var seen=Set(candidates.map(\.text))
            candidates += (learned+suggestions).filter{seen.insert($0).inserted}.prefix(12).map{Candidate($0)}
        }
    }
    private func insertLatinAutomaticSpace() {
        let context=before?() ?? ""
        if automaticSpaces,!context.isEmpty,context.last?.isWhitespace != true,!LatinInputRules.looksLikeURL(context) { insert?(" ") }
    }
    private func insertLatinSeparatorInsideWord(_ separator:String)->Bool {
        guard mode.language.isLatin,!engine.raw.isEmpty,engine.compositionCursorUTF16<engine.composition.utf16.count else { return false }
        let text=engine.composition,offset=engine.compositionCursorUTF16
        let prefix=String(decoding:text.utf16.prefix(offset),as:UTF16.self),suffix=String(decoding:text.utf16.dropFirst(offset),as:UTF16.self)
        engine.reset();mark?(prefix+separator+suffix);unmark?();move?(-suffix.count)
        engine.isResumedWord=true;latinSpace = .none;sync();updateCapitalization();return true
    }
    private func latinSeparator(_ value:String,fromCandidate:Bool=false) {
        guard let character=value.first else { return }
        if insertLatinSeparatorInsideWord(value) { return }
        let old=latinSpace,context=before?() ?? ""
        let closingQuote=character == "\"" && LatinInputRules.insideQuoteOrAfterDigit(context)
        var swap=false
        if character == "\n",old == .swapped,context.hasSuffix(" ") { erase?() }
        else if fromCandidate,(old == .weak || old == .swapped),!LatinInputRules.precededBySpace(character),context.hasSuffix(" ") {
            erase?();swap=LatinInputRules.followedBySpace(character)
        }
        if old == .phantom,(character == "\"" ? !closingQuote:LatinInputRules.precededBySpace(character)) { insertLatinAutomaticSpace() }
        commitWithCorrection(suffix:value+(swap ? " ":""))
        latinSpace=swap ? .swapped:((old == .phantom && LatinInputRules.followedBySpace(character)) || closingQuote ? .phantom:.none)
        sync(predictions:true);updateCapitalization()
    }
    /// Resume suggestions without modifying the document on cursor/focus changes.
    /// UITextDocumentProxy has no setComposingRegion; materialize only on an edit.
    func resumeLatinSuggestions() {
        guard mode.language.isLatin,allowSpellChecking,store.settings.suggestions,engine.raw.isEmpty,(selected?() ?? "").isEmpty,
              let context=before?(),let following=after?(),!LatinInputRules.looksLikeURL(context) else { return }
        let prefix=String(context.reversed().prefix{LatinInputRules.word($0)}.reversed()),suffix=String(following.prefix{LatinInputRules.word($0)}),word=prefix+suffix
        guard !word.isEmpty,word.first?.isLetter==true,word.unicodeScalars.count<48 else { return }
        engine.previousWord=String(context.dropLast(prefix.count))
        engine.isResumedWord=true
        engine.append(word);if !suffix.isEmpty { engine.moveCompositionCursor(-suffix.count) }
        reconversion=(word,context,following,suffix.count);sync()
    }
    private func materializeLatinReconversion() {
        guard let original=reconversion else { return };reconversion=nil
        guard before?()==original.before,after?()==original.after,(selected?() ?? "").isEmpty else { engine.reset();sync();return }
        if original.suffixCount>0 { move?(original.suffixCount) }
        for _ in original.word { erase?() }
        markComposition()
    }
    private func learn(_ word:String) {
        if engine.nativeConfiguration != nil { engine.learn(word,previous:engine.previousWord,autoCapitalized:wordAutoCapitalized) }
        else { store.learn(word,language:mode.language,previous:engine.previousWord) }
    }
    func forget(_ candidate:Candidate) { engine.forget(candidate);store.forget(candidate.text,language:mode.language);sync() }
    func loadMoreCandidates(after candidate:Candidate) {
        guard candidate.id == candidates.last?.id,engine.hasMoreCandidates else { return }
        engine.loadMoreCandidates();sync()
    }
    private func feedback() {
        if fullAccess && store.settings.haptics { haptics.play(milliseconds:store.settings.vibrationDuration) }
        if store.settings.sound { AudioServicesPlaySystemSound(1104) }
    }
}
