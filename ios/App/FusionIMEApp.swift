import SwiftUI
import UIKit
import FusionCore

@main @MainActor struct FusionIMEApp:App {
    @StateObject private var store=SettingsStore()
    @Environment(\.scenePhase) private var scenePhase
    var body:some Scene {
        WindowGroup {
            HomeView(store:store).preferredColorScheme(store.colorScheme)
                .onChange(of:scenePhase) { phase in if phase == .active { store.reload(allowShared:true) } }
        }
    }
}
struct HomeView:View {
    @ObservedObject var store:SettingsStore
    var body:some View {
        NavigationStack {
            List {
                NavigationLink { InputMethodSettingsView() } label: { Label("입력 방식",systemImage:"checklist") }
                NavigationLink { AppearanceSettingsView(store:store) } label: { Label("외관",systemImage:"paintbrush") }
                NavigationLink { BehaviorSettingsView(store:store) } label: { Label("행동",systemImage:"hand.tap") }
                NavigationLink { LanguageSettingsView(store:store) } label: { Label("입력 모드",systemImage:"keyboard") }
                NavigationLink { AboutView(store:store) } label: { Label("정보",systemImage:"info.circle") }
            }.navigationTitle("FusionIME").navigationBarTitleDisplayMode(.inline)
        }.tint(.blue)
    }
}
struct InputMethodSettingsView:View {
    var body:some View {
        Form {
            Section {
                Button("iPhone 설정 열기") {
                    if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } header: { Text("키보드 추가") } footer: {
                Text("설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가 → FusionIME")
            }
            Section {
                NavigationLink("입력 연습") { PracticeView() }
            } footer: {
                Text("입력창에서 지구본을 길게 눌러 FusionIME를 선택하세요.")
            }
        }.navigationTitle("입력 방식").navigationBarTitleDisplayMode(.inline)
    }
}
struct PracticeView:View {
    @State private var text=""
    @FocusState private var focused:Bool
    var body:some View {
        TextEditor(text:$text).focused($focused)
            .font(.title3).accessibilityLabel("FusionIME 입력 연습")
            .padding().navigationTitle("입력 연습").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.navigationBarTrailing) { Button("키보드 닫기") { focused=false } } }
            .onAppear { focused=true }
    }
}
struct AboutView:View {
    @ObservedObject var store:SettingsStore
    var body:some View {
        List {
            Section("앱 정보") {
                LabeledContent("FusionIME",value:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "")
                Link("소스 코드",destination:URL(string:"https://github.com/Lee0701/FusionIME")!)
                Link("원본 개발자 연락처",destination:URL(string:"mailto:hgl1002@naver.com")!)
            }
            Section {
                NavigationLink("백업과 복원") { BackupSettingsView(store:store) }
            }
            Section("오픈소스 라이선스") {
                ForEach([("FusionIME","FusionIME-GPL-3.0"),("Mozc","Mozc"),("Mozc 사전","Mozc-dictionary"),("Chewing","Chewing-LGPL-2.1"),("PinyinIME","AOSP-Pinyin"),("LatinIME","AOSP-LatinIME"),("AndroidX EmojiPicker","AndroidX-EmojiPicker"),("Noto CJK","Noto-CJK-OFL"),("기타 고지","NOTICE")],id:\.1) { title,name in
                    NavigationLink(L10n.text(title)) { LicenseView(name:name) }
                }
            }
            Section("사용한 프로젝트") {
                ForEach([("Cangjie","https://github.com/hilarycheng/another_android_cangjie"),("Chewing","https://github.com/hiroshiyui/libchewingAndroidAppModule"),("LatinIME","https://android.googlesource.com/platform/packages/inputmethods/LatinIME"),("Mozc","https://github.com/google/mozc"),("PinyinIME","https://android.googlesource.com/platform/packages/inputmethods/PinyinIME"),("Jyutping","https://github.com/yuetyam/jyutping-android"),("Vietnamese AnySoftKeyboard","https://github.com/sh000gun/vietnamese-anysoftkeyboard"),("TrueTap Keyboard","https://github.com/RedZero13/TrueTap-Keyboard")],id:\.0) { name,url in Link(name,destination:URL(string:url)!) }
            }
        }.navigationTitle("정보").navigationBarTitleDisplayMode(.inline)
    }
}
struct LicenseView:View {
    let name:String
    var body:some View {
        ScrollView {
            Text(contents).font(.system(.caption,design:.monospaced)).textSelection(.enabled).padding()
        }.navigationTitle(name)
    }
    var contents:String {
        guard let url=Bundle.main.url(forResource:name,withExtension:"txt",subdirectory:"Licenses"), let text=try? String(contentsOf:url,encoding:.utf8) else { return L10n.text("라이선스 리소스를 찾을 수 없습니다.") }
        return text
    }
}
