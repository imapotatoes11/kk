import AppKit
import SwiftUI
import Combine

@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    let selection = SettingsSelection()
    private var appearanceSubscription: AnyCancellable?

    init(appState: AppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "kk Settings"
        window.toolbarStyle = .preference
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed, .moveToActiveSpace]
        super.init(window: window)
        let view = SettingsView(preferences: appState.preferences, selection: selection)
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 640, height: 480))

        let toolbar = NSToolbar(identifier: "kkSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = .init(selection.section.rawValue)
        window.toolbar = toolbar
        window.center()
        window.appearance = appState.preferences.appearance.nsAppearance
        appearanceSubscription = appState.preferences.$appearance
            .receive(on: RunLoop.main)
            .sink { [weak window] appearance in window?.appearance = appearance.nsAppearance }
    }

    required init?(coder: NSCoder) { nil }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + SettingsSection.allCases.map { .init($0.rawValue) } + [.flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsSection.allCases.map { .init($0.rawValue) }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let section = SettingsSection(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = section.title
        item.paletteLabel = section.title
        item.toolTip = section.title
        item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title)
        item.target = self
        item.action = #selector(selectSection(_:))
        return item
    }

    @objc func selectSection(_ sender: NSToolbarItem) {
        guard let section = SettingsSection(rawValue: sender.itemIdentifier.rawValue) else { return }
        selection.section = section
        window?.toolbar?.selectedItemIdentifier = sender.itemIdentifier
        if let window {
            let top = window.frame.maxY
            let desiredHeight: CGFloat = section == .customization ? 640 : (section == .shortcuts ? 600 : 480)
            let height = min(desiredHeight, max(360, (window.screen?.visibleFrame.height ?? 1000) - 120))
            window.setContentSize(NSSize(width: 640, height: height))
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        }
    }
}
