import SwiftUI

struct AuthDomainStepView: View {
    @Binding var domain: String
    @Binding var probeState: DomainProbeState
    @FocusState.Binding var focus: AuthFieldFocus?
    let onContinue: () -> Void

    private var isValid: Bool {
        // .online считается актуальным только пока AuthView сбрасывает probeState в .idle при изменении domain (см. Task 12).
        if case .online = probeState { return true }
        guard !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return URLValidator.validateDomain(domain) != nil
    }

    private var isProbing: Bool {
        if case .probing = probeState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "auth.domain"))
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, options: .repeating, isActive: isProbing)
                        .accessibilityHidden(true)

                    TextField("auth.domain", text: $domain, prompt: Text(verbatim: "mycompany.megaplan.ru"))
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .domain)
                        .submitLabel(.continue)
                        .onSubmit { if isValid { onContinue() } }
                        .accessibilityIdentifier("auth.domain.field")

                    if isProbing {
                        ProgressView()
                            .controlSize(.small)
                    } else if case .online = probeState {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel(Text(String(localized: "auth.probe.online.a11y")))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                )

                if let error = errorMessage {
                    InlineErrorBanner(message: error)
                } else {
                    Text(String(localized: "auth.step1.hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: onContinue) {
                HStack {
                    Text(String(localized: "auth.step1.continue"))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid || isProbing)

            Spacer(minLength: 0)
        }
        .padding(24)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.system(size: 40))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            Text(String(localized: "auth.step1.title"))
                .font(.title3.weight(.semibold))

            Text(String(localized: "auth.step1.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var errorMessage: String? {
        switch probeState {
        case .invalid: return String(localized: "auth.error.invalidDomain")
        case .blocked: return String(localized: "auth.error.blockedDomain")
        case .unreachable: return String(localized: "auth.error.unreachableDomain")
        default: return nil
        }
    }
}
