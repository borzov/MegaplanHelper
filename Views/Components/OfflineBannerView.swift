import SwiftUI

struct OfflineBannerView: View {
    @Environment(\.popoverFontMetrics) private var metrics
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
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: metrics.iconMedium, weight: .medium))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "offline.mode.title"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                if lastSyncTime != nil {
                    Text(verbatim: "\(String(localized: "offline.mode.lastSync")) \(timeAgoText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(String(localized: "offline.mode.noSync"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        OfflineBannerView(lastSyncTime: Date().addingTimeInterval(-300))
        OfflineBannerView(lastSyncTime: nil)
    }
    .padding()
}
