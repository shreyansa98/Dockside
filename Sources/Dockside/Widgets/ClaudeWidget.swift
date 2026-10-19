import SwiftUI

struct ClaudeWidget: View {
    @ObservedObject private var chat = ClaudeChat.shared
    @Environment(\.palette) private var p

    private var subtitle: String {
        if chat.streaming { return "Thinking…" }
        if let last = chat.current?.messages.last(where: { $0.role == "assistant" && $0.error == nil }), !last.text.isEmpty {
            // Plain-text preview: drop Markdown markers and collapse lines.
            return last.text
                .replacingOccurrences(of: #"[*_`#>]+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return "Ask anything…"
    }

    var body: some View {
        Tile(width: 196, padding: 10) {
            HStack(spacing: 10) {
                ClaudeBadge(size: 42)
                    .overlay(alignment: .topTrailing) {
                        if chat.streaming {
                            Circle().fill(Color.green).frame(width: 9, height: 9)
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1))
                                .offset(x: 3, y: -3)
                                .symbolEffect(.pulse)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.primary)
                    Text(subtitle).font(.system(size: 11.5, weight: .medium)).foregroundStyle(p.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .onTapGesture { ClaudeWindowController.shared.toggle() }
        .help("Claude — ⌃⌥C")
    }
}
