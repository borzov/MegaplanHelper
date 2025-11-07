import AppKit
import SwiftUI

struct NotificationListView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showingSettings: Bool

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
                appState.refreshNow()
            }
        }
        .onChange(of: showingSettings) { newValue in
            if newValue {
                SettingsWindowManager.shared.showSettings(appState: appState)
                // Reset the binding after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showingSettings = false
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.isAuthenticated {
                HStack {
                    Text("notifications.title")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button {
                        appState.refreshNow()
                    } label: {
                        if appState.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("notifications.refresh"))
                }
                
                // Персональное приветствие
                if !appState.firstName.isEmpty {
                    Text(String(format: String(localized: "notifications.greeting"), appState.firstName, appState.unreadCount))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Copy API Log"))
                
                // Кнопки быстрого доступа
                Button {
                    if let url = URL(string: "https://\(appState.domain)/knowledge/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "book.closed")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Knowledge Base"))
                
                Button {
                    if let url = URL(string: "https://\(appState.domain)/deals/list/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "briefcase")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Deals"))
                
                Button {
                    if let url = URL(string: "https://\(appState.domain)/task/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "checklist")
                        .foregroundColor(.purple)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Tasks"))
            }
            
            Spacer()
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.gray)
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Settings"))
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Quit Application"))
        }
        .padding(.vertical, 0)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var content: some View {
        if appState.notifications.isEmpty {
            if appState.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("notifications.loading")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Text("notifications.empty")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .foregroundColor(.secondary)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.notifications) { notification in
                        NotificationRow(notification: notification, onMarkRead: {
                            appState.markNotificationAsRead(notification)
                        })
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.vertical, 2)
            }
            .refreshable {
                await appState.refresh()
            }
        }
    }
}

private struct NotificationRow: View {
    let notification: MegaplanNotification
    let onMarkRead: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var isMarkingAsRead = false
    @State private var avatarImage: NSImage?
    @State private var isLoadingAvatar = false
    @State private var avatarLoadTask: Task<Void, Never>?
    @State private var cachedSenderName: String?

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
                    // ФИО
                    if let senderName = notification.senderName ?? cachedSenderName {
                        Text(senderName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    
                    // Время под ФИО
                    HStack(alignment: .center, spacing: 6) {
                        Text(notification.displayDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if notification.isMention {
                            Image(systemName: "at")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                }
            }
            
            // Контент без отступа (выровнен по левому краю)
            VStack(alignment: .leading, spacing: notification.title.isEmpty ? 0 : 4) {
                if !notification.title.isEmpty {
                    Text(notification.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                
                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
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
                    .background(Color.gray)
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
                .fill(notification.isMention ? Color.orange.opacity(0.05) : Color(.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
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
            do {
                let success = NSWorkspace.shared.open(finalURL)
                if !success {
                    AppLogger.error("NSWorkspace.shared.open returned false for URL: \(finalURL.absoluteString)")
                } else {
                    AppLogger.debug("Successfully opened notification link: \(finalURL.absoluteString)")
                }
            } catch {
                AppLogger.error("Failed to open notification link: \(finalURL.absoluteString), error: \(error.localizedDescription)")
            }
        }
        .onChange(of: notification.isRead) { _ in
            isMarkingAsRead = false
        }
        .task {
            avatarLoadTask = Task {
                await loadAvatar()
            }
        }
        .onDisappear {
            avatarLoadTask?.cancel()
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
        
        // Try to load from cache first
        if await loadAvatarFromCache(senderId: senderId) {
            extractSenderNameFromContent()
            return
        }
        
        // Try to load from provided URL
        if let avatarURL = notification.senderAvatarURL {
            let finalURL = buildFullAvatarURL(from: avatarURL)
            if await loadAvatarFromURL(finalURL, userId: senderId) {
                extractSenderNameFromContent()
                return
            }
        }
        
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
        let image = await AvatarCacheManager.shared.loadImage(from: url, for: userId)
        
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
                let image = await AvatarCacheManager.shared.loadImage(from: avatarURL, for: senderId)
                
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
