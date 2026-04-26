import SwiftUI

struct InlineErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .symbolRenderingMode(.hierarchical)
                .font(.callout)
                .accessibilityHidden(true)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.red.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(localized: "auth.error.banner.label")))
        .accessibilityValue(Text(message))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

#if DEBUG
#Preview {
    InlineErrorBanner(message: "Wrong login or password")
        .padding()
        .frame(width: 360)
}
#endif
