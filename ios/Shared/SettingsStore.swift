import Foundation
import SwiftUI
import FusionCore

@MainActor final class SettingsStore: ObservableObject {
    @Published var settings:KeyboardSettings { didSet { save() } }
    @Published private(set) var sharedAvailable=false
    private var defaults:UserDefaults
    private var sharedReader:UserDefaults?
    private var sharedBaseline:Data?
    private var loading=false
    private let customDefaults:UserDefaults?
    // Keyboard session state stays local even when shared settings are enabled.
    // Changing languages must not republish/reload the whole settings document.
    private let selectionDefaults:UserDefaults
    private static let key="fusion.settings.v1"
    private static let baselineKey="fusion.settings.sharedBaseline.v1"
    private static let selectedModeKey="fusion.keyboard.selectedModeID.v1"
    static var group:String { Bundle.main.object(forInfoDictionaryKey:"FusionAppGroup") as? String ?? "group.ee.oyatl.ime.fusion.ios" }
    init(allowShared:Bool = true,storage:UserDefaults? = nil) {
        customDefaults=storage
        selectionDefaults=storage ?? .standard
        let readable=storage == nil && FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:Self.group) != nil
        sharedReader=readable ? UserDefaults(suiteName:Self.group):nil
        sharedBaseline=sharedReader?.data(forKey:Self.key)
        let shared = readable && allowShared
        defaults = storage ?? (shared ? UserDefaults(suiteName:Self.group) ?? .standard:.standard)
        sharedAvailable=shared
        let data=Self.settingsData(local:selectionDefaults,shared:sharedReader)
        if let data, var value=try? KeyboardSettings.decodeCompatible(data) {
            value.validate(); settings=value
        } else { settings=KeyboardSettings(); save() }
    }
    func reload(allowShared:Bool) {
        let wasShared=sharedAvailable
        let readable=customDefaults == nil && FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:Self.group) != nil
        sharedReader=readable ? UserDefaults(suiteName:Self.group):nil
        sharedBaseline=sharedReader?.data(forKey:Self.key)
        let shared=readable && allowShared
        defaults=customDefaults ?? (shared ? UserDefaults(suiteName:Self.group) ?? .standard:.standard)
        sharedAvailable=shared
        loading=true;defer { loading=false }
        if let data=Self.settingsData(local:selectionDefaults,shared:sharedReader), var value=try? KeyboardSettings.decodeCompatible(data) {
            value.validate(); if settings != value { settings=value }
            if shared { defaults.set(data,forKey:Self.key);selectionDefaults.removeObject(forKey:Self.baselineKey) }
        } else if shared != wasShared {
            settings=KeyboardSettings()
        }
    }
    private func save() {
        guard !loading else { return }
        var safe=settings; safe.validate()
        if let data=try? JSONEncoder().encode(safe) {
            defaults.set(data,forKey:Self.key)
            if sharedReader != nil && !sharedAvailable { selectionDefaults.set(sharedBaseline ?? Data(),forKey:Self.baselineKey) }
        }
    }
    static func settingsData(local:UserDefaults,shared:UserDefaults?)->Data? {
        guard let shared else { return local.data(forKey:key) }
        let current=shared.data(forKey:key)
        if local.data(forKey:baselineKey) == (current ?? Data()),let draft=local.data(forKey:key) { return draft }
        return current ?? local.data(forKey:key)
    }
    var selectedModeIndex:Int {
        let id=selectionDefaults.string(forKey:Self.selectedModeKey).flatMap { UUID(uuidString:$0) }
        return settings.modes.firstIndex { $0.id == id } ?? 0
    }
    func rememberSelectedMode(_ mode:InputMode) {
        selectionDefaults.set(mode.id.uuidString,forKey:Self.selectedModeKey)
    }
    func learned(language:InputLanguage,prefix:String,previous:String = "") -> [String] {
        let words=defaults.dictionary(forKey:"fusion.words.\(language.rawValue)") as? [String:Int] ?? [:]
        let contexts=defaults.dictionary(forKey:"fusion.context.\(language.rawValue)") as? [String:[String:Int]] ?? [:]
        let next=contexts[previous.lowercased()] ?? [:]
        let pool=prefix.isEmpty ? next:words
        return pool.filter{$0.key.lowercased().hasPrefix(prefix.lowercased())}.sorted { a,b in
            let x=a.value+(next[a.key] ?? 0)*100,y=b.value+(next[b.key] ?? 0)*100
            return x == y ? a.key<b.key:x>y
        }.prefix(8).map(\.key)
    }
    func learn(_ word:String,language:InputLanguage,previous:String = "") {
        guard settings.learnWords, language.isLatin, word.count>1, word.count<48 else { return }
        let key="fusion.words.\(language.rawValue)"
        var words=defaults.dictionary(forKey:key) as? [String:Int] ?? [:]
        words[word]=min(1000,(words[word] ?? 0)+1)
        if words.count>1000 { words=Dictionary(uniqueKeysWithValues:words.sorted{$0.value>$1.value}.prefix(1000).map{($0.key,$0.value)}) }
        defaults.set(words,forKey:key)
        if !previous.isEmpty,previous.count<48 {
            let key="fusion.context.\(language.rawValue)"
            var contexts=defaults.dictionary(forKey:key) as? [String:[String:Int]] ?? [:]
            var next=contexts[previous.lowercased()] ?? [:]
            next[word]=min(1000,(next[word] ?? 0)+1)
            if next.count>32 { next=Dictionary(uniqueKeysWithValues:next.sorted{$0.value>$1.value}.prefix(32).map{($0.key,$0.value)}) }
            contexts[previous.lowercased()]=next
            if contexts.count>1000 { contexts=Dictionary(uniqueKeysWithValues:contexts.sorted{$0.value.values.reduce(0,+)>$1.value.values.reduce(0,+)}.prefix(1000).map{($0.key,$0.value)}) }
            defaults.set(contexts,forKey:key)
        }
    }
    func migrateLatinHistory(to engine:CompositionEngine) {
        let language=engine.mode.language
        guard language.isLatin,let config=engine.nativeConfiguration,config.learning else { return }
        let key="fusion.nativeHistoryMigrated.\(language.rawValue).\(settings.historyGeneration).\(settings.latinHistoryGenerations[language.rawValue] ?? "v1")"
        guard !defaults.bool(forKey:key) else { return }
        let words=defaults.dictionary(forKey:"fusion.words.\(language.rawValue)") as? [String:Int] ?? [:]
        let contexts=defaults.dictionary(forKey:"fusion.context.\(language.rawValue)") as? [String:[String:Int]] ?? [:]
        for (word,count) in words { engine.learn(word,previous:"",count:count) }
        for (previous,next) in contexts { for (word,count) in next { engine.learn(word,previous:previous,count:count) } }
        engine.flushLearning();defaults.set(true,forKey:key)
    }
    func clearHistory() {
        for language in InputLanguage.allCases { clearHistory(language:language) }
        if let profile=nativeConfiguration?.profile { try? FileManager.default.removeItem(at:profile) }
        settings.historyGeneration=UUID().uuidString
    }
    func clearHistory(language:InputLanguage) {
        if language.isLatin {
            let version=settings.latinHistoryGenerations[language.rawValue] ?? "v1"
            if let profile=nativeConfiguration?.profile { try? FileManager.default.removeItem(at:profile.appendingPathComponent("latin-\(language.rawValue)-\(version)")) }
            settings.latinHistoryGenerations[language.rawValue]=UUID().uuidString
        }
        defaults.removeObject(forKey:"fusion.words.\(language.rawValue)")
        defaults.removeObject(forKey:"fusion.context.\(language.rawValue)")
    }
    func forget(_ word:String,language:InputLanguage) {
        let key="fusion.words.\(language.rawValue)"
        var words=defaults.dictionary(forKey:key) as? [String:Int] ?? [:]
        words.removeValue(forKey:word);defaults.set(words,forKey:key)
        let contextKey="fusion.context.\(language.rawValue)"
        var contexts=defaults.dictionary(forKey:contextKey) as? [String:[String:Int]] ?? [:]
        for previous in Array(contexts.keys) { contexts[previous]?.removeValue(forKey:word) }
        defaults.set(contexts,forKey:contextKey)
    }
    var nativeConfiguration:NativeConfiguration? {
        guard var config=NativeConfiguration.bundled else { return nil }
        if sharedAvailable,let container=FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:Self.group) {
            config.profile=container.appendingPathComponent("FusionHistory",isDirectory:true)
        }
        config.learning=settings.learnWords
        config.profile.appendPathComponent(settings.historyGeneration,isDirectory:true)
        config.userDictionary=settings.userDictionary
        config.latinHistoryGenerations=settings.latinHistoryGenerations
        return config
    }
    var colorScheme:ColorScheme? { settings.theme == .system ? nil:settings.theme == .dark ? .dark:.light }
}
