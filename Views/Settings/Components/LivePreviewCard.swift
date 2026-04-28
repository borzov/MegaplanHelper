import SwiftUI

/// Renders a mock notification card that reacts to current Appearance settings
/// (theme + fontSize). Used inside AppearanceSettingsView.
struct LivePreviewCard: View {
    @AppStorage("fontSize") private var fontSize: String = "medium"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.appearance.preview.title"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Circle()
                    .fill(LinearGradient(colors: [.indigo, .purple],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(Text(String(localized: "settings.appearance.preview.senderInitials"))
                                .font(.system(size: bodySize, weight: .semibold))
                                .foregroundStyle(.white))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(String(localized: "settings.appearance.preview.senderName"))
                            .font(.system(size: bodySize, weight: .semibold))
                        Spacer()
                        Text("14:32")
                            .font(.system(size: bodySize))
                            .foregroundStyle(.secondary)
                    }

                    Text(String(localized: "settings.appearance.preview.title2"))
                        .font(.system(size: titleSize, weight: .medium))
                        .lineLimit(1)

                    Text(String(localized: "settings.appearance.preview.body"))
                        .font(.system(size: bodySize))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 0.5))
        }
        .animation(.snappy(duration: 0.2), value: fontSize)
    }

    /// Explicit point sizes per fontSize bucket. `.system(size:)` is the only
    /// reliable way to make Picker changes visible in a SwiftUI preview on macOS —
    /// `.dynamicTypeSize` is an accessibility hint, not a layout override, and
    /// fixed system fonts (`.subheadline`, `.caption`) ignore it on macOS.
    private var titleSize: CGFloat {
        metrics.title
    }

    private var bodySize: CGFloat {
        metrics.badge
    }

    private var avatarSize: CGFloat {
        switch fontSize {
        case "small":  return 26
        case "large":  return 36
        default:       return 30
        }
    }

    private var metrics: PopoverFontMetrics {
        PopoverFontMetrics.resolve(fontSize)
    }
}

#Preview {
    LivePreviewCard().frame(width: 320).padding()
}
