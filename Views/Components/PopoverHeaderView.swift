import SwiftUI
import AppKit

enum AppTab: String, CaseIterable, Identifiable {
    case notifications
    case tasks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notifications: return String(localized: "tabs.notifications")
        case .tasks: return String(localized: "tabs.tasks")
        }
    }
}

struct PopoverHeaderView: View {
    @Environment(\.popoverFontMetrics) private var metrics
    @Binding var selectedTab: AppTab
    let firstName: String
    let unreadCount: Int
    let tasksUnreadCount: Int
    let isLoading: Bool
    let isSearchActive: Bool
    let isFilterActive: Bool
    let showsFilterButton: Bool
    let onRefresh: () -> Void
    let onToggleSearch: () -> Void
    let onToggleFilter: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                if !firstName.isEmpty {
                    Text(String(format: String(localized: "popover.greeting"), firstName))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("menu.title")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }

                Spacer()

                if showsFilterButton {
                    Button(action: onToggleFilter) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: metrics.iconMedium, weight: .medium))
                            .foregroundColor(isFilterActive ? .accentColor : .primary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("tasks.filter"))
                }

                Button(action: onToggleSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: metrics.iconMedium, weight: .medium))
                        .foregroundColor(isSearchActive ? .accentColor : .primary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("notifications.search"))

                Button(action: onRefresh) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: metrics.iconMedium, weight: .medium))
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("notifications.refresh"))
            }

            NativeEqualWidthSegmentedControl(
                selectedTab: $selectedTab,
                notificationTitle: tabTitle(for: .notifications, count: unreadCount),
                taskTitle: tabTitle(for: .tasks, count: tasksUnreadCount)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabTitle(for tab: AppTab, count: Int) -> String {
        let baseTitle = tab.displayName
        guard count > 0 else { return baseTitle }
        return "\(baseTitle) (\(count))"
    }
}

private struct NativeEqualWidthSegmentedControl: NSViewRepresentable {
    @Binding var selectedTab: AppTab
    let notificationTitle: String
    let taskTitle: String

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: [notificationTitle, taskTitle], trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.valueChanged(_:)))
        control.segmentStyle = .rounded
        control.segmentDistribution = .fillEqually
        control.selectedSegment = selectedIndex
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        control.setLabel(notificationTitle, forSegment: 0)
        control.setLabel(taskTitle, forSegment: 1)
        if control.selectedSegment != selectedIndex {
            control.selectedSegment = selectedIndex
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedTab: $selectedTab)
    }

    private var selectedIndex: Int {
        selectedTab == .notifications ? 0 : 1
    }

    final class Coordinator: NSObject {
        private var selectedTab: Binding<AppTab>

        init(selectedTab: Binding<AppTab>) {
            self.selectedTab = selectedTab
        }

        @objc func valueChanged(_ sender: NSSegmentedControl) {
            selectedTab.wrappedValue = sender.selectedSegment == 0 ? .notifications : .tasks
        }
    }
}

/// Reusable section-header text matching the macOS sidebar group-title style.
/// Shared by `PopoverHeaderView`, `NotificationListView`, and `TaskListView`
/// so all section headers (and the toolbar inline header) look identical.
struct SectionHeaderText: View {
    @Environment(\.popoverFontMetrics) private var metrics
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: metrics.sectionHeader, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

#if DEBUG
struct PopoverHeaderView_Previews: PreviewProvider {
    @State static var tab: AppTab = .notifications
    static var previews: some View {
        PopoverHeaderView(
            selectedTab: .constant(.notifications),
            firstName: "Максим",
            unreadCount: 12,
            tasksUnreadCount: 7,
            isLoading: false,
            isSearchActive: false,
            isFilterActive: false,
            showsFilterButton: false,
            onRefresh: {},
            onToggleSearch: {},
            onToggleFilter: {}
        )
        .padding()
        .frame(width: 370)
    }
}
#endif
