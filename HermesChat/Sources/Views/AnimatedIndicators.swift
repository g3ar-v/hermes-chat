import SwiftUI

// MARK: - Animated Loading Circle

/// A pulsing circle that indicates the model is processing.
/// Appears in the InputBar while `loadingState == .loading` and `liveContent` is empty.
struct AnimatedLoadingCircle: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.primary)
            .opacity(isAnimating ? 0.8 : 1)
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 0.65 : 1, anchor: .center)
            .animation(
                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - Live Processing Indicator

/// A label that shows the pulsing circle + "Thinking…" while the model is generating.
/// Replaces the static status text in the InputBar's bottom row.
struct ProcessingIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            AnimatedLoadingCircle()
            Text("Thinking…")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
    }
}

// MARK: - Error Indicator

/// An animated error badge that slides in from the trailing edge.
/// Shows the error message briefly and can be dismissed.
struct ErrorIndicator: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(1)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(.red.opacity(0.1))
                .overlay(
                    Capsule()
                        .stroke(.red.opacity(0.3), lineWidth: 0.5)
                )
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ProcessingIndicator()
        ErrorIndicator(message: "Connection failed") {}
    }
    .padding()
    .frame(width: 300)
}