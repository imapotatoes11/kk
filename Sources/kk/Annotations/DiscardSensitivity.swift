import Foundation

struct DiscardSensitivity: Equatable {
    let strokeCount: Int
    let strokeLength: CGFloat
    static let levels: [Self] = [
        .init(strokeCount: 1, strokeLength: 60),
        .init(strokeCount: 2, strokeLength: 160),
        .init(strokeCount: 3, strokeLength: 280),
        .init(strokeCount: 4, strokeLength: 440),
        .init(strokeCount: 6, strokeLength: 640),
        .init(strokeCount: 8, strokeLength: 900)
    ]
    static func level(_ index: Int) -> Self { levels[min(max(index, 0), levels.count - 1)] }
}
