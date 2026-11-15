import SwiftUI
import UniformTypeIdentifiers
import FusionCore

struct SettingsDocument:FileDocument {
    static var readableContentTypes:[UTType] { [.json,.plainText] }
    var data:Data
    init(data:Data) { self.data=data }
    init(configuration:ReadConfiguration) throws { data=configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}

struct UserDictionaryView:View {
    @ObservedObject var store:SettingsStore
    @State private var language:InputLanguage = .japanese
    @State private var reading=""
    @State private var word=""
    @State private var importing=false
    @State private var exporting=false
    @State private var message:String?
    var body:some View {
        Form {
            Section("단어 추가") {
                Picker("언어",selection:$language) { ForEach(InputLanguage.allCases){Text($0.localizedName).tag($0)} }
                TextField(L10n.text(language == .japanese ? "읽기 (히라가나)":"읽기"),text:$reading).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("변환할 단어",text:$word)
                Button("추가") {
                    let entry=UserEntry(language:language,reading:reading.trimmingCharacters(in:.whitespacesAndNewlines),text:word.trimmingCharacters(in:.whitespacesAndNewlines))
                    if !store.settings.userDictionary.contains(where:{$0.language==entry.language && $0.reading==entry.reading && $0.text==entry.text}) { store.settings.userDictionary.append(entry) }
                    reading="";word=""
                }.disabled(reading.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || word.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || reading.count>127 || word.count>127)
            }
            Section("저장된 단어") {
                ForEach(store.settings.userDictionary) { entry in
                    VStack(alignment:.leading) { Text(entry.text);Text("\(entry.language.localizedName) · \(entry.reading)").font(.caption).foregroundStyle(.secondary) }
                }.onDelete { store.settings.userDictionary.remove(atOffsets:$0) }
            }
            Section {
                Button("TSV 사전 가져오기") { importing=true }
                Button("TSV 사전 내보내기") { exporting=true }
                if let message { Text(message).font(.footnote) }
            } footer: {
                Text("언어가 없는 항목은 위에서 선택한 언어로 가져옵니다.")
            }
        }.navigationTitle("사용자 사전")
            .fileImporter(isPresented:$importing,allowedContentTypes:[.plainText,.tabSeparatedText,.data]) { result in
                do {
                    let url=try result.get();let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
                    let data=try Data(contentsOf:url)
                    let entries=try UserDictionaryFile.read(data,defaultLanguage:language)
                    var existing=Set(store.settings.userDictionary.map{"\($0.language.rawValue)\t\($0.reading)\t\($0.text)"})
                    store.settings.userDictionary += entries.filter{existing.insert("\($0.language.rawValue)\t\($0.reading)\t\($0.text)").inserted}
                    store.settings.validate();message=L10n.format("%d개 항목을 읽었습니다.",entries.count)
                } catch { message=L10n.format("가져오기 실패: %@",error.localizedDescription) }
            }
            .fileExporter(isPresented:$exporting,document:SettingsDocument(data:UserDictionaryFile.write(store.settings.userDictionary)),contentType:.plainText,defaultFilename:"FusionIME-dictionary.tsv") { result in
                if case .failure(let error)=result { message=error.localizedDescription }
            }
    }
}

struct BackupSettingsView:View {
    @ObservedObject var store:SettingsStore
    @State private var importing=false
    @State private var exporting=false
    @State private var message:String?
    var body:some View {
        Form {
            Section {
                Button("백업 내보내기") { exporting=true }
                Button("백업 가져오기") { importing=true }
            } footer: {
                Text("설정과 사용자 사전을 저장합니다. 학습 기록은 포함하지 않습니다.")
            }
            Section {
                DisclosureGroup("지원 파일 형식") {
                    Text("FusionIME 백업(JSON), Android 설정(XML·JSON)").font(.footnote)
                }
            }
            if let message { Text(message) }
        }.navigationTitle("백업과 복원")
            .fileImporter(isPresented:$importing,allowedContentTypes:[.json,.xml,.plainText]) { result in
                do {
                    let url=try result.get();let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
                    let data=try Data(contentsOf:url)
                    guard data.count<8_000_000 else { throw CocoaError(.fileReadTooLarge) }
                    var settings=try SettingsImport.read(data)
                    settings.historyGeneration=store.settings.historyGeneration
                    store.settings=settings;message=L10n.text("설정과 사전을 복원했습니다.")
                } catch { message=L10n.format("복원 실패: %@",error.localizedDescription) }
            }
            .fileExporter(isPresented:$exporting,document:SettingsDocument(data:(try? JSONEncoder().encode(store.settings)) ?? Data()),contentType:.json,defaultFilename:"FusionIME-settings.json") { result in
                if case .failure(let error)=result { message=error.localizedDescription }
            }
    }
}
