import SwiftUI
import UIKit
import FusionCore

/// Match the system keyboard's neutral key surfaces in both appearances.
enum KeyboardPalette {
    static let background=Color(uiColor:UIColor { $0.userInterfaceStyle == .dark ? UIColor(white:0.12,alpha:1):UIColor(red:0.82,green:0.83,blue:0.85,alpha:1) })
    static let key=Color(uiColor:UIColor { $0.userInterfaceStyle == .dark ? UIColor(white:0.31,alpha:1):.white })
    static let utility=Color(uiColor:UIColor { $0.userInterfaceStyle == .dark ? UIColor(white:0.22,alpha:1):UIColor(red:0.68,green:0.70,blue:0.74,alpha:1) })
}

struct KeyboardView:View {
    @ObservedObject var model:KeyboardModel
    @ObservedObject var store:SettingsStore
    let globe:AnyView
    weak var menuContainer:UIView?
    @State private var wide=false
    @StateObject private var touches:KeyboardTouchCoordinator
    @State private var emojiGroup=0
    @MainActor init(model:KeyboardModel,store:SettingsStore,globe:AnyView,menuContainer:UIView?=nil,touches:KeyboardTouchCoordinator?=nil) {
        self.model=model;self.store=store;self.globe=globe;self.menuContainer=menuContainer
        _touches=StateObject(wrappedValue:touches ?? KeyboardTouchCoordinator())
    }
    private var settings:KeyboardSettings { model.effectiveSettings }
    private var syllables:Bool { [.kanaSyllables,.kanaIroha].contains(model.mode.layout) && !model.symbols && !model.isNumberPad && !model.emoji }
    private var candidateHeight:CGFloat { wide ? 28:36 }
    private var candidatesExpanded:Bool { model.candidatesExpanded && !model.candidates.isEmpty }
    private var visibleCandidates:[Candidate] { store.settings.suggestions ? model.candidates:Array(model.candidates.prefix(1)) }
    private var kanaPad:Bool { model.mode.layout == .kana12 && !model.symbols && !model.emoji && !model.numericField }
    var body:some View {
        VStack(spacing:wide ? 5:7) {
            if model.settingsVisible {
                HStack { Text("FusionIME 설정").font(.headline); Spacer(); Button("완료") { model.settingsVisible=false } }.padding(.horizontal)
                NavigationStack {
                    List {
                        NavigationLink("입력 모드") { LanguageSettingsView(store:store) }
                        NavigationLink("키보드 설정") { KeyboardSettingsView(store:store) }
                    }.navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
                }.tint(.blue)
            } else {
                toolbar
                if let message=model.message {
                    HStack { Text(message).font(.caption2); Button("닫기") { model.message=nil } }.padding(.horizontal)
                }
                if candidatesExpanded {
                    expandedCandidates
                } else {
                    if model.emoji {
                        VStack(spacing:4) {
                            ScrollView(.horizontal,showsIndicators:false) {
                                HStack { ForEach(Array(EmojiCatalog.groups.enumerated()),id:\.element.id) { index,group in
                                    Button(group.symbol) { emojiGroup=index }.font(.system(size:24)).padding(.horizontal,6)
                                        .background(emojiGroup == index ? KeyboardPalette.utility:.clear,in:RoundedRectangle(cornerRadius:6))
                                } }
                            }
                            ScrollView {
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:2),count:8),spacing:6) {
                                ForEach(EmojiCatalog.groups[emojiGroup].items,id:\.self) { values in
                                    Button(values[0]) { model.chooseEmoji(values[0]) }.font(.system(size:27)).frame(minHeight:36)
                                        .contextMenu { ForEach(values,id:\.self) { value in Button(value) { model.chooseEmoji(value);model.commit() } } }
                                }
                            }
                            }
                        }
                    } else if kanaPad {
                        kanaKeyboard
                    } else {
                        VStack(spacing:wide ? 5:7) {
                            ForEach(Array(model.rows.enumerated()),id:\.offset) { index,row in
                                keyRow(row,index:index)
                            }
                        }
                    }
                    if !kanaPad { bottomBar }
                }
            }
        }
        .padding(.horizontal,4).padding(.top,3).padding(.bottom,5)
        .background(KeyboardPalette.background)
        .background(GeometryReader { geometry in
            Color.clear.onAppear { wide=geometry.size.width>550;touches.width=geometry.size.width }
                .onChange(of:geometry.size.width) { wide=$0>550;touches.width=$0 }
        })
        .foregroundStyle(.primary).tint(.primary)
        .preferredColorScheme(store.colorScheme)
        .coordinateSpace(name:"fusion.keys")
        .overlay(alignment:.topLeading) {
            if let popup=touches.alternatives {
                HStack(spacing:0) {
                    ForEach(Array(popup.values.enumerated()),id:\.offset) { index,value in
                        Text(LatinKeyValue.display(value)).font(.system(size:26)).minimumScaleFactor(0.6).lineLimit(1)
                            .frame(width:popup.cellWidth,height:popup.frame.height)
                            .foregroundStyle(popup.selected==index ? Color.white:Color.primary)
                            .background(popup.selected==index ? Color.accentColor:Color.clear,in:RoundedRectangle(cornerRadius:6))
                    }
                }
                .background(KeyboardPalette.key,in:RoundedRectangle(cornerRadius:8))
                .shadow(color:.black.opacity(0.3),radius:4,y:2)
                .offset(x:popup.frame.minX,y:popup.frame.minY).allowsHitTesting(false)
            }
        }
        .onPreferenceChange(KeyFramesPreference.self) { frames in
            touches.frames=frames
            touches.updateKeys(model.rows)
        }
        .onChange(of:model.rows) { rows in
            // Shift and Caps Lock change key values without moving their frames.
            touches.updateKeys(rows)
            touches.reset()
        }
    }
    var toolbar:some View {
        HStack(spacing:4) {
            LanguageMenuButton(modes:store.settings.modes,selectedIndex:model.modeIndex,container:menuContainer,select:model.switchMode)
                .frame(width:30,height:candidateHeight)
            if model.candidates.isEmpty,let clipboard=model.clipboardText {
                Button { model.useClipboard() } label: { Label(clipboard,systemImage:"doc.on.clipboard").lineLimit(1) }
                    .contextMenu { Button("클립보드 지우기",role:.destructive) { model.clearClipboard() } }
                Button { model.clipboardText=nil } label: { Image(systemName:"xmark.circle") }.accessibilityLabel("닫기")
            } else if model.candidates.isEmpty {
                Text(model.mode.localizedDisplayName).font(.system(size:14)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth:.infinity,alignment:.leading)
            } else {
                ScrollView(.horizontal,showsIndicators:false) {
                    LazyHGrid(rows:Array(repeating:GridItem(.fixed(candidateHeight),spacing:0),count:settings.candidateRows),spacing:0) {
                        ForEach(visibleCandidates) { candidate in candidateView(candidate) }
                    }
                }
            }
            if !model.candidates.isEmpty {
                Button { model.candidatesExpanded.toggle() } label: {
                    Image(systemName:model.candidatesExpanded ? "chevron.up":"chevron.down").frame(width:30,height:candidateHeight)
                }.accessibilityLabel(L10n.text(model.candidatesExpanded ? "변환 후보 접기":"변환 후보 펼치기"))
            }
            if model.mode.cursorKeys ?? store.settings.cursorKeys {
                Button { model.cursor(-1) } label: { Image(systemName:"chevron.left").frame(width:24,height:candidateHeight) }.accessibilityLabel("커서 왼쪽")
                Button { model.cursor(1) } label: { Image(systemName:"chevron.right").frame(width:24,height:candidateHeight) }.accessibilityLabel("커서 오른쪽")
            }
            Menu {
                Button { model.commit(predictAfter:false); model.settingsVisible=true } label: { Label("키보드 설정",systemImage:"gearshape") }
                Button { model.paste() } label: { Label("붙여넣기",systemImage:"doc.on.clipboard") }
                Button { model.toggleNumbers() } label: { Label("숫자 키보드",systemImage:"number") }
                Button { model.dismiss?() } label: { Label("키보드 닫기",systemImage:"keyboard.chevron.compact.down") }
            } label: { Image(systemName:"ellipsis.circle").frame(width:30,height:candidateHeight) }.accessibilityLabel("키보드 메뉴")
        }.frame(height:candidateHeight*CGFloat(settings.candidateRows))
    }
    var expandedCandidates:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:0) {
                ForEach(Array(stride(from:0,to:visibleCandidates.count,by:40)),id:\.self) { start in
                    CandidateFlowLayout {
                        ForEach(Array(visibleCandidates.dropFirst(start).prefix(40))) { candidate in candidateView(candidate) }
                    }
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    private func candidateView(_ candidate:Candidate)->some View {
        Button { model.commit(candidate:candidate) } label: {
            VStack(spacing:0) {
                CandidateTypography.text(candidate.text,size:candidate.annotation.isEmpty ? 20:18).lineLimit(1)
                if !candidate.annotation.isEmpty { Text(candidate.annotation).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1) }
            }
                .padding(.horizontal,12).frame(height:candidateHeight)
                .background(candidate.focused ? KeyboardPalette.utility:.clear)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("후보 \(candidate.text)")
            .onAppear { model.loadMoreCandidates(after:candidate) }
            .contextMenu { Button("이 후보 학습 지우기",role:.destructive) { model.forget(candidate) } }
    }
    func keyRow(_ row:[KeySpec],index:Int)->some View {
        GeometryReader { geometry in
            let last=index==model.rows.count-1
            let split=wide ? store.settings.splitLandscape:store.settings.splitPortrait
            let gap=split ? geometry.size.width*(wide ? settings.splitGapLandscape:settings.splitGap):0
            let columns=max(model.rows.map(\.count).max() ?? 10,(model.rows.last?.count ?? 0)+(syllables ? 0:2))
            let keyWidth=max(10,(geometry.size.width-gap-CGFloat(columns-1)*6)/CGFloat(columns))
            HStack(spacing:0) {
                if last && !model.isNumberPad && !syllables {
                    shiftKey.frame(width:row.count<8 ? max(36,keyWidth*1.15):keyWidth)
                }
                Spacer(minLength:0)
                HStack(spacing:6) {
                    ForEach(Array(row.enumerated()),id:\.element.id) { offset,key in
                        if split && offset==row.count/2 { Spacer().frame(width:gap) }
                        if key.isSpacer { Color.clear.frame(width:keyWidth).accessibilityHidden(true) }
                        else {
                            KeyCap(key:key,settings:settings,touches:touches,refreshKeys:refreshTouchKeys,pressBegan:model.useHeldShift,action:{model.text($0,holdingShift:$1)},flickAction:{model.flick($0,key:$1,holdingShift:$2)})
                                .frame(width:keyWidth)
                        }
                    }
                }
                Spacer(minLength:0)
                if last && !syllables { RepeatDeleteKey { model.backspace() }.frame(width:row.count<8 ? max(36,keyWidth*1.15):keyWidth) }
            }
        }
    }
    private func refreshTouchKeys()->Bool {
        // Touch dispatch must use the model now, not a previous SwiftUI frame.
        touches.updateKeys(model.rows)
        return model.isShifted
    }
    var shiftKey:some View {
        Group {
            if model.symbols {
                Button { model.symbolsSecond.toggle() } label: {
                    Text(model.symbolsSecond ? "123":"#+=").font(.system(size:14)).frame(maxWidth:.infinity,maxHeight:.infinity)
                }.accessibilityLabel("Shift")
            } else if model.mode.language == .pinyin {
                Button { model.text("'") } label: { Text("'").font(.system(size:24)).frame(maxWidth:.infinity,maxHeight:.infinity) }
            } else {
                ShiftKey(shifted:model.isShifted,capsLocked:model.capsLocked,press:{
                    model.beginShift();touches.updateKeys(model.rows)
                },release:{ cancelled in
                    model.endShift(cancelled:cancelled);touches.updateKeys(model.rows)
                },tap:{ model.shift();touches.updateKeys(model.rows) })
                    .onDisappear { model.endShift(cancelled:true);touches.updateKeys(model.rows) }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(model.isShifted && !model.symbols ? KeyboardPalette.key:KeyboardPalette.utility,in:RoundedRectangle(cornerRadius:6))
    }
    var kanaKeyboard:some View {
        VStack(spacing:wide ? 5:7) {
            ForEach(Array(model.rows.enumerated()),id:\.offset) { index,row in
                HStack(spacing:6) {
                    Group {
                        switch index {
                        case 0: utility("123",label:"문자와 기호 전환") { model.toggleSymbols() }
                        case 1: utility("☺︎",label:"이모지") { model.toggleEmoji() }
                        case 2: utility("ー",label:"장음 기호") { model.text("ー") }
                        default:
                            if model.needsGlobe { globe.background(KeyboardPalette.utility,in:RoundedRectangle(cornerRadius:6)) }
                            else { utility("⌄",label:"키보드 닫기") { model.dismiss?() } }
                        }
                    }.frame(width:wide ? 54:44)
                    ForEach(row) { key in
                        KeyCap(key:key,settings:settings,touches:touches,refreshKeys:refreshTouchKeys,pressBegan:model.useHeldShift,action:{model.text($0,holdingShift:$1)},flickAction:{model.flick($0,key:$1,holdingShift:$2)})
                    }
                    Group {
                        switch index {
                        case 0: RepeatDeleteKey { model.backspace() }
                        case 1: utility("공백",label:"공백") { model.space() }
                        case 2: utility("줄바꿈",label:"Return") { model.enter() }
                        default: utility("→",label:"커서 오른쪽") { model.cursor(1) }
                        }
                    }.frame(width:wide ? 66:52)
                }
            }
        }
    }
    var bottomBar:some View {
        HStack(spacing:6) {
            utility(model.symbols || model.numberPad ? "ABC":"123",label:"문자와 기호 전환") {
                if model.numberPad { model.toggleNumbers() } else { model.toggleSymbols() }
            }.frame(width:46)
            if model.needsGlobe { globe.frame(width:36).background(KeyboardPalette.utility,in:RoundedRectangle(cornerRadius:6)) }
            if !syllables { utility(model.emoji ? "ABC":"☺︎",label:"이모지") { model.toggleEmoji() }.frame(width:34) }
            if syllables {
                utility("ん",label:"ん") { model.text("ん") }.frame(width:30)
                utility("小゛゜",label:"小゛゜") { model.text("*") }.frame(width:40)
            }
            if model.mode.language == .japanese && model.mode.layout != .romaji {
                utility("ー",label:"장음 기호") { model.text("ー") }.frame(width:34)
            }
            SpaceKey(title:L10n.text("공백"),
                     action:model.space,move:model.cursor)
            if model.emoji || syllables { RepeatDeleteKey { model.backspace() }.frame(width:34) }
            utility(model.returnLabel,label:"Return") { model.enter() }.frame(width:wide ? 88:74)
        }.frame(height:wide ? 32:43)
    }
    func utility(_ text:String,label:String,action:@escaping()->Void) -> some View {
        Button(action:action) { Text(L10n.text(text)).font(.system(size:16)).minimumScaleFactor(0.7).lineLimit(1).frame(maxWidth:.infinity,maxHeight:.infinity).background(KeyboardPalette.utility,in:RoundedRectangle(cornerRadius:6)) }
            .accessibilityLabel(L10n.text(label))
    }
}

/// Wrap the same candidate labels used by the strip, preserving their natural
/// widths instead of turning them into a grid of keyboard keys.
private struct CandidateFlowLayout:Layout {
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let idealWidth=subviews.reduce(CGFloat.zero) { $0+$1.sizeThatFits(.unspecified).width }
        let width=proposal.width.flatMap { $0.isFinite ? max(0,$0):nil } ?? idealWidth
        let frames=frames(width:width,subviews:subviews)
        return CGSize(width:width,height:frames.last?.maxY ?? 0)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        for (subview,frame) in zip(subviews,frames(width:bounds.width,subviews:subviews)) {
            subview.place(at:CGPoint(x:bounds.minX+frame.minX,y:bounds.minY+frame.minY),anchor:.topLeading,proposal:ProposedViewSize(frame.size))
        }
    }
    private func frames(width:CGFloat,subviews:Subviews)->[CGRect] {
        var x:CGFloat=0,y:CGFloat=0,rowHeight:CGFloat=0
        return subviews.map { subview in
            let ideal=subview.sizeThatFits(.unspecified)
            let size=CGSize(width:min(width,ideal.width),height:ideal.height)
            if x>0 && x+size.width>width { x=0;y+=rowHeight;rowHeight=0 }
            let frame=CGRect(origin:CGPoint(x:x,y:y),size:size)
            x+=size.width;rowHeight=max(rowHeight,size.height)
            return frame
        }
    }
}

struct KeyCap:View {
    let key:KeySpec
    let settings:KeyboardSettings
    @ObservedObject var touches:KeyboardTouchCoordinator
    let refreshKeys:()->Bool
    let pressBegan:()->Bool
    let action:(String,Bool)->Void
    let flickAction:(FlickAction,KeySpec,Bool)->Void
    @State private var pressed=false
    @State private var direction=0
    @State private var longPressed=false
    @State private var startKey:KeySpec?
    @State private var holdTask:Task<Void,Never>?
    @GestureState private var tracking=false
    private var highlighted:Bool { key.flick || settings.touchMode == .flick ? pressed:touches.active.values.contains(key.id) }
    private var labels:[String] { key.hints ?? key.values }
    var body:some View {
        face.background(GeometryReader { geometry in Color.clear.preference(key:KeyFramesPreference.self,value:[key.id:geometry.frame(in:.named("fusion.keys"))]) })
            .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("fusion.keys"))
                .updating($tracking) { _,tracking,_ in tracking=true }
                .onChanged { value in
                    let preferCurrent=refreshKeys()
                    if startKey == nil {
                        longPressed=false
                        touches.begin(key.id,holdingShift:pressBegan())
                        startKey=key.flick ? touches.key(key.id,start:key.id) ?? key:touches.target(value.startLocation,correct:settings.touchCorrection,learn:true,start:key.id) ?? key
                        if let startKey,!key.flick,startKey.values.count>1 {
                            holdTask=Task { @MainActor in
                                do { try await Task.sleep(nanoseconds:350_000_000) } catch { return }
                                guard !Task.isCancelled,self.startKey != nil else { return }
                                longPressed=true
                                touches.showAlternatives(start:key.id,key:startKey)
                            }
                        }
                    }
                    if longPressed { touches.trackAlternatives(start:key.id,point:value.location);return }
                    if max(abs(value.translation.width),abs(value.translation.height))>settings.flickSensitivity { holdTask?.cancel();holdTask=nil }
                    pressed=true;direction=flickDirection(value.translation)
                    if !key.flick && settings.touchMode == .seek {
                        touches.highlight(start:key.id,key:touches.target(value.location,correct:settings.touchCorrection,learn:false,start:key.id,preferCurrent:preferCurrent))
                    }
                }.onEnded { value in
                    defer { endPress() }
                    if longPressed {
                        if let value=touches.selectedAlternative(start:key.id,point:value.location) { send(value) }
                        return
                    }
                    let preferCurrent=refreshKeys()
                    let selected=touches.key(startKey?.id ?? key.id,start:key.id,preferCurrent:preferCurrent) ?? startKey ?? key
                    let direction=flickDirection(value.translation)
                    if key.flick { send(selected.values[min(direction,selected.values.count-1)]) }
                    else if settings.touchMode == .seek {
                        if let selected=touches.target(value.location,correct:settings.touchCorrection,learn:false,start:key.id,preferCurrent:preferCurrent) { send(selected.values[0]) }
                    }
                    else if direction==2 { flickAction(settings.flickUp,selected,touches.holdingShift(key.id)) }
                    else if direction==4 { flickAction(settings.flickDown,selected,touches.holdingShift(key.id)) }
                    else { send(selected.values[0]) }
                })
                .accessibilityAction {
                    let preferCurrent=refreshKeys()
                    send((touches.key(key.id,preferCurrent:preferCurrent) ?? key).values[0])
                }
                .accessibilityActions { ForEach(Array(key.values.dropFirst().enumerated()),id:\.offset) { _,value in Button(LatinKeyValue.display(value)) { send(value) } } }
                .accessibilityLabel(key.label).accessibilityAddTraits(.isButton)
                .onChange(of:tracking) { if !$0 { DispatchQueue.main.async { if !tracking { endPress() } } } }
                .onDisappear { endPress() }
    }
    private func endPress() { holdTask?.cancel();holdTask=nil;pressed=false;longPressed=false;touches.end(key.id);startKey=nil }
    private func send(_ value:String) { action(value,touches.holdingShift(key.id)) }
    var face:some View {
        VStack(spacing:1) {
            Text(pressed && key.flick ? labels[min(direction,labels.count-1)] : key.label)
                .font(.system(size:22)).minimumScaleFactor(0.6).lineLimit(1)
            if key.flick && settings.flickHints { Text(labels.dropFirst().joined(separator:" ")).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(highlighted ? KeyboardPalette.utility:KeyboardPalette.key,in:RoundedRectangle(cornerRadius:6))
            .shadow(color:.black.opacity(0.18),radius:0,y:1)
            .contentShape(Rectangle()).foregroundStyle(.primary)
            .overlay(alignment:.top) {
                if highlighted && settings.keyPreview && !longPressed {
                    Text(key.flick ? labels[min(direction,labels.count-1)]:key.label)
                        .font(.system(size:30)).lineLimit(1).fixedSize()
                        .padding(.horizontal,10).padding(.vertical,8)
                        .frame(minWidth:48,minHeight:54)
                        .fixedSize().background(.regularMaterial,in:RoundedRectangle(cornerRadius:8))
                        .offset(y:-40).allowsHitTesting(false)
                }
            }.zIndex(highlighted ? 1:0)
    }
    func flickDirection(_ size:CGSize)->Int {
        if max(abs(size.width),abs(size.height))<settings.flickSensitivity { return 0 }
        if abs(size.width)>abs(size.height) { return size.width<0 ? 1:3 }
        return size.height<0 ? 2:4
    }
}
struct ShiftKey:UIViewRepresentable {
    let shifted:Bool
    let capsLocked:Bool
    let press:()->Void
    let release:(Bool)->Void
    let tap:()->Void
    func makeUIView(context:Context)->ShiftControl {
        let control=ShiftControl(type:.custom)
        update(control);return control
    }
    func updateUIView(_ control:ShiftControl,context:Context) { update(control) }
    private func update(_ control:ShiftControl) {
        control.press=press;control.release=release;control.tap=tap
        control.setImage(UIImage(systemName:capsLocked ? "capslock.fill":shifted ? "shift.fill":"shift",withConfiguration:UIImage.SymbolConfiguration(pointSize:20)),for:.normal)
        control.accessibilityTraits=shifted ? [.button,.selected]:.button
    }
    static func dismantleUIView(_ control:ShiftControl,coordinator:()) { control.invalidate() }
}
final class ShiftControl:UIButton,UIGestureRecognizerDelegate {
    var press:(()->Void)?
    var release:((Bool)->Void)?
    var tap:(()->Void)?
    private var pressed=false
    override init(frame:CGRect) {
        super.init(frame:frame)
        isExclusiveTouch=false;tintColor = .label;accessibilityLabel="Shift"
        // SwiftUI's ancestor recognizers can delay UIButton touch-down events.
        // Recognize the press immediately and coexist with the letter gestures.
        let gesture=UILongPressGestureRecognizer(target:self,action:#selector(trackPress(_:)))
        gesture.minimumPressDuration=0
        gesture.cancelsTouchesInView=false
        gesture.delaysTouchesBegan=false;gesture.delaysTouchesEnded=false
        gesture.delegate=self;addGestureRecognizer(gesture)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func trackPress(_ gesture:UILongPressGestureRecognizer) {
        handlePress(gesture.state,inside:bounds.contains(gesture.location(in:self)))
    }
    func handlePress(_ state:UIGestureRecognizer.State,inside:Bool=true) {
        switch state {
        case .began:
            guard !pressed else { return }
            pressed=true;isHighlighted=true;press?()
        case .ended:finish(cancelled:!inside)
        case .cancelled,.failed:finish(cancelled:true)
        default:break
        }
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer:UIGestureRecognizer)->Bool { true }
    private func finish(cancelled:Bool) {
        guard pressed else { return };pressed=false;isHighlighted=false;release?(cancelled)
    }
    // SwiftUI's onDisappear cancels the modifier. Teardown itself must not
    // publish model changes while SwiftUI is updating its view hierarchy.
    func invalidate() { pressed=false;isHighlighted=false;press=nil;release=nil;tap=nil }
    override func accessibilityActivate()->Bool { tap?();return true }
}
struct SpaceKey:View {
    let title:String
    let action:()->Void
    let move:(Int)->Void
    @GestureState private var pressed=false
    var body:some View {
        Text(title).font(.system(size:16)).frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(pressed ? KeyboardPalette.utility:KeyboardPalette.key,in:RoundedRectangle(cornerRadius:6))
            .shadow(color:.black.opacity(0.18),radius:0,y:1)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0)
                .updating($pressed) { _,pressed,_ in pressed=true }
                .onEnded { value in
                    let offset=Int(value.translation.width/15)
                    if offset != 0 { move(offset) }
                    else if max(abs(value.translation.width),abs(value.translation.height))<15 { action() }
                })
            .accessibilityLabel("공백").accessibilityAddTraits(.isButton).accessibilityAction { action() }
    }
}
struct RepeatDeleteKey:View {
    let action:()->Void
    @State private var repeating:Task<Void,Never>?
    @State private var pressed=false
    var body:some View {
        Image(systemName:"delete.left").frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(KeyboardPalette.utility,in:RoundedRectangle(cornerRadius:6)).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged { _ in
                guard !pressed else { return }; pressed=true; action()
                repeating=Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds:400_000_000)
                        while !Task.isCancelled { action(); try await Task.sleep(nanoseconds:75_000_000) }
                    } catch {}
                }
            }.onEnded { _ in stop() })
            .onDisappear(perform:stop).accessibilityLabel("삭제").accessibilityAddTraits(.isButton).accessibilityAction { action() }
    }
    func stop() { repeating?.cancel(); repeating=nil; pressed=false }
}

struct GlobeButton:UIViewRepresentable {
    weak var controller:UIInputViewController?
    func makeUIView(context:Context)->UIButton {
        let button=UIButton(type:.system)
        button.setImage(UIImage(systemName:"globe"),for:.normal)
        button.accessibilityLabel=L10n.text("다음 키보드")
        button.tintColor = .label
        if let controller { button.addTarget(controller,action:#selector(UIInputViewController.handleInputModeList(from:with:)),for:.allTouchEvents) }
        return button
    }
    func updateUIView(_ uiView:UIButton,context:Context) {}
}

