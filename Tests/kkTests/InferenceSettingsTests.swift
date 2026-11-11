import AppKit
import SwiftUI
import XCTest
@testable import kk

final class InferenceSettingsTests: XCTestCase {
    func testCustomInstructionsAreAppendedToTheSystemPrompt() {
        let base = KKCopy.systemPrompt(diagrams: true)
        XCTAssertEqual(KKCopy.systemPrompt(diagrams: true, customInstructions: "  \n "), base, "Blank instructions change nothing")
        let prompt = KKCopy.systemPrompt(diagrams: false, customInstructions: "  Reply in French.\n")
        XCTAssertTrue(prompt.hasPrefix(KKCopy.systemPrompt(diagrams: false)))
        XCTAssertTrue(prompt.contains(KKCopy.customInstructionsPreamble))
        XCTAssertTrue(prompt.hasSuffix("<user_instructions>\nReply in French.\n</user_instructions>"))
    }

    @MainActor
    func testCustomInstructionsAreCappedAtTheLimit() {
        let limit = KKCopy.customInstructionsLimit
        let long = String(repeating: "a", count: limit) + "OVERFLOW"
        XCTAssertTrue(KKCopy.systemPrompt(diagrams: false, customInstructions: long)
            .hasSuffix("<user_instructions>\n" + String(repeating: "a", count: limit) + "\n</user_instructions>"))
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(long, forKey: "customInstructions")
        XCTAssertEqual(Preferences(defaults: defaults).customInstructions.count, limit, "Oversized saved text loads trimmed")
    }

    @MainActor
    func testRequestsCarryCustomInstructions() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.customInstructions = "Be brief."
        let messages = ChatRequestBuilder.messages(for: [ChatMessage(role: .user, content: "hi")], firstImage: nil,
            systemPrompt: KKCopy.systemPrompt(diagrams: prefs.renderDiagrams, customInstructions: prefs.customInstructions))
        guard case .text(let system) = messages.first?.content else { return XCTFail("Missing system message") }
        XCTAssertTrue(system.contains("<user_instructions>\nBe brief.\n</user_instructions>"))
    }

    @MainActor
    func testNewPreferencesPersistAndAdvancedResetRestoresFocus() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.focusOnAnswerComplete, "Focusing after an answer stays the default")
        XCTAssertEqual(prefs.customInstructions, "")
        prefs.focusOnAnswerComplete = false
        prefs.customInstructions = "Use metric units."
        let reloaded = Preferences(defaults: defaults)
        XCTAssertFalse(reloaded.focusOnAnswerComplete)
        XCTAssertEqual(reloaded.customInstructions, "Use metric units.")
        reloaded.resetAdvanced()
        reloaded.resetCustomization()
        XCTAssertTrue(reloaded.focusOnAnswerComplete)
        XCTAssertEqual(reloaded.customInstructions, "Use metric units.", "Restore defaults keeps inference settings")
    }

    @MainActor
    func testFinishedAnswerCaptureCanLeaveFocusAlone() throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let screen = try XCTUnwrap(NSScreen.main)
        for focus in [true, false] {
            let controller = AnnotationController(preferences: prefs)
            var focused = 0
            controller.onFocusPopup = { focused += 1 }
            controller.begin(on: screen)
            controller.focusesPopupOnCapture = focus
            controller.receiveCapture(ScreenSnapshot(image: image, data: Data()))
            XCTAssertNotNil(controller.canvasPanel)
            XCTAssertEqual(focused, focus ? 1 : 0)
            controller.end()
        }
    }
}
