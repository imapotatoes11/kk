import AppKit
import Combine
import Sparkle

struct AppVersion: Equatable {
    let version: String?
    let build: String?

    init(info: [String: Any] = Bundle.main.bundleIdentifier == "dev.kw2.kk" ? (Bundle.main.infoDictionary ?? [:]) : [:]) {
        version = info["CFBundleShortVersionString"] as? String
        build = info["CFBundleVersion"] as? String
    }

    var description: String {
        guard let version, !version.isEmpty else { return "Development build" }
        guard let build, !build.isEmpty else { return "Version \(version)" }
        return "Version \(version) (\(build))"
    }
}

/// One updater for the application's lifetime. Sparkle owns scheduling, persistence,
/// signature verification, download/install UI, and relaunching the app.
@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var unavailableReason: String?
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            guard let updater = controller?.updater,
                  updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    @Published var automaticallyDownloadsUpdates = false {
        didSet {
            guard let updater = controller?.updater,
                  updater.automaticallyDownloadsUpdates != automaticallyDownloadsUpdates else { return }
            updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }
    private var controller: SPUStandardUpdaterController?
    private var subscriptions = Set<AnyCancellable>()

    init() {
        let bundle = Bundle.main
        // SwiftPM executables and test runners aren't installable application bundles.
        guard bundle.bundleURL.pathExtension == "app", bundle.bundleIdentifier == "dev.kw2.kk" else {
            unavailableReason = "Updates are available in the kk app."
            return
        }
        guard let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            unavailableReason = "Updates aren't configured for this development build."
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.canCheckForUpdates = self.isAvailable && value
            }.store(in: &subscriptions)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyDownloadsUpdates = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastCheck = $0 }.store(in: &subscriptions)
        do {
            try updater.start()
        } catch {
            unavailableReason = "Updates could not start: \(error.localizedDescription)"
        }
    }

    var isAvailable: Bool { controller != nil && unavailableReason == nil }

    func checkForUpdates() {
        guard isAvailable, canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }
}
