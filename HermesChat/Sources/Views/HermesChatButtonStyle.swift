import SwiftUI

// MARK: - Highlight on Hover

/// A button style that shows a subtle rounded background on hover
/// and a scale-down effect on press. Matches HuggingChat macOS patterns.
struct HighlightOnHover: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .padding(.horizontal, 7)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.gray.opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Highlight on Press

/// A simpler button style that shows background only while pressed.
struct HighlightOnPress: ButtonStyle {
    let defaultBackground: Color

    init(defaultBackground: Color = .clear) {
        self.defaultBackground = defaultBackground
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.2) : defaultBackground)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Static Extensions

extension ButtonStyle where Self == HighlightOnHover {
    static var highlightOnHover: HighlightOnHover { HighlightOnHover() }
}

extension ButtonStyle where Self == HighlightOnPress {
    static var highlightOnPress: HighlightOnPress { HighlightOnPress() }
    static func highlightOnPress(defaultBackground: Color) -> HighlightOnPress {
        HighlightOnPress(defaultBackground: defaultBackground)
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 16) {
        Button(action: {}) {
            Image(systemName: "globe")
                .font(.title3)
        }
        .buttonStyle(.highlightOnHover)

        Button(action: {}) {
            Image(systemName: "arrow.up")
                .font(.title3)
                .foregroundColor(.white)
        }
        .background(Circle().fill(Color.accentColor).frame(width: 28, height: 28))
        .buttonStyle(.highlightOnPress)
    }
    .padding()
    .frame(width: 200)
}