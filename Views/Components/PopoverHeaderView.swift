import SwiftUI

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
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isFilterActive ? .accentColor : .primary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("tasks.filter"))
                }

                Button(action: onToggleSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
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
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("notifications.refresh"))
            }

            HStack(spacing: 4) {
                TabPillButton(
                    title: AppTab.notifications.displayName,
                    count: unreadCount,
                    isSelected: selectedTab == .notifications,
                    onSelect: { selectedTab = .notifications }
                )
                TabPillButton(
                    title: AppTab.tasks.displayName,
                    count: tasksUnreadCount,
                    isSelected: selectedTab == .tasks,
                    onSelect: { selectedTab = .tasks }
                )
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.controlBackgroundColor))
            )
        }
    }
}

// MARK: - Subcomponents

private struct TabPillButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                if count > 0 {
                    Text("·")
                    Text("\(count)")
                        .font(.system(size: 12).monospacedDigit())
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(count > 0 ? Text("\(count)") : Text(""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Reusable section-header text matching the macOS sidebar group-title style.
/// Shared by `PopoverHeaderView`, `NotificationListView`, and `TaskListView`
/// so all section headers (and the toolbar inline header) look identical.
struct SectionHeaderText: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
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
