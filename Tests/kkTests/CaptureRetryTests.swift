import AppKit
import ScreenCaptureKit
import XCTest
@testable import kk

final class CaptureRetryTests: XCTestCase {
    func testTransientSelfExclusionRetriesOnceAfterDelayOnSameDisplay() async throws {
        let probe = try CaptureProbe(failures: 1)
        let service = ScreenCaptureService(permissionCheck: { true }, captureAttempt: { try await probe.capture($0) }, retryDelay: .milliseconds(60))
        XCTAssertEqual(ScreenCaptureService().retryDelay, .milliseconds(250))
        let result = try await service.captureSnapshot(displayID: 42)
        XCTAssertEqual(result.data, Data([1, 2, 3]))
        let attempts = await probe.attempts
        XCTAssertEqual(attempts.map(\.display), [42, 42])
        XCTAssertGreaterThanOrEqual(attempts[0].time.duration(to: attempts[1].time), .milliseconds(60))
    }

    func testRepeatedFailureStopsAfterTwoAttemptsAndSuggestsRecovery() async throws {
        let probe = try CaptureProbe(failures: 10)
        let service = ScreenCaptureService(permissionCheck: { true }, captureAttempt: { try await probe.capture($0) }, retryDelay: .zero)
        do {
            _ = try await service.captureSnapshot(displayID: 42)
            XCTFail("Both attempts should fail")
        } catch let error as KKError {
            guard case .screenCaptureFailed(let message) = error else { return XCTFail("Wrong error: \(error)") }
            XCTAssertTrue(message.contains("reopening the kk popup"))
            XCTAssertTrue(message.contains("relaunching kk"))
        }
        let attempts = await probe.attempts
        XCTAssertEqual(attempts.count, 2)
    }

    func testOtherCaptureErrorsAndPermissionDenialsAreNotRetried() async throws {
        for error in [KKError.screenCapturePermission, .screenCaptureFailed("Display disconnected")] {
            let probe = try CaptureProbe(failures: 10, error: error)
            let service = ScreenCaptureService(permissionCheck: { true }, captureAttempt: { try await probe.capture($0) }, retryDelay: .zero)
            do { _ = try await service.captureSnapshot(displayID: 42); XCTFail("Must fail") }
            catch let actual as KKError { XCTAssertEqual(actual, error) }
            let attempts = await probe.attempts
            XCTAssertEqual(attempts.count, 1)
        }
        let probe = try CaptureProbe(failures: 0)
        let denied = ScreenCaptureService(permissionCheck: { false }, captureAttempt: { try await probe.capture($0) })
        do { _ = try await denied.captureSnapshot(displayID: 42); XCTFail("Permission must gate discovery") }
        catch let error as KKError { XCTAssertEqual(error, .screenCapturePermission) }
        let attempts = await probe.attempts
        XCTAssertEqual(attempts.count, 0)
    }

    func testCancellationDuringDelayPreventsSecondCapture() async throws {
        let probe = try CaptureProbe(failures: 10)
        let service = ScreenCaptureService(permissionCheck: { true }, captureAttempt: { try await probe.capture($0) }, retryDelay: .seconds(30))
        let task = Task { try await service.captureSnapshot(displayID: 42) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await probe.attempts.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Must cancel") }
        catch is CancellationError {}
        let attempts = await probe.attempts
        XCTAssertEqual(attempts.count, 1)
    }

    @MainActor
    func testPopupStaysCapturingDuringRetryAndDismissCancelsIt() async throws {
        _ = NSApplication.shared
        let probe = try CaptureProbe(failures: 10)
        let service = ScreenCaptureService(permissionCheck: { true }, captureAttempt: { try await probe.capture($0) }, retryDelay: .milliseconds(150))
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: service, apiClient: OpenAICompatibleClient())
        chat.beginCapture(for: try XCTUnwrap(NSScreen.main))
        try await Task.sleep(for: .milliseconds(50))
        guard case .capturing = chat.screenContextState else { return XCTFail("Do not flash the warning before the retry") }
        chat.dismiss()
        try await Task.sleep(for: .milliseconds(200))
        guard case .disabled = chat.screenContextState else { return XCTFail("A dismissed session must not receive a late warning") }
        let attempts = await probe.attempts
        XCTAssertEqual(attempts.count, 1)
    }
}

private actor CaptureProbe {
    struct Attempt: Sendable { let display: CGDirectDisplayID?; let time: ContinuousClock.Instant }
    var attempts: [Attempt] = []
    let failures: Int
    let error: (any Error & Sendable)?
    let snapshot: ScreenSnapshot
    init(failures: Int, error: (any Error & Sendable)? = nil) throws {
        self.failures = failures; self.error = error
        let image = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        snapshot = ScreenSnapshot(image: image, data: Data([1, 2, 3]))
    }
    func capture(_ display: CGDirectDisplayID?) throws -> ScreenSnapshot {
        attempts.append(Attempt(display: display, time: .now))
        if attempts.count <= failures { throw error ?? ScreenCaptureAttemptError.selfExclusionUnavailable }
        return snapshot
    }
}
