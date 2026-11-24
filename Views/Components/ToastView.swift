import SwiftUI

struct ToastView: View {
    @Environment(\.popoverFontMetrics) private var metrics
    let message: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: metrics.iconLarge - 20, weight: .medium))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: metrics.body, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.green)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - View Modifier

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    let icon: String

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 8) {
                if isShowing {
                    ToastView(message: message, icon: icon)
                        .padding(.bottom, 8)
                }
            }
    }
}

extension View {
    func toast(isShowing: Binding<Bool>, message: String, icon: String = "checkmark.circle.fill") -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message, icon: icon))
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var showToast = true

        var body: some View {
            VStack {
                Button("Show Toast") {
                    showToast = true
                }
            }
            .frame(width: 400, height: 600)
            .toast(isShowing: $showToast, message: "Marked as read")
            .task(id: showToast) {
                guard showToast else { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                showToast = false
            }
        }
    }

    return PreviewWrapper()
}
