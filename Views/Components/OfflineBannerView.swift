import SwiftUI

struct OfflineBannerView: View {
    let lastSyncTime: Date?

    private var timeAgoText: String {
        guard let lastSync = lastSyncTime else {
            return String(localized: "offline.never")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale.current
        return formatter.localizedString(for: lastSync, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("offline.mode.title")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                if lastSyncTime != nil {
                    Text("offline.mode.lastSync \(timeAgoText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("offline.mode.noSync")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack(spacing: 12) {
        OfflineBannerView(lastSyncTime: Date().addingTimeInterval(-300))
        OfflineBannerView(lastSyncTime: nil)
    }
    .padding()
}
