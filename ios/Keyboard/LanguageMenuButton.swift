import SwiftUI
import UIKit
import FusionCore

struct LanguageMenuButton:UIViewRepresentable {
    let modes:[InputMode]
    let selectedIndex:Int
    weak var container:UIView?
    let select:(Int)->Void

    func makeUIView(context:Context)->LanguageSwitchControl { makeControl() }
    func makeControl()->LanguageSwitchControl {
        let control=LanguageSwitchControl()
        update(control)
        return control
    }
    func updateUIView(_ control:LanguageSwitchControl,context:Context) { update(control) }
    private func update(_ control:LanguageSwitchControl) {
        control.menuContainer=container
        control.configure(modes:modes,selectedIndex:selectedIndex,select:select)
    }
    static func dismantleUIView(_ control:LanguageSwitchControl,coordinator:()) { control.cancelInteraction() }
}

/// Keep the original touch captured while a menu is drawn over the keyboard.
/// UIContextMenuInteraction waits for a long press and can reject a moving touch.
final class LanguageSwitchControl:UIControl {
    weak var menuContainer:UIView?
    private var modes:[InputMode]=[]
    private var reportedIndex = -1
    private var currentIndex=0
    private var select:((Int)->Void)?
    private let icon=UIImageView(image:UIImage(systemName:"globe"))
    private var holdTimer:Timer?
    private var origin:CGPoint?
    private var moved=false
    private(set) var languageMenu:LanguageSelectionOverlay?

    override init(frame:CGRect) {
        super.init(frame:frame)
        icon.tintColor = .label;icon.contentMode = .scaleAspectFit
        addSubview(icon)
        isExclusiveTouch=true
        isAccessibilityElement=true;accessibilityTraits = .button
        accessibilityLabel=L10n.text("입력 언어 선택")
        accessibilityHint=L10n.text("탭하면 다음 언어로 전환합니다. 누른 채 움직이거나 길게 눌러 메뉴를 열고 원하는 언어에서 손을 떼십시오.")
        addTarget(self,action:#selector(advance),for:.primaryActionTriggered)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        icon.frame=CGRect(x:(bounds.width-21)/2,y:(bounds.height-21)/2,width:21,height:21)
    }
    override var isHighlighted:Bool { didSet { icon.alpha=isHighlighted ? 0.5:1 } }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelInteraction() }
    }
    func configure(modes:[InputMode],selectedIndex:Int,select:@escaping(Int)->Void) {
        self.select=select
        if self.modes != modes { cancelInteraction();self.modes=modes }
        if reportedIndex != selectedIndex { currentIndex=selectedIndex;reportedIndex=selectedIndex }
        accessibilityValue=modes.indices.contains(currentIndex) ? modes[currentIndex].localizedDisplayName:nil
        accessibilityCustomActions=modes.enumerated().map { index,mode in
            UIAccessibilityCustomAction(name:mode.localizedDisplayName) { [weak self] _ in self?.choose(index);return true }
        }
    }
    @objc private func advance() {
        guard modes.count>1 else { return }
        choose((currentIndex+1)%modes.count)
    }
    func choose(_ index:Int) {
        guard modes.indices.contains(index) else { return }
        dismissMenu();currentIndex=index
        accessibilityValue=modes[index].localizedDisplayName
        select?(index)
    }
    override func accessibilityActivate()->Bool { advance();return true }

    override func beginTracking(_ touch:UITouch,with event:UIEvent?)->Bool {
        guard let container=menuContainer else { return false }
        beginInteraction(at:touch.location(in:container));return true
    }
    override func continueTracking(_ touch:UITouch,with event:UIEvent?)->Bool {
        guard let container=menuContainer else { return false }
        moveInteraction(to:touch.location(in:container));return true
    }
    override func endTracking(_ touch:UITouch?,with event:UIEvent?) {
        guard let touch,let container=menuContainer else { cancelInteraction();return }
        endInteraction(at:touch.location(in:container))
    }
    override func cancelTracking(with event:UIEvent?) { cancelInteraction() }

    func beginInteraction(at point:CGPoint) {
        cancelInteraction();origin=point;moved=false;isHighlighted=true
        let timer=Timer(timeInterval:0.4,repeats:false) { [weak self] _ in self?.showMenu() }
        holdTimer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    func moveInteraction(to point:CGPoint) {
        guard let origin else { return }
        // A small tolerance avoids opening the menu from normal finger jitter.
        if max(abs(point.x-origin.x),abs(point.y-origin.y))>=4 {
            moved=true;showMenu()
        }
        languageMenu?.track(point)
    }
    func endInteraction(at point:CGPoint) {
        guard origin != nil else { return }
        // A very fast drag can arrive with no intermediate tracking callback.
        // Include the final location before deciding between a tap and a drag.
        moveInteraction(to:point)
        holdTimer?.invalidate();holdTimer=nil;origin=nil;isHighlighted=false
        if let menu=languageMenu {
            let index=menu.index(at:point)
            menu.stopTracking()
            if let index { choose(index) }
            else if moved || !buttonFrame.contains(point) { dismissMenu() }
            // Releasing a stationary long press on the globe keeps the menu
            // open for a separate tap or accessibility navigation.
        } else if !moved && buttonFrame.contains(point) {
            sendActions(for:.primaryActionTriggered)
        }
    }
    func cancelInteraction() {
        holdTimer?.invalidate();holdTimer=nil;origin=nil;moved=false
        isHighlighted=false;dismissMenu()
    }
    private var buttonFrame:CGRect { menuContainer.map{convert(bounds,to:$0)} ?? .zero }
    private func showMenu() {
        guard origin != nil,languageMenu == nil,let container=menuContainer,!modes.isEmpty else { return }
        holdTimer?.invalidate();holdTimer=nil
        let menu=LanguageSelectionOverlay(frame:container.bounds,modes:modes,selectedIndex:currentIndex,anchor:buttonFrame)
        menu.overrideUserInterfaceStyle=traitCollection.userInterfaceStyle
        menu.onSelect={ [weak self] in self?.choose($0) }
        menu.onDismiss={ [weak self] in self?.cancelInteraction() }
        languageMenu=menu;container.addSubview(menu)
    }
    private func dismissMenu() {
        languageMenu?.stopTracking();languageMenu?.removeFromSuperview();languageMenu=nil
    }
}

