import AppKit
import SwiftUI

struct NotificationListView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: NotificationListViewModel
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @Binding var showingSettings: Bool
    @State private var showToast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if appState.isAuthenticated {
                content
            } else {
                AuthView()
            }
            
            Spacer()
            
            if appState.isAuthenticated {
                bottomButtons
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert(item: $appState.alertItem) { alert in
            Alert(
                title: Text("error.title"),
                message: Text(alert.message),
                dismissButton: .default(Text("general.ok"))
            )
        }
        .onAppear {
            if appState.isAuthenticated {
                Task {
                    await viewModel.refresh()
                }
            }
        }
        .onChange(of: appState.notifications) { _ in
            // Обновляем ViewModel при изменении уведомлений в AppState
            viewModel.updateGroupedNotifications()
        }
        .toast(isShowing: $showToast, message: String(localized: "toast.markedAsRead"))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.isAuthenticated {
                HStack {
                    Text("notifications.title")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            viewModel.isSearchActive.toggle()
                            if !viewModel.isSearchActive {
                                viewModel.clearSearch()
                            }
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(viewModel.isSearchActive ? .accentColor : .primary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("notifications.search"))
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(viewModel.isSearchActive ? Color.accentColor.opacity(0.15) : Color.clear)
                            .frame(width: 24, height: 24)
                    )
                    .buttonPressEffect()
                    
                    Button {
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("notifications.refresh"))
                    .buttonPressEffect()
                }
                
                // Персональное приветствие
                if !appState.firstName.isEmpty {
                    if viewModel.isSearchActive && viewModel.searchQuery.count >= 2 {
                        Text(String(format: String(localized: "notifications.search.results"), viewModel.searchResultsCount))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text(String(format: String(localized: "notifications.greeting"), appState.firstName, appState.unreadCount))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                HStack {
                    Text("notifications.title")
                        .font(.headline)
                    
                    Spacer()
                }
            }
        }
    }
    
    private var bottomButtons: some View {
        HStack(spacing: 14) {
            // Кнопка API логов только для администратора
            if appState.isAdmin {
                Button {
                    let logContent = APILogger.getLogContent()
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logContent, forType: .string)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Copy API Log"))
                .buttonPressEffect()
                
                // Кнопки быстрого доступа
                Button {
                    if let url = URL(string: "https://\(appState.domain)/knowledge/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "book.closed")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Knowledge Base"))
                .buttonPressEffect()
                
                Button {
                    if let url = URL(string: "https://\(appState.domain)/deals/list/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "briefcase")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Deals"))
                .buttonPressEffect()
                
                Button {
                    if let url = URL(string: "https://\(appState.domain)/task/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Tasks"))
                .buttonPressEffect()
            }
            
            Spacer()
            
            Button {
                SettingsWindowManager.shared.showSettings(appState: appState, settingsViewModel: settingsViewModel)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Settings"))
            .buttonPressEffect()
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Quit Application"))
            .buttonPressEffect()
        }
        .padding(.vertical, 0)
        .padding(.horizontal, 4)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            
            TextField("notifications.search.placeholder", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .onSubmit {
                    if viewModel.searchQuery.isEmpty {
                        viewModel.clearSearch()
                    }
                }
            
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.clearSearch()
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
            if viewModel.isLoading {
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
    @State private var avatarLoadTask: Task<Void, Never>?
    @State private var cachedSenderName: String?
    @State private var isPressed = false
    
    private var cardBackgroundColor: Color {
        if notification.isMention {
            return Color.orange.opacity(0.08)
        } else if notification.isCommentNotification {
            return Color.blue.opacity(0.05)
        } else if notification.isStatusChangeNotification {
            return Color.green.opacity(0.05)
        } else {
            return Color(.windowBackgroundColor)
        }
    }
    
    private var cardBorderColor: Color {
        if notification.isMention {
            return Color.orange.opacity(0.3)
        } else if notification.isCommentNotification {
            return Color.blue.opacity(0.2)
        } else if notification.isStatusChangeNotification {
            return Color.green.opacity(0.2)
        } else {
            return Color.clear
        }
    }
    
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // Аватарка
                Group {
                    if isLoadingAvatar {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            )
                    } else if let image = avatarImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 14))
                            )
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    // ФИО с иконкой категории
                    HStack(spacing: 6) {
                        Image(systemName: categoryIcon)
                            .foregroundColor(categoryColor)
                            .font(.caption2)
                        
                        if let senderName = notification.senderName ?? cachedSenderName {
                            Text(senderName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                    }
                    
                    // Время под ФИО
                    HStack(alignment: .center, spacing: 6) {
                        Text(notification.displayDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
            
            // Контент без отступа (выровнен по левому краю)
            VStack(alignment: .leading, spacing: notification.title.isEmpty ? 0 : 6) {
                if !notification.title.isEmpty {
                    Text(notification.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                // Показываем количество комментариев только для уведомлений о комментариях
                // Используем unreadCommentsCount если есть, иначе size только для комментариев
                let commentsCount = notification.isCommentNotification ? (notification.unreadCommentsCount > 0 ? notification.unreadCommentsCount : notification.size) : 0
                if commentsCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right.fill")
                            .font(.caption2)
                        Text(String(format: String(localized: "notifications.comments"), commentsCount, commentsCount.pluralized((one: String(localized: "notifications.comment.one"), few: String(localized: "notifications.comment.few"), many: String(localized: "notifications.comment.many")))))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(categoryColor)
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                Button {
                    onMarkRead()
                } label: {
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .brightness(isPressed ? -0.05 : 0)
        .opacity(viewModel.isVisited(notification) ? 0.65 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .animation(.easeInOut(duration: 0.3), value: isMarkingAsRead)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isVisited(notification))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    // Открываем ссылку после завершения жеста
                    openNotificationLink()
                }
        )
        .onChange(of: notification.isRead) { _ in
            isMarkingAsRead = false
        }
        .task(priority: .userInitiated) {
            avatarLoadTask = Task(priority: .userInitiated) {
                await loadAvatar()
            }
            await avatarLoadTask?.value
        }
        .onDisappear {
            avatarLoadTask?.cancel()
            avatarLoadTask = nil
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
        NotificationListView(showingSettings: .constant(false))
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
