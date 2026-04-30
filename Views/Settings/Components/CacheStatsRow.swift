import SwiftUI

/// Row showing cache details across avatar, memory and snapshot caches.
struct CacheStatsRow: View {
    @EnvironmentObject private var appState: AppState

    @State private var avatarSizeBytes: Int64 = 0
    @State private var avatarCount: Int = 0
    @State private var userInfoCount: Int = 0
    @State private var snapshotSizeBytes: Int64 = 0
    @State private var snapshotNotificationsCount: Int = 0
    @State private var snapshotUnreadCount: Int = 0
    @State private var snapshotSavedAt: Date?
    @State private var isClearing = false

    private let avatarLimit: Int64 = Constants.CacheConfig.maxDiskCacheSize

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .file
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    /// Minimum spinner display so the Clear action feels acknowledged.
    private static let perceptualClearDelay: UInt64 = 250_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.storage.cacheOverviewTitle"))
                        .font(.headline)
                    Text(totalCacheSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: avatarSizeBytes)
                    Text(cacheIntro)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    Task { await clear() }
                } label: {
                    if isClearing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(String(localized: "settings.storage.clearAllCaches"))
                    }
                }
                .disabled(isClearing || !hasAnyCacheData)
            }
            StorageBar(used: avatarSizeBytes, limit: avatarLimit)
                .accessibilityLabel(String(localized: "settings.storage.avatarQuotaAccessibilityLabel"))
                .accessibilityValue(avatarQuotaAccessibilityValue)
            Text(avatarQuotaLine)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text(String(localized: "settings.storage.avatarsTitle"))
                        .foregroundStyle(.secondary)
                    Text(String(format: String(localized: "settings.storage.statsLine"),
                                Self.sizeFormatter.string(fromByteCount: avatarSizeBytes),
                                avatarCount))
                }

                GridRow {
                    Text(String(localized: "settings.storage.userInfoCacheTitle"))
                        .foregroundStyle(.secondary)
                    Text(String(format: String(localized: "settings.storage.userInfoCacheLine"),
                                userInfoCount,
                                Constants.CacheConfig.maxUserInfoEntries))
                }

                GridRow {
                    Text(String(localized: "settings.storage.snapshotCacheTitle"))
                        .foregroundStyle(.secondary)
                    Text(snapshotSummary)
                }

                GridRow {
                    Text(String(localized: "settings.storage.runtimeNotificationsTitle"))
                        .foregroundStyle(.secondary)
                    Text(String(format: String(localized: "settings.storage.runtimeNotificationsLine"),
                                appState.notifications.count,
                                appState.unreadCount))
                }
            }
            .font(.caption)
        }
        .task { await refresh() }
    }

    private var hasAnyCacheData: Bool {
        avatarCount > 0 || avatarSizeBytes > 0 || userInfoCount > 0 || snapshotSavedAt != nil
    }

    private var totalCacheSummary: String {
        let diskTotal = avatarSizeBytes + snapshotSizeBytes
        return String(format: String(localized: "settings.storage.totalSummary"),
                      Self.sizeFormatter.string(fromByteCount: diskTotal),
                      userInfoCount)
    }

    private var cacheIntro: String {
        String(
            format: String(localized: "settings.storage.cacheIntro"),
            Self.sizeFormatter.string(fromByteCount: avatarLimit),
            Constants.CacheConfig.maxUserInfoEntries,
            Int(Constants.SnapshotConfig.notificationsTTL / 3600)
        )
    }

    private var avatarQuotaLine: String {
        String(
            format: String(localized: "settings.storage.avatarQuotaLine"),
            Self.sizeFormatter.string(fromByteCount: avatarSizeBytes),
            Self.sizeFormatter.string(fromByteCount: avatarLimit)
        )
    }

    private var avatarQuotaAccessibilityValue: String {
        let percent = avatarLimit > 0 ? Int((Double(avatarSizeBytes) / Double(avatarLimit) * 100).rounded()) : 0
        return String(
            format: String(localized: "settings.storage.avatarQuotaAccessibilityValue"),
            Self.sizeFormatter.string(fromByteCount: avatarSizeBytes),
            Self.sizeFormatter.string(fromByteCount: avatarLimit),
            percent
        )
    }

    private var snapshotSummary: String {
        guard let snapshotSavedAt else {
            return String(localized: "settings.storage.snapshotMissing")
        }
        return String(
            format: String(localized: "settings.storage.snapshotLine"),
            Self.sizeFormatter.string(fromByteCount: snapshotSizeBytes),
            snapshotNotificationsCount,
            snapshotUnreadCount,
            Self.dateFormatter.string(from: snapshotSavedAt)
        )
    }

    private func refresh() async {
        avatarSizeBytes = await AvatarCacheManager.shared.cacheSize()
        avatarCount = await AvatarCacheManager.shared.entryCount()
        userInfoCount = await UserInfoCache.shared.entryCount()

        if let workspaceKey = AppState.workspaceKey(from: appState.domain),
           let stats = await NotificationsSnapshotStore.shared.snapshotStats(workspaceKey: workspaceKey) {
            snapshotSizeBytes = stats.sizeBytes
            snapshotNotificationsCount = stats.notificationsCount
            snapshotUnreadCount = stats.unreadCount
            snapshotSavedAt = stats.savedAt
        } else {
            snapshotSizeBytes = 0
            snapshotNotificationsCount = 0
            snapshotUnreadCount = 0
            snapshotSavedAt = nil
        }
    }

    private func clear() async {
        isClearing = true
        await AvatarCacheManager.shared.clearCache()
        await UserInfoCache.shared.clearCache()
        await NotificationsSnapshotStore.shared.clear()
        try? await Task.sleep(nanoseconds: Self.perceptualClearDelay)
        await refresh()
        isClearing = false
    }
}

private struct StorageBar: View {
    let used: Int64
    let limit: Int64

    var body: some View {
        GeometryReader { geo in
            let progress = limit > 0 ? min(1, Double(used) / Double(limit)) : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(progress > 0.9 ? .red : .blue)
                    .frame(width: geo.size.width * progress)
                    .animation(.snappy, value: progress)
            }
        }
        .frame(height: 6)
    }
}

#Preview {
    CacheStatsRow().frame(width: 420).padding()
}
