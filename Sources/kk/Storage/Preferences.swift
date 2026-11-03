import Foundation
import Combine

@MainActor
final class Preferences: ObservableObject {
    @Published var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Keys.baseURL) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }

    @Published var popupSize: PopupSize {
        didSet { defaults.set(popupSize.rawValue, forKey: Keys.popupSize) }
    }
    @Published var popupMaterial: PopupMaterial {
        didSet { defaults.set(popupMaterial.rawValue, forKey: Keys.popupMaterial) }
    }
    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    @Published var accent: AppAccent {
        didSet { defaults.set(accent.rawValue, forKey: Keys.accent) }
    }
    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }
    @Published var answerTextSize: AnswerTextSize {
        didSet { defaults.set(answerTextSize.rawValue, forKey: Keys.answerTextSize) }
    }
    @Published var copyShortcutAction: CopyShortcutAction {
        didSet { defaults.set(copyShortcutAction.rawValue, forKey: Keys.copyShortcutAction) }
    }
    @Published var showThinking: Bool {
        didSet { defaults.set(showThinking, forKey: Keys.showThinking) }
    }
    @Published var popupOpeningPosition: PopupOpeningPosition {
        didSet { defaults.set(popupOpeningPosition.rawValue, forKey: Keys.popupOpeningPosition) }
    }
    @Published var snapToDefaultPosition: Bool {
        didSet { defaults.set(snapToDefaultPosition, forKey: Keys.snapToDefaultPosition) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baseURL = defaults.string(forKey: Keys.baseURL) ?? Defaults.baseURL
        model = defaults.string(forKey: Keys.model) ?? Defaults.model
        popupSize = PopupSize(rawValue: defaults.string(forKey: Keys.popupSize) ?? "") ?? .fullSize
        popupMaterial = PopupMaterial(rawValue: defaults.string(forKey: Keys.popupMaterial) ?? "") ?? .opaque
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        accent = AppAccent(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .system
        alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        answerTextSize = AnswerTextSize(rawValue: defaults.string(forKey: Keys.answerTextSize) ?? "") ?? .standard
        copyShortcutAction = CopyShortcutAction(rawValue: defaults.string(forKey: Keys.copyShortcutAction) ?? "") ?? .disabled
        showThinking = defaults.object(forKey: Keys.showThinking) as? Bool ?? false
        popupOpeningPosition = PopupOpeningPosition(rawValue: defaults.string(forKey: Keys.popupOpeningPosition) ?? "") ?? .defaultPosition
        snapToDefaultPosition = defaults.object(forKey: Keys.snapToDefaultPosition) as? Bool ?? true
    }

    func resetCustomization() {
        popupSize = .fullSize
        popupMaterial = .opaque
        appearance = .system
        accent = .system
        alwaysOnTop = true
        answerTextSize = .standard
        showThinking = false
        popupOpeningPosition = .defaultPosition
        snapToDefaultPosition = true
    }

    private enum Keys {
        static let baseURL = "baseURL"
        static let model = "model"
        static let popupSize = "popupSize"
        static let popupMaterial = "popupMaterial"
        static let appearance = "appearance"
        static let accent = "accent"
        static let alwaysOnTop = "alwaysOnTop"
        static let answerTextSize = "answerTextSize"
        static let copyShortcutAction = "copyShortcutAction"
        static let showThinking = "showThinking"
        static let popupOpeningPosition = "popupOpeningPosition"
        static let snapToDefaultPosition = "snapToDefaultPosition"
    }
}
