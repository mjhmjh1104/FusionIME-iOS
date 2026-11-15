import Foundation

public final class CompositionEngine {
    public var mode:InputMode { didSet { if mode != oldValue { reset(); releaseNativeResources() } } }
    public var nativeConfiguration:NativeConfiguration? { didSet { if nativeConfiguration != oldValue { reset(); releaseNativeResources() } } }
    public var previousWord=""
    /// A word resumed from the document keeps the source dictionary's case.
    /// Unlike newly typed capitals, it must not force every suggestion uppercase.
    public var isResumedWord=false
    public var usesNativeSession:Bool { native != nil }
    public var hasLoadedNativeResources:Bool { native != nil || predictor != nil }
    private var nativeAttempted=false
    public private(set) var raw=""
    public private(set) var composition=""
    public private(set) var candidates:[Candidate]=[]
    public private(set) var dictionaryError:String?
    private let lexicon:Lexicon?
    private var native:NativeSession?
    private var predictor:NativePredictor?
    private var vietnameseDictionary:VietnameseDictionary?
    private var vietnameseCursor=0
    private var rawCursor:Int?
    private var candidateLimit=40
    private var hanjaCache:(input:String,phrase:Bool,candidates:[Candidate])?
    private var cantoneseCache:(input:String,candidates:[Candidate])?
    public private(set) var hasMoreCandidates=false
    public var compositionCursorUTF16:Int {
        if let native { return native.cursorUTF16 }
        if mode.language == .vietnamese { return vietnameseCursor }
        if let rawCursor { return render(String(String.UnicodeScalarView(raw.unicodeScalars.prefix(rawCursor)))).utf16.count }
        return composition.utf16.count
    }
    public var textBeforeCompositionCursor:String { String(decoding:composition.utf16.prefix(compositionCursorUTF16),as:UTF16.self) }
    public init(mode:InputMode = .init(language:.korean), lexicon:Lexicon? = nil,nativeConfiguration:NativeConfiguration? = .bundled) {
        self.mode=mode
        self.nativeConfiguration=nativeConfiguration
        if let lexicon { self.lexicon=lexicon }
        else {
            do { self.lexicon=try Lexicon() }
            catch { self.lexicon=nil; dictionaryError=String(describing:error) }
        }
    }
    /// Loading dictionaries must not delay presenting an idle keyboard.
    private func prepareNativeIfNeeded() {
        guard !nativeAttempted else { return }
        nativeAttempted=true
        if lexicon != nil { dictionaryError=nil }
        guard let config=nativeConfiguration else { return }
        if [.japanese,.pinyin,.zhuyin].contains(mode.language) {
            do { native=try NativeSession(mode:mode,configuration:config) }
            catch { dictionaryError=String(describing:error) }
        } else if mode.language.isLatin || mode.language == .korean {
            predictor=NativePredictor(language:mode.language,configuration:config)
            if predictor == nil { dictionaryError="LatinIME dictionary: \(mode.language.rawValue)" }
        }
    }
    /// Keep at most one language engine; drop it on memory pressure or a mode change.
    public func releaseNativeResources() {
        guard raw.isEmpty else { return }
        native=nil; predictor=nil; nativeAttempted=false
        vietnameseDictionary=nil
        cantoneseCache=nil;hanjaCache=nil
    }
    private func apply(_ frame:NativeFrame) -> String {
        composition=frame.preedit; raw=native?.mode.language == .pinyin ? native!.input:frame.preedit
        candidates=frame.candidates
        hasMoreCandidates=native?.hasMoreCandidates ?? false
        candidates.insert(contentsOf:userCandidates(composition),at:0)
        if !composition.isEmpty { candidates.insert(Candidate(composition),at:0) }
        return frame.committed
    }
    private func userCandidates(_ reading:String) -> [Candidate] {
        guard !reading.isEmpty else { return [] }
        return (nativeConfiguration?.userDictionary ?? []).filter{$0.language==mode.language && $0.reading.hasPrefix(reading)}.map{Candidate($0.text,reading:$0.reading)}
    }
    public func reset() { if !raw.isEmpty { native?.reset() }; raw=""; composition=""; candidates=[]; vietnameseCursor=0;rawCursor=nil;candidateLimit=40;hasMoreCandidates=false;isResumedWord=false }
    public func predictNext(after context:String) {
        guard raw.isEmpty else { return }
        previousWord=mode.language.isLatin ? context:context.split(whereSeparator:{$0.isWhitespace}).last.map(String.init) ?? ""
        candidates=native?.predict(after:context) ?? predictor?.suggest("",previous:previousWord) ?? []
    }
    /// Native Space converts a segment or completes a tone; nil means ordinary space.
    public func convertSpace() -> String? {
        guard let native,!composition.isEmpty else { return nil }
        return apply(native.space())
    }
    /// The original Pinyin decoder has a 120-byte spelling buffer; other engines
    /// retain the full composition and enforce their own protocol constraints.
    @discardableResult public func append(_ text:String) -> String? {
        prepareNativeIfNeeded()
        candidateLimit=40
        var committed:String?
        let size=mode.language == .pinyin ? mode.doublePinyin.expand(raw+text).utf8.count:raw.unicodeScalars.count+text.unicodeScalars.count
        if mode.language == .pinyin && size>120 { committed=commit() }
        if let native {
            let result=apply(native.append(text))
            let combined=(committed ?? "")+result
            return combined.isEmpty ? nil:combined
        }
        if mode.language == .vietnamese {
            let prefix=String(decoding:raw.utf16.prefix(vietnameseCursor),as:UTF16.self)
            let suffix=String(decoding:raw.utf16.dropFirst(vietnameseCursor),as:UTF16.self)
            let converted=VietnameseComposer.appending(text,to:prefix,layout:mode.layout)
            raw=converted+suffix; vietnameseCursor=converted.utf16.count
        } else if mode.language == .japanese && ["゛","゜","小","*"].contains(text) {
            modifyKana(text)
        } else if let cursor=rawCursor {
            var units=Array(raw.unicodeScalars);units.insert(contentsOf:text.unicodeScalars,at:cursor)
            raw=String(String.UnicodeScalarView(units));rawCursor=cursor+text.unicodeScalars.count
        } else { raw += text }
        refresh()
        return committed
    }
    @discardableResult public func backspace() -> Bool {
        guard !raw.isEmpty else { return false }
        candidateLimit=40
        if let native { _=apply(native.backspace()); return true }
        // A Jamo cluster is one Swift Character; delete one input scalar, not the whole syllable.
        if mode.language == .vietnamese {
            if vietnameseCursor>0 {
                var units=Array(raw.utf16);units.remove(at:vietnameseCursor-1)
                raw=String(decoding:units,as:UTF16.self);vietnameseCursor-=1
            }
        } else if let cursor=rawCursor {
            if cursor>0 { var units=Array(raw.unicodeScalars);units.remove(at:cursor-1);raw=String(String.UnicodeScalarView(units));rawCursor=cursor-1 }
        } else if mode.language == .korean { raw=String(raw.unicodeScalars.dropLast()) }
        else { raw.removeLast() }
        refresh(); return true
    }
    public func commit(candidate:Candidate? = nil) -> String {
        if mode.language == .vietnamese,let candidate {
            guard candidates.contains(candidate),let count=candidate.consumedUTF16,
                  count>0,count<=vietnameseCursor else { return "" }
            raw=String(decoding:raw.utf16.dropFirst(count),as:UTF16.self)
            vietnameseCursor=raw.utf16.count;refresh()
            return candidate.text + (!mode.hanNom && !raw.isEmpty ? " ":"")
        }
        if let native {
            if let candidate,candidate.nativeID != nil { return apply(native.choose(candidate)) }
            if let candidate { let text=candidate.text; reset(); return text }
            return apply(native.submit())
        }
        if let candidate,let consumed=candidate.consumedUTF16 {
            guard candidates.contains(candidate),let count=rawBoundary(forUTF16:consumed) else { return "" }
            raw=String(String.UnicodeScalarView(raw.unicodeScalars.dropFirst(count)));rawCursor=nil;candidateLimit=40;refresh()
            return candidate.text
        }
        let text = candidate?.text ?? (mode.language == .japanese ? KanaComposer.compose(raw,finalize:true):composition)
        reset(); return text
    }
    public func accepts(_ text:String) -> Bool {
        guard !text.isEmpty else { return false }
        if mode.language == .vietnamese { return !text.contains(where:{$0.isNewline}) }
        if mode.language.isLatin { return text.allSatisfy{LatinInputRules.word($0) || $0.isNumber} }
        if mode.language == .japanese && (mode.layout == .godan || ["ー","゛","゜","小","*"].contains(text)) { return true }
        if mode.language == .zhuyin { return text.unicodeScalars.allSatisfy { (0x3105...0x312f).contains($0.value) || "ˉˊˇˋ˙".unicodeScalars.contains($0) } }
        if mode.language == .korean { return text.unicodeScalars.allSatisfy { (0x1100...0x11ff).contains($0.value) || (0x3131...0x318e).contains($0.value) || (0xa960...0xa97f).contains($0.value) || (0xd7b0...0xd7ff).contains($0.value) || (0x302e...0x302f).contains($0.value) || $0.value == 0xf1169 || $0.value == 0xf116e } }
        if mode.language == .dayi { return text.allSatisfy { $0.isLetter || $0.isNumber || "`-=[]\\',./;".contains($0) } }
        if mode.language == .pinyin && text==";" { return mode.doublePinyin.usesSemicolon && raw.split(separator:"'").last.map{$0.count%2 == 1} == true }
        if mode.layout == .vni { return text.allSatisfy{$0.isLetter || $0.isNumber} }
        return text.allSatisfy { $0.isLetter || $0=="'" || (mode.language == .jyutping && "123456".contains($0)) }
    }
    @discardableResult public func moveCompositionCursor(_ offset:Int) -> Bool {
        guard !raw.isEmpty else { return false }
        if let native { _=apply(native.moveCursor(offset));return true }
        if mode.language == .vietnamese { vietnameseCursor=max(0,min(raw.utf16.count,vietnameseCursor+offset)) }
        else {
            let before=String(decoding:composition.utf16.prefix(compositionCursorUTF16),as:UTF16.self).count
            let target=String(composition.prefix(max(0,min(composition.count,before+offset)))).utf16.count
            // Moving the original Korean cursor closes the active Jamo combiner.
            if mode.language == .korean { raw=composition }
            guard let boundary=rawBoundary(forUTF16:target) else { return true }
            rawCursor=boundary
        }
        refresh();return true
    }
    private func rawBoundary(forUTF16 count:Int) -> Int? {
        let prefix=String(decoding:composition.utf16.prefix(count),as:UTF16.self)
        let units=Array(raw.unicodeScalars)
        return (0...units.count).last { render(String(String.UnicodeScalarView(units.prefix($0)))) == prefix }
    }
    public func loadMoreCandidates() {
        guard hasMoreCandidates else { return }
        if let native { _=apply(native.loadMore());return }
        candidateLimit+=40;refresh()
    }
    public var autoCorrection:Candidate? {
        guard mode.language.isLatin,!isResumedWord,rawCursor == nil else { return nil }
        return predictor?.autoCorrection(for:composition)
    }
    private func modifyKana(_ action:String) {
        let cursor=rawCursor ?? raw.unicodeScalars.count
        let prefix=String(String.UnicodeScalarView(raw.unicodeScalars.prefix(cursor)))
        let suffix=String(String.UnicodeScalarView(raw.unicodeScalars.dropFirst(cursor)))
        let converted=KanaComposer.modified(KanaComposer.compose(prefix,finalize:true),action:action)
        raw=converted+suffix
        if rawCursor != nil { rawCursor=converted.unicodeScalars.count }
    }

