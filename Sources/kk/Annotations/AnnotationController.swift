import AppKit
import Combine
import SwiftUI

@MainActor
final class AnnotationController {
    let document = AnnotationDocument()
    let colorPicker = AnnotationColorPanel()
    private let preferences: Preferences
    private let capture: @Sendable (CGDirectDisplayID?) async throws -> ScreenSnapshot
    private(set) var canvasPanel: NSPanel?
    private(set) var toolbarPanel: NSPanel?
    private var canvas: AnnotationCanvasView?
    private var subscriptions: Set<AnyCancellable> = []
    private var keyMonitor: Any?
    weak var textPanel: NSPanel?
    private var shiftDetector = DoubleShiftDetector()
    private var screenObserver: AnyCancellable?
    private var screen: NSScreen?
    private var frozenImage: CGImage?
    private var sessionID = UUID()
    private var freeze = false
    private var suspended = false
    private(set) var isActive = false
    var onActiveChange: ((Bool) -> Void)?
    var onFocusPopup: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onEmptyCanvasClick: (() -> Bool)?

    init(preferences: Preferences, captureService: ScreenCaptureService = ScreenCaptureService(),
         capture: (@Sendable (CGDirectDisplayID?) async throws -> ScreenSnapshot)? = nil) {
        self.preferences = preferences
        self.capture = capture ?? { displayID in try await captureService.captureSnapshot(displayID: displayID) }
    }

