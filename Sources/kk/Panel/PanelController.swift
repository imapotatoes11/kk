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
    private var responseContentHeight: CGFloat?
    private var responseWidth: CGFloat?
    private var responseStreaming = false
    private var layoutUpdate: Task<Void, Never>?
    private var lastOpeningWidth: CGFloat = 0
    private var minimumContentHeight: CGFloat = 64
    private var frameAnimation: Task<Void, Never>?
    private var animationTarget: NSRect?
    private let alignmentGuides = PanelAlignmentGuides()
    private(set) var isDragging = false
    private(set) var currentSnap: PanelSnapResult?
    private var dragScreen: NSScreen?
    private var blankSpace: NSRect?
    private var placementTask: Task<Void, Never>?
    private var placementID = UUID()
    private let placementCapture: @Sendable (CGDirectDisplayID?) async throws -> CGImage
    var onDismiss: (() -> Void)?
    var annotationLayerActive = false {
        didSet { applyWindowAppearance() }
    }
    private(set) var hasUserResized = false

    var isVisible: Bool { panel?.isVisible == true }
    var isAnimatingLayout: Bool { frameAnimation != nil }
    var alignmentGuidesVisible: Bool { alignmentGuides.panel?.isVisible == true }
    static let expansionDuration: TimeInterval = 0.28

    init(preferences: Preferences = Preferences(), placementCapture: @escaping @Sendable (CGDirectDisplayID?) async throws -> CGImage = { try await ScreenCaptureService().capturePlacementImage(displayID: $0) }) {
        self.preferences = preferences
        self.placementCapture = placementCapture
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
        responseContentHeight = nil
        responseWidth = nil
        responseStreaming = false
        blankSpace = nil
        lastOpeningWidth = preferences.openingWidth
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
            contentWidth: preferences.openingWidth,
            position: preferences.popupOpeningPosition,
            cursor: cursorLocation ?? NSEvent.mouseLocation
        ), display: false)
        panel.minSize.width = min(preferences.openingWidth, screen.visibleFrame.width - 32)
        panel.maxSize = NSSize(width: max(UIConstants.panelWidth, preferences.openingWidth), height: UIConstants.panelMaxHeight)
        panel.focusPrompt()
        NSApp.activate(ignoringOtherApps: true)
        moveToBlankSpace()
    }

    func hide() {
        cancelPlacement()
        blankSpace = nil
        endDrag(restoreLayout: false)
        stopFrameAnimation()
        panel?.orderOut(nil)
    }

    /// Re-scan only on explicit open/send events, never on streaming tokens.
    func moveToBlankSpace() {
        cancelPlacement()
        guard preferences.placeInBlankSpace, let panel, panel.isVisible,
              let screen = panel.screen ?? screen else { return }
        let displayID = DisplayResolver.displayID(for: screen)
        let screenFrame = screen.frame, visibleFrame = screen.visibleFrame
        let preferred = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let id = placementID
        placementTask = Task { @MainActor [weak self, placementCapture] in
            do {
                let image = try await placementCapture(displayID)
                try Task.checkCancellation()
                let space = await Task.detached(priority: .userInitiated) {
                    BlankSpaceFinder.find(in: image, screenFrame: screenFrame, visibleFrame: visibleFrame, near: preferred)
                }.value
                try Task.checkCancellation()
                guard let self, self.placementID == id, self.preferences.placeInBlankSpace,
                      self.isVisible, !self.isDragging,
                      let currentScreen = self.panel?.screen,
                      DisplayResolver.displayID(for: currentScreen) == displayID,
                      currentScreen.frame == screenFrame, currentScreen.visibleFrame == visibleFrame else { return }
                self.placementTask = nil
                self.stopFrameAnimation()
                self.blankSpace = space
                self.hasUserResized = false
                self.applyLayout()
            } catch {
                // Placement is optional. Permission/capture failures must not interrupt chat.
                guard let self, self.placementID == id else { return }
                self.placementTask = nil
            }
        }
    }

    private func cancelPlacement() {
        placementID = UUID()
        placementTask?.cancel()
        placementTask = nil
    }

    /// Measurements coalesce while streaming. An active transition always finishes before
    /// applying a newer target, rather than restarting at every token or intermediate frame.
    func updateLayout(hasResponse: Bool, minimumHeight: CGFloat, contentHeight: CGFloat? = nil, preferredWidth: CGFloat? = nil, streaming: Bool = false) {
        hasExpanded = hasExpanded || hasResponse
        minimumContentHeight = minimumHeight
        if let contentHeight { responseContentHeight = contentHeight }
        if let preferredWidth { responseWidth = preferredWidth }
        responseStreaming = streaming
        if hasResponse && contentHeight != nil {
            guard layoutUpdate == nil else { return }
            layoutUpdate = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled, let self else { return }
                self.layoutUpdate = nil
                self.applyLayout()
            }
        } else { applyLayout() }
    }

    private func applyLayout() {
        guard !isDragging, let panel, let screen = panel.screen ?? screen else { return }
        let openingWidth = min(preferences.openingWidth, screen.visibleFrame.width - 32)
        let minHeight = min(minimumContentHeight, UIConstants.panelMaxHeight, screen.visibleFrame.height - 32)
        let adaptive = preferences.placeInBlankSpace ? blankSpace : nil
        let minimumWidth = preferences.placeInBlankSpace ? min(320, openingWidth) : openingWidth
        panel.minSize = NSSize(width: minimumWidth, height: minHeight)
        panel.maxSize = NSSize(width: min(max(UIConstants.panelWidth, openingWidth), screen.visibleFrame.width - 32), height: min(UIConstants.panelMaxHeight, screen.visibleFrame.height - 32))
        if let adaptive, !hasUserResized {
            guard !isAnimatingLayout else { return }
            let desired = NSSize(width: hasExpanded ? (responseWidth ?? panel.maxSize.width) : openingWidth,
                height: hasExpanded ? (responseContentHeight ?? panel.maxSize.height) : minHeight)
            let frame = BlankSpaceFinder.fittedFrame(in: adaptive,
                desired: NSSize(width: min(openingWidth, desired.width), height: min(panel.maxSize.height, desired.height)),
                minimum: panel.minSize, visible: screen.visibleFrame)
            setFrame(frame, animated: panel.isVisible)
            return
        }
        if hasUserResized {
            var frame = panel.frame
            frame.size.width = min(panel.maxSize.width, max(minimumWidth, frame.width))
            frame.size.height = min(panel.maxSize.height, max(minHeight, frame.height))
            frame.origin.y = panel.frame.maxY - frame.height
            setFrame(PanelPositioning.clamped(frame, to: screen), animated: false)
            return
        }
        guard !isAnimatingLayout else { return }
        var width = hasExpanded ? (responseWidth ?? max(UIConstants.panelWidth, openingWidth)) : openingWidth
        var height = hasExpanded ? (responseContentHeight ?? UIConstants.panelMaxHeight) : minHeight
        width = min(panel.maxSize.width, max(openingWidth, width))
        height = min(panel.maxSize.height, max(minHeight, height))
        if hasExpanded && responseStreaming {
            width = max(width, panel.frame.width)
            height = max(height, panel.frame.height)
        }
        let frame = NSRect(x: panel.frame.midX - width / 2, y: panel.frame.maxY - height, width: width, height: height)
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
        cancelPlacement()
        blankSpace = nil
        endDrag(restoreLayout: false)
        stopFrameAnimation()
        hasUserResized = true
    }

    func windowDidMove(_ notification: Notification) {
        if let activeScreen = panel?.screen, activeScreen != screen {
            cancelPlacement()
            blankSpace = nil
        }
        screen = panel?.screen ?? screen
    }

    func beginDrag() {
        if blankSpace != nil { hasUserResized = true }
        cancelPlacement()
        blankSpace = nil
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
            applyLayout()
        }
    }

    private func applyPreferences() {
        applyWindowAppearance()
        if !preferences.placeInBlankSpace {
            cancelPlacement()
            blankSpace = nil
        }
        if !preferences.snapToDefaultPosition {
            currentSnap = nil
            alignmentGuides.hide()
        }
        if preferences.popupSize != lastPopupSize || preferences.openingWidth != lastOpeningWidth {
            lastOpeningWidth = preferences.openingWidth
            lastPopupSize = preferences.popupSize
            hasUserResized = false
        }
        guard isVisible else { return }
        applyLayout()
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
            self?.applyLayout()
        }
    }

    private func stopFrameAnimation() {
        layoutUpdate?.cancel()
        layoutUpdate = nil
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
