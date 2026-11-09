import AppKit
import SwiftUI

/// A wrapping row of attachment chips, used above the question field and under sent questions.
struct AttachmentStrip: View {
    let attachments: [Attachment]
    var alignment: HorizontalAlignment = .leading
    var endpointHost: String?
    var onRemove: ((UUID) -> Void)?

    var body: some View {
        FlowLayout(spacing: 6, alignment: alignment) {
            ForEach(attachments) { attachment in
                AttachmentChip(attachment: attachment, endpointHost: endpointHost, onRemove: onRemove.map { remove in { remove(attachment.id) } })
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(attachments.count == 1 ? "1 attachment" : "\(attachments.count) attachments")
    }
}

struct AttachmentChip: View {
    let attachment: Attachment
    var endpointHost: String?
    var onRemove: (() -> Void)?
    @State private var showPreview = false
    @State private var hovering = false

    private var failed: Bool { attachment.failureMessage != nil }

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.filename)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Text(attachment.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(failed ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: 160, alignment: .leading)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovering || failed ? 1 : 0.55)
                .help("Remove \(attachment.filename)")
                .accessibilityLabel("Remove \(attachment.filename)")
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, onRemove == nil ? 10 : 5)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(hovering && attachment.isReady ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(failed ? Color.red.opacity(0.45) : Color(nsColor: .separatorColor), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .onTapGesture { if attachment.isReady { showPreview = true } }
        .popover(isPresented: $showPreview, arrowEdge: .top) {
            AttachmentPreview(attachment: attachment, endpointHost: endpointHost)
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(attachment.filename), \(attachment.detail)")
        .accessibilityAddTraits(attachment.isReady ? .isButton : [])
        .accessibilityAction(named: "Preview") { if attachment.isReady { showPreview = true } }
    }

    private var helpText: String {
        if let message = attachment.failureMessage { return "\(attachment.filename): \(message). This file won't be sent." }
        if attachment.isProcessing { return "Reading \(attachment.filename)…" }
        return "\(attachment.filename) · \(attachment.detail). Click to preview."
    }

    @ViewBuilder private var icon: some View {
        if attachment.isProcessing {
            ProgressView().controlSize(.small)
        } else if failed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
        } else if let data = attachment.content?.thumbnail, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5) }
        } else {
            Image(systemName: attachment.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct AttachmentPreview: View {
    let attachment: Attachment
    var endpointHost: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(attachment.detail).font(.caption).foregroundStyle(.secondary)
            }
            content
            if let note { Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(14)
        .frame(width: UIConstants.previewMaxWidth * 0.85)
    }

    @ViewBuilder private var content: some View {
        if let payload = attachment.content {
            switch attachment.kind {
            case .image:
                if let data = payload.images.first, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: UIConstants.previewMaxHeight)
                        .accessibilityLabel("Preview of \(attachment.filename)")
                }
            case .text:
                textPreview(payload.text ?? "")
            case .pdf:
                if payload.images.isEmpty {
                    textPreview(payload.text ?? "")
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Array(payload.images.enumerated()), id: \.offset) { index, data in
                                if let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit()
                                        .overlay { Rectangle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5) }
                                        .accessibilityLabel("Page \(index + 1)")
                                }
                            }
                        }
                    }
                    .frame(maxHeight: UIConstants.previewMaxHeight)
                }
            }
        }
    }

    private func textPreview(_ text: String) -> some View {
        ScrollView {
            Text(String(text.prefix(20_000)))
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
        }
        .frame(maxHeight: UIConstants.previewMaxHeight * 0.8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private var note: String? {
        guard let payload = attachment.content else { return nil }
        var parts: [String] = []
        if attachment.kind == .pdf {
            if !payload.images.isEmpty, let pages = payload.pageCount {
                parts.append(payload.images.count >= pages ? "Sends the text and an image of every page." : "Sends the text of every page and images of the first \(payload.images.count).")
            } else {
                parts.append("Sends the extracted text.")
            }
            if !payload.ocrPages.isEmpty {
                parts.append("Text on \(payload.ocrPages.count == 1 ? "1 page was" : "\(payload.ocrPages.count) pages were") recognized with OCR.")
            }
        }
        if payload.truncated { parts.append("Long content is truncated.") }
        if let endpointHost { parts.append("Goes to \(endpointHost) with your question.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Blurs the question field and shows a dashed drop target while files are dragged over kk.
struct AttachmentDropFeedback: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        // SwiftUI's blur doesn't reach the AppKit text view inside the field, so a material layer
        // blurs everything beneath it while the field's own contents fade out.
        content
            .blur(radius: isActive ? 3 : 0)
            .opacity(isActive ? 0.35 : 1)
            .overlay {
                if isActive {
                    shape.fill(.ultraThinMaterial)
                        .overlay { shape.fill(Color.accentColor.opacity(0.10)) }
                        .overlay {
                            shape.strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        }
                        .overlay {
                            Label("Drop to attach", systemImage: "paperclip")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Drop files to attach")
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isActive)
    }
}

/// Lays out chips left to right, wrapping onto new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = alignment == .trailing ? bounds.maxX - row.width : bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
