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

    let appState: AppState
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var visitedTaskIds: Set<String> = []

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

        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeGroups()
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
        }
    }

    func clearSearch() {
        searchQuery = ""
    }

    func isVisited(_ task: MegaplanTask) -> Bool {
        visitedTaskIds.contains(task.id)
    }

    func markAsVisited(_ task: MegaplanTask) {
        visitedTaskIds.insert(task.id)
        userDefaults.set(Array(visitedTaskIds), forKey: Constants.UserDefaultsKeys.visitedTaskIds)
        objectWillChange.send()
    }

    private func recomputeGroups() {
        let filtered: [MegaplanTask]
        if isSearchActive, searchQuery.count >= 2 {
            let query = searchQuery.lowercased()
            filtered = tasks.filter { task in
                task.name.lowercased().contains(query)
                    || (task.responsible?.name.lowercased().contains(query) ?? false)
                    || (task.owner?.name.lowercased().contains(query) ?? false)
            }
        } else {
            filtered = tasks
        }

        let sortKey = appState.taskSortKey
        let now = Date()

        // Bucket by date of the active sort timestamp, preserving server-side ordering inside each bucket.
        var buckets: [(DateFormatters.Bucket, [MegaplanTask])] = [
            (.today, []), (.yesterday, []), (.thisWeek, []), (.earlier, [])
        ]
        var indexByBucket: [DateFormatters.Bucket: Int] = [.today: 0, .yesterday: 1, .thisWeek: 2, .earlier: 3]

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
