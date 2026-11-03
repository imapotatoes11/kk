import Foundation
import Combine
import CoreGraphics

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

    @Published var annotationsEnabled: Bool {
        didSet { defaults.set(annotationsEnabled, forKey: "annotationsEnabled") }
    }
    @Published var freezeScreen: Bool {
        didSet { defaults.set(freezeScreen, forKey: "freezeScreen") }
    }
    @Published var annotationTool: AnnotationTool {
        didSet { defaults.set(annotationTool.rawValue, forKey: "annotationTool") }
    }
    @Published var annotationColor: AnnotationColor {
        didSet { defaults.set(annotationColor.rawValue, forKey: "annotationColor") }
    }
    @Published var annotationLineWidth: Int {
        didSet { defaults.set(annotationLineWidth, forKey: "annotationLineWidth") }
    }

    @Published var smoothStrokes: Bool { didSet { defaults.set(smoothStrokes, forKey: "smoothStrokes") } }
    @Published var confirmDiscard: Bool { didSet { defaults.set(confirmDiscard, forKey: "confirmDiscard") } }
    var onboardingComplete: Bool {
        get { defaults.bool(forKey: "onboardingComplete") }
        set { defaults.set(newValue, forKey: "onboardingComplete") }
    }
    @Published var annotationBindings: [String: AnnotationShortcut] {
        didSet { defaults.set(try? JSONEncoder().encode(annotationBindings), forKey: "annotationBindings") }
    }
    @Published var annotationReturnKey: AnnotationReturnKey {
        didSet { defaults.set(annotationReturnKey.rawValue, forKey: "annotationReturnKey") }
    }
    var permissionSetupPending: Bool {
        get { defaults.bool(forKey: "permissionSetupPending") }
        set { defaults.set(newValue, forKey: "permissionSetupPending") }
    }
    @Published var palettePosition: PalettePosition { didSet { defaults.set(palettePosition.rawValue, forKey: "palettePosition") } }
    @Published var discardSensitivityLevel: Int { didSet { defaults.set(discardSensitivityLevel, forKey: "discardSensitivityLevel") } }
    @Published var showPreviewButton: Bool { didSet { defaults.set(showPreviewButton, forKey: "showPreviewButton") } }
    @Published var showSubmitButton: Bool { didSet { defaults.set(showSubmitButton, forKey: "showSubmitButton") } }
    @Published var compactWidthLevel: Int { didSet { defaults.set(compactWidthLevel, forKey: "compactWidthLevel") } }
    @Published var fullWidthLevel: Int { didSet { defaults.set(fullWidthLevel, forKey: "fullWidthLevel") } }
    @Published var copyChatOnDismiss: Bool { didSet { defaults.set(copyChatOnDismiss, forKey: "copyChatOnDismiss") } }
    @Published var confirmDismissChat: Bool { didSet { defaults.set(confirmDismissChat, forKey: "confirmDismissChat") } }
    @Published var captureDisplayMode: CaptureDisplayMode { didSet { defaults.set(captureDisplayMode.rawValue, forKey: "captureDisplayMode") } }
    var openingWidth: CGFloat { popupSize == .compact ? BarWidths.compact[BarWidths.clamp(compactWidthLevel)] : BarWidths.full[BarWidths.clamp(fullWidthLevel)] }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        captureDisplayMode = CaptureDisplayMode(rawValue: defaults.string(forKey: "captureDisplayMode") ?? "") ?? .cursor
        compactWidthLevel = BarWidths.clamp(defaults.object(forKey: "compactWidthLevel") as? Int ?? BarWidths.compactDefault)
        fullWidthLevel = BarWidths.clamp(defaults.object(forKey: "fullWidthLevel") as? Int ?? BarWidths.fullDefault)
        copyChatOnDismiss = defaults.object(forKey: "copyChatOnDismiss") as? Bool ?? false
        confirmDismissChat = defaults.object(forKey: "confirmDismissChat") as? Bool ?? false
        let rawLegacyLength = defaults.object(forKey: "discardStrokeThreshold") as? Double ?? 160
        let legacyLength = rawLegacyLength.isFinite ? rawLegacyLength : 160
        let migrated = DiscardSensitivity.levels.indices.min { abs(Double(DiscardSensitivity.levels[$0].strokeLength) - legacyLength) < abs(Double(DiscardSensitivity.levels[$1].strokeLength) - legacyLength) } ?? 1
        let sensitivity = defaults.object(forKey: "discardSensitivityLevel") as? Int ?? migrated
        discardSensitivityLevel = min(max(sensitivity, 0), 5)
        showPreviewButton = defaults.object(forKey: "showPreviewButton") as? Bool ?? true
        showSubmitButton = defaults.object(forKey: "showSubmitButton") as? Bool ?? true
        palettePosition = PalettePosition(rawValue: defaults.string(forKey: "palettePosition") ?? "") ?? .bottom
        annotationReturnKey = AnnotationReturnKey(rawValue: defaults.string(forKey: "annotationReturnKey") ?? "") ?? .doubleShift
        annotationBindings = defaults.data(forKey: "annotationBindings").flatMap { try? JSONDecoder().decode([String: AnnotationShortcut].self, from: $0) } ?? AnnotationShortcut.defaults
        smoothStrokes = defaults.object(forKey: "smoothStrokes") as? Bool ?? true
        confirmDiscard = defaults.object(forKey: "confirmDiscard") as? Bool ?? true
        annotationsEnabled = defaults.object(forKey: "annotationsEnabled") as? Bool ?? true
        freezeScreen = defaults.object(forKey: "freezeScreen") as? Bool ?? true
        annotationTool = AnnotationTool(rawValue: defaults.string(forKey: "annotationTool") ?? "") ?? .freehand
        annotationColor = AnnotationColor(rawValue: defaults.string(forKey: "annotationColor") ?? "") ?? .red
        let weight = defaults.integer(forKey: "annotationLineWidth")
        annotationLineWidth = [2, 3, 5].contains(weight) ? weight : 3
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
        captureDisplayMode = .cursor
        compactWidthLevel = BarWidths.compactDefault
        fullWidthLevel = BarWidths.fullDefault
        copyChatOnDismiss = false
        confirmDismissChat = false
        showPreviewButton = true
        showSubmitButton = true
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
