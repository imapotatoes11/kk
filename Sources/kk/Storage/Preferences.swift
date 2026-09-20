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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baseURL = defaults.string(forKey: Keys.baseURL) ?? Defaults.baseURL
        model = defaults.string(forKey: Keys.model) ?? Defaults.model
    }

    private enum Keys {
        static let baseURL = "baseURL"
        static let model = "model"
    }
}
