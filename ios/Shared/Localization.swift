import Foundation
import FusionCore

/// Use the host bundle's iOS language selection, independently of input modes.
enum L10n {
    static func text(_ key:String,bundle:Bundle = .main)->String {
        bundle.localizedString(forKey:key,value:nil,table:"Localizable")
    }
    static func format(_ key:String,_ arguments:CVarArg...)->String {
        String(format:text(key),locale:Locale.current,arguments:arguments)
    }
}
extension InputLanguage {
    var localizedName:String { L10n.text(name) }
}
extension KeyboardLayout {
    var localizedName:String { L10n.text(name) }
}
extension DoublePinyin {
    var localizedName:String { L10n.text(name) }
}
extension FlickAction {
    var localizedName:String { L10n.text(name) }
}
extension InputMode {
    var localizedTitle:String { language.localizedName }
    var localizedDisplayName:String { localizedTitle+" "+layout.localizedName }
}
