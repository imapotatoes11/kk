import AppKit
import SwiftUI

enum PopupSize: String, CaseIterable, Identifiable {
    case fullSize, compact
    var id: Self { self }
    var title: String { self == .fullSize ? "Full size" : "Compact" }
}

enum PopupOpeningPosition: String, CaseIterable, Identifiable {
    case defaultPosition, cursor
    var id: Self { self }
    var title: String { self == .defaultPosition ? "Default position" : "At cursor" }
}

enum PopupMaterial: String, CaseIterable, Identifiable {
    case opaque, translucent, liquidGlass
    var id: Self { self }
    var title: String {
        switch self {
        case .opaque: "Opaque"
        case .translucent: "Translucent"
        case .liquidGlass: "Liquid Glass"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AppAccent: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, green, graphite
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var nsColor: NSColor? {
        switch self {
        case .system: nil
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .green: .systemGreen
        case .graphite: .systemGray
        }
    }
    var color: Color? { nsColor.map { Color(nsColor: $0) } }
}

struct AnswerTextSize: Equatable, Sendable {
    static let range: ClosedRange<Double> = 12...24
    static let small = Self(points: 13)
    static let standard = Self(points: 14)
    static let large = Self(points: 16)

    let points: CGFloat
    var rawValue: String { String(Int(points)) }

    init(points: CGFloat) {
        let value = points.isFinite ? points.rounded() : 14
        self.points = min(CGFloat(Self.range.upperBound), max(CGFloat(Self.range.lowerBound), value))
    }

    init?(rawValue: String) {
        // Preserve selections saved by the former Small / Standard / Large picker.
        switch rawValue {
        case "small": self = .small
        case "standard": self = .standard
        case "large": self = .large
        default:
            guard let value = Double(rawValue) else { return nil }
            self.init(points: CGFloat(value))
        }
    }
}

enum CopyShortcutAction: String, CaseIterable, Identifiable {
    case disabled, copy, copyAndClose
    var id: Self { self }
    var title: String {
        switch self {
        case .disabled: "Standard text copy"
        case .copy: "Copy latest answer"
        case .copyAndClose: "Copy answer and close"
        }
    }
}

/// Six deliberate stops, retaining the original 480 / 680 point defaults.
enum BarWidths {
    static let compact: [CGFloat] = [440, 480, 520, 560, 600, 640]
    static let full: [CGFloat] = [520, 560, 620, 680, 720, 760]
    static let compactDefault = 1
    static let fullDefault = 3
    static func clamp(_ level: Int) -> Int { min(5, max(0, level)) }
}

enum CaptureDisplayMode: String, CaseIterable, Identifiable {
    case active, cursor, all
    var id: Self { self }
    var title: String {
        switch self {
        case .active: "Active desktop"
        case .cursor: "Desktop at cursor"
        case .all: "All desktops"
        }
    }
}
