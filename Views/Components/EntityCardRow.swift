import AppKit
import SwiftUI

// MARK: - Shared value types (non-generic so callers can refer to them without
// pinning a Trailing generic parameter)

enum EntityCardTint {
    case neutral
    case mention      // orange — @mentions on notifications
    case comment      // blue — has new comments
    case statusChange // green — task / item status flipped
    case overdue      // red — overdue tasks

    var background: Color {
        switch self {
        case .neutral: return Color(.windowBackgroundColor)
        case .mention: return Color.orange.opacity(0.08)
        case .comment: return Color.blue.opacity(0.05)
        case .statusChange: return Color.green.opacity(0.05)
        case .overdue: return Color.red.opacity(0.06)
        }
    }

    var border: Color {
        switch self {
        case .neutral: return .clear
        case .mention: return Color.orange.opacity(0.3)
        case .comment: return Color.blue.opacity(0.2)
        case .statusChange: return Color.green.opacity(0.2)
        case .overdue: return Color.red.opacity(0.25)
        }
    }
}

struct EntityCardCategoryIcon {
    let systemName: String
    let color: Color
}

struct EntityCardBadge {
    let systemName: String
    let text: String
    let color: Color
}

/// Avatar source — either a loaded NSImage, gradient initials, or a system fallback.
enum EntityCardAvatar {
    case image(NSImage)
    case initials(String)
    case icon(String)  // SF Symbol name
}

/// Shared card-row visual template used by both `NotificationRow` and `TaskRow`.
/// Keeps padding, shadow, avatar rendering, gestures, and tint logic in one place
/// so both lists look identical and styling tweaks land in a single file.
struct EntityCardRow<Trailing: View>: View {
    let avatar: EntityCardAvatar
    let actorName: String?
    let isActorPlaceholder: Bool   // true → render name in italic secondary tone
    let categoryIcon: EntityCardCategoryIcon?
    let time: String?
    let title: String
    let bodyText: String?
    let subBody: String?
    let badge: EntityCardBadge?
    let tint: EntityCardTint
    let isVisited: Bool
    let onTap: () -> Void
    let trailing: Trailing

    @State private var isPressed = false

    init(avatar: EntityCardAvatar,
         actorName: String?,
         isActorPlaceholder: Bool = false,
         categoryIcon: EntityCardCategoryIcon? = nil,
         time: String? = nil,
         title: String,
         bodyText: String? = nil,
         subBody: String? = nil,
         badge: EntityCardBadge? = nil,
         tint: EntityCardTint = .neutral,
         isVisited: Bool = false,
         onTap: @escaping () -> Void,
         @ViewBuilder trailing: () -> Trailing) {
        self.avatar = avatar
        self.actorName = actorName
        self.isActorPlaceholder = isActorPlaceholder
        self.categoryIcon = categoryIcon
        self.time = time
        self.title = title
        self.bodyText = bodyText
        self.subBody = subBody
        self.badge = badge
        self.tint = tint
        self.isVisited = isVisited
        self.onTap = onTap
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                avatarView

                VStack(alignment: .leading, spacing: 4) {
                    actorRow
                    if let time, !time.isEmpty {
                        Text(time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: titleBodySpacing) {
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let bodyText, !bodyText.isEmpty {
                    Text(bodyText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let subBody, !subBody.isEmpty {
                    Text(subBody)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.85))
                }
            }

            if badge != nil || hasTrailing {
                HStack(spacing: 12) {
                    if let badge {
                        badgeView(badge)
                    }
                    Spacer()
                    trailing
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tint.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .brightness(isPressed ? -0.05 : 0)
        .opacity(isVisited ? 0.65 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .animation(.easeInOut(duration: 0.3), value: isVisited)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in
                    isPressed = false
                    onTap()
                }
        )
    }

    private var titleBodySpacing: CGFloat {
        title.isEmpty ? 0 : 6
    }

    private var hasTrailing: Bool {
        Trailing.self != EmptyView.self
    }

    @ViewBuilder
    private var avatarView: some View {
        Group {
            switch avatar {
            case .image(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .initials(let initials) where !initials.isEmpty:
                Text(initials)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        LinearGradient(colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
            case .initials, .icon:
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: avatarSymbolName)
                            .foregroundColor(.gray)
                            .font(.system(size: 14))
                    )
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private var avatarSymbolName: String {
        if case .icon(let name) = avatar { return name }
        return "person.fill"
    }

    @ViewBuilder
    private var actorRow: some View {
        HStack(spacing: 6) {
            if let categoryIcon {
                Image(systemName: categoryIcon.systemName)
                    .foregroundColor(categoryIcon.color)
                    .font(.caption2)
            }
            if let actorName, !actorName.isEmpty {
                Text(actorName)
                    .font(.subheadline)
                    .fontWeight(isActorPlaceholder ? .regular : .semibold)
                    .italic(isActorPlaceholder)
                    .foregroundColor(isActorPlaceholder ? .secondary : .primary)
            }
        }
    }

    @ViewBuilder
    private func badgeView(_ badge: EntityCardBadge) -> some View {
        HStack(spacing: 6) {
            Image(systemName: badge.systemName)
                .font(.caption2)
            Text(badge.text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(badge.color)
        .clipShape(Capsule())
    }
}

extension EntityCardRow where Trailing == EmptyView {
    init(avatar: EntityCardAvatar,
         actorName: String?,
         isActorPlaceholder: Bool = false,
         categoryIcon: EntityCardCategoryIcon? = nil,
         time: String? = nil,
         title: String,
         bodyText: String? = nil,
         subBody: String? = nil,
         badge: EntityCardBadge? = nil,
         tint: EntityCardTint = .neutral,
         isVisited: Bool = false,
         onTap: @escaping () -> Void) {
        self.init(
            avatar: avatar,
            actorName: actorName,
            isActorPlaceholder: isActorPlaceholder,
            categoryIcon: categoryIcon,
            time: time,
            title: title,
            bodyText: bodyText,
            subBody: subBody,
            badge: badge,
            tint: tint,
            isVisited: isVisited,
            onTap: onTap,
            trailing: { EmptyView() }
        )
    }
}
