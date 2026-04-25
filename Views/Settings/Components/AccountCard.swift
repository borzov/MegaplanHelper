import SwiftUI

/// Account header card used at the top of AccountSettingsView.
/// Shows avatar, full name, email, domain and connection status.
struct AccountCard: View {
    let displayName: String
    let email: String
    let domain: String
    let avatar: NSImage?
    let isConnected: Bool
    let lastSyncRelative: String?

    var body: some View {
        HStack(spacing: 12) {
            avatarView
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().stroke(.separator, lineWidth: 0.5))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.headline)
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(domain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? .green : .secondary)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(isConnected ? .green : .secondary)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatar {
            Image(nsImage: avatar).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [.purple, .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(initials)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var statusText: String {
        if let lastSyncRelative {
            return isConnected
                ? String(format: String(localized: "settings.account.connectedSyncedAgo"), lastSyncRelative)
                : String(localized: "settings.account.disconnected")
        } else {
            return isConnected
                ? String(localized: "settings.account.connected")
                : String(localized: "settings.account.disconnected")
        }
    }
}

#Preview {
    AccountCard(
        displayName: "Максим Борзов",
        email: "max@megaplan.ru",
        domain: "demo.megaplan.ru",
        avatar: nil,
        isConnected: true,
        lastSyncRelative: "12 мин назад"
    )
    .frame(width: 480)
    .padding()
}
