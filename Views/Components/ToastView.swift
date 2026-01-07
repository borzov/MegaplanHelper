import SwiftUI

struct ToastView: View {
    let message: String
    let icon: String
    @Binding var isShowing: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.green)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .opacity(isShowing ? 1 : 0)
        .scaleEffect(isShowing ? 1 : 0.8)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isShowing)
        .onAppear {
            // Auto-hide after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    isShowing = false
                }
            }
        }
    }
}

// MARK: - View Modifier

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    let icon: String

    func body(content: Content) -> some View {
        ZStack {
            content

            VStack {
                Spacer()
                if isShowing {
                    ToastView(message: message, icon: icon, isShowing: $isShowing)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Spacer().frame(height: 20)
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
        }
    }

    return PreviewWrapper()
}
