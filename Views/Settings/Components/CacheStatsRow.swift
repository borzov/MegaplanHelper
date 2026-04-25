import SwiftUI

/// Row showing avatar cache size + entry count + Clear button + visual progress.
struct CacheStatsRow: View {
    @State private var sizeBytes: Int64 = 0
    @State private var count: Int = 0
    @State private var isClearing = false

    private let limit: Int64 = Constants.CacheConfig.maxDiskCacheSize

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .file
        return f
    }()

    /// Minimum spinner display so the Clear action feels acknowledged.
    private static let perceptualClearDelay: UInt64 = 250_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.storage.avatarsTitle"))
                        .font(.headline)
                    Text(String(format: String(localized: "settings.storage.statsLine"),
                                Self.sizeFormatter.string(fromByteCount: sizeBytes),
                                count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: sizeBytes)
                }
                Spacer()
                Button(role: .destructive) {
                    Task { await clear() }
                } label: {
                    if isClearing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(String(localized: "settings.storage.clear"))
                    }
                }
                .disabled(isClearing || count == 0)
            }
            StorageBar(used: sizeBytes, limit: limit)
                .accessibilityHidden(true)
        }
        // Refresh runs once on appear; users see live updates after the next time they
        // re-open Storage settings. A periodic Timer would address concurrent cache
        // growth, but is deferred — Phase 1 doesn't require it.
        .task { await refresh() }
    }

    private func refresh() async {
        sizeBytes = await AvatarCacheManager.shared.cacheSize()
        count = await AvatarCacheManager.shared.entryCount()
    }

    private func clear() async {
        isClearing = true
        await AvatarCacheManager.shared.clearCache()
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