    private func render(_ input:String) -> String {
        switch mode.language {
        case .korean:
            let codes=input.unicodeScalars.map { s in s.value >= 0xf0000 ? Int(s.value & 0xffff) | 0x1000000 : Int(s.value) }
            return HangulComposer.compose(codes,layout:mode.layout,correctOrders:mode.correctHangulOrder)
        case .japanese:return KanaComposer.compose(input)
        case .pinyin:return mode.doublePinyin.expand(input)
        default:return input
        }
    }
    private func refresh() {
        if let cursor=rawCursor {
            composition=render(String(String.UnicodeScalarView(raw.unicodeScalars.prefix(cursor))))+render(String(String.UnicodeScalarView(raw.unicodeScalars.dropFirst(cursor))))
        } else { composition=render(raw) }
        hasMoreCandidates=false
        guard !raw.isEmpty else { candidates=[];isResumedWord=false; return }
        if mode.language == .vietnamese {
            refreshVietnameseCandidates();return
        }
        if mode.language == .jyutping,let lexicon {
            let input=textBeforeCompositionCursor
            if cantoneseCache?.input != input { cantoneseCache=(input,CantoneseEngine(lexicon:lexicon).candidates(input)) }
            let hits=cantoneseCache!.candidates
            hasMoreCandidates=hits.count>candidateLimit
            candidates=[Candidate(composition)]+Array(hits.prefix(candidateLimit));return
        }
        if mode.language == .korean,mode.hanja,["word","phrase"].contains(mode.koreanConverter),let lexicon {
            let input=textBeforeCompositionCursor,phrase=mode.koreanConverter=="phrase"
            if hanjaCache?.input != input || hanjaCache?.phrase != phrase { hanjaCache=(input,phrase,lexicon.hanjaCandidates(input,phrase:phrase)) }
            let hits=hanjaCache!.candidates
            hasMoreCandidates=hits.count>candidateLimit
            candidates=[Candidate(composition)]+Array(hits.prefix(candidateLimit));return
        }
        var hits:[Candidate]=[]
        let dictionaryMode:String
        var reading=textBeforeCompositionCursor
        switch mode.language {
        case .korean:
            dictionaryMode="korean"
            if mode.hanja {
                if mode.koreanConverter=="jeongun" { hits += prefixCandidates(reading,mode:"jeongun") }
                else if mode.koreanConverter != "hangul" {
                    hits += prefixCandidates(reading,mode:"hanja")
                    if mode.koreanConverter=="phrase" { hits=(lexicon?.convertHanjaPhrase(reading) ?? []).map{$0.consuming(reading.utf16.count)}+hits }
                }
            }
        case .japanese:
            dictionaryMode="japanese"; reading=KanaComposer.compose(raw,finalize:true)
        case .pinyin: dictionaryMode=mode.traditional ? "pinyinTraditional":"pinyin"
        case .zhuyin: dictionaryMode="zhuyin"; reading=reading.filter { !"ˉˊˇˋ˙".contains($0) }
        case .cangjie: dictionaryMode="cangjie"
        case .quick: dictionaryMode="quick"
        case .dayi: dictionaryMode="dayi"
        case .jyutping: dictionaryMode=reading.contains(where:{$0.isNumber}) ? "jyutping":"jyutpingPlain"
        default: dictionaryMode=""
        }
        let exact=(lexicon?.lookup(reading,mode:dictionaryMode,prefix:false,limit:candidateLimit+1) ?? []).map{$0.consuming(reading.utf16.count)}
        hits=exact+hits
        if exact.isEmpty && [.japanese,.pinyin,.zhuyin].contains(mode.language), let phrase=lexicon?.convertPhrase(reading,mode:dictionaryMode) {
            hits.insert(Candidate(phrase,reading:reading),at:0)
        }
        if [.cangjie,.quick,.dayi,.jyutping].contains(mode.language) { hits += prefixCandidates(reading,mode:dictionaryMode) }
        hits += (lexicon?.lookup(reading,mode:dictionaryMode,limit:candidateLimit+1) ?? []).map{$0.consuming(reading.utf16.count)}
        if let predictor { hits=predictor.suggest(composition,previous:previousWord,resumed:isResumedWord)+hits }
        if mode.language == .japanese { hits += [Candidate(reading),Candidate(KanaComposer.katakana(reading))] }
        // The literal is always available, including for unknown names and incomplete syllables.
        hits.insert(contentsOf:userCandidates(reading).map{$0.consuming(reading.utf16.count)},at:0)
        hits.insert(Candidate(composition,reading:reading),at:0)
        var seen=Set<String>(); let all=hits.filter{!$0.text.isEmpty && seen.insert($0.text).inserted}
        hasMoreCandidates=all.count>candidateLimit;candidates=Array(all.prefix(candidateLimit))
    }
    private func prefixCandidates(_ reading:String,mode:String) -> [Candidate] {
        guard !reading.isEmpty else { return [] }
        return (1...reading.count).reversed().flatMap { count -> [Candidate] in
            let prefix=String(reading.prefix(count))
            return (lexicon?.lookup(prefix,mode:mode,prefix:false,limit:candidateLimit+1) ?? []).map{$0.consuming(prefix.utf16.count)}
        }
    }
    private func refreshVietnameseCandidates() {
        guard mode.hanNom || mode.layout == .qwerty else { candidates=[];return }
        if vietnameseDictionary == nil {
            let name=mode.hanNom ? (mode.layout == .qwerty ? "nom_qwerty":"nom_quoc_ngu"):"quoc_ngu_qwerty"
            do { vietnameseDictionary=try VietnameseDictionary(name:name) }
            catch { dictionaryError=String(describing:error) }
        }
        candidates=vietnameseDictionary?.candidates(beforeCursor:textBeforeCompositionCursor) ?? []
    }
    public func learn(_ text:String,previous:String,autoCapitalized:Bool=false,count:Int=1) {
        guard mode.language.isLatin,nativeConfiguration?.learning==true else { return }
        prepareNativeIfNeeded();predictor?.learn(text,previous:previous,autoCapitalized:autoCapitalized,count:count)
    }
    public func flushLearning() { predictor?.flush() }
    public func forget(_ candidate:Candidate) {
        predictor?.forget(candidate.text)
        if let native { _=apply(native.forget(candidate)) }
    }
}
