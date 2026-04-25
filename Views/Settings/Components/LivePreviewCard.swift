import SwiftUI

/// Renders a mock notification card that reacts to current Appearance settings
/// (theme + fontSize). Used inside AppearanceSettingsView.
struct LivePreviewCard: View {
    @AppStorage("appTheme") private var theme: String = "system"
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
                    .frame(width: 30, height: 30)
                    .overlay(Text("АП").font(.caption.weight(.semibold)).foregroundStyle(.white))

                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text("Анна Петрова").fontWeight(.semibold)
                        Spacer()
                        Text("14:32").foregroundStyle(.secondary)
                    }
                    .font(scaledFont(.caption))

                    Text(String(localized: "settings.appearance.preview.title2"))
                        .font(scaledFont(.subheadline))

                    Text(String(localized: "settings.appearance.preview.body"))
                        .font(scaledFont(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 0.5))
        }
        .preferredColorScheme(scheme)
    }

    private var scheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    private func scaledFont(_ base: Font) -> Font {
        switch fontSize {
        case "small":  return base
        case "large":  return base.weight(.semibold)
        default:       return base
        }
    }
}

#Preview {
    LivePreviewCard().frame(width: 320).padding()
}
