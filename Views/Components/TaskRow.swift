import AppKit
import SwiftUI

struct TaskRow: View {
    let task: MegaplanTask
    let sortKey: TaskSortKey
    let isVisited: Bool
    let onOpen: () -> Void

    @State private var resolvedName: String?
    @State private var resolvedAvatarURL: URL?
    @State private var avatarImage: NSImage?

    private var primaryParticipant: TaskParticipant? {
        task.responsible ?? task.owner
    }

    private var participantId: String? {
        let id = primaryParticipant?.id
        return (id?.isEmpty == false) ? id : nil
    }

    private var displayName: String? {
        if let name = primaryParticipant?.name, !name.isEmpty { return name }
        if let resolvedName, !resolvedName.isEmpty { return resolvedName }
        return nil
    }

    private var isActorPlaceholder: Bool { displayName == nil }

    private var actorName: String {
        displayName ?? String(localized: "tasks.responsible.none")
    }

    private var avatarSource: EntityCardAvatar {
        if let image = avatarImage {
            return .image(image)
        }
        if !isActorPlaceholder, let participant = primaryParticipant, !participant.initials.isEmpty {
            return .initials(participant.initials)
        }
        return .icon("person.fill")
    }

    private var tint: EntityCardTint {
        if task.status == .overdue || task.status == .expired { return .overdue }
        if task.unreadCommentsCount > 0 { return .comment }
        return .neutral
    }

    private var badge: EntityCardBadge? {
        guard task.unreadCommentsCount > 0 else { return nil }
        return .init(systemName: "bubble.right.fill",
                     text: String(task.unreadCommentsCount),
                     color: .blue)
    }

    private var timeText: String {
        DateFormatters.relative(task.timestamp(for: sortKey))
    }

    private var subBody: String {
        String(format: String(localized: "tasks.row.created"), DateFormatters.absoluteShort(task.timeCreated))
    }

    var body: some View {
        EntityCardRow(
            avatar: avatarSource,
            actorName: actorName,
            isActorPlaceholder: isActorPlaceholder,
            categoryIcon: nil,
            time: timeText,
            title: task.name.isEmpty ? String(localized: "tasks.untitled") : task.name,
            bodyText: nil,
            subBody: subBody,
            badge: badge,
            tint: tint,
            isVisited: isVisited,
            onTap: onOpen
        )
        .task(id: participantId ?? "") {
            await resolveActor()
        }
        .task(id: resolvedAvatarURL) {
            await loadAvatar()
        }
    }

    // MARK: - Actor resolution

    private func resolveActor() async {
        // Start from whatever the DTO already exposes.
        let dtoName = primaryParticipant?.name
        let dtoURL = primaryParticipant?.avatarURL

        if let dtoName, !dtoName.isEmpty {
            await MainActor.run { resolvedName = dtoName }
        }
        if let dtoURL {
            await MainActor.run { resolvedAvatarURL = dtoURL }
        }

        // Anything missing? Ask the shared resolver — it walks UserInfoCache first
        // and only falls back to /api/v3/employee/{id} when necessary.
        guard let id = participantId else { return }
        let needsName = (dtoName?.isEmpty ?? true)
        let needsAvatar = (dtoURL == nil)
        guard needsName || needsAvatar else { return }

        if let info = await UserInfoResolver.shared.resolve(id: id) {
            await MainActor.run {
                if needsName, let name = info.name, !name.isEmpty {
                    resolvedName = name
                }
                if needsAvatar, let url = info.avatarURL {
                    resolvedAvatarURL = url
                }
            }
        }
    }

    private func loadAvatar() async {
        guard let url = resolvedAvatarURL,
              let id = participantId else {
            await MainActor.run { avatarImage = nil }
            return
        }

        if let cached = await AvatarCacheManager.shared.getCachedImage(for: id, from: url) {
            await MainActor.run { avatarImage = cached }
            return
        }
        if let loaded = await AvatarCacheManager.shared.loadImage(from: url, for: id) {
            await MainActor.run { avatarImage = loaded }
        }
    }
}
