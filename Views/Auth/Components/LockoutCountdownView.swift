import SwiftUI

struct LockoutCountdownView: View {
    let lockedUntil: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityHidden(true)

            Text(String(localized: "auth.lockout.tryAgainIn"))
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(timerInterval: Date()...lockedUntil, countsDown: true)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
                .accessibilityLabel(Text(String(localized: "auth.lockout.countdown.label")))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

#if DEBUG
#Preview {
    LockoutCountdownView(lockedUntil: Date().addingTimeInterval(890))
        .padding()
        .frame(width: 360)
}
#endif
