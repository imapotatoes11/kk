import Foundation

struct DoubleShiftDetector {
    private var downAt: TimeInterval?
    private var lastRelease: TimeInterval?
    mutating func reset() { downAt = nil; lastRelease = nil }
    mutating func changed(isDown: Bool, onlyShift: Bool, time: TimeInterval) -> Bool {
        guard onlyShift else { reset(); return false }
        if isDown { downAt = time; return false }
        guard let downAt, time - downAt <= 0.22 else { reset(); return false }
        self.downAt = nil
        if let lastRelease, time - lastRelease <= 0.4 { reset(); return true }
        lastRelease = time
        return false
    }
}

enum AnnotationReturnKey: String, CaseIterable, Identifiable {
    case doubleShift, shortcut, disabled
    var id: Self { self }
    var title: String { switch self { case .doubleShift: "Double Shift"; case .shortcut: "Shortcut"; case .disabled: "Off" } }
}
