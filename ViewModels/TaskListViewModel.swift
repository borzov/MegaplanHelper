import Combine
import Foundation
import SwiftUI

/// Section displayed in the Tasks tab — items grouped by date bucket of the active sort key.
struct TaskGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let tasks: [MegaplanTask]
}

@MainActor
final class TaskListViewModel: ObservableObject {
    @Published private(set) var tasks: [MegaplanTask] = []
    @Published private(set) var groupedTasks: [TaskGroup] = []
    @Published var searchQuery: String = ""
    @Published var isSearchActive: Bool = false
    @Published var isFilterPanelActive: Bool = false
    @Published private(set) var isServerSearching: Bool = false

    let appState: AppState
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var visitedTaskIds: Set<String> = []
    private var serverSearchResults: [MegaplanTask] = []
    private var lastServerSearchQuery: String = ""
    private var serverSearchTask: Task<Void, Never>?
    private static let minSearchLength = 2

    init(appState: AppState, userDefaults: UserDefaults = .standard) {
        self.appState = appState
        self.userDefaults = userDefaults

        if let stored = userDefaults.array(forKey: Constants.UserDefaultsKeys.visitedTaskIds) as? [String] {
            visitedTaskIds = Set(stored)
        }

        appState.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newTasks in
                self?.tasks = newTasks
                self?.recomputeGroups()
            }
            .store(in: &cancellables)

        // Recompute when sort key changes so date-bucket grouping stays consistent.
        appState.$taskSortKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeGroups()
            }
            .store(in: &cancellables)

        // Local filter is instant — every keystroke recomputes against the cache.
        $searchQuery
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeGroups()
            }
            .store(in: &cancellables)

        // Server search runs in parallel with a debounce so we don't fire a request
        // for every keystroke; latest result wins thanks to per-query Task cancellation.
        $searchQuery
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] query in
                self?.scheduleServerSearch(for: query)
            }
            .store(in: &cancellables)

        recomputeGroups()
    }

    func refresh() async {
        await appState.refresh()
    }

    func setSortKey(_ key: TaskSortKey) {
        appState.updateTaskSortKey(key)
    }

    func setStatusFilter(_ filter: TaskStatusFilter) {
        appState.updateTaskStatusFilter(filter)
    }

    func toggleSearch() {
        isSearchActive.toggle()
        if !isSearchActive {
            searchQuery = ""
            cancelServerSearch()
        }
    }

    func clearSearch() {
        searchQuery = ""
        cancelServerSearch()
    }

    /// Triggered by Shift+Cmd-click on a task card. Pulls comments and copies a
    /// markdown export. Best-effort — failures are logged.
    func copyCommentsAsMarkdown(for task: MegaplanTask) async {
        _ = await appState.copyTaskCommentsAsMarkdown(for: task)
    }

    func isVisited(_ task: MegaplanTask) -> Bool {
        visitedTaskIds.contains(task.id)
    }

    func markAsVisited(_ task: MegaplanTask) {
        visitedTaskIds.insert(task.id)
        userDefaults.set(Array(visitedTaskIds), forKey: Constants.UserDefaultsKeys.visitedTaskIds)
        objectWillChange.send()
    }

    // MARK: - Server search

    private func scheduleServerSearch(for rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearchActive, trimmed.count >= Self.minSearchLength else {
            cancelServerSearch()
            return
        }
        guard trimmed != lastServerSearchQuery else { return }

        serverSearchTask?.cancel()
        lastServerSearchQuery = trimmed
        isServerSearching = true

        let task = Task { [weak self, trimmed] in
            guard let self else { return }
            let results = await self.appState.searchTasks(query: trimmed)
            if Task.isCancelled { return }
            await MainActor.run {
                // Drop late results from stale queries.
                guard self.lastServerSearchQuery == trimmed, self.isSearchActive else { return }
                self.serverSearchResults = results
                self.isServerSearching = false
                self.recomputeGroups()
            }
        }
        serverSearchTask = task
    }

    private func cancelServerSearch() {
        serverSearchTask?.cancel()
        serverSearchTask = nil
        if !serverSearchResults.isEmpty {
            serverSearchResults = []
        }
        lastServerSearchQuery = ""
        isServerSearching = false
    }

    private func mergeForSearch(query: String) -> [MegaplanTask] {
        let lowered = query.lowercased()
        let cached = tasks.filter { task in
            task.name.lowercased().contains(lowered)
                || (task.responsible?.name.lowercased().contains(lowered) ?? false)
                || (task.owner?.name.lowercased().contains(lowered) ?? false)
        }
        // Append server-only matches (de-dup by id) so cache hits stay on top.
        var seen = Set(cached.map(\.id))
        var merged = cached
        for task in serverSearchResults where !seen.contains(task.id) {
            merged.append(task)
            seen.insert(task.id)
        }
        return merged
    }

    private func recomputeGroups() {
        let filtered: [MegaplanTask]
        if isSearchActive, searchQuery.count >= Self.minSearchLength {
            filtered = mergeForSearch(query: searchQuery)
        } else {
            filtered = tasks
        }

        let sortKey = appState.taskSortKey
        let now = Date()

        // Bucket by date of the active sort timestamp, preserving server-side ordering inside each bucket.
        var buckets: [(DateFormatters.Bucket, [MegaplanTask])] = [
            (.today, []), (.yesterday, []), (.thisWeek, []), (.earlier, [])
        ]
        let indexByBucket: [DateFormatters.Bucket: Int] = [.today: 0, .yesterday: 1, .thisWeek: 2, .earlier: 3]

        for task in filtered {
            let bucket = DateFormatters.bucket(for: task.timestamp(for: sortKey), now: now)
            if let idx = indexByBucket[bucket] {
                buckets[idx].1.append(task)
            }
        }

        let nonEmpty = buckets.filter { !$0.1.isEmpty }
        groupedTasks = nonEmpty.enumerated().map { offset, pair in
            TaskGroup(id: "bucket-\(offset)-\(pair.0)", title: pair.0.title, tasks: pair.1)
        }
    }
}

extension DateFormatters.Bucket: Hashable {}