    func begin(on screen: NSScreen) {
        end()
        guard preferences.annotationsEnabled else { return }
        self.screen = screen
        freeze = preferences.freezeScreen
        document.isDrawing = preferences.annotationTool != .pointer
        isActive = true
        onActiveChange?(true)
        screenObserver = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                // A changed display geometry would misalign the marks and captured pixels.
                self?.onDismiss?()
            }
    }

    func receiveCapture(_ snapshot: ScreenSnapshot) {
        guard isActive, let screen else { return }
        // Keep the very first successful capture as the frozen backdrop.
        guard canvasPanel == nil else { return }
        document.isDrawing = preferences.annotationTool != .pointer
        if freeze { frozenImage = snapshot.image }
        document.isFrozen = freeze
        let canvas = AnnotationCanvasView(document: document, preferences: preferences)
        canvas.frozenImage = frozenImage
        canvas.onEmptyClick = { [weak self] in self?.onEmptyCanvasClick?() ?? false }
        let overlay = AnnotationPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // A nearly transparent fill keeps WindowServer hit testing active in live mode.
        overlay.backgroundColor = NSColor.black.withAlphaComponent(0.002)
        canvas.onFocus = { [weak overlay, weak canvas] in overlay?.makeKey(); if let canvas { overlay?.makeFirstResponder(canvas) } }
        overlay.onEscape = { [weak self] in self?.onDismiss?() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
            guard let self, self.isActive, !self.suspended, !self.document.isPreparing else { return event }
            guard let eventWindow = event.window ?? NSApp.keyWindow else { self.shiftDetector.reset(); return event }
            guard eventWindow === self.textPanel || eventWindow === self.canvasPanel || eventWindow === self.toolbarPanel else { self.shiftDetector.reset(); return event }
            if event.type == .leftMouseDown { self.shiftDetector.reset(); return event }
            if event.type == .flagsChanged {
                guard eventWindow === self.textPanel, self.preferences.annotationReturnKey == .doubleShift,
                      [56, 60].contains(event.keyCode) else { self.shiftDetector.reset(); return event }
                let flags = event.modifierFlags.intersection(AnnotationShortcut.modifierMask)
                if self.shiftDetector.changed(isDown: flags.contains(.shift), onlyShift: flags.subtracting(.shift).isEmpty, time: event.timestamp) {
                    self.focusDrawing(); return nil
                }
                return event
            }
            self.shiftDetector.reset()
            if eventWindow === self.textPanel {
                if self.preferences.annotationReturnKey == .shortcut,
                   self.preferences.annotationBindings["annotate"]?.matches(event) == true {
                    self.focusDrawing(); return nil
                }
                return event
            }
            if event.keyCode == 53 { self.onDismiss?(); return nil }
            if self.preferences.annotationBindings["focus"]?.matches(event) == true { self.onFocusPopup?(); return nil }
            if self.handleToolShortcut(event) { return nil }
            return event
        }
        overlay.acceptsMouseMovedEvents = true
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.hidesOnDeactivate = false
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlay.isReleasedWhenClosed = false
        overlay.contentView = canvas
        self.canvas = canvas
        canvasPanel = overlay
        overlay.ignoresMouseEvents = !document.isDrawing

        let toolbar = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toolbar.backgroundColor = .clear
        toolbar.isOpaque = false
        toolbar.hasShadow = true
        toolbar.hidesOnDeactivate = false
        toolbar.isFloatingPanel = true
        toolbar.becomesKeyOnlyIfNeeded = true
        toolbar.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        toolbar.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        toolbar.isReleasedWhenClosed = false
        let root = AnnotationToolbar(document: document, preferences: preferences, onFocus: { [weak self] in self?.onFocusPopup?() }, onClear: { [weak self] in self?.clearWithConfirmation() }, colorPicker: colorPicker)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        toolbar.contentView = host
        let width: CGFloat = min(textPanel?.frame.width ?? 480, screen.visibleFrame.width - 32)
        toolbar.setFrame(preferences.palettePosition.frame(in: screen.visibleFrame, size: NSSize(width: width, height: 56), popup: textPanel?.frame), display: false)
        toolbarPanel = toolbar
        colorPicker.popup = textPanel
        document.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            guard let self else { return }
            self.canvasPanel?.ignoresMouseEvents = !self.document.isDrawing || self.document.isPreparing
            self.canvas?.needsDisplay = true
        }.store(in: &subscriptions)
        preferences.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            self?.toolbarPanel?.appearance = self?.preferences.appearance.nsAppearance
            self?.updatePalettePosition()
        }.store(in: &subscriptions)
        preferences.$annotationTool.dropFirst().receive(on: RunLoop.main).sink { [weak self] tool in
            guard let self else { return }
            self.document.finish()
            self.document.isDrawing = tool != .pointer
            self.canvasPanel?.ignoresMouseEvents = !self.document.isDrawing || self.document.isPreparing
        }.store(in: &subscriptions)
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] event in
                guard let self, let window = event.object as? NSWindow, window === self.textPanel else { return }
                self.updatePalettePosition()
            }.store(in: &subscriptions)
        }
        toolbar.appearance = preferences.appearance.nsAppearance
        if !suspended {
            overlay.orderFrontRegardless()
            toolbar.orderFrontRegardless()
            onFocusPopup?()
        }
    }

    func updatePalettePosition() {
        guard let toolbarPanel, let screen else { return }
        let targetScreen = preferences.palettePosition == .popup ? (textPanel?.screen ?? screen) : screen
        let size = NSSize(width: min(textPanel?.frame.width ?? 480, targetScreen.visibleFrame.width - 32), height: 56)
        toolbarPanel.setFrame(preferences.palettePosition.frame(in: targetScreen.visibleFrame, size: size, popup: textPanel?.frame), display: false)
        colorPicker.updatePosition()
    }

    @discardableResult
    func handleToolShortcut(_ event: NSEvent) -> Bool {
        let window = event.window ?? NSApp.keyWindow
        guard isActive, !suspended, !document.isPreparing,
              window === canvasPanel || window === toolbarPanel else { return false }
        if preferences.annotationBindings["pointer"]?.matches(event) == true { selectPointer(); return true }
        if let tool = AnnotationTool.drawingTools.first(where: { preferences.annotationBindings[$0.rawValue]?.matches(event) == true }) {
            document.finish(); preferences.annotationTool = tool; document.isDrawing = true
            return true
        }
        return false
    }

    func selectPointer() {
        document.finish()
        document.isDrawing = false
        canvasPanel?.ignoresMouseEvents = true
        NSCursor.arrow.set()
    }

    func focusDrawing() {
        guard isActive, !suspended, !document.isPreparing, let canvasPanel, let canvas else { return }
        if preferences.annotationTool == .pointer { preferences.annotationTool = .freehand }
        document.isDrawing = true
        canvasPanel.ignoresMouseEvents = false
        canvasPanel.makeKey()
        canvasPanel.makeFirstResponder(canvas)
        canvas.needsDisplay = true
    }

    func suspend() {
        colorPicker.close()
        shiftDetector.reset()
        suspended = true
        document.finish()
        canvasPanel?.orderOut(nil)
        toolbarPanel?.orderOut(nil)
    }

    func resume() {
        suspended = false
        guard isActive else { return }
        canvasPanel?.orderFrontRegardless()
        toolbarPanel?.orderFrontRegardless()
        onFocusPopup?()
    }

    func previewImage(fallback: Data) -> Data {
        guard isActive, let screen,
              let image = frozenImage ?? ImageProcessor.cgImage(from: fallback),
              let composed = try? AnnotationRenderer.composite(document.visibleAnnotations, onto: image, canvasSize: screen.frame.size),
              let data = try? ImageProcessor.jpegData(from: composed) else { return fallback }
        return data
    }

    func prepareImage(fallback: Data) async throws -> Data {
        guard isActive, let screen else { return fallback }
        document.finish()
        document.isPreparing = true
        canvasPanel?.ignoresMouseEvents = true
        let id = sessionID
        let marks = document.annotations
        let image: CGImage
        do {
            if let frozenImage { image = frozenImage }
            else { image = try await capture(DisplayResolver.displayID(for: screen)).image }
            try Task.checkCancellation()
            guard sessionID == id, isActive else { throw CancellationError() }
            let size = screen.frame.size
            let result = try await Task.detached(priority: .userInitiated) {
                let composed = try AnnotationRenderer.composite(marks, onto: image, canvasSize: size)
                return try ImageProcessor.jpegData(from: composed)
            }.value
            try Task.checkCancellation()
            guard sessionID == id, isActive else { throw CancellationError() }
            end()
            return result
        } catch {
            if sessionID == id {
                document.isPreparing = false
                canvasPanel?.ignoresMouseEvents = !document.isDrawing
            }
            throw error
        }
    }

    func allowDiscard() -> Bool {
        let sensitivity = DiscardSensitivity.level(preferences.discardSensitivityLevel)
        guard preferences.confirmDiscard, document.requiresDiscardConfirmation(strokeThreshold: sensitivity.strokeLength, strokeCount: sensitivity.strokeCount) else { return true }
        let alert = NSAlert()
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 4)
        alert.messageText = "Discard annotations?"
        alert.informativeText = "Your marks will be cleared."
        alert.addButton(withTitle: "Keep drawing")
        alert.addButton(withTitle: "Discard")
        let wasSuspended = suspended
        suspend()
        let result = alert.runModal() == .alertSecondButtonReturn
        if !wasSuspended { resume() }
        return result
    }

    func clearWithConfirmation() { if allowDiscard() { document.clear() } }

    func end() {
        colorPicker.close()
        shiftDetector.reset()
        sessionID = UUID()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        canvasPanel?.orderOut(nil)
        toolbarPanel?.orderOut(nil)
        canvasPanel = nil
        toolbarPanel = nil
        canvas = nil
        frozenImage = nil
        screen = nil
        suspended = false
        subscriptions.removeAll()
        screenObserver = nil
        document.reset()
        let wasActive = isActive
        isActive = false
        if wasActive { onActiveChange?(false) }
    }
}

