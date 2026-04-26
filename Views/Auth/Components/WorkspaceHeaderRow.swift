import SwiftUI

struct WorkspaceHeaderRow: View {
    let domain: String
    let info: WorkspaceInfo?
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text(String(localized: "auth.step2.back")))

            workspaceIcon
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(info?.displayName ?? domain)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let info, info.displayName != nil {
                    Text(info.canonicalDomain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var workspaceIcon: some View {
        if let url = info?.faviconURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "building.2.crop.circle")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.tint)
            .symbolRenderingMode(.hierarchical)
    }
}

#if DEBUG
#Preview {
    WorkspaceHeaderRow(
        domain: "acme.megaplan.ru",
        info: WorkspaceInfo(canonicalDomain: "acme.megaplan.ru",
                            displayName: "ACME",
                            faviconURL: nil,
                            supportsSSO: false),
        onBack: {}
    )
    .frame(width: 420)
}
#endif
