import AppKit
import SwiftUI

struct NotificationListView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: NotificationListViewModel
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @State private var showToast = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            contextualHeader

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if appState.isAuthenticated {
                Task {
                    await viewModel.refresh()
                }
            }
        }
        // Примечание: ViewModel уже подписан на appState.$notifications через Combine
        // Не добавляйте .onChange здесь чтобы избежать дублирования обновлений
        .toast(isShowing: $showToast, message: String(localized: "toast.markedAsRead"))
    }

    /// Tab-local header: subtitle + search toggle. The greeting + global refresh
    /// are owned by `PopoverHeaderView` in `RootPopoverView`.
    private var contextualHeader: some View {
        HStack(spacing: 8) {
            if viewModel.isSearchActive && viewModel.searchQuery.count >= 2 {
                Text(String(format: String(localized: "notifications.search.results"), viewModel.searchResultsCount))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if appState.unreadCount > 0 {
                Text(String(format: String(localized: "notifications.greeting"), appState.firstName, appState.unreadCount))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                withAnimation {
                    viewModel.isSearchActive.toggle()
                    if viewModel.isSearchActive {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFieldFocused = true
                        }
                    } else {
                        viewModel.clearSearch()
                        isSearchFieldFocused = false
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(viewModel.isSearchActive ? .accentColor : .primary)
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("notifications.search"))
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))

            TextField("notifications.search.placeholder", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    if viewModel.searchQuery.isEmpty {
                        viewModel.clearSearch()
                    }
                }
            
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.clearSearch()
                    // Keep focus on search field after clearing
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("notifications.search.clear"))
                .buttonPressEffect()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
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
            VStack(spacing: 12) {
                if viewModel.isSearchActive {
                    searchBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    // Offline banner
                    if appState.isOffline {
                        OfflineBannerView(lastSyncTime: appState.lastSyncTime)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ForEach(viewModel.groupedNotifications) { group in
                        if !group.title.isEmpty {
                            // Заголовок группы
                            Text(group.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 4)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }
                        
                        ForEach(group.notifications) { notification in
                            NotificationRow(notification: notification, onMarkRead: {
                                viewModel.markAsRead(notification)
                                withAnimation {
                                    showToast = true
                                }
                            })
                            .environmentObject(viewModel)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .refreshable {
                await viewModel.refresh()
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.groupedNotifications.count)
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isSearchActive)
        }
    }
}

private struct NotificationRow: View {
    let notification: MegaplanNotification
    let onMarkRead: () -> Void
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: NotificationListViewModel
    @State private var isMarkingAsRead = false
    @State private var avatarImage: NSImage?
    @State private var isLoadingAvatar = false
    @State private var cachedSenderName: String?

    private var categoryIcon: String {
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

    private var tint: EntityCardTint {
        if notification.isMention { return .mention }
        if notification.isCommentNotification { return .comment }
        if notification.isStatusChangeNotification { return .statusChange }
        return .neutral
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
            categoryIcon: .init(systemName: categoryIcon, color: categoryColor),
            time: notification.displayDate,
            title: notification.title,
            bodyText: notification.body.isEmpty ? nil : notification.body,
            subBody: nil,
            badge: commentBadge,
            tint: tint,
            isVisited: viewModel.isVisited(notification),
            onTap: openNotificationLink,
            trailing: { AnyView(markAsReadButton) }
        )
        .overlay(loadingAvatarOverlay)
        .animation(.easeInOut(duration: 0.3), value: isMarkingAsRead)
        .onChange(of: notification.isRead) { _ in
            isMarkingAsRead = false
        }
        .task(id: notification.senderId) {
            await loadAvatar()
        }
    }

    @ViewBuilder
    private var markAsReadButton: some View {
        Button(action: onMarkRead) {
            HStack(spacing: 4) {
                if isMarkingAsRead {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.green)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isMarkingAsRead)
        .accessibilityLabel(Text("notifications.markRead"))
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
        
        // Проверяем, что URL валидный перед открытием
        var finalURL = link
        
        // Если URL относительный (нет схемы или хоста), строим полный URL
        if link.scheme == nil || link.host == nil {
            if link.path.hasPrefix("/") {
                // Относительный URL - строим полный URL используя домен
                let domain = appState.domain.hasPrefix("http") ? appState.domain : "https://\(appState.domain)"
                if let baseURL = URL(string: domain),
                   let fullURL = URL(string: link.path, relativeTo: baseURL) {
                    finalURL = fullURL
                    AppLogger.debug("Constructed full URL from relative path: \(link.path) -> \(finalURL.absoluteString)")
                } else {
                    AppLogger.error("Failed to construct full URL from relative path: \(link.path), domain: \(domain)")
                    return
                }
            } else {
                AppLogger.error("Invalid notification link (no scheme/host and not relative): \(link.absoluteString)")
                return
            }
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
        // Проверяем отмену задачи перед началом
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
        
        // Проверяем отмену перед загрузкой из кеша
        guard !Task.isCancelled else { return }
        
        // Try to load from cache first (быстрая операция)
        if await loadAvatarFromCache(senderId: senderId) {
            extractSenderNameFromContent()
            return
        }
        
        // Проверяем отмену перед загрузкой из сети
        guard !Task.isCancelled else { return }
        
        // Try to load from provided URL
        if let avatarURL = notification.senderAvatarURL {
            let finalURL = buildFullAvatarURL(from: avatarURL)
            if await loadAvatarFromURL(finalURL, userId: senderId) {
                extractSenderNameFromContent()
                return
            }
        }
        
        // Проверяем отмену перед fallback загрузкой
        guard !Task.isCancelled else { return }
        
        // Try fallback if domain is available
        if !appState.domain.isEmpty {
            await tryFallbackAvatarLoad(senderId: senderId)
        } else {
            AppLogger.debug("Cannot load avatar - missing domain")
        }
        
        extractSenderNameFromContent()
    }
    
    private func loadAvatarFromCache(senderId: String) async -> Bool {
        guard let cached = await UserInfoCache.shared.getUserInfo(for: senderId) else {
            AppLogger.debug("No cached user info found for \(senderId)")
            return false
        }
        
        // Update cached sender name if notification doesn't have it
        if notification.senderName == nil, let cachedName = cached.name {
            await MainActor.run {
                self.cachedSenderName = cachedName
                AppLogger.debug("Updated sender name from cache: \(cachedName)")
            }
        }
        
        // Use cached avatar URL if available
        guard let cachedAvatarURL = cached.avatarURL else {
            AppLogger.debug("User \(senderId) has no avatar (cached)")
            return true // Return true to indicate we checked cache
        }
        
        AppLogger.debug("Loading avatar from cache for \(senderId) from URL: \(cachedAvatarURL.absoluteString)")
        let image = await AvatarCacheManager.shared.loadImage(from: cachedAvatarURL, for: senderId)
        
        await MainActor.run {
            self.avatarImage = image
            if image == nil {
                AppLogger.debug("Failed to load avatar from cache for \(senderId)")
            } else {
                AppLogger.debug("Successfully loaded avatar from cache for \(senderId)")
            }
        }
        
        return image != nil
    }
    
    private func buildFullAvatarURL(from avatarURL: URL) -> URL {
        // Handle relative URLs
        if avatarURL.scheme == nil || avatarURL.host == nil {
            if !appState.domain.isEmpty {
                let domainURL = appState.domain.hasPrefix("http") ? appState.domain : "https://\(appState.domain)"
                if let baseURL = URL(string: domainURL),
                   let fullURL = URL(string: avatarURL.path, relativeTo: baseURL) {
                    AppLogger.debug("Constructed full avatar URL from relative path: \(avatarURL.path) -> \(fullURL.absoluteString)")
                    return fullURL
                }
            }
        }
        return avatarURL
    }
    
    private func loadAvatarFromURL(_ url: URL, userId: String) async -> Bool {
        guard !Task.isCancelled else { return false }
        
        AppLogger.debug("Loading avatar for user \(userId) from URL: \(url.absoluteString)")
        
        // Используем приоритетную задачу для загрузки
        let image = await Task(priority: .userInitiated) {
            await AvatarCacheManager.shared.loadImage(from: url, for: userId)
        }.value
        
        guard !Task.isCancelled else { return false }
        
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
    
    private func tryFallbackAvatarLoad(senderId: String) async {
        guard !Task.isCancelled else { return }
        
        // Check if we already tried and cached this user
        if let cached = await UserInfoCache.shared.getUserInfo(for: senderId) {
            // Update cached sender name if notification doesn't have it
            if notification.senderName == nil, let cachedName = cached.name {
                await MainActor.run {
                    self.cachedSenderName = cachedName
                    AppLogger.debug("Updated sender name from cache in fallback: \(cachedName)")
                }
            }
            
            if cached.avatarURL == nil {
                AppLogger.debug("User \(senderId) has no avatar (cached)")
                return
            }
        }
        
        let domainURL = appState.domain.hasPrefix("http") ? appState.domain : "https://\(appState.domain)"
        
        // Try multiple avatar endpoint formats
        let avatarPaths = [
            "/api/v3/user/\(senderId)/avatar/thumbnail?size=64x64",
            "/api/v3/user/\(senderId)/avatar",
            "/api/v3/employee/\(senderId)/avatar/thumbnail?size=64x64",
            "/BumsCommonBundle/images/personal/noavatar_64x64.jpg" // Default avatar
        ]
        
        for avatarPath in avatarPaths {
            guard !Task.isCancelled else { return }
            
            if let baseURL = URL(string: domainURL),
               let avatarURL = URL(string: avatarPath, relativeTo: baseURL) {
                AppLogger.debug("Trying fallback avatar URL for senderId \(senderId): \(avatarURL.absoluteString)")
                
                // Используем приоритетную задачу для fallback загрузки
                let image = await Task(priority: .utility) {
                    await AvatarCacheManager.shared.loadImage(from: avatarURL, for: senderId)
                }.value
                
                guard !Task.isCancelled else { return }
                
                if let image = image {
                    await MainActor.run {
                        self.avatarImage = image
                    }
                    
                    // Cache the successful URL
                    await UserInfoCache.shared.cacheUserInfo(
                        userId: senderId,
                        name: notification.senderName,
                        avatarURL: avatarURL
                    )
                    
                    AppLogger.debug("Successfully loaded fallback avatar for senderId \(senderId)")
                    return
                }
            }
        }
        
        // Cache that this user has no avatar
        await UserInfoCache.shared.cacheUserInfo(
            userId: senderId,
            name: notification.senderName,
            avatarURL: nil
        )
        
        AppLogger.debug("Failed to load fallback avatar for senderId \(senderId) from all endpoints")
    }
}

extension View {
    func buttonPressEffect() -> some View {
        self.modifier(ButtonPressEffectModifier())
    }
}

private struct ButtonPressEffectModifier: ViewModifier {
    @State private var isPressed = false
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.9 : (isHovered ? 1.05 : 1.0))
            .opacity(isPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
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