@MainActor
final class AnnotationCanvasView: NSView {
    let document: AnnotationDocument
    let preferences: Preferences
    var frozenImage: CGImage?
    var onFocus: (() -> Void)?
    var onEmptyClick: (() -> Bool)?
    private var tracking: NSTrackingArea?
    private var hovered: Int?
    private var transformHit: AnnotationHit?
    private var originalMark: ScreenAnnotation?
    private var dragStart: CGPoint = .zero
    private var transformStarted = false
    private var gestureStarted: TimeInterval = 0
    private var gestureDistance: CGFloat = 0
    private var lastPoint: CGPoint = .zero
    init(document: AnnotationDocument, preferences: Preferences) {
        self.document = document
        self.preferences = preferences
        super.init(frame: .zero)
        setAccessibilityLabel("Screen annotation canvas")
        setAccessibilityHelp("Drag to draw. Use the floating toolbar for tools and undo. The kk popup remains movable.")
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        guard document.isDrawing, !document.isPreparing else { return }
        let point = convert(event.locationInWindow, from: nil)
        let hit = AnnotationTransform.hit(at: point, marks: document.annotations, hovered: hovered)
        if let hit { hovered = hit.index }
        else if let interior = document.annotations.indices.reversed().first(where: {
            [.ellipse, .rectangle].contains(document.annotations[$0].tool) && document.annotations[$0].path.contains(point)
        }) { hovered = interior }
        else if let index = hovered, document.annotations.indices.contains(index), document.annotations[index].tool != .freehand {
            let handles = AnnotationTransform.corners(of: document.annotations[index])
            if handles.count != 4 || !CGRect(x: handles[0].x, y: handles[0].y, width: handles[2].x - handles[0].x, height: handles[2].y - handles[0].y).insetBy(dx: -12, dy: -12).contains(point) { hovered = nil }
        } else { hovered = nil }
        if hit?.corner != nil { NSCursor.crosshair.set() }
        else if hit != nil { NSCursor.openHand.set() }
        else { NSCursor.crosshair.set() }
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        guard transformHit == nil else { return }
        hovered = nil
        needsDisplay = true
        NSCursor.arrow.set()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)
        context.setFillColor(CGColor(gray: 0, alpha: 0.002)); context.fill(dirtyRect)
        if document.isDrawing, let frozenImage { context.draw(frozenImage, in: bounds) }
        AnnotationRenderer.draw(document.visibleAnnotations, in: context)
        // Editing chrome belongs only to the canvas, never the submitted image.
        if document.isDrawing, let hovered, document.annotations.indices.contains(hovered) {
            let handles = AnnotationTransform.corners(of: document.annotations[hovered])
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.setStrokeColor(document.annotations[hovered].color.cgColor)
            context.setLineWidth(1.5)
            for point in handles {
                let circle = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.fillEllipse(in: circle)
                context.strokeEllipse(in: circle)
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        onFocus?()
        gestureStarted = event.timestamp
        gestureDistance = 0
        lastPoint = convert(event.locationInWindow, from: nil)
        dragStart = lastPoint
        transformHit = AnnotationTransform.hit(at: lastPoint, marks: document.annotations, hovered: hovered)
        if let hit = transformHit, document.isDrawing, !document.isPreparing {
            originalMark = document.annotations[hit.index]
            hovered = hit.index
            transformStarted = false
            NSCursor.closedHand.set()
            needsDisplay = true
            return
        }
        transformHit = nil
        document.begin(at: convert(event.locationInWindow, from: nil), tool: preferences.annotationTool,
                       color: preferences.annotationColor, lineWidth: CGFloat(preferences.annotationLineWidth))
        document.setSmoothing(preferences.smoothStrokes)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        gestureDistance += hypot(point.x - lastPoint.x, point.y - lastPoint.y)
        lastPoint = point
        if transformHit != nil { updateTransform(to: point); return }
        document.move(to: point)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        gestureDistance += hypot(point.x - lastPoint.x, point.y - lastPoint.y)
        if transformHit != nil {
            updateTransform(to: point)
            transformHit = nil
            originalMark = nil
            NSCursor.openHand.set()
            needsDisplay = true
            return
        }
        if document.annotations.isEmpty, gestureDistance <= 6, event.timestamp - gestureStarted <= 0.35 {
            if onEmptyClick?() == true { document.cancelCurrent(); return }
        }
        document.move(to: convert(event.locationInWindow, from: nil))
        document.finish()
        needsDisplay = true
    }
    private func updateTransform(to point: CGPoint) {
        guard let hit = transformHit, let originalMark else { return }
        guard transformStarted || hypot(point.x - dragStart.x, point.y - dragStart.y) > 1 else { return }
        if !transformStarted { document.beginTransform(); transformStarted = true }
        let mark: ScreenAnnotation
        if let corner = hit.corner {
            let handle = AnnotationTransform.corners(of: originalMark)[corner]
            mark = AnnotationTransform.resized(originalMark, corner: corner, to: CGPoint(x: handle.x + point.x - dragStart.x, y: handle.y + point.y - dragStart.y))
        }
        else { mark = AnnotationTransform.moved(originalMark, by: CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)) }
        document.replace(at: hit.index, with: mark)
        needsDisplay = true
    }

}