/// The overlay is confined to the extension, so it works without full access.
final class LanguageSelectionOverlay:UIControl {
    var onSelect:((Int)->Void)?
    var onDismiss:(()->Void)?
    private let surface=UIVisualEffectView(effect:UIBlurEffect(style:.systemMaterial))
    private let scroll=UIScrollView()
    private(set) var rows:[UIButton]=[]
    private let initialSize:CGSize
    private let rowHeight:CGFloat
    private var trackingPoint:CGPoint?
    private var scrollTimer:Timer?
    private var hovered:Int?

    init(frame:CGRect,modes:[InputMode],selectedIndex:Int,anchor:CGRect) {
        initialSize=frame.size;rowHeight=frame.height<220 ? 36:44
        super.init(frame:frame)
        autoresizingMask=[.flexibleWidth,.flexibleHeight]
        accessibilityViewIsModal=true
        addTarget(self,action:#selector(dismiss),for:.touchUpInside)
        let width=min(bounds.width-8,320)
        let top=min(anchor.maxY+2,max(4,bounds.height-rowHeight-4))
        let height=min(CGFloat(modes.count)*rowHeight,bounds.height-top-4)
        surface.frame=CGRect(x:max(4,min(anchor.minX,bounds.width-width-4)),y:top,width:width,height:height)
        surface.layer.cornerRadius=14;surface.clipsToBounds=true
        addSubview(surface)
        scroll.frame=surface.bounds;scroll.alwaysBounceVertical=false
        scroll.contentSize=CGSize(width:width,height:CGFloat(modes.count)*rowHeight)
        surface.contentView.addSubview(scroll)
        for (index,mode) in modes.enumerated() {
            let button=UIButton(type:.system)
            var configuration=UIButton.Configuration.plain()
            configuration.title=mode.localizedDisplayName
            configuration.image=UIImage(systemName:index==selectedIndex ? "checkmark":"circle")
            configuration.imagePadding=10
            configuration.contentInsets=NSDirectionalEdgeInsets(top:0,leading:14,bottom:0,trailing:12)
            configuration.baseForegroundColor = .label
            configuration.titleLineBreakMode = .byTruncatingTail
            button.configuration=configuration
            button.contentHorizontalAlignment = .leading
            button.frame=CGRect(x:0,y:CGFloat(index)*rowHeight,width:width,height:rowHeight)
            button.accessibilityLabel=mode.localizedDisplayName
            if index==selectedIndex { button.accessibilityTraits.insert(.selected) }
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(index) },for:.primaryActionTriggered)
            rows.append(button);scroll.addSubview(button)
        }
        let offset=max(0,min(CGFloat(selectedIndex)*rowHeight-height+rowHeight,scroll.contentSize.height-height))
        scroll.contentOffset=CGPoint(x:0,y:offset)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != initialSize { onDismiss?() }
    }
    @objc private func dismiss() { onDismiss?() }
    func index(at point:CGPoint)->Int? {
        guard surface.frame.contains(point) else { return nil }
        let y=point.y-surface.frame.minY+scroll.contentOffset.y
        let index=Int(y/rowHeight)
        return rows.indices.contains(index) ? index:nil
    }
    func track(_ point:CGPoint) {
        trackingPoint=point;highlight(index(at:point))
        guard scrollTimer == nil else { return }
        let timer=Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in self?.scrollAtEdge() }
        scrollTimer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    private func highlight(_ index:Int?) {
        guard hovered != index else { return }
        if let hovered { rows[hovered].backgroundColor = .clear }
        hovered=index
        if let index { rows[index].backgroundColor = .tertiarySystemFill }
    }
    private func scrollAtEdge() {
        guard let point=trackingPoint,surface.frame.contains(point) else { return }
        let y=point.y-surface.frame.minY
        let delta:CGFloat=y<20 ? -6:y>surface.bounds.height-20 ? 6:0
        let offset=max(0,min(scroll.contentOffset.y+delta,scroll.contentSize.height-scroll.bounds.height))
        scroll.contentOffset.y=offset
        highlight(index(at:point))
    }
    func stopTracking() { scrollTimer?.invalidate();scrollTimer=nil;trackingPoint=nil }
}
