import AppKit
import Combine
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private(set) var panel: KKPanel?
    private var screen: NSScreen?
    private let preferences: Preferences
    private var preferenceSubscription: AnyCancellable?
    private var lastPopupSize: PopupSize
    private var hasExpanded = false
    private var minimumContentHeight: CGFloat = 64
    private var frameAnimation: Task<Void, Never>?
    private var animationTarget: NSRect?
    private let alignmentGuides = PanelAlignmentGuides()
    private(set) var isDragging = false
    private(set) var currentSnap: PanelSnapResult?
    private var dragScreen: NSScreen?
    var onDismiss: (() -> Void)?
    var annotationLayerActive = false {
        didSet { applyWindowAppearance() }
    }
    private(set) var hasUserResized = false

    var isVisible: Bool { panel?.isVisible == true }
    var isAnimatingLayout: Bool { frameAnimation != nil }
    var alignmentGuidesVisible: Bool { alignmentGuides.panel?.isVisible == true }
    static let expansionDuration: TimeInterval = 0.28

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        lastPopupSize = preferences.popupSize
        super.init()
        preferenceSubscription = preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applyPreferences() }
    }

    func show(rootView: AnyView, on screen: NSScreen, cursorLocation: NSPoint? = nil) {
        endDrag(restoreLayout: false)
        stopFrameAnimation()
        self.screen = screen
        hasUserResized = false
        hasExpanded = false
        minimumContentHeight = preferences.popupSize == .compact ? 56 : 121
        lastPopupSize = preferences.popupSize

        let panel = panel ?? makePanel()
        applyWindowAppearance()
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        let compact = preferences.popupSize == .compact
        panel.setFrame(PanelPositioning.initialFrame(
            on: screen,
            contentHeight: compact ? 56 : 121,
            contentWidth: compact ? UIConstants.compactPanelWidth : UIConstants.panelWidth,
            position: preferences.popupOpeningPosition,
            cursor: cursorLocation ?? NSEvent.mouseLocation
        ), display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        endDrag(restoreLayout: false)
        stopFrameAnimation()
        panel?.orderOut(nil)
    }

    /// Content can raise the minimum height, but only the first question expands compact mode.
    /// Token-by-token rendering therefore never restarts the expansion animation.
    func updateLayout(hasResponse: Bool, minimumHeight: CGFloat) {
        hasExpanded = hasExpanded || hasResponse
        minimumContentHeight = minimumHeight
        guard !isDragging else { return }
        guard let panel, let screen = panel.screen ?? screen else { return }
        panel.minSize.height = min(minimumHeight, screen.visibleFrame.height - 32)
        if hasUserResized {
            resize(height: panel.frame.height, minimumHeight: minimumHeight, animated: false)
            return
        }
        let fullSize = preferences.popupSize == .fullSize || hasExpanded
        let base = isAnimatingLayout ? (animationTarget ?? panel.frame) : panel.frame
        let width = fullSize ? UIConstants.panelWidth : UIConstants.compactPanelWidth
        let height = hasExpanded ? max(minimumHeight, UIConstants.panelMaxHeight) : minimumHeight
        let frame = NSRect(x: base.midX - width / 2, y: base.maxY - height, width: width, height: height)
        setFrame(PanelPositioning.clamped(frame, to: screen), animated: panel.isVisible)
    }

    func resize(height: CGFloat, minimumHeight: CGFloat = 200, animated: Bool = true) {
        guard let panel, let screen = panel.screen ?? screen else { return }
        let minimum = min(minimumHeight, screen.visibleFrame.height - 32)
        panel.minSize.height = minimum
        guard !hasUserResized || panel.frame.height < minimum else { return }
        let targetHeight = hasUserResized ? minimum : max(minimum, min(height, UIConstants.panelMaxHeight))
        var frame = panel.frame
        frame.origin.y = frame.maxY - targetHeight
        frame.size.height = targetHeight
        setFrame(PanelPositioning.clamped(frame, to: screen), animated: animated)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        endDrag(restoreLayout: false)
        stopFrameAnimation()
        hasUserResized = true
    }

    func windowDidMove(_ notification: Notification) {
        screen = panel?.screen ?? screen
    }

    func beginDrag() {
        stopFrameAnimation()
        isDragging = true
        currentSnap = nil
        dragScreen = nil
    }

    func drag(to proposedFrame: NSRect, cursor: NSPoint) {
        guard isDragging, let panel else { return }
        let activeScreen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? panel.screen ?? screen
        guard let activeScreen else { return }
        if dragScreen?.frame != activeScreen.frame { currentSnap = nil }
        dragScreen = activeScreen
        screen = activeScreen
        if preferences.snapToDefaultPosition {
            let result = PanelPositioning.snapping(proposedFrame, in: activeScreen.visibleFrame, previous: currentSnap)
            currentSnap = result
            panel.setFrame(result.frame, display: false)
            alignmentGuides.show(for: result, on: activeScreen, above: panel)
        } else {
            currentSnap = nil
            alignmentGuides.hide()
            panel.setFrame(proposedFrame, display: false)
        }
    }

    func endDrag(restoreLayout: Bool = true) {
        let wasDragging = isDragging
        isDragging = false
        currentSnap = nil
        dragScreen = nil
        alignmentGuides.hide()
        if wasDragging && restoreLayout && isVisible {
            updateLayout(hasResponse: hasExpanded, minimumHeight: minimumContentHeight)
        }
    }

    private func applyPreferences() {
        applyWindowAppearance()
        if !preferences.snapToDefaultPosition {
            currentSnap = nil
            alignmentGuides.hide()
        }
        if preferences.popupSize != lastPopupSize {
            lastPopupSize = preferences.popupSize
            hasUserResized = false
        }
        guard isVisible else { return }
        updateLayout(hasResponse: hasExpanded, minimumHeight: minimumContentHeight)
    }

    private func applyWindowAppearance() {
        panel?.appearance = preferences.appearance.nsAppearance
        // Setting isFloatingPanel can reset AppKit's window level, so apply the explicit level last.
        panel?.isFloatingPanel = annotationLayerActive || preferences.alwaysOnTop
        panel?.level = annotationLayerActive ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2) : (preferences.alwaysOnTop ? .floating : .normal)
    }

    private func setFrame(_ target: NSRect, animated: Bool) {
        guard let panel else { return }
        let target = target.integral
        if isAnimatingLayout, animationTarget == target { return }
        if !isAnimatingLayout, panel.frame == target { return }
        stopFrameAnimation()
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(target, display: true)
            return
        }
        let startFrame = panel.frame
        animationTarget = target
        // Drive the actual window frame, including its hosting view, on the main actor.
        // A cancellable transition also prevents an old expansion from resizing a reopened popup.
        frameAnimation = Task { @MainActor [weak self, weak panel] in
            let clock = ContinuousClock()
            let start = clock.now
            while !Task.isCancelled {
                let elapsed = start.duration(to: clock.now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                let progress = min(1, seconds / Self.expansionDuration)
                let eased = CGFloat(progress * progress * (3 - 2 * progress))
                let frame = NSRect(
                    x: startFrame.minX + (target.minX - startFrame.minX) * eased,
                    y: startFrame.minY + (target.minY - startFrame.minY) * eased,
                    width: startFrame.width + (target.width - startFrame.width) * eased,
                    height: startFrame.height + (target.height - startFrame.height) * eased
                )
                panel?.setFrame(frame, display: progress >= 1)
                if progress >= 1 { break }
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            self?.frameAnimation = nil
            self?.animationTarget = nil
        }
    }

    private func stopFrameAnimation() {
        frameAnimation?.cancel()
        frameAnimation = nil
        animationTarget = nil
    }

    private func makePanel() -> KKPanel {
        let panel = KKPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.isMovable = true
        panel.minSize = NSSize(width: 440, height: 56)
        panel.delegate = self
        panel.hidesOnDeactivate = false
        panel.onEscape = { [weak self] in self?.onDismiss?() }
        panel.onBeginDrag = { [weak self] in self?.beginDrag() }
        panel.onDragFrame = { [weak self] frame, cursor in self?.drag(to: frame, cursor: cursor) }
        panel.onEndDrag = { [weak self] in self?.endDrag() }
        self.panel = panel
        return panel
    }
}
