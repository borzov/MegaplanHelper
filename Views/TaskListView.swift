import AppKit
import SwiftUI

struct ListSearchBar: View {
    @Environment(\.popoverFontMetrics) private var metrics
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let clearAccessibilityLabel: LocalizedStringKey?
    let onSubmit: (() -> Void)?
    let onClear: (() -> Void)?

    init(
        placeholder: LocalizedStringKey,
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        clearAccessibilityLabel: LocalizedStringKey? = nil,
        onSubmit: (() -> Void)? = nil,
        onClear: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.isFocused = isFocused
        self.clearAccessibilityLabel = clearAccessibilityLabel
        self.onSubmit = onSubmit
        self.onClear = onClear
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: metrics.body))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    if let onClear {
                        onClear()
                    } else {
                        text = ""
                    }
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: metrics.body))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(clearAccessibilityLabel ?? "notifications.search.clear"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }
}

struct TaskListView: View {
    @Environment(\.popoverFontMetrics) private var metrics
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: TaskListViewModel
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isSearchActive {
                searchBar
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFieldFocused = true
                        }
                    }
                    .onDisappear { isSearchFieldFocused = false }
            }

            if viewModel.isFilterPanelActive {
                filterBar
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if appState.isOffline {
                OfflineBannerView(lastSyncTime: appState.lastTasksSyncTime ?? appState.lastSyncTime)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            content
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSearchActive)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isFilterPanelActive)
        .animation(.easeInOut(duration: 0.3), value: viewModel.groupedTasks.count)
        .onAppear {
            if appState.isAuthenticated, appState.tasks.isEmpty {
                Task { await viewModel.refresh() }
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(TaskSortKey.allCases, id: \.self) { key in
                    Button {
                        viewModel.setSortKey(key)
                    } label: {
                        if appState.taskSortKey == key {
                            Label(key.displayName, systemImage: "checkmark")
                        } else {
                            Text(key.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: metrics.subBody, weight: .medium))
                    Text(appState.taskSortKey.displayName)
                        .font(.system(size: metrics.badge))
                    Image(systemName: "chevron.down")
                        .font(.system(size: max(8, metrics.subBody - 2), weight: .semibold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(.controlBackgroundColor))
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Picker("", selection: filterBinding) {
                ForEach(TaskStatusFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 160)

            Spacer()
        }
    }

    private var filterBinding: Binding<TaskStatusFilter> {
        Binding(
            get: { appState.taskStatusFilter },
            set: { viewModel.setStatusFilter($0) }
        )
    }

    private var searchBar: some View {
        ListSearchBar(
            placeholder: "tasks.search.placeholder",
            text: $viewModel.searchQuery,
            isFocused: $isSearchFieldFocused,
            onClear: {
                viewModel.clearSearch()
            }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if appState.isTasksLoading && viewModel.tasks.isEmpty {
            SkeletonListView(count: 3)
                .transition(.opacity)
        } else if viewModel.groupedTasks.isEmpty {
            taskEmptyState
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.groupedTasks) { group in
                        if !group.title.isEmpty {
                            SectionHeaderText(title: group.title)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 7)
                        }

                        ForEach(group.tasks) { task in
                            TaskRow(
                                task: task,
                                sortKey: appState.taskSortKey,
                                isVisited: viewModel.isVisited(task),
                                onOpen: { openTask(task) },
                                onCopyMarkdown: {
                                    Task { await viewModel.copyCommentsAsMarkdown(for: task) }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    private var taskEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: metrics.iconLarge))
                .foregroundColor(.secondary)
            Text("tasks.empty.title")
                .font(.system(size: metrics.title, weight: .semibold))
                .foregroundColor(.primary)
            Text("tasks.empty.subtitle")
                .font(.system(size: metrics.badge))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: {
                Task { await viewModel.refresh() }
            }) {
                Label("notifications.refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: metrics.badge))
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Open in browser

    private func openTask(_ task: MegaplanTask) {
        guard let url = task.webURL(host: appState.domain) else {
            AppLogger.error("Failed to build task URL for id=\(task.id), domain=\(appState.domain)")
            return
        }
        let opened = NSWorkspace.shared.open(url)
        if opened {
            viewModel.markAsVisited(task)
            AppLogger.debug("Opened task in browser: \(url.absoluteString)")
        } else {
            AppLogger.error("NSWorkspace.shared.open failed for \(url.absoluteString)")
        }
    }
}
