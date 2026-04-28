import AppKit
import SwiftUI

struct TaskRow: View {
    let task: MegaplanTask
    let sortKey: TaskSortKey
    let isVisited: Bool
    let onOpen: () -> Void
    let onCopyMarkdown: () -> Void

    @State private var resolvedCreatorName: String?
    @State private var resolvedCreatorAvatarURL: URL?
    @State private var resolvedResponsibleName: String?
    @State private var avatarImage: NSImage?

    // MARK: - Participants

    /// "Creator" of the task — Megaplan calls this `owner`. Drives the avatar
    /// and name in the card header.
    private var creator: TaskParticipant? {
        guard let p = task.owner, !p.id.isEmpty else { return nil }
        return p
    }

    /// "Assignee" — Megaplan `responsible`. Surfaced in the card footer next to
    /// the creation date so it's visually distinct from the creator above.
    private var responsible: TaskParticipant? {
        guard let p = task.responsible, !p.id.isEmpty else { return nil }
        return p
    }

    /// Header avatar prefers creator (`owner`); falls back to responsible if
    /// the task has no creator (rare but possible for system-generated tasks).
    private var headerParticipant: TaskParticipant? {
        creator ?? responsible
    }

    private var headerParticipantId: String? {
        headerParticipant?.id
    }

    // MARK: - Display strings

    private var creatorDisplayName: String? {
        if let name = creator?.name, !name.isEmpty { return name }
        return resolvedCreatorName
    }

    private var responsibleDisplayName: String? {
        if let name = responsible?.name, !name.isEmpty { return name }
        return resolvedResponsibleName
    }

    private var headerDisplayName: String? {
        creator != nil ? creatorDisplayName : responsibleDisplayName
    }

    private var isHeaderActorPlaceholder: Bool { headerDisplayName == nil }

    private var headerActorName: String {
        headerDisplayName ?? String(localized: "tasks.creator.none")
    }

    // MARK: - Visual props

    private var avatarSource: EntityCardAvatar {
        if let image = avatarImage {
            return .image(image)
        }
        if !isHeaderActorPlaceholder, let participant = headerParticipant, !participant.initials.isEmpty {
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
                     text: Pluralization.commentsLabel(task.unreadCommentsCount),
                     color: .blue)
    }

    private var timeText: String {
        DateFormatters.relative(task.timestamp(for: sortKey))
    }

    /// Footer line: assignee name + creation date whenever the name is known (including when assignee equals creator).
    /// Falls back to date-only when the name never resolves.
    private var subBody: String {
        let createdAt = DateFormatters.absoluteShort(task.timeCreated)
        if let name = responsibleDisplayName, !name.isEmpty {
            return String(format: String(localized: "tasks.row.actorAndCreated"), name, createdAt)
        }
        return String(format: String(localized: "tasks.row.created"), createdAt)
    }

    var body: some View {
        EntityCardRow(
            avatar: avatarSource,
            actorName: headerActorName,
            isActorPlaceholder: isHeaderActorPlaceholder,
            categoryIcon: nil,
            time: timeText,
            title: task.name.isEmpty ? String(localized: "tasks.untitled") : task.name,
            bodyText: nil,
            subBody: subBody,
            badge: badge,
            tint: tint,
            isVisited: isVisited,
            onTap: handleTap
        )
        .task(id: headerParticipantId ?? "") {
            await resolveHeader()
        }
        .task(id: responsible?.id ?? "") {
            await resolveResponsibleName()
        }
        .task(id: resolvedCreatorAvatarURL) {
            await loadAvatar()
        }
    }

    // MARK: - Tap routing

    /// Shift+Cmd → copy a markdown summary of all comments to the pasteboard.
    /// Plain click → open the task in the browser.
    private func handleTap() {
        let mods = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains([.command, .shift]) {
            onCopyMarkdown()
        } else {
            onOpen()
        }
    }

    // MARK: - Async resolution

    private func resolveHeader() async {
        let dtoName = headerParticipant?.name
        let dtoURL = headerParticipant?.avatarURL

        if let dtoName, !dtoName.isEmpty {
            await MainActor.run { resolvedCreatorName = dtoName }
        }
        if let dtoURL {
            await MainActor.run { resolvedCreatorAvatarURL = dtoURL }
        }

        guard let id = headerParticipantId else { return }
        let needsName = (dtoName?.isEmpty ?? true)
        let needsAvatar = (dtoURL == nil)
        guard needsName || needsAvatar else { return }

        if let info = await UserInfoResolver.shared.resolve(id: id) {
            await MainActor.run {
                if needsName, let name = info.name, !name.isEmpty {
                    resolvedCreatorName = name
                }
                if needsAvatar, let url = info.avatarURL {
                    resolvedCreatorAvatarURL = url
                }
            }
        }
    }

    private func resolveResponsibleName() async {
        guard let participant = responsible else {
            await MainActor.run { resolvedResponsibleName = nil }
            return
        }

        if !participant.name.isEmpty {
            await MainActor.run { resolvedResponsibleName = participant.name }
            return
        }

        // Same person as creator? Skip a redundant resolve — header logic
        // already triggers the fetch under the same id.
        if participant.id == creator?.id, let cached = resolvedCreatorName {
            await MainActor.run { resolvedResponsibleName = cached }
            return
        }

        if let info = await UserInfoResolver.shared.resolve(id: participant.id),
           let name = info.name, !name.isEmpty {
            await MainActor.run { resolvedResponsibleName = name }
        }
    }

    private func loadAvatar() async {
        guard let url = resolvedCreatorAvatarURL,
              let id = headerParticipantId else {
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
