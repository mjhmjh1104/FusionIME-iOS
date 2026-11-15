import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum SettingsImport {
    /// iOS JSON, Android SharedPreferences XML, or the Android input_modes JSON array.
    public static func read(_ data:Data) throws -> KeyboardSettings {
        guard data.count<8_000_000 else { throw CocoaError(.fileReadTooLarge) }
        var values:[String:String]=[:]
        if String(data:data.prefix(100),encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("<")==true {
            let delegate=PreferencesXML();let parser=XMLParser(data:data)
            parser.shouldResolveExternalEntities=false;parser.delegate=delegate
            guard parser.parse() else { throw CocoaError(.fileReadCorruptFile) }
            values=delegate.values
        } else {
            let object=try JSONSerialization.jsonObject(with:data)
            if let modes=object as? [String] { values["input_modes"]=String(data:try JSONSerialization.data(withJSONObject:modes),encoding:.utf8) }
            else if let dictionary=object as? [String:Any],dictionary["input_modes"] != nil {
                for (key,value) in dictionary { values[key]=value as? String ?? String(describing:value) }
            } else { return try KeyboardSettings.decodeCompatible(data) }
        }
        guard let modesString=values["input_modes"],let json=modesString.data(using:.utf8),let modes=try JSONSerialization.jsonObject(with:json) as? [String] else { throw CocoaError(.fileReadCorruptFile) }
        var settings=KeyboardSettings();settings.modes=[]
        for text in modes {
            var map:[String:String]=[:]
            for item in text.split(separator:";") {
                let pair=item.split(separator:"=",maxSplits:1,omittingEmptySubsequences:false)
                if pair.count==2 { map[String(pair[0])]=String(pair[1]) }
            }
            guard var mode=mode(map) else { continue }
            mode.numberRow=map["number_row"].flatMap(Bool.init);mode.cursorKeys=map["cursor_keys"].flatMap(Bool.init)
            mode.autoCapitalization=map["auto_caps"].flatMap(Bool.init);mode.doubleSpacePeriod=map["auto_period"].flatMap(Bool.init)
            mode.candidateRows=map["candidate_view_height"].flatMap(Double.init).map(Int.init)
            mode.flickHints=map["flick_hint"].flatMap(Bool.init)
            settings.modes.append(mode)
        }
        guard !settings.modes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        settings.splitPortrait=values["split_keyboard_portrait"]=="true"
        settings.splitLandscape=values["split_keyboard_landscape"]=="true"
        settings.splitGap=(values["split_ratio_portrait"].flatMap(Double.init) ?? 20)/100
        settings.splitGapLandscape=(values["split_ratio_landscape"].flatMap(Double.init) ?? 20)/100
        // Android stores the height of one key row; iOS stores the complete view.
        if let row=values["keyboard_height_portrait"].flatMap(Double.init) { settings.height=row*4+70 }
        if let row=values["keyboard_height_landscape"].flatMap(Double.init) { settings.landscapeHeight=row*4+56 }
        settings.sound=values["sound_feedback"]=="true"
        settings.haptics=values["haptic_feedback"].flatMap(Bool.init) ?? true
        settings.vibrationDuration=values["vibration_duration"].flatMap(Double.init) ?? 10
        settings.keyPreview=values["preview_popup"].flatMap(Bool.init) ?? true
        settings.screenMode=["mobile":.mobile,"tablet":.tablet][values["screen_mode"]?.lowercased() ?? ""] ?? .automatic
        settings.symbolLayout=values["symbol_layout"].flatMap(SymbolLayout.init(rawValue:)) ?? .g
        settings.touchMode=values["touch_mode"].map{$0.lowercased()}.flatMap(KeyboardTouchMode.init(rawValue:)) ?? .seek
        settings.touchCorrection=values["touch_correction"].flatMap(Bool.init) ?? true
        settings.showVoiceInputButton=values["show_voice_input_button"].flatMap(Bool.init) ?? false
        settings.clipboardCandidates=values["clipboard_candidate_enabled"].flatMap(Bool.init) ?? true
        // Android stores display pixels; retain the number in the adjustable iOS pt preference.
        if let distance=values["flick_sensitivity"].flatMap(Double.init) { settings.flickSensitivity=distance }
        let actions:[String:FlickAction]=["None":.none,"Default":.standard,"Shifted":.shift,"Symbol":.symbol,"ShiftedSymbol":.shiftedSymbol]
        settings.flickUp=actions[values["default_flick_action_up"] ?? "Shifted"] ?? .shift
        settings.flickDown=actions[values["default_flick_action_down"] ?? "Symbol"] ?? .symbol
        settings.validate();return settings
    }
    private static func mode(_ m:[String:String]) -> InputMode? {
        let languages:[String:InputLanguage]=["korean":.korean,"mozc":.japanese,"pinyin":.pinyin,"zhuyin":.zhuyin,"cangjie":.cangjie,"jyutping":.jyutping,"viet":.vietnamese,"emoji":.emoji]
        let locales:[String:InputLanguage]=["en":.english,"de":.german,"es":.spanish,"fr":.french,"it":.italian,"pt":.portuguese]
        let language=m["type"]=="latin" ? locales[String((m["locale"] ?? "en").prefix(2))]:languages[m["type"] ?? ""]
        guard let language else { return nil }
        var mode=InputMode(language:language)
        let layout=m["layout"] ?? ""
        let layouts:[String:KeyboardLayout]=["Set2KS":.hangul2,"Set3390":.hangul390,"Set3391":.hangul391,"Set3391Strict":.hangul391Strict,"Set2Old":.hangulOld2,"Set3Old393":.hangul393,"Qwerty":.qwerty,"Deutsch":.qwertz,"Qwertz":.qwertz,"Azerty":.azerty,"Dvorak":.dvorak,"Colemak":.colemak,"RomajiQwerty":.romaji,"Kana12Key":.kana12,"Godan":.godan,"KanaJIS":.kanaJIS,"KanaSyllables":.kanaSyllables,"KanaIroha":.kanaIroha]
        mode.layout=layouts[layout] ?? mode.layout
        mode.correctHangulOrder=m["correct_orders"]=="true"
        mode.koreanConverter=["Word":"word","Phrase":"phrase","JeongUn":"jeongun","HangulOnly":"hangul"][m["converter"] ?? "Word"] ?? "word"
        mode.traditional=m["chinese_traditional"]=="true"
        mode.fullWidth=m["full_width"]=="true"
        mode.doublePinyin=DoublePinyin.allCases.first{$0.rawValue.lowercased()==m["pinyin_spelling"]?.lowercased()} ?? .full
        if layout=="Quick" { mode.language = .quick;mode.layout = .cangjie }
        if layout=="Dayi" || layout=="Dayi3" { mode.language = .dayi;mode.layout = .dayi }
        if layout=="Deutsch" { mode.layout = .deutsch }
        if language == .vietnamese {
            mode.layout=layout.hasPrefix("VNI") ? .vni:layout.hasPrefix("Telex") ? .telex:.qwerty
            mode.hanNom=layout.isEmpty || layout.hasSuffix("Nom")
        }
        mode.kanaTapCycle=m["flick_mode"] != "FlickOnly"
        mode.kanaFlick=m["flick_mode"] != "ToggleOnly"
        mode.syllablesDirection=["Horizontal":"horizontal","VerticalLeft":"left","VerticalRight":"right"][m["syllables_key_layout"] ?? "Horizontal"] ?? "horizontal"
        mode.zhuyinEngine=["SIMPLE_CONVERSION_ENGINE":0,"CHEWING_CONVERSION_ENGINE":1,"FUZZY_CHEWING_CONVERSION_ENGINE":2][m["conversion_engine"] ?? "FUZZY_CHEWING_CONVERSION_ENGINE"] ?? 2
        return mode
    }
}
private final class PreferencesXML:NSObject,XMLParserDelegate {
    var values:[String:String]=[:]
    private var key:String?
    private var text=""
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName qName:String?,attributes:[String:String]) {
        key=attributes["name"];text=""
        if let key,let value=attributes["value"] { values[key]=value }
    }
    func parser(_ parser:XMLParser,foundCharacters string:String) { text+=string }
    func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName qName:String?) {
        if elementName=="string",let key { values[key]=text };key=nil
    }
}
