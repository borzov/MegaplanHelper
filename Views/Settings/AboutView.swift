import SwiftUI

struct AboutView: View {
    @EnvironmentObject var appState: AppState

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.linearGradient(colors: [.orange, .pink],
                                                         startPoint: .top, endPoint: .bottom))
                    VStack(alignment: .leading) {
                        Text("MegaplanHelper").font(.title2.weight(.semibold))
                        Text(version).font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(String(localized: "settings.about.linksSection")) {
                Link(destination: URL(string: "https://github.com/borzov/MegaplanHelper")!) {
                    Label(String(localized: "settings.about.github"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/borzov/MegaplanHelper#readme")!) {
                    Label(String(localized: "settings.about.docs"), systemImage: "book")
                }
                Link(destination: URL(string: "https://github.com/borzov/MegaplanHelper/issues/new")!) {
                    Label(String(localized: "settings.about.feedback"), systemImage: "envelope")
                }
            }

            if appState.isAdmin {
                Section(String(localized: "settings.about.adminSection")) {
                    Button(String(localized: "settings.about.copyLog")) {
                        appState.copyLogToPasteboard()
                    }
                    if let kbURL = appState.knowledgeBaseURL {
                        Link(String(localized: "settings.about.knowledgeBase"), destination: kbURL)
                    }
                    if let dealsURL = appState.dealsURL {
                        Link(String(localized: "settings.about.deals"), destination: dealsURL)
                    }
                    if let tasksURL = appState.tasksURL {
                        Link(String(localized: "settings.about.tasks"), destination: tasksURL)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