struct AnnotationToolbar: View {
    @ObservedObject var document: AnnotationDocument
    @ObservedObject var preferences: Preferences
    let onFocus: () -> Void
    let onClear: () -> Void
    var colorPicker = AnnotationColorPanel()
    var body: some View {
        HStack(spacing: 0) {
            PaletteButton("Pointer mode", action: {
                document.finish()
                if !document.isDrawing, preferences.annotationTool == .pointer { preferences.annotationTool = .freehand }
                document.isDrawing.toggle()
                onFocus()
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "cursorarrow")
                    Text(preferences.annotationBindings["pointer"]?.label ?? "—").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
                .frame(width: 44, height: PopupGeometry.actionHeight)
                .background(!document.isDrawing ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: PopupGeometry.actionRadius))
                .contentShape(Rectangle())
            }
            .help("Pointer mode: pass clicks through to the desktop")
            .accessibilityLabel("Pointer mode")
            ForEach(AnnotationTool.drawingTools) { tool in
                PaletteButton(tool.title, action: {
                    document.finish()
                    preferences.annotationTool = tool
                    document.isDrawing = true
                    onFocus()
                }) {
                    VStack(spacing: 3) { Image(systemName: tool.symbol); Text(preferences.annotationBindings[tool.rawValue]?.label ?? "—").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) }.frame(width: 44, height: PopupGeometry.actionHeight)
                        .background(document.isDrawing && preferences.annotationTool == tool ? preferences.annotationColor.color.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: PopupGeometry.actionRadius))
                        .contentShape(Rectangle())
                }
                .help(tool.title).accessibilityLabel(tool.title)
            }
            Divider().frame(height: 22)
            PaletteButton("Drawing color", action: {}, anchorAction: { anchor in
                colorPicker.toggle(from: anchor, preferences: preferences, onSelection: onFocus)
            }) {
                Circle().fill(preferences.annotationColor.color).frame(width: 18, height: 18)
                    .overlay { Circle().strokeBorder(.gray.opacity(0.5), lineWidth: 0.5) }
                    .frame(width: 44, height: 48).contentShape(Rectangle())
            }
            .help("Drawing color").accessibilityLabel("Drawing color")
            Spacer(minLength: 0)
            PaletteButton("Undo last annotation", action: { document.undo(); onFocus() }) { Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 48).contentShape(Rectangle()) }
                .disabled(!document.canUndo).help("Undo last annotation").accessibilityLabel("Undo last annotation")
            PaletteButton("Clear all annotations", action: { onClear(); onFocus() }) { Image(systemName: "trash").frame(width: 40, height: 48).contentShape(Rectangle()) }
                .disabled(document.annotations.isEmpty).help("Clear all annotations").accessibilityLabel("Clear all annotations")
            PaletteButton("Ask kk", action: onFocus) { VStack(spacing: 3) { Text("Ask kk"); Text(preferences.annotationBindings["focus"]?.label ?? "—").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) }.padding(.horizontal, 8).frame(height: PopupGeometry.actionHeight).background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: PopupGeometry.actionRadius)) }
        }
        .buttonStyle(.plain)
        .disabled(document.isPreparing)
        .frame(height: 48)
        .padding(4)
        .foregroundStyle(Color.primary)
        .modifier(PopupSurface(material: preferences.popupMaterial))
    }
}

final class AnnotationPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
