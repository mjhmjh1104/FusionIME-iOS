import SwiftUI
import FusionCore

struct LanguageSettingsView: View {
    @ObservedObject var store:SettingsStore
    var body:some View {
        List {
            Section("사용 중인 언어") {
                ForEach($store.settings.modes) { $mode in
                    NavigationLink { ModeSettingsView(mode:$mode,store:store) } label: {
                        HStack { Text(mode.localizedTitle); Spacer(); Text(mode.layout.localizedName).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .onDelete { indices in
                    if store.settings.modes.count>indices.count { store.settings.modes.remove(atOffsets:indices) }
                }
                .onMove { store.settings.modes.move(fromOffsets:$0,toOffset:$1) }
            }
            Section {
                NavigationLink("언어 추가") { AddLanguageView(store:store) }
                NavigationLink("사용자 사전") { UserDictionaryView(store:store) }
            }
        }
        .navigationTitle("입력 모드").toolbar { EditButton() }
    }
}
struct AddLanguageView:View {
    @ObservedObject var store:SettingsStore
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        List(InputLanguage.allCases) { language in
            Button(language.localizedName) {
                store.settings.modes.append(InputMode(language:language));dismiss()
            }
        }.navigationTitle("언어 추가")
    }
}
struct ModeSettingsView:View {
    @Binding var mode:InputMode
    @ObservedObject var store:SettingsStore
    @State private var cleared=false
    var body:some View {
        Form {
            Picker("키보드 배열",selection:$mode.layout) {
                ForEach(mode.language.layouts) { Text($0.localizedName).tag($0) }
            }
            if mode.language == .korean {
                Toggle("한자 변환",isOn:$mode.hanja)
                Toggle("자모 순서 자동 보정",isOn:$mode.correctHangulOrder)
                Picker("한자 변환 방식",selection:$mode.koreanConverter) { Text("단어").tag("word");Text("어절 · 문맥").tag("phrase");Text("동국정운").tag("jeongun");Text("한글 예측").tag("hangul") }
            }
            if mode.language == .pinyin {
                Toggle("번체자",isOn:$mode.traditional)
                Picker("병음 방식",selection:$mode.doublePinyin) { ForEach(DoublePinyin.allCases) { Text($0.localizedName).tag($0) } }
            }
            if mode.language == .vietnamese { Toggle("쯔놈 후보",isOn:$mode.hanNom) }
            if mode.layout == .kana12 {
                Picker("12키 입력 방식",selection:$mode.kanaInputStyle) {
                    Text("플릭 및 반복 입력").tag(KanaInputStyle.both)
                    Text("플릭만").tag(KanaInputStyle.flick)
                    Text("반복 입력만").tag(KanaInputStyle.toggle)
                }
            }
            if mode.language == .japanese {
                Picker("후보 창 높이",selection:$mode.candidateRows) {
                    Text("공통 설정").tag(Optional<Int>.none)
                    ForEach(1...3,id:\.self) { Text("\($0)").tag(Optional($0)) }
                }
                Picker("플릭 문자 안내",selection:$mode.flickHints) {
                    Text("공통 설정").tag(Optional<Bool>.none);Text("표시").tag(Optional(true));Text("숨기기").tag(Optional(false))
                }
            }
            if [.kanaSyllables,.kanaIroha].contains(mode.layout) {
                Picker("가나 배열 방향",selection:$mode.syllablesDirection) { Text("가로").tag("horizontal");Text("세로 · 왼쪽부터").tag("left");Text("세로 · 오른쪽부터").tag("right") }
            }
            if mode.language.isLatin {
                Picker("자동 대문자",selection:$mode.autoCapitalization) { Text("공통 설정").tag(Optional<Bool>.none);Text("켜기").tag(Optional(true));Text("끄기").tag(Optional(false)) }
                Picker("공백 두 번으로 마침표",selection:$mode.doubleSpacePeriod) { Text("공통 설정").tag(Optional<Bool>.none);Text("켜기").tag(Optional(true));Text("끄기").tag(Optional(false)) }
                Button("이 언어의 학습 기록 지우기",role:.destructive) { store.clearHistory(language:mode.language);cleared=true }
                if cleared { Text("학습 기록을 지웠습니다.").foregroundStyle(.secondary) }
            }
            if mode.language == .zhuyin {
                Picker("주음 변환 엔진",selection:$mode.zhuyinEngine) { Text("단순 · 글자 선택").tag(0);Text("문맥 변환").tag(1);Text("유사 발음 문맥 변환").tag(2) }
            }
            if [.cangjie,.quick,.dayi].contains(mode.language) { Toggle("전각 영문·기호",isOn:$mode.fullWidth) }
            Picker("숫자 행",selection:$mode.numberRow) { Text("공통 설정").tag(Optional<Bool>.none);Text("표시").tag(Optional(true));Text("숨기기").tag(Optional(false)) }
            Picker("커서 버튼",selection:$mode.cursorKeys) { Text("공통 설정").tag(Optional<Bool>.none);Text("표시").tag(Optional(true));Text("숨기기").tag(Optional(false)) }
        }.navigationTitle(mode.localizedTitle)
    }
}
struct AppearanceSettingsView:View {
    @ObservedObject var store:SettingsStore
    var body:some View {
        Form {
            Section("기본") {
                Picker("테마",selection:$store.settings.theme) {
                    Text("시스템").tag(KeyboardTheme.system); Text("밝게").tag(KeyboardTheme.light); Text("어둡게").tag(KeyboardTheme.dark)
                }
                Picker("화면 모드",selection:$store.settings.screenMode) {
                    Text("시스템").tag(KeyboardScreenMode.automatic);Text("모바일").tag(KeyboardScreenMode.mobile);Text("태블릿").tag(KeyboardScreenMode.tablet)
                }
                Picker("기호 배열",selection:$store.settings.symbolLayout) {
                    ForEach(SymbolLayout.allCases) { Text(L10n.text($0 == .system ? "시스템":"symbol_"+$0.rawValue)).tag($0) }
                }
                Toggle("음성 입력 버튼",isOn:$store.settings.showVoiceInputButton)
                Toggle("숫자 행",isOn:$store.settings.numberRow)
                Toggle("커서 이동 버튼",isOn:$store.settings.cursorKeys)
                Stepper(L10n.format("후보 행: %d",store.settings.candidateRows),value:$store.settings.candidateRows,in:1...3)
            }
            Section("키보드 높이") {
                LabeledContent("세로 키보드 높이",value:"\(Int(store.settings.height)) pt")
                Slider(value:$store.settings.height,in:210...360,step:10)
                LabeledContent("가로 키보드 높이",value:"\(Int(store.settings.landscapeHeight)) pt")
                Slider(value:$store.settings.landscapeHeight,in:170...280,step:10)
            }
            Section("분할 키보드") {
                Toggle("세로 분할 키보드",isOn:$store.settings.splitPortrait)
                Toggle("가로 분할 키보드",isOn:$store.settings.splitLandscape)
                LabeledContent("세로 분할 간격",value:"\(Int(store.settings.splitGap*100))%")
                Slider(value:$store.settings.splitGap,in:0.1...0.5,step:0.05)
                LabeledContent("가로 분할 간격",value:"\(Int(store.settings.splitGapLandscape*100))%")
                Slider(value:$store.settings.splitGapLandscape,in:0.1...0.5,step:0.05)
            }
        }.navigationTitle("외관")
    }
}
struct BehaviorSettingsView:View {
    @ObservedObject var store:SettingsStore
    @State private var cleared=false
    var body:some View {
        Form {
            Section("입력") {
                Toggle("후보 표시",isOn:$store.settings.suggestions)
                Toggle("클립보드 후보",isOn:$store.settings.clipboardCandidates)
                Toggle("자동 대문자",isOn:$store.settings.autoCapitalization)
                Toggle("자동 수정",isOn:$store.settings.autoCorrection)
                Toggle("공백 두 번으로 마침표",isOn:$store.settings.doubleSpacePeriod)
            }
            Section("반응") {
                Toggle("햅틱",isOn:$store.settings.haptics)
                if store.settings.haptics {
                    LabeledContent("진동 지속 시간",value:"\(Int(store.settings.vibrationDuration)) ms")
                    Slider(value:$store.settings.vibrationDuration,in:5...50,step:5)
                }
                Toggle("키 소리",isOn:$store.settings.sound)
                Toggle("키 미리보기",isOn:$store.settings.keyPreview)
            }
            Section("터치") {
                Picker("터치 모드",selection:$store.settings.touchMode) { Text("Seek").tag(KeyboardTouchMode.seek);Text("Flick").tag(KeyboardTouchMode.flick) }
                Toggle("터치 교정",isOn:$store.settings.touchCorrection)
                Toggle("플릭 문자 안내",isOn:$store.settings.flickHints)
                Picker("위로 밀기",selection:$store.settings.flickUp) { ForEach(FlickAction.allCases){Text($0.localizedName).tag($0)} }
                Picker("아래로 밀기",selection:$store.settings.flickDown) { ForEach(FlickAction.allCases){Text($0.localizedName).tag($0)} }
                LabeledContent("플릭 이동 거리",value:"\(Int(store.settings.flickSensitivity)) pt")
                Slider(value:$store.settings.flickSensitivity,in:8...150,step:2)
            }
            Section {
                Toggle("단어·문맥 학습",isOn:$store.settings.learnWords)
                Button("학습 기록 지우기",role:.destructive) { store.clearHistory(); cleared=true }
                if cleared { Text("학습 기록을 지웠습니다.").foregroundStyle(.secondary) }
            } header: { Text("기기 내 학습") } footer: {
                Text("확정한 단어를 기기에 저장해 후보에 반영합니다.")
            }
        }.navigationTitle("행동")
    }
}
struct KeyboardSettingsView:View {
    @ObservedObject var store:SettingsStore
    var body:some View {
        List {
            NavigationLink("외관") { AppearanceSettingsView(store:store) }
            NavigationLink("행동") { BehaviorSettingsView(store:store) }
            NavigationLink("사용자 사전") { UserDictionaryView(store:store) }
            NavigationLink("백업과 복원") { BackupSettingsView(store:store) }
        }.navigationTitle("키보드 설정")
    }
}
