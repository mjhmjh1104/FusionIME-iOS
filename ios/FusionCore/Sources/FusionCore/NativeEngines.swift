import Foundation
import CPinyin
import CChewing
import CLatin
#if canImport(CMozc)
import CMozc
#endif

public struct NativeConfiguration:Equatable {
    public var resources:URL
    public var profile:URL
    public var learning:Bool
    public var userDictionary:[UserEntry]=[]
    public var latinHistoryGenerations:[String:String]=[:]
    public init(resources:URL,profile:URL,learning:Bool=false) {
        self.resources=resources; self.profile=profile; self.learning=learning
    }
    public static var bundled:Self? {
        guard let resources=Bundle.main.url(forResource:"Native",withExtension:nil) else { return nil }
        let profile=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("FusionHistory",isDirectory:true)
        return Self(resources:resources,profile:profile)
    }
}

struct NativeFrame {
    var preedit=""
    var committed=""
    var candidates:[Candidate]=[]
    var cursorUTF16:Int=0
}
enum NativeError:Error { case unavailable(String) }

/// One native session at a time: the Pinyin library has shared language-model globals.
final class NativeSession {
    let mode:InputMode
    let configuration:NativeConfiguration
    let profile:URL
    var handle:UnsafeMutableRawPointer?
    var chewing:OpaquePointer?
    var input=""
    var generation=UUID()
    private(set) var frame=NativeFrame()
    private var inputCursor=0
    private var candidateLimit=80
    private(set) var hasMoreCandidates=false
    var cursorUTF16:Int { frame.cursorUTF16 }
    init(mode:InputMode,configuration:NativeConfiguration) throws {
        self.mode=mode; self.configuration=configuration
        profile=configuration.learning ? configuration.profile:FileManager.default.temporaryDirectory.appendingPathComponent("fusion-private-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:profile,withIntermediateDirectories:true)
        switch mode.language {
        case .pinyin:
            let name=mode.traditional ? "dict_pinyin_hant.dat":"dict_pinyin_hans.dat"
            handle=fp_create(configuration.resources.appendingPathComponent(name).path,profile.appendingPathComponent(name+".user").path)
            guard handle != nil else { throw NativeError.unavailable("Pinyin dictionary: "+name) }
        case .zhuyin:
            // Explicit names also support the original Android dictionary set.
            for name in ["tsi.dat","word.dat"] {
                guard FileManager.default.fileExists(atPath:configuration.resources.appendingPathComponent(name).path) else { throw NativeError.unavailable("Chewing dictionary: "+name) }
            }
            chewing=chewing_new3(configuration.resources.path,configuration.learning ? profile.appendingPathComponent("chewing.dat").path:":memory:","tsi.dat,word.dat",nil,nil)
            guard let chewing else { throw NativeError.unavailable("Chewing dictionary") }
            chewing_set_ChiEngMode(chewing,1)
            chewing_set_maxChiSymbolLen(chewing,32)
            chewing_set_autoLearn(chewing,configuration.learning ? AUTOLEARN_ENABLED:AUTOLEARN_DISABLED)
            chewing_config_set_int(chewing,"chewing.conversion_engine",Int32(mode.zhuyinEngine))
            chewing_set_spaceAsSelection(chewing,1)
            for entry in configuration.userDictionary where entry.language == .zhuyin {
                chewing_userphrase_add(chewing,entry.text,entry.reading)
            }
        case .japanese:
            #if canImport(CMozc)
            try FileManager.default.createDirectory(at:profile.appendingPathComponent("mozc"),withIntermediateDirectories:true)
            handle=fm_create(configuration.resources.appendingPathComponent("mozc.data").path,profile.appendingPathComponent("mozc",isDirectory:true).path)
            guard handle != nil else { throw NativeError.unavailable("Mozc: "+String(cString:fm_error())) }
            // Kana keys already resolve the on-screen flick/toggle; pass literal kana to QWERTY.
            fm_configure(handle,mode.layout == .godan ? "GODAN":"QWERTY_JA",configuration.learning ? 1:0)
            let dictionary=configuration.userDictionary.filter{$0.language == .japanese}.map { "\($0.reading)\t\($0.text)\t名詞" }.joined(separator:"\n")
            if !dictionary.isEmpty { fm_command(handle,7,0,dictionary) }
            #else
            throw NativeError.unavailable("Mozc library")
            #endif
        default: throw NativeError.unavailable("Unsupported session")
        }
    }
    deinit {
        if let chewing { chewing_delete(chewing) }
        if mode.language == .pinyin { fp_destroy(handle) }
        #if canImport(CMozc)
        if mode.language == .japanese { fm_destroy(handle) }
        #endif
        if !configuration.learning { try? FileManager.default.removeItem(at:profile) }
    }
    func reset() {
        input="";inputCursor=0; frame=NativeFrame(); generation=UUID();candidateLimit=80;hasMoreCandidates=false
        if let chewing { chewing_Reset(chewing) }
        if mode.language == .pinyin { fp_reset(handle) }
        #if canImport(CMozc)
        if mode.language == .japanese { fm_command(handle,0,0,nil) }
        #endif
    }
    func append(_ text:String) -> NativeFrame {
        generation=UUID()
        candidateLimit=80
        if mode.language == .pinyin {
            var chars=Array(input);chars.insert(contentsOf:text.lowercased(),at:min(inputCursor,chars.count));input=String(chars);inputCursor+=text.count
            fp_search(handle,mode.doublePinyin.expand(input)); return read()
        }
        var committed=""
        for character in text {
            if let chewing {
                let keys=Array("1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-7634")
                let symbols=Array("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ˙ˊˇˋ")
                if character == "ˉ" { chewing_handle_Space(chewing) }
                else if let index=symbols.firstIndex(of:character) { chewing_handle_Default(chewing,Int32(keys[index].asciiValue!)) }
            }
            #if canImport(CMozc)
            if mode.language == .japanese {
                if ["゛","゜","小","*"].contains(character) {
                    let last=String(decoding:frame.preedit.utf16.prefix(frame.cursorUTF16),as:UTF16.self).last.map(String.init) ?? ""
                    if !last.isEmpty {
                        let kana=KanaComposer.modified(last,action:String(character))
                        fm_special(handle,0); fm_key(handle,kana)
                    }
                } else { fm_key(handle,String(character)) }
            }
            #endif
            committed += read().committed
        }
        frame.committed=committed; return frame
    }
    func backspace() -> NativeFrame {
        generation=UUID()
        if mode.language == .pinyin {
            if fp_fixed_length(handle)>0 { fp_cancel_choice(handle) }
            else if inputCursor>0 { var chars=Array(input);chars.remove(at:inputCursor-1);input=String(chars);inputCursor-=1;fp_search(handle,mode.doublePinyin.expand(input)) }
        }
        if let chewing { chewing_handle_Backspace(chewing) }
        #if canImport(CMozc)
        if mode.language == .japanese { fm_special(handle,0) }
        #endif
        return read()
    }
    func space() -> NativeFrame {
        if mode.language == .pinyin { return choose(frame.candidates.first) }
        generation=UUID()
        if let chewing { chewing_handle_Space(chewing) }
        #if canImport(CMozc)
        if mode.language == .japanese { fm_special(handle,1) }
        #endif
        return read()
    }
    func choose(_ candidate:Candidate?) -> NativeFrame {
        if let candidate, candidate.nativeGeneration != generation { return frameWithoutCommit() }
        generation=UUID()
        if mode.language == .pinyin {
            let index=candidate?.nativeID ?? 0
            fp_choose(handle,Int32(index))
            let full=fp_fully_selected(handle) != 0
            let result=read()
            if full {
                let committed=pinyinCandidate(0)
                if configuration.learning { fp_flush(handle) }
                reset(); frame.committed=committed; return frame
            }
            return result
        }
        if let chewing,let id=candidate?.nativeID {
            chewing_cand_open(chewing); chewing_cand_choose_by_index(chewing,Int32(id))
        }
        #if canImport(CMozc)
        if mode.language == .japanese { fm_command(handle,2,Int32(candidate?.nativeID ?? 0),nil) }
        #endif
        return read()
    }
    func submit() -> NativeFrame {
        generation=UUID()
        if mode.language == .pinyin {
            let text=frame.preedit; reset(); frame.committed=text; return frame
        }
        if let chewing {
            if chewing_bopomofo_Check(chewing) != 0 { chewing_handle_Space(chewing) }
            chewing_cand_close(chewing); chewing_commit_preedit_buf(chewing)
        }
        #if canImport(CMozc)
        if mode.language == .japanese { fm_command(handle,1,0,nil) }
        #endif
        return read()
    }
    func forget(_ candidate:Candidate) -> NativeFrame {
        guard candidate.nativeGeneration==generation,let id=candidate.nativeID else { return frameWithoutCommit() }
        #if canImport(CMozc)
        if mode.language == .japanese { generation=UUID();fm_command(handle,3,Int32(id),nil);return read() }
        #endif
        return frameWithoutCommit()
    }
    private func frameWithoutCommit() -> NativeFrame { var f=frame; f.committed=""; return f }
    func moveCursor(_ offset:Int) -> NativeFrame {
        generation=UUID()
        if mode.language == .pinyin {
            inputCursor=max(0,min(input.count,inputCursor+offset))
            if fp_fixed_length(handle)>0 { fp_reset(handle);fp_search(handle,mode.doublePinyin.expand(input)) }
        }
        if let chewing {
            for _ in 0..<abs(offset) { if offset<0 { chewing_handle_Left(chewing) } else { chewing_handle_Right(chewing) } }
        }
        #if canImport(CMozc)
        if mode.language == .japanese {
            let current=String(decoding:frame.preedit.utf16.prefix(frame.cursorUTF16),as:UTF16.self).unicodeScalars.count
            fm_command(handle,9,Int32(max(0,min(frame.preedit.unicodeScalars.count,current+offset))),nil)
        }
        #endif
        return read()
    }
    func loadMore() -> NativeFrame {
        candidateLimit+=80
        var result=read();result.committed="";frame=result;return result
    }
    func predict(after context:String) -> [Candidate]? {
        guard mode.language == .pinyin else { return nil }
        let suffix=String(context.suffix(7))
        let units=Array(suffix.utf16)+[0]
        let count=fp_predict(handle,units)
        return (0..<count).compactMap { index in
            guard let pointer=fp_prediction(handle,index) else { return nil }
            var length=0;while length<8 && pointer[length] != 0 { length+=1 }
            let text=String(decoding:UnsafeBufferPointer(start:pointer,count:length),as:UTF16.self)
            return text.isEmpty ? nil:Candidate(text)
        }
    }
    private func pinyinCandidate(_ index:Int32) -> String {
        guard let chars=fp_candidate(handle,index) else { return "" }
        var count=0; while count<256 && chars[count] != 0 { count+=1 }
        return String(decoding:UnsafeBufferPointer(start:chars,count:count),as:UTF16.self)
    }
    @discardableResult private func read() -> NativeFrame {
        var result=NativeFrame()
        if mode.language == .pinyin {
            let fixed=Int(fp_fixed_length(handle)), consumed=Int(fp_fixed_pinyin_length(handle))
            result.preedit=String(pinyinCandidate(0).prefix(fixed))+String(mode.doublePinyin.expand(input).dropFirst(consumed))
            result.cursorUTF16=max(0,min(result.preedit.utf16.count,fixed+mode.doublePinyin.expand(String(input.prefix(inputCursor))).utf16.count-consumed))
            hasMoreCandidates=fp_candidate_count(handle)>candidateLimit
            for i in 0..<min(Int32(candidateLimit),fp_candidate_count(handle)) {
                result.candidates.append(Candidate(pinyinCandidate(i),nativeID:Int(i),nativeGeneration:generation))
            }
        }
        if let chewing {
            result.committed=String(cString:chewing_commit_String_static(chewing)); chewing_ack(chewing)
            let buffer=String(cString:chewing_buffer_String_static(chewing))
            let phonetic=String(cString:chewing_bopomofo_String_static(chewing))
            let position=min(buffer.count,max(0,Int(chewing_cursor_Current(chewing))))
            result.preedit=String(buffer.prefix(position))+phonetic+String(buffer.dropFirst(position))
            result.cursorUTF16=(String(buffer.prefix(position))+phonetic).utf16.count
            if phonetic.isEmpty && !buffer.isEmpty { chewing_cand_open(chewing) }
            hasMoreCandidates=chewing_cand_TotalChoice(chewing)>candidateLimit
            for i in 0..<min(Int32(candidateLimit),chewing_cand_TotalChoice(chewing)) {
                result.candidates.append(Candidate(String(cString:chewing_cand_string_by_index_static(chewing,i)),nativeID:Int(i),nativeGeneration:generation))
            }
            // Leave the engine in entering state so the next syllable isn't a selection key.
            chewing_cand_close(chewing)
        }
        #if canImport(CMozc)
        if mode.language == .japanese {
            result.preedit=String(cString:fm_preedit(handle)); result.committed=String(cString:fm_committed(handle))
            result.cursorUTF16=String(String.UnicodeScalarView(result.preedit.unicodeScalars.prefix(max(0,Int(fm_cursor(handle)))))).utf16.count
            hasMoreCandidates=fm_candidate_count(handle)>candidateLimit
            for i in 0..<min(Int32(candidateLimit),fm_candidate_count(handle)) {
                result.candidates.append(Candidate(String(cString:fm_candidate_text(handle,i)),reading:String(cString:fm_candidate_reading(handle,i)),nativeID:Int(fm_candidate_id(handle,i)),nativeGeneration:generation,annotation:String(cString:fm_candidate_annotation(handle,i)),focused:fm_candidate_focused(handle,i) != 0))
            }
        }
        #endif
        frame=result; return result
    }
}

final class NativePredictor {
    private let handle:UnsafeMutableRawPointer
    private var latest:[Candidate]=[]
    private let locale:Locale
    init?(language:InputLanguage,configuration:NativeConfiguration) {
        let names:[InputLanguage:String]=[.korean:"ko",.english:"en",.german:"de",.french:"fr",.spanish:"es",.italian:"it",.portuguese:"pt_br"]
        guard let name=names[language],let pointer=fl_create(configuration.resources.appendingPathComponent("main_\(name).dict").path) else { return nil }
        handle=pointer;locale=Locale(identifier:language.locale)
        if configuration.learning,language.isLatin {
            try? FileManager.default.createDirectory(at:configuration.profile,withIntermediateDirectories:true)
            let version=configuration.latinHistoryGenerations[language.rawValue] ?? "v1"
            fl_set_history(handle,configuration.profile.appendingPathComponent("latin-\(language.rawValue)-\(version)").path,name)
        }
    }
    deinit { fl_destroy(handle) }
    func flush() { fl_flush(handle) }
    private func context(_ text:String)->[Int32] {
        let line=text.split(whereSeparator:{$0.isNewline}).last.map(String.init) ?? ""
        let words=line.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        var result:[Int32]=[]
        // The source's NgramContextUtils and decoder use up to three prior words.
        for index in 0..<3 {
            let position=words.count-index-1
            if position+1<words.count,words[position+1].first.map(LatinInputRules.connector)==true { result += [-2,0];break }
            guard position>=0,let last=words[position].last else { result += [-1,0];break }
            if ".?!".contains(last) { result += [-1,0];break }
            if LatinInputRules.separator(last) || LatinInputRules.connector(last) { result += [-2,0];break }
            result += words[position].unicodeScalars.map{Int32($0.value)}+[0]
        }
        return result
    }
    private func probability(_ word:String)->Int32 {
        let codes=word.unicodeScalars.map{Int32($0.value)};return fl_probability(handle,codes,Int32(codes.count))
    }
    func learn(_ text:String,previous:String,autoCapitalized:Bool=false,count:Int=1) {
        var previous=previous
        for (index,part) in text.split(separator:" ").enumerated() {
            let word=String(part),lower=word.lowercased(with:locale),frequency=probability(word),lowerFrequency=probability(lower)
            let normalized=(autoCapitalized && index==0 && !(frequency>=0 && lowerFrequency<0)) || (frequency<lowerFrequency && lowerFrequency>=140) ? lower:word
            let codes=normalized.unicodeScalars.map{Int32($0.value)},context=context(previous)
            fl_learn(handle,codes,Int32(codes.count),context,Int32(context.count),frequency>0 ? 1:0,Int32(clamping:count))
            previous += " "+word
        }
    }
    func forget(_ text:String) { let codes=text.unicodeScalars.map{Int32($0.value)};fl_forget(handle,codes,Int32(codes.count)) }

