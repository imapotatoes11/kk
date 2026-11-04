import AppKit
import SwiftUI
import XCTest
@testable import kk

final class DarkAppearanceTests: XCTestCase {
    @MainActor
    func testLiveStreamingAnswerStaysWhiteThroughUpdatesAndCompletion() async throws {
        _ = NSApplication.shared
        let state = DarkStreamState()
        let host = NSHostingView(rootView: DarkStreamHarness(state: state))
        let window = mount(host)
        defer { window.close() }
        window.appearance = NSAppearance(named: .darkAqua)
        try await Task.sleep(for: .milliseconds(200))
        try assertWhiteTextPixels(host, name: "dark-stream-initial")
        state.text += " More streamed words arrive."
        try await Task.sleep(for: .milliseconds(200))
        try assertWhiteTextPixels(host, name: "dark-stream-updated")
        state.scheme = .light
        window.appearance = NSAppearance(named: .aqua)
        try await Task.sleep(for: .milliseconds(100))
        state.scheme = .dark
        window.appearance = NSAppearance(named: .darkAqua)
        state.text += " Still streaming after changing appearance."
        try await Task.sleep(for: .milliseconds(200))
        try assertWhiteTextPixels(host, name: "dark-stream-after-theme-change")
        state.streaming = false
        try await Task.sleep(for: .milliseconds(150))
        try assertWhiteTextPixels(host, name: "dark-stream-completed")
    }

    @MainActor
    func testEditorRecolorsExistingAndNewTextWhenAppearanceChanges() async throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: editor(scheme: .light))
        let window = mount(host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let textView = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        XCTAssertLessThan(try XCTUnwrap(textView.textColor?.usingColorSpace(.deviceRGB)).redComponent, 0.1)
        window.appearance = NSAppearance(named: .darkAqua)
        host.rootView = editor(scheme: .dark)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThan(try XCTUnwrap(textView.textColor?.usingColorSpace(.deviceRGB)).redComponent, 0.9)
        let typing = try XCTUnwrap(textView.typingAttributes[.foregroundColor] as? NSColor)
        XCTAssertGreaterThan(try XCTUnwrap(typing.usingColorSpace(.deviceRGB)).redComponent, 0.9)
        let existing = try XCTUnwrap(textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        XCTAssertGreaterThan(try XCTUnwrap(existing.usingColorSpace(.deviceRGB)).redComponent, 0.9)
        try assertWhiteTextPixels(host, name: "dark-editor")
    }

    @MainActor
    func testAnswerAndBubbleDrawWhiteGlyphsOnDarkBackground() async throws {
        _ = NSApplication.shared
        for bubble in [false, true] {
            let content = AnyView(Group {
                if bubble { UserMessageBubble(text: "Readable at night") }
                else { ResponseView(markdown: "Readable at night", isStreaming: false) }
            }.padding(16).frame(width: 360).background(Color.black).environment(\.colorScheme, .dark))
            let host = NSHostingView(rootView: content)
            let window = mount(host)
            defer { window.close() }
            window.appearance = NSAppearance(named: .darkAqua)
            try await Task.sleep(for: .milliseconds(150))
            try assertWhiteTextPixels(host, name: bubble ? "dark-bubble" : "dark-answer")
        }
    }

    @MainActor
    private func editor(scheme: ColorScheme) -> some View {
        PromptEditor(text: .constant("Readable at night"), isDisabled: false, onSubmit: {})
            .frame(width: 340, height: 40).padding(12)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
    }

    @MainActor
    private func mount<Content: View>(_ host: NSHostingView<Content>) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        return window
    }

    @MainActor
    private func assertWhiteTextPixels(_ view: NSView, name: String) throws {
        view.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        var whitePixels = 0
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.9 && color.redComponent > 0.85 && color.greenComponent > 0.85 && color.blueComponent > 0.85 { whitePixels += 1 }
            }
        }
        XCTAssertGreaterThan(whitePixels, 30, "Text must actually draw white glyphs, not black on a dark background")
        if let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
}

@MainActor
private final class DarkStreamState: ObservableObject {
    @Published var text = "Readable at night while streaming."
    @Published var streaming = true
    @Published var scheme = ColorScheme.dark
}

private struct DarkStreamHarness: View {
    @ObservedObject var state: DarkStreamState
    var body: some View {
        ResponseView(markdown: state.text, isStreaming: state.streaming)
            .padding(16).frame(width: 360)
            .background(state.scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, state.scheme)
    }
}
