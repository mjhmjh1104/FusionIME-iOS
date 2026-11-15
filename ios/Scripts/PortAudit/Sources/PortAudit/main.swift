import Foundation
import FusionCore

// Read-only observations for the port audit, not assertions that codify gaps.
let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let lexicon=try Lexicon(url:root.appendingPathComponent("Resources/lexicon.sqlite"))
var result:[String:Any]=[:]
var layouts:[[String:Any]]=[]
for language in InputLanguage.allCases {
    for layout in language.layouts {
        for shifted in [false,true] {
            let mode=InputMode(language:language,layout:layout)
            let rows=LayoutCatalog.rows(for:mode,shifted:shifted,numberRow:true)
            layouts.append(["language":language.rawValue,"layout":layout.rawValue,"shifted":shifted,
                "rows":rows.map { $0.map { ["label":$0.label,"values":$0.values,"id":$0.id] as [String:Any] } }])
        }
    }
}
result["layouts"]=layouts
result["kanaDirections"]=[KeyboardLayout.kanaSyllables,.kanaIroha].flatMap { layout in
    ["horizontal","left","right"].map { direction -> [String:Any] in
        var mode=InputMode(language:.japanese,layout:layout);mode.syllablesDirection=direction
        return ["layout":layout.rawValue,"direction":direction,"rows":LayoutCatalog.rows(for:mode).map{$0.map(\.label).joined()}]
    }
}
var imports:[[String:Any]]=[]
for source in ["type=cangjie;layout=Dayi3", "type=latin;locale=de;layout=Deutsch", "type=latin;locale=de;layout=Qwertz", "type=emoji", "type=mozc;layout=KanaSyllables;syllables_key_layout=VerticalRight;flick_hint=false;candidate_view_height=2", "type=viet;layout=VNINom"] {
    do {
        let settings=try SettingsImport.read(JSONSerialization.data(withJSONObject:[source]))
        let data=try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings))
        imports.append(["source":source,"settings":data])
    } catch { imports.append(["source":source,"error":String(describing:error)]) }
}
result["imports"]=imports
let nativeResources=root.appendingPathComponent("Resources/Native",isDirectory:true)
let profile=FileManager.default.temporaryDirectory.appendingPathComponent("fusion-port-audit-"+UUID().uuidString)
defer { try? FileManager.default.removeItem(at:profile) }
var probes:[[String:Any]]=[]
func probe(_ name:String,mode:InputMode,input:String,native:Bool=false,choose:String?=nil) {
    let config=native ? NativeConfiguration(resources:nativeResources,profile:profile,learning:false):nil
    let engine=CompositionEngine(mode:mode,lexicon:lexicon,nativeConfiguration:config)
    for char in input { engine.append(String(char)) }
    var item:[String:Any]=["name":name,"input":input,"composition":engine.composition,
        "candidates":engine.candidates.prefix(12).map { ["text":$0.text,"reading":$0.reading] },
        "nativeLoaded":engine.usesNativeSession,"error":engine.dictionaryError ?? ""]
    if let choose, let candidate=engine.candidates.first(where:{$0.text==choose}) {
        item["selected"]=choose;item["committed"]=engine.commit(candidate:candidate);item["remaining"]=engine.composition
    }
    probes.append(item)
}
probe("korean-prefix-selection",mode:.init(language:.korean),input:"ㅎㅏㄴㄱㅜㄱㅇㅓ",choose:"韓國")
for layout in [KeyboardLayout.qwerty,.telex,.vni] {
    for nom in [false,true] {
        var mode=InputMode(language:.vietnamese,layout:layout);mode.hanNom=nom
        let input=layout == .qwerty ? "tieng viet":layout == .telex ? "tieengs vieetj":"tie6ng1 vie6t5"
        probe("vietnamese-\(layout.rawValue)-\(nom ? "nom":"quoc-ngu")",mode:mode,input:input,choose:nom ? "㗂":"tiếng")
    }
}
probe("jyutping-full",mode:.init(language:.jyutping),input:"nei5hou2")
probe("jyutping-initials",mode:.init(language:.jyutping),input:"nh")
probe("dayi-quote",mode:.init(language:.dayi),input:"'")
probe("japanese-literal",mode:.init(language:.japanese,layout:.kanaSyllables),input:"にほん",native:true)
var acceptance:[String:Bool]=[:]
let dayiEngine=CompositionEngine(mode:.init(language:.dayi),lexicon:lexicon,nativeConfiguration:nil)
for key in ["`","-","[","]","\\","'",";",",",".","/"] { acceptance[key]=dayiEngine.accepts(key) }
result["dayiAcceptance"]=acceptance
let prefixEngine=CompositionEngine(mode:.init(language:.korean),lexicon:lexicon,nativeConfiguration:nil)
prefixEngine.append("ㅎㅏㄴㄱㅜㄱㅇㅓ")
while !prefixEngine.candidates.contains(where:{$0.text=="韓國" && $0.consumedUTF16==2}),prefixEngine.hasMoreCandidates { prefixEngine.loadMoreCandidates() }
if let prefix=prefixEngine.candidates.first(where:{$0.text=="韓國" && $0.consumedUTF16==2}) {
    result["koreanPrefixCommit"]=["candidatePresent":prefixEngine.candidates.contains(where:{$0.text==prefix.text}),
        "committed":prefixEngine.commit(candidate:prefix),"remaining":prefixEngine.composition]
}
result["doublePinyinSemicolon"]=DoublePinyin.allCases.filter{$0 != .full}.map { scheme -> [String:Any] in
    var mode=InputMode(language:.pinyin);mode.doublePinyin=scheme
    return ["scheme":scheme.rawValue,"decodedJsemicolon":scheme.expand("j;"),
        "reachableInTextRows":LayoutCatalog.rows(for:mode).flatMap{$0}.contains{$0.values.contains(";")},
        "acceptsSemicolonAtStart":CompositionEngine(mode:mode,lexicon:lexicon,nativeConfiguration:nil).accepts(";")]
}
if CommandLine.arguments.count>2 {
    let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
    result["doublePinyinExamples"]=(input["doublePinyin"] as! [[String:String]]).map { entry -> [String:String] in
        var item=entry
        let scheme=DoublePinyin.allCases.first{$0.rawValue.lowercased()==entry["scheme"]!.lowercased()}!
        item["actual"]=scheme.expand(entry["keys"]!);return item
    }
    result["vietnameseExamples"]=(input["vietnamese"] as! [[String:String]]).map { entry -> [String:String] in
        var item=entry
        item["actual"]=entry["mode"]=="telex" ? TelexComposer.compose(entry["keys"]!):VNIComposer.compose(entry["keys"]!)
        return item
    }
    let dictionaries=try Dictionary(uniqueKeysWithValues:["nom_qwerty","nom_quoc_ngu","quoc_ngu_qwerty"].map { ($0,try VietnameseDictionary(name:$0)) })
    let dictionaryVectors=input["vietnameseDictionaries"] as! [[String:Any]]
    var mismatches:[[String:Any]]=[]
    for vector in dictionaryVectors {
        let actual=dictionaries[vector["dictionary"] as! String]!.candidates(beforeCursor:vector["input"] as! String).map { candidate -> [String:Any] in
            ["text":candidate.text,"reading":candidate.reading,"score":candidate.score,"consumedUTF16":candidate.consumedUTF16!]
        }
        if !(actual as NSArray).isEqual(to:vector["expected"] as! [Any]) {
            var mismatch=vector;mismatch["actual"]=actual;mismatches.append(mismatch)
        }
    }
    result["vietnameseDictionaries"]=["checked":dictionaryVectors.count,"mismatches":mismatches]
}
result["probes"]=probes
let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
