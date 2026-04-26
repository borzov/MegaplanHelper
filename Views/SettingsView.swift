import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("settings.lastSection") private var lastSectionRaw: String = SettingsSection.account.rawValue
    @State private var selection: SettingsSection?
    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detailContent
        }
        .navigationTitle(String(localized: "settings.windowTitle"))
        .frame(minWidth: 720, idealWidth: 760, minHeight: 520, idealHeight: 560)
        .onAppear {
            if selection == nil {
                selection = SettingsSection(rawValue: lastSectionRaw) ?? .account
            }
        }
        .onChange(of: selection) { _, newValue in
            if let newValue { lastSectionRaw = newValue.rawValue }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            sidebarList
        }
    }

    /// Custom search field embedded above the list — matches the look of
    /// macOS Sonoma+ System Settings (single capsule, full sidebar width).
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            TextField(String(localized: "settings.searchPrompt"), text: $searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .help(String(localized: "general.clear"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(searchFocused ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .animation(.snappy(duration: 0.18), value: searchFocused)
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            ForEach(SettingsGroup.allCases) { group in
                let visible = visibleSections(for: group)
                if !visible.isEmpty {
                    Section {
                        ForEach(visible, id: \.self) { section in
                            NavigationLink(value: section) {
                                Label {
                                    Text(section.titleKey)
                                } icon: {
                                    Image(systemName: section.iconName)
                                        .frame(width: 18, height: 18)
                                        .foregroundStyle(.white)
                                        .background(tintColor(section.tint), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    } header: {
                        Text(group.titleKey)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func visibleSections(for group: SettingsGroup) -> [SettingsSection] {
        let allInGroup = SettingsSection.allCases.filter { $0.group == group }
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return allInGroup }
        let matches = Set(SettingsSearchIndex.shared.search(trimmed))
        return allInGroup.filter { matches.contains($0) }
    }

    private func tintColor(_ tint: SettingsSection.TintColor) -> Color {
        switch tint {
        case .purple: return .purple
        case .blue:   return .blue
        case .red:    return .red
        case .orange: return .orange
        case .grey:   return .gray
        case .green:  return .green
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .account {
        case .account:       AccountSettingsView()
        case .sync:          SyncSettingsView()
        case .appearance:    AppearanceSettingsView()
        case .notifications: NotificationsSettingsView()
        case .shortcuts:     ShortcutsSettingsView()
        case .storage:       StorageSettingsView()
        case .about:         AboutView()
        }
    }
}
