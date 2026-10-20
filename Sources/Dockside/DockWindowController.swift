import AppKit
import SwiftUI
import Combine

final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Reports SwiftUI's intrinsic size whenever widgets are added, removed or resized.
final class DockHostingView: NSHostingView<DockRootView> {
    var onIntrinsicSizeChange: ((CGSize) -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        notify()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notify()
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onIntrinsicSizeChange?(self.intrinsicContentSize)
        }
    }
}

/// Horizontal-only scroll view. AppKit's own horizontal handling doesn't engage in this borderless panel, so
/// every wheel and trackpad event (including momentum) is applied here, clamped to the content's ends.
final class DockScrollView: NSScrollView {
    override func scrollWheel(with e: NSEvent) {
        guard let doc = documentView else { return }
        // Sideways swipes scroll directly; a vertical swipe or mouse wheel scrolls sideways too.
        let raw = abs(e.scrollingDeltaX) >= abs(e.scrollingDeltaY) ? e.scrollingDeltaX : e.scrollingDeltaY
        let step = e.hasPreciseScrollingDeltas ? raw : raw * 20
        guard step != 0 else { return }
        let maxX = max(0, doc.frame.width - contentView.bounds.width)
        var origin = contentView.bounds.origin
        origin.x = min(max(origin.x - step, 0), maxX)
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }
}

/// Owns the borderless floating panel that hosts the dock: sizing, scrolling, placement and hover-to-reveal.
final class DockWindowController: NSObject {
    let panel: DockPanel
    private let container = NSView()
    private let scrollView = DockScrollView()
    private let tiles = DockHostingView(rootView: DockRootView())
    private let fadeMask = CAGradientLayer()

    private var contentSize: CGSize = .zero
    private var bag = Set<AnyCancellable>()
    private var lastVisibleFrame: NSRect = .zero
    private var isPositioning = false

    // Auto-hide state
    private var hoverTimer: Timer?
    private(set) var revealed = false
    private var pinned = false
    private var edgeDwell: TimeInterval = 0
    private var awayTime: TimeInterval = 0
    private var peekUntil = Date.distantPast

