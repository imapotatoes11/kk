import AppKit
import CoreGraphics
import KeyboardShortcuts
import SwiftUI

@MainActor
final class OnboardingController: NSWindowController, NSWindowDelegate {
    private var presentation: Task<Void, Never>?
    init(appState: AppState, completion: @escaping () -> Void) {
        let window = OnboardingWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Welcome to kk"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(state: appState) { [weak window] in
            appState.preferences.onboardingComplete = true
            window?.close()
            completion()
        })
        window.appearance = appState.preferences.appearance.nsAppearance
        window.center()
    }
    override func showWindow(_ sender: Any?) {
        presentation?.cancel()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
        // Menu tracking and the source Settings close finish on the next run loop.
        // Restore key status once after that handoff; never keep stealing focus.
        presentation = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let window = self?.window, window.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        presentation?.cancel()
        Task { @MainActor in
            await Task.yield()
            AppState.refreshActivationPolicy()
        }
    }

    required init?(coder: NSCoder) { nil }
}

private struct OnboardingView: View {
    let state: AppState
    let completion: () -> Void
    @State private var page = 0
    @State private var key = ""
    @State private var endpoint = ""
    @State private var model = ""
    @State private var error: String?
    @State private var finished = false
    @State private var permission = CGPreflightScreenCaptureAccess()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var needsConnection: Bool {
        state.keychain.loadAPIKey()?.isEmpty != false ||
        (try? APIConfiguration(baseURL: state.preferences.baseURL, apiKey: "", model: state.preferences.model).validated()) == nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Group {
                if page == 0 {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Ask about your screen").font(.title2.weight(.semibold))
                        Text("Connect a vision-capable model.").foregroundStyle(.secondary)
                        TextField("Base URL", text: $endpoint)
                        TextField("Model", text: $model)
                        SecureField("API key", text: $key)
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                } else if page == 1 {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "keyboard").font(.system(size: 32)).foregroundStyle(.secondary)
                        Text("One shortcut away").font(.title2.weight(.semibold))
                        KeyboardShortcuts.Recorder("Open kk", name: .askKK)
                        Text("Ask, mark your screen, and keep going.").foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "rectangle.on.rectangle").font(.system(size: 32)).foregroundStyle(.secondary)
                        Text("Let kk see your screen").font(.title2.weight(.semibold))
                        Text("Screen access enables images and annotations. You can also use text only.").foregroundStyle(.secondary)
                        Button("Allow screen access") {
                            permission = state.captureService.requestAccess()

                        }
                    }
                }
            }
            .id(page)
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
            Spacer(minLength: 0)
            HStack {
                if page > 0 { Button("Back") { advance(to: page == 2 ? 1 : 0) } }
                Spacer()
                Button(page == 2 ? "Use text only" : "Continue") {
                    if page == 0 {
                        do {
                            _ = try APIConfiguration(baseURL: endpoint, apiKey: key, model: model).validated()
                            if !key.isEmpty { try state.keychain.saveAPIKey(key) }
                            state.preferences.baseURL = endpoint
                            state.preferences.model = model
                            advance(to: 1)
                        } catch { self.error = error.localizedDescription }
                    } else if page == 1 {
                        if CGPreflightScreenCaptureAccess() { finish() } else { advance(to: 2) }
                    } else { finish() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 480, height: 380)
        .background { PopupBackground(material: .liquidGlass) }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.18), lineWidth: 1) }
        .overlay(alignment: .topTrailing) {
            Button { NSApp.keyWindow?.close() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).padding(12) }
                .buttonStyle(.plain).foregroundStyle(.secondary).padding(8).accessibilityLabel("Close onboarding")
        }
        .task(id: page) {
            guard page == 2 else { return }
            while !Task.isCancelled {
                if !state.permissionSetupActive, await state.captureService.hasAccess() { finish(); return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear {
            endpoint = state.preferences.baseURL
            model = state.preferences.model
            if !needsConnection { page = 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission = CGPreflightScreenCaptureAccess()
            if page == 2 && permission && !state.permissionSetupActive { finish() }
        }
    }
    private func finish() {
        guard !finished else { return }
        finished = true
        completion()
    }
    private func advance(to value: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { page = value }
    }
}

final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
