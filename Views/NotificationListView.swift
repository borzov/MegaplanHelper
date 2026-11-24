import AppKit
import SwiftUI

private enum TopBarLayout {
    static let horizontalPadding: CGFloat = 4
    static let topPadding: CGFloat = 6
    static let bottomPadding: CGFloat = 6
    static let filterTopPadding: CGFloat = -6
    static let filterBottomPadding: CGFloat = 6
    static let minFilterRowHeight: CGFloat = 24
}

struct NotificationListView: View {
    @Environment(\.popoverFontMetrics) private var metrics
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: NotificationListViewModel
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isSearchActive {
                searchBar
                    .padding(.horizontal, TopBarLayout.horizontalPadding)
                    .padding(.top, TopBarLayout.topPadding)
                    .padding(.bottom, TopBarLayout.bottomPadding)
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
                    .padding(.horizontal, TopBarLayout.horizontalPadding)
                    .padding(.top, TopBarLayout.filterTopPadding)
                    .padding(.bottom, TopBarLayout.filterBottomPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSearchActive)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isFilterPanelActive)
        .onAppear {
            if appState.isAuthenticated {
                Task {
                    await viewModel.refresh()
                }
            }
        }
        // Примечание: ViewModel уже подписан на appState.$notifications через Combine
        // Не добавляйте .onChange здесь чтобы избежать дублирования обновлений
    }

    private func markGroupAsRead(_ group: NotificationGroup) {
        for notification in group.unreadNotifications {
            viewModel.markAsRead(notification)
        }
    }

    private var searchBar: some View {
        ListSearchBar(
            placeholder: "notifications.search.placeholder",
            text: $viewModel.searchQuery,
            isFocused: $isSearchFieldFocused,
            clearAccessibilityLabel: "notifications.search.clear",
            onSubmit: {
                if viewModel.searchQuery.isEmpty {
                    viewModel.clearSearch()
                }
            },
            onClear: {
                viewModel.clearSearch()
            }
        )
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    viewModel.selectedTypeFilterKeys.removeAll()
                    viewModel.updateGroupedNotifications()
                } label: {
                    if viewModel.selectedTypeFilterKeys.isEmpty {
                        Label(String(localized: "notifications.filter.all"), systemImage: "checkmark")
                    } else {
                        Text("notifications.filter.all")
                    }
                }

                ForEach(viewModel.typeFilterOptions) { option in
                    Button {
                        if viewModel.selectedTypeFilterKeys.contains(option.typeKey) {
                            viewModel.selectedTypeFilterKeys.remove(option.typeKey)
                        } else {
                            viewModel.selectedTypeFilterKeys.insert(option.typeKey)
                        }
                        viewModel.updateGroupedNotifications()
                    } label: {
                        if viewModel.selectedTypeFilterKeys.contains(option.typeKey) {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: metrics.subBody, weight: .medium))
                    Text(selectedFilterTitle)
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

            Spacer()
        }
        .frame(minHeight: TopBarLayout.minFilterRowHeight, alignment: .leading)
    }

    private var selectedFilterTitle: String {
        guard !viewModel.selectedTypeFilterKeys.isEmpty else {
            return String(localized: "notifications.filter.all")
        }
        if viewModel.selectedTypeFilterKeys.count == 1,
           let selected = viewModel.selectedTypeFilterKeys.first,
           let option = viewModel.typeFilterOptions.first(where: { $0.typeKey == selected }) {
            return option.title
        }
        return String(format: String(localized: "notifications.filter.selectedCount"), viewModel.selectedTypeFilterKeys.count)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.notifications.isEmpty {
            if appState.isLoading {
                SkeletonListView(count: 3)
                    .transition(.opacity)
            } else {
                EmptyStateView(onRefresh: {
                    appState.refreshNow()
                })
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // Offline banner
                    if appState.isOffline {
                        OfflineBannerView(lastSyncTime: appState.lastSyncTime)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ForEach(viewModel.groupedNotifications) { group in
                        if !group.title.isEmpty {
                            notificationGroupHeader(group)
                        }

                        ForEach(group.notifications) { notification in
                            NotificationRow(notification: notification, onMarkRead: {
                                viewModel.markAsRead(notification)
                            })
                            .environmentObject(viewModel)
                        }
                    }
                }
                .padding(.vertical, 2)
                .animation(.easeOut(duration: 0.22), value: notificationFeedIDs)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    private var notificationFeedIDs: [String] {
        viewModel.groupedNotifications.flatMap { group in
            [group.id] + group.notifications.map(\.id)
        }
    }

    private func notificationGroupHeader(_ group: NotificationGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SectionHeaderText(title: group.title)
            Spacer(minLength: 8)
            if !group.unreadNotifications.isEmpty {
                NotificationMarkAllButton {
                    markGroupAsRead(group)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

private struct NotificationRow: View {
    let notification: MegaplanNotification
    let onMarkRead: () -> Void
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: NotificationListViewModel
    @State private var avatarImage: NSImage?
    @State private var isLoadingAvatar = false
    @State private var cachedSenderName: String?

    private var categoryIconName: String {
        if notification.isMention {
            return "at.circle.fill"
        } else if notification.isCommentNotification {
            return "bubble.left.and.bubble.right.fill"
        } else if notification.isStatusChangeNotification {
            return "arrow.triangle.2.circlepath.circle.fill"
        } else {
            return notification.notificationIcon
        }
    }
    
    private var categoryColor: Color {
        if notification.isMention {
            return .orange
        } else if notification.isCommentNotification {
            return .blue
        } else if notification.isStatusChangeNotification {
            return .green
        } else {
            return .gray
        }
    }

    private var cardCategoryIcon: EntityCardCategoryIcon? {
        .init(systemName: categoryIconName, color: categoryColor)
    }

    private var commentBadge: EntityCardBadge? {
        let commentsCount = notification.isCommentNotification
            ? (notification.unreadCommentsCount > 0 ? notification.unreadCommentsCount : notification.size)
            : 0
        guard commentsCount > 0 else { return nil }
        return .init(systemName: "bubble.right.fill",
                     text: Pluralization.commentsLabel(commentsCount),
                     color: categoryColor)
    }

    private var avatarSource: EntityCardAvatar {
        if let image = avatarImage { return .image(image) }
        return .icon("person.fill")
    }

    var body: some View {
        EntityCardRow(
            avatar: avatarSource,
            actorName: notification.senderName ?? cachedSenderName,
            isActorPlaceholder: false,
            categoryIcon: cardCategoryIcon,
            time: notification.displayDate,
            title: notification.title,
            bodyText: notification.body.isEmpty ? nil : notification.body,
            subBody: nil,
            badge: commentBadge,
            isVisited: viewModel.isVisited(notification),
            chrome: .plate,
            onTap: openNotificationLink,
            trailing: { markAsReadButton }
        )
        .overlay(loadingAvatarOverlay)
        .task(id: notification.senderId) {
            await loadAvatar()
        }
    }

    private var markAsReadButton: some View {
        NotificationReadButton(action: onMarkRead)
    }

    /// While the avatar is loading we want a small spinner — the overlay sits exactly
    /// where the avatar lives in `EntityCardRow`. Only shown while in-flight; the row
    /// renders the resolved image / fallback icon as soon as `avatarImage` is set.
    @ViewBuilder
    private var loadingAvatarOverlay: some View {
        if isLoadingAvatar && avatarImage == nil {
            VStack {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .padding(.leading, 20)
                        .padding(.top, 18)
                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }
    
    private func openNotificationLink() {
        guard let link = notification.link else { return }
        
        let finalURL: URL
        if link.scheme != nil, link.host != nil {
            finalURL = link
        } else if link.path.hasPrefix("/") {
            guard let resolved = WorkspaceAddress.resolve(link: link, domain: appState.domain) else {
                AppLogger.error("Failed to construct full URL from relative path: \(link.path), domain: \(appState.domain)")
                return
            }
            finalURL = resolved
            AppLogger.debug("Constructed full URL from relative path: \(link.path) -> \(finalURL.absoluteString)")
        } else {
            AppLogger.error("Invalid notification link (no scheme/host and not relative): \(link.absoluteString)")
            return
        }
        
        // Проверяем, что финальный URL валидный
        guard finalURL.scheme != nil, finalURL.host != nil else {
            AppLogger.error("Invalid final notification link: \(finalURL.absoluteString)")
            return
        }
        
        // Открываем ссылку с обработкой ошибок
        let success = NSWorkspace.shared.open(finalURL)
        if !success {
            AppLogger.error("NSWorkspace.shared.open returned false for URL: \(finalURL.absoluteString)")
        } else {
            AppLogger.debug("Successfully opened notification link: \(finalURL.absoluteString)")
            // Помечаем уведомление как посещенное после успешного открытия
            viewModel.markAsVisited(notification)
        }
    }
    
    private func loadAvatar() async {
        guard !Task.isCancelled else { return }

        await MainActor.run {
            isLoadingAvatar = true
        }

        defer {
            Task { @MainActor in
                isLoadingAvatar = false
            }
        }

        guard let senderId = notification.senderId else {
            AppLogger.debug("No senderId in notification")
            extractSenderNameFromContent()
            return
        }

        guard !Task.isCancelled else { return }

        let dtoName = notification.senderName
        if let dtoName, !dtoName.isEmpty {
            await MainActor.run { cachedSenderName = dtoName }
        }

        var didLoadAvatar = false
        if let avatarURL = notification.senderAvatarURL {
            let finalURL = buildFullAvatarURL(from: avatarURL)
            didLoadAvatar = await loadAvatarFromURL(finalURL, userId: senderId)
        }

        guard !Task.isCancelled else { return }

        let needsName = dtoName?.isEmpty ?? true
        if needsName || !didLoadAvatar {
            if let info = await UserInfoResolver.shared.resolve(id: senderId) {
                if needsName, let name = info.name, !name.isEmpty {
                    await MainActor.run { cachedSenderName = name }
                }
                if !didLoadAvatar, let url = info.avatarURL {
                    _ = await loadAvatarFromURL(url, userId: senderId)
                }
            }
        }

        extractSenderNameFromContent()
    }
    
    private func buildFullAvatarURL(from avatarURL: URL) -> URL {
        guard avatarURL.scheme == nil || avatarURL.host == nil else {
            return avatarURL
        }
        guard let fullURL = WorkspaceAddress.resolve(link: avatarURL, domain: appState.domain) else {
            return avatarURL
        }
        AppLogger.debug("Constructed full avatar URL from relative path: \(avatarURL.path) -> \(fullURL.absoluteString)")
        return fullURL
    }
    
    private func loadAvatarFromURL(_ url: URL, userId: String, allowReplacement: Bool = true) async -> Bool {
        guard !Task.isCancelled else { return false }

        AppLogger.debug("Loading avatar for user \(userId) from URL: \(url.absoluteString)")

        let image = await Task(priority: .userInitiated) {
            await AvatarCacheManager.shared.loadImage(from: url, for: userId)
        }.value

        guard !Task.isCancelled else { return false }

        if image == nil, allowReplacement,
           let next = await UserInfoResolver.shared.replacementAvatar(id: userId, failedURL: url) {
            return await loadAvatarFromURL(next, userId: userId, allowReplacement: false)
        }

        await MainActor.run {
            self.avatarImage = image
            if image == nil {
                AppLogger.debug("Failed to load avatar for user \(userId) from provided URL")
            }
        }

        return image != nil
    }
    
    private func extractSenderNameFromContent() {
        guard notification.senderName == nil && cachedSenderName == nil else { return }
        
        let content = notification.body.isEmpty ? notification.title : notification.body
        guard !content.isEmpty else { return }
        
        let extractedName = NotificationParser.extractSenderNameFromContent(content)
        if let name = extractedName {
            Task { @MainActor in
                self.cachedSenderName = name
                AppLogger.debug("Extracted sender name from content: \(name)")
            }
        }
    }
    
}

private struct NotificationReadButton: View {
    @Environment(\.popoverFontMetrics) private var metrics
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("notifications.readAction")
                .font(.system(size: metrics.badge, weight: .medium))
                .foregroundStyle(isHovered ? Color.white : Color.accentColor)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? Color.accentColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(isHovered ? 1 : 0.35), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text("notifications.readAction"))
        .help(Text("notifications.markRead"))
    }
}

private struct NotificationMarkAllButton: View {
    @Environment(\.popoverFontMetrics) private var metrics
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("notifications.markAllInGroup")
                .font(.system(size: metrics.badge, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovered = $0 }
    }
}

#if DEBUG
struct NotificationListView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationListView()
            .environmentObject({
                let state = AppState()
                state.notifications = [
                    .previewSample
                ]
                state.isAuthenticated = true
                return state
            }())
            .frame(width: 360, height: 420)
    }
}
#endif
