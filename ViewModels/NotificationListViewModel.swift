import Combine
import Foundation
import SwiftUI

@MainActor
final class NotificationListViewModel: ObservableObject {
    @Published var notifications: [MegaplanNotification] = []
    @Published var groupedNotifications: [NotificationGroup] = []
    @Published var isLoading: Bool = false
    @Published var isOffline: Bool = false
    @Published var errorMessage: String?
    @Published var groupingEnabled: Bool = true
    @Published var showOnlyUnread: Bool = false
    
    private let appState: AppState
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var lastSuccessfulNotifications: [MegaplanNotification] = []
    
    init(appState: AppState, userDefaults: UserDefaults = .standard) {
        self.appState = appState
        self.userDefaults = userDefaults
        
        // Загружаем настройки
        groupingEnabled = userDefaults.object(forKey: Constants.UserDefaultsKeys.groupingEnabled) as? Bool ?? true
        showOnlyUnread = userDefaults.bool(forKey: Constants.UserDefaultsKeys.showOnlyUnread)
        
        // Подписываемся на изменения уведомлений из AppState
        appState.$notifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newNotifications in
                self?.notifications = newNotifications
                self?.updateGroupedNotifications()
            }
            .store(in: &cancellables)
        
        // Подписываемся на состояние загрузки
        appState.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)
        
        // Подписываемся на оффлайн-режим
        appState.$isOffline
            .receive(on: DispatchQueue.main)
            .assign(to: &$isOffline)
        
        // Инициализируем группировку
        updateGroupedNotifications()
    }
    
    func refresh() async {
        await appState.refresh()
    }
    
    func markAsRead(_ notification: MegaplanNotification) {
        appState.markNotificationAsRead(notification)
    }
    
    func updateGroupedNotifications() {
        var filteredNotifications = notifications
        
        // Фильтруем по непрочитанным, если включена настройка
        if showOnlyUnread {
            filteredNotifications = filteredNotifications.filter { !$0.isRead }
        }
        
        // Группируем, если включена настройка
        if groupingEnabled {
            groupedNotifications = NotificationGrouper.group(filteredNotifications)
        } else {
            // Если группировка отключена, создаем одну группу со всеми уведомлениями
            groupedNotifications = [NotificationGroup(
                id: "all",
                title: "",
                notifications: filteredNotifications,
                date: Date()
            )]
        }
    }
    
    func updateGroupingEnabled(_ enabled: Bool) {
        groupingEnabled = enabled
        userDefaults.set(enabled, forKey: Constants.UserDefaultsKeys.groupingEnabled)
        updateGroupedNotifications()
    }
    
    func updateShowOnlyUnread(_ enabled: Bool) {
        showOnlyUnread = enabled
        userDefaults.set(enabled, forKey: Constants.UserDefaultsKeys.showOnlyUnread)
        updateGroupedNotifications()
    }
}

