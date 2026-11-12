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
    private(set) var expandsToFit = false
    private var expansionAnchor: NSRect?
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
    /// The latest blank-space scan: quiet cells, where kk may go, and the chosen spot.
    private struct BlankPlacement: Sendable {
        let map: BlankMap
        let region: CGRect
        let base: CGRect
    }
    private var blankPlacement: BlankPlacement?
    var hasBlankPlacement: Bool { blankPlacement != nil }
    /// The window the user was working in when kk opened. Blank-space placement avoids it.
    var avoidedWindowFrame: CGRect?
    private var placementTask: Task<Void, Never>?
    private var placementID = UUID()
    private let placementCapture: @Sendable (CGDirectDisplayID?) async throws -> CGImage
    var onDismiss: (() -> Void)?
    var annotationLayerActive = false {
        didSet { applyWindowAppearance(); if isVisible { applyLayout() } }
    }
    private(set) var hasUserResized = false

    var isVisible: Bool { panel?.isVisible == true }
    var isAnimatingLayout: Bool { frameAnimation != nil }
    var alignmentGuidesVisible: Bool { alignmentGuides.panel?.isVisible == true }
    static let expansionDuration: TimeInterval = 0.28
    /// The narrowest kk gets, by manual resizing or blank-space placement.
    static let minimumWidth: CGFloat = 360
    /// The shortest a chat with answers gets, so the answer and composer stay usable.
    static let minimumChatHeight: CGFloat = 220
    /// The smallest usable size for the current content. Kept here because the hosting view's
    /// layout resets the window's own `minSize`.
    private(set) var minimumSize = NSSize(width: minimumWidth, height: 56)

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
        expandsToFit = false
        expansionAnchor = nil
        hasExpanded = false
        responseContentHeight = nil
        responseWidth = nil
        responseStreaming = false
        blankPlacement = nil
        lastOpeningWidth = preferences.openingWidth
        minimumContentHeight = preferences.popupSize == .compact ? 56 : 121
        lastPopupSize = preferences.popupSize

        let panel = panel ?? makePanel()
        applyWindowAppearance()
        let hostingView = PanelHostingView(rootView: rootView)
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
        minimumSize = NSSize(width: panel.minSize.width, height: minimumContentHeight)
        panel.maxSize = NSSize(width: max(UIConstants.panelWidth, preferences.openingWidth), height: UIConstants.panelMaxHeight)
        panel.focusPrompt()
        NSApp.activate(ignoringOtherApps: true)
        moveToBlankSpace()
    }

    func hide() {
        cancelPlacement()
        blankPlacement = nil
        endDrag(restoreLayout: false)
        stopFrameAnimation()
        panel?.orderOut(nil)
    }

    /// Re-scan only on explicit open/send events, never on streaming tokens.
    func moveToBlankSpace() {
        cancelPlacement()
        // A size or position the user chose by hand stays put for follow-up questions.
        guard !hasUserResized else { return }
        guard preferences.placeInBlankSpace, let panel, panel.isVisible,
              let screen = panel.screen ?? screen else { return }
        let displayID = DisplayResolver.displayID(for: screen)
        let screenFrame = screen.frame, visibleFrame = screen.visibleFrame
        let safeBounds = automaticBounds(on: screen)
        let preferred = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let avoided = avoidedWindowFrame
        let width = min(preferences.openingWidth, visibleFrame.width - 32)
        let minimum = CGSize(width: min(Self.minimumWidth, width), height: Self.minimumChatHeight)
        let id = placementID
        placementTask = Task { @MainActor [weak self, placementCapture] in
            do {
                let image = try await placementCapture(displayID)
                try Task.checkCancellation()
                let placement = await Task.detached(priority: .userInitiated) { () -> BlankPlacement? in
                    guard let map = BlankSpaceFinder.map(from: image, screenFrame: screenFrame, visibleFrame: visibleFrame) else { return nil }
                    let region = BlankSpaceFinder.allowedRegion(in: map.bounds.intersection(safeBounds), avoiding: avoided,
                        minimum: minimum)
                    // Score a typical chat height, so the spot also has room to grow after sending.
                    let probe = BlankSpaceFinder.placement(of: CGSize(width: width, height: min(region.height, 360)),
                        in: map, region: region, avoiding: avoided, near: preferred)
                    return BlankPlacement(map: map, region: region, base: probe)
                }.value
                try Task.checkCancellation()
                guard let self, self.placementID == id, self.preferences.placeInBlankSpace,
                      self.isVisible, !self.isDragging,
                      let currentScreen = self.panel?.screen,
                      DisplayResolver.displayID(for: currentScreen) == displayID,
                      currentScreen.frame == screenFrame, currentScreen.visibleFrame == visibleFrame else { return }
                self.placementTask = nil
                self.stopFrameAnimation()
                self.blankPlacement = placement
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

    private func automaticBounds(on screen: NSScreen) -> NSRect {
        PanelPositioning.automaticBounds(in: screen.visibleFrame,
            palette: annotationLayerActive ? preferences.palettePosition : nil,
            paletteWidth: preferences.openingWidth,
            contentSize: NSSize(width: responseWidth ?? preferences.openingWidth, height: responseContentHeight ?? minimumContentHeight))
    }

    func expandToFit() {
        guard let panel, panel.isVisible else { return }
        stopFrameAnimation()
        hasUserResized = false
        expandsToFit = true
        expansionAnchor = panel.frame
        applyLayout()
    }

    private func applyLayout() {
        guard !isDragging, let panel, let screen = panel.screen ?? screen else { return }
        let bounds = automaticBounds(on: screen)
        let openingWidth = min(preferences.openingWidth, bounds.width)
        let minHeight = min(max(minimumContentHeight, hasExpanded ? Self.minimumChatHeight : 0), UIConstants.panelMaxHeight, bounds.height)
        let adaptive = preferences.placeInBlankSpace ? blankPlacement : nil
        let expansionWidth = min(bounds.width, floor(screen.frame.width * CGFloat(preferences.expandWidthPercent) / 100))
        let minimumWidth = expandsToFit ? min(openingWidth, expansionWidth)
            : (preferences.placeInBlankSpace ? min(Self.minimumWidth, openingWidth) : openingWidth)
        minimumSize = NSSize(width: minimumWidth, height: minHeight)
        panel.minSize = minimumSize
        let maximumHeight = expandsToFit || preferences.placeInBlankSpace ? bounds.height : min(UIConstants.panelMaxHeight, bounds.height)
        panel.maxSize = NSSize(width: min(max(UIConstants.panelWidth, openingWidth), screen.visibleFrame.width - 32), height: maximumHeight)
        if expandsToFit {
            guard !isAnimatingLayout else { return }
            panel.maxSize = NSSize(width: expansionWidth, height: bounds.height)
            let size = NSSize(width: min(expansionWidth, max(openingWidth, responseWidth ?? openingWidth)),
                              height: min(bounds.height, max(minHeight, responseContentHeight ?? minHeight)))
            let anchor = expansionAnchor ?? panel.frame
            var frame = PanelPositioning.fitted(anchor, size: size, in: bounds)
            if let adaptive {
                // Keep the requested size, but score every direction across the display.
                frame = BlankSpaceFinder.placement(of: size, in: adaptive.map, region: bounds,
                    avoiding: avoidedWindowFrame, near: NSPoint(x: anchor.midX, y: anchor.midY))
                frame = PanelPositioning.fitted(frame, size: size, in: bounds)
            }
            // Integralizing a half-point origin can otherwise add a point to the width.
            frame.origin.x = floor(frame.minX)
            frame.size.width = floor(frame.width)
            setFrame(frame, animated: panel.isVisible)
            return
        }
        if let adaptive, !hasUserResized {
            guard !isAnimatingLayout else { return }
            // Quiet space is a ceiling, not an instruction to consume it before
            // the response needs it. Grow from its top as measured text arrives.
            var frame = CGRect(x: adaptive.base.minX, y: adaptive.base.maxY - minHeight, width: adaptive.base.width, height: minHeight)
            if hasExpanded {
                let available = BlankSpaceFinder.expanded(frame, in: adaptive.map, region: adaptive.region, minimumHeight: minHeight)
                var height = max(minHeight, responseContentHeight ?? minHeight)
                if responseStreaming { height = max(height, panel.frame.height) }
                let area = adaptive.region.intersection(adaptive.map.bounds)
                frame = BlankSpaceFinder.fitted(available, height: min(height, maximumHeight),
                    within: area.isNull ? adaptive.map.bounds : area)
            }
            setFrame(PanelPositioning.fitted(frame, size: frame.size, in: bounds), animated: panel.isVisible)
            return
        }
        if hasUserResized {
            panel.maxSize = screen.visibleFrame.size
            if panel.frame.height < minHeight {
                var frame = panel.frame
                frame.origin.y = frame.maxY - minHeight
                frame.size.height = minHeight
                setFrame(frame, animated: false)
            }
            return
        }
        guard !isAnimatingLayout else { return }
        var width = hasExpanded ? (responseWidth ?? max(UIConstants.panelWidth, openingWidth)) : openingWidth
        var height = hasExpanded ? (responseContentHeight ?? minHeight) : minHeight
        width = min(panel.maxSize.width, max(openingWidth, width))
        height = min(panel.maxSize.height, max(minHeight, height))
        if hasExpanded && responseStreaming {
            width = max(width, panel.frame.width)
            height = max(height, panel.frame.height)
        }
        let frame = NSRect(x: panel.frame.midX - width / 2, y: panel.frame.maxY - height, width: width, height: height)
        setFrame(PanelPositioning.fitted(frame, size: frame.size, in: bounds), animated: panel.isVisible)
    }

    func resize(height: CGFloat, minimumHeight: CGFloat = 200, animated: Bool = true) {
        guard let panel, let screen = panel.screen ?? screen else { return }
        let bounds = automaticBounds(on: screen)
        let minimum = min(minimumHeight, bounds.height)
        panel.minSize.height = minimum
        minimumSize.height = minimum
        guard !hasUserResized || panel.frame.height < minimum else { return }
        let targetHeight = hasUserResized ? minimum : max(minimum, min(height, UIConstants.panelMaxHeight))
        var frame = panel.frame
        frame.origin.y = frame.maxY - targetHeight
        frame.size.height = targetHeight
        setFrame(PanelPositioning.fitted(frame, size: frame.size, in: bounds), animated: animated)
    }

    /// Clamps every manual resize step to the size the current content needs. The window's own
    /// `minSize` can't be relied on: SwiftUI's hosting view resets it during layout.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, minimumSize.width), height: max(frameSize.height, minimumSize.height))
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        cancelPlacement()
        blankPlacement = nil
        endDrag(restoreLayout: false)
        stopFrameAnimation()
        hasUserResized = true
        expandsToFit = false
        panel?.maxSize = (panel?.screen ?? screen)?.visibleFrame.size ?? NSSize(width: 10000, height: 10000)
    }

    func windowDidMove(_ notification: Notification) {
        if let activeScreen = panel?.screen, activeScreen != screen {
            cancelPlacement()
            blankPlacement = nil
        }
        screen = panel?.screen ?? screen
    }

    func beginDrag() {
        if blankPlacement != nil || expandsToFit { hasUserResized = true }
        expandsToFit = false
        cancelPlacement()
        blankPlacement = nil
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
            blankPlacement = nil
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
        panel.onExpandShortcut = { [weak self] event in
            guard let self, self.preferences.windowBindings["expand"]?.matches(event) == true else { return false }
            self.expandToFit()
            return true
        }
        panel.onEscape = { [weak self] in self?.onDismiss?() }
        panel.onBeginDrag = { [weak self] in self?.beginDrag() }
        panel.onDragFrame = { [weak self] frame, cursor in self?.drag(to: frame, cursor: cursor) }
        panel.onEndDrag = { [weak self] in self?.endDrag() }
        self.panel = panel
        return panel
    }
}