    override init() {
        panel = DockPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        // Movable only so WindowDragArea can drag it in free-placement mode; the background doesn't move it.
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none

        buildViews()

        Store.shared.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] s in self?.apply(s) }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self] _ in self?.rememberFloatingPosition() }
            .store(in: &bag)

        // The system Dock can grow, shrink or change auto-hide without a screen-change notification.
        Timer.publish(every: 2, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &bag)

        // Polling the pointer needs no permissions, unlike a global event monitor. Default run-loop mode means
        // it pauses while a context menu is tracking, so the dock never hides under an open menu.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.trackPointer() }
    }

    private func buildViews() {
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.layer?.cornerCurve = .continuous

        let background = NSHostingView(rootView: DockBackgroundRoot())
        background.sizingOptions = []
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.autoresizingMask = [.width, .height]
        scrollView.wantsLayer = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        container.addSubview(scrollView)

        tiles.sizingOptions = [.intrinsicContentSize]
        tiles.onIntrinsicSizeChange = { [weak self] size in self?.resize(to: size) }
        scrollView.documentView = tiles

        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)

        NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            .sink { [weak self] _ in self?.updateFades() }
            .store(in: &bag)

        panel.contentView = container
    }

    /// The display the dock is on: the main one, or the last one the pointer visited when following it.
    private var currentScreen: NSScreen?
    private var screenDwell: TimeInterval = 0

    private var screen: NSScreen? {
        if let c = currentScreen, Store.shared.settings.display == .pointer, NSScreen.screens.contains(c) { return c }
        return NSScreen.screens.first
    }

    private func screenUnderPointer() -> NSScreen? {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) }
    }

    private func move(to s: NSScreen) {
        currentScreen = s
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.reposition()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                self.panel.animator().alphaValue = 1
            }
        })
    }

    private var autoHideActive: Bool {
        let s = Store.shared.settings
        return s.autoHide && !s.floating
    }

    // MARK: Settings

    private func apply(_ s: DockSettings) {
        panel.level = s.aboveWindows ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = s.allSpaces
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            : [.managed, .ignoresCycle, .fullScreenNone]
        panel.appearance = switch s.theme {
        case .dark, .glass: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .system: nil
        }
        container.layer?.cornerRadius = DockMetrics.barRadius * s.size.scale

        if !s.visible {
            pinned = false
            setRevealed(false)
        } else if !autoHideActive {
            setRevealed(true)
        }
        DispatchQueue.main.async { self.reposition() }
    }

    /// Briefly shows an auto-hidden dock, e.g. at launch or while changing its appearance.
    func peek(for seconds: TimeInterval = 2.5) {
        guard Store.shared.settings.visible else { return }
        peekUntil = Date().addingTimeInterval(seconds)
        setRevealed(true)
    }

    /// The keyboard shortcut: with auto-hide on it pins the dock open (or releases it); otherwise it shows/hides.
    func toggleFromShortcut() {
        let s = Store.shared.settings
        if s.visible && autoHideActive {
            pinned.toggle()
            setRevealed(pinned)
        } else {
            Store.shared.settings.visible.toggle()
        }
    }

    // MARK: Hover to reveal

    private func trackPointer() {
        // SwiftUI has no drag-cancelled callback; once the button is up, any widget drag is over.
        if DockDragState.shared.dragging != nil && NSEvent.pressedMouseButtons == 0 {
            DockDragState.shared.dragging = nil
        }

        let settings = Store.shared.settings
        if settings.display == .pointer, !settings.floating, settings.visible, let ps = screenUnderPointer(), ps != screen {
            if !revealed {
                // Hidden: just remember where the pointer is so the dock reveals on that display.
                currentScreen = ps
                screenDwell = 0
            } else if !autoHideActive {
                screenDwell += 0.05
                if screenDwell >= 0.35 { screenDwell = 0; move(to: ps) }
            }
        } else {
            screenDwell = 0
        }

        guard autoHideActive, Store.shared.settings.visible, let screen, contentSize != .zero else { return }
        let m = NSEvent.mouseLocation
        let top = Store.shared.settings.position == .top
        let f = screen.frame
        let dt = 0.05

        if !revealed {
            let atEdge = f.contains(CGPoint(x: m.x, y: top ? m.y - 1 : m.y + 1)) && (top ? m.y >= f.maxY - 2 : m.y <= f.minY + 2)
            edgeDwell = atEdge ? edgeDwell + dt : 0
            if edgeDwell >= 0.1 { edgeDwell = 0; setRevealed(true) }
            return
        }

        if pinned || Date() < peekUntil || popoverOpen || isInKeepZone(m, screen: screen) {
            awayTime = 0
        } else {
            awayTime += dt
            if awayTime >= 0.45 { setRevealed(false) }
        }
    }

    /// Anywhere over the dock, between it and the screen edge (including the macOS Dock), or just around it.
    private func isInKeepZone(_ m: CGPoint, screen: NSScreen) -> Bool {
        let d = targetFrame(on: screen)
        let nearX = m.x >= d.minX - 60 && m.x <= d.maxX + 60
        if Store.shared.settings.position == .top {
            return m.y >= d.minY - 30 && (nearX || m.y >= screen.visibleFrame.maxY)
        }
        return m.y <= d.maxY + 30 && (nearX || m.y <= screen.frame.minY + macDockLift(screen))
    }

    private var popoverOpen: Bool {
        NSApp.windows.contains { $0.isVisible && NSStringFromClass(type(of: $0)).contains("Popover") }
    }

    private func setRevealed(_ show: Bool) {
        guard let screen else { return }
        if show == revealed && (show == panel.isVisible) { return }
        revealed = show
        awayTime = 0
        let target = targetFrame(on: screen)
        let slide = autoHideActive ? hiddenFrame(for: target, on: screen) : target

        if show {
            if !panel.isVisible {
                panel.setFrame(slide, display: false)
                panel.alphaValue = 0
                panel.orderFrontRegardless()
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            // Lets a video playing in the dock pop out to picture-in-picture before the dock slides away.
            NotificationCenter.default.post(name: .docksideDockDidHide, object: nil)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(slide, display: true)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, !self.revealed else { return }
                self.panel.orderOut(nil)
            })
        }
    }

    private func hiddenFrame(for target: NSRect, on screen: NSScreen) -> NSRect {
        var r = target
        r.origin.y = Store.shared.settings.position == .top ? target.minY + 24 : target.minY - 24
        return r
    }

    // MARK: Layout

    private func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0, size != contentSize else { return }
        let first = contentSize == .zero
        contentSize = size
        tiles.setFrameSize(size)
        if first {
            // Start at the first widget rather than wherever the clip view landed while sizing.
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        reposition()
    }

    /// How high an auto-hiding macOS Dock reaches when it slides in, so Dockside can sit above it.
    /// (A Dock that doesn't auto-hide is already excluded from the screen's visible frame.)
    private func macDockLift(_ screen: NSScreen) -> CGFloat {
        let app = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(app)
        let autohide = CFPreferencesCopyAppValue("autohide" as CFString, app) as? Bool ?? false
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, app) as? String ?? "bottom"
        // The macOS Dock slides in on whichever display the pointer reaches, so leave room on every display.
        guard autohide, orientation == "bottom" else { return 0 }
        let tile = CFPreferencesCopyAppValue("tilesize" as CFString, app) as? Double ?? 48
        return CGFloat(tile) + 22
    }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let s = Store.shared.settings
        let vf = screen.visibleFrame
        let w = min(contentSize.width, vf.width - 24)
        let h = contentSize.height
        var origin: CGPoint

        if s.floating, let x = s.floatingX, let y = s.floatingY {
            origin = CGPoint(x: x - w / 2, y: y)
            origin.x = min(max(origin.x, screen.frame.minX), screen.frame.maxX - w)
            origin.y = min(max(origin.y, screen.frame.minY), vf.maxY - h)
        } else if s.position == .top {
            origin = CGPoint(x: vf.midX - w / 2, y: vf.maxY - h - s.edgeMargin)
        } else {
            let lift = s.avoidMacDock ? macDockLift(screen) : 0
            origin = CGPoint(x: vf.midX - w / 2, y: max(vf.minY, screen.frame.minY + lift) + s.edgeMargin)
        }
        return NSRect(origin: origin, size: CGSize(width: w, height: h)).integral
    }

    func reposition() {
        guard contentSize != .zero, let screen else { return }
        lastVisibleFrame = screen.visibleFrame
        let frame = targetFrame(on: screen)
        updateFades(width: frame.width)
        // While auto-hidden, the frame is applied when the dock slides in.
        guard revealed, frame != panel.frame else { return }
        isPositioning = true
        panel.setFrame(frame, display: true)
        isPositioning = false
        panel.invalidateShadow()
    }

    /// Fades whichever edge has more tiles scrolled out of view.
    private func updateFades(width: CGFloat? = nil) {
        let visible = width ?? scrollView.bounds.width
        let x = scrollView.contentView.bounds.origin.x
        let overflow = contentSize.width - visible
        guard overflow > 1, visible > 0 else {
            scrollView.layer?.mask = nil
            return
        }
        let fade = min(0.12, 36 / visible)
        let left: CGFloat = x > 1 ? 0 : 1
        let right: CGFloat = x < overflow - 1 ? 0 : 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = CGRect(origin: .zero, size: CGSize(width: visible, height: contentSize.height))
        fadeMask.colors = [NSColor.black.withAlphaComponent(left).cgColor, NSColor.black.cgColor,
                           NSColor.black.cgColor, NSColor.black.withAlphaComponent(right).cgColor]
        fadeMask.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
        scrollView.layer?.mask = fadeMask
        CATransaction.commit()
    }

    private func rememberFloatingPosition() {
        guard !isPositioning, Store.shared.settings.floating else { return }
        let f = panel.frame
        Store.shared.settings.floatingX = f.midX
        Store.shared.settings.floatingY = f.minY
    }
}
