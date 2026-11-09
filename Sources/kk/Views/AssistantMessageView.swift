import SwiftUI

struct AssistantMessageView: View {
    let message: ChatMessage
    let isStreaming: Bool
    @ObservedObject var preferences: Preferences
    let onCopy: () -> Void
    var onRetry: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var actionsDisabled = false
    @State private var expanded = false
    @State private var showActivity = false

    private var waiting: Bool { isStreaming && message.content.isEmpty }
    private var hasThinking: Bool { preferences.showThinking && !message.reasoning.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasThinking {
                TimelineView(.animation(minimumInterval: 1, paused: !waiting)) { timeline in
                    Button {
                        expanded.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            if waiting && showActivity { ThinkingGlyph().frame(width: 20, height: 16) }
                            Text(waiting ? "Thinking… " + ThinkingDuration.label(message.thinkingDuration(at: timeline.date)) : "Thought for " + ThinkingDuration.label(message.thinkingDuration()))
                            Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .medium))
                        }
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                }
                if expanded {
                    ResponseView(markdown: message.reasoning, isStreaming: waiting, textSize: preferences.answerTextSize.points - 1)
                        .padding(12)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
            } else if waiting {
                HStack(spacing: 8) {
                    if showActivity { ThinkingGlyph().frame(width: 20, height: 16) }
                    Text("Working…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Waiting for an answer")
            }
            if !message.content.isEmpty {
                ResponseView(markdown: message.content, isStreaming: isStreaming, textSize: preferences.answerTextSize.points)
                HStack(spacing: 14) {
                    Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
                        .accessibilityLabel("Copy answer")
                        .help("Copy the newest answer, including when viewing an older version")
                    if let onRetry { Button(action: onRetry) { Label("Retry", systemImage: "arrow.clockwise") }.accessibilityLabel("Retry generation") }
                    if let onEdit { Button(action: onEdit) { Label("Edit prompt", systemImage: "pencil") }.accessibilityLabel("Edit prompt") }
                }
                .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(.secondary)
                .disabled(actionsDisabled)
            }
        }
        .task(id: waiting) {
            showActivity = false
            guard waiting else { return }
            let elapsed = Date.now.timeIntervalSince(message.generationStartedAt ?? .now)
            let delay = max(0, 0.5 - elapsed)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            showActivity = true
        }
    }
}

enum ThinkingDuration {
    static func label(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(seconds))
        if seconds == 0 { return "<1 sec" }
        if seconds < 60 { return "\(seconds) sec" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder) sec"
    }
}

/// Three quiet, phase-shifted strokes fold toward the center while a response is pending.
struct ThinkingGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<3 {
                    let phase = sin(time * 2.4 - Double(index) * 0.9)
                    let height = 4 + (phase + 1) * 3
                    let rect = CGRect(x: Double(index) * 6 + 1, y: (size.height - height) / 2, width: 2, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.secondary.opacity(0.5 + Double(index) * 0.15)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