    func suggest(_ word:String,previous:String,resumed:Bool=false) -> [Candidate] {
        let quotes=word.reversed().prefix{$0 == "'"}.count
        let codes=word.dropLast(quotes).lowercased().unicodeScalars.map{Int32($0.value)}, context=context(previous)
        let count=fl_suggest(handle,codes,Int32(codes.count),context,Int32(context.count))
        latest=(0..<count).compactMap { index in
            guard let buffer=fl_candidate(handle,index) else { return nil }
            var text=""; for i in 0..<48 { if buffer[i]==0 { break }; if let scalar=UnicodeScalar(UInt32(bitPattern:buffer[i])) { text.unicodeScalars.append(scalar) } }
            let letters=word.filter{$0.isLetter},quotes=word.reversed().prefix{$0 == "'"}.count
            // Suggest.getTransformedSuggestedWordInfoList excludes resumed words
            // from all-caps conversion, while retaining initial-capital handling.
            if !resumed && letters.count>1 && letters.allSatisfy({$0.isUppercase}) { text=text.uppercased(with:locale) }
            else if word.first?.isUppercase==true,word.dropFirst().allSatisfy({!$0.isUppercase}) { text=text.prefix(1).uppercased(with:locale)+text.dropFirst() }
            text += String(repeating:"'",count:max(0,quotes-(text.contains("'") ? 1:0)))
            return Candidate(text,score:Double(fl_score(handle,index)))
        }
        return latest
    }
    func autoCorrection(for word:String)->Candidate? {
        guard !word.isEmpty,!word.contains(where:{$0.isNumber}),word.filter({$0.isUppercase}).count<=1 else { return nil }
        let quotes=word.reversed().prefix{$0 == "'"}.count
        let codes=word.dropLast(quotes).unicodeScalars.map{Int32($0.value)}
        let index=Int(fl_autocorrection(handle,codes,Int32(codes.count),0.185))
        guard latest.indices.contains(index) else { return nil }
        let candidate=latest[index]
        guard fl_whitelisted(handle,Int32(index)) != 0 || (word.count>1 && !latest.contains(where:{$0.text==word})) else { return nil }
        guard candidate.text != word else { return nil }
        if locale.languageCode=="de",candidate.text.utf16.count>12,candidate.text.contains(" ") { return nil }
        return candidate
    }
}
