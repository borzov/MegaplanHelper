import Foundation

/// Domain representation of a Megaplan v3 Comment used by the markdown exporter.
struct MegaplanComment: Identifiable, Hashable {
    let id: String
    let authorName: String?
    let authorId: String?
    let timeCreated: Date?
    /// Raw HTML body straight from the API. Conversion to plain text/markdown
    /// happens in `MarkdownCommentExporter` so the same DTO can later feed an
    /// in-app comment viewer with full formatting.
    let contentHTML: String
    let attachments: [Attachment]
    let forwardedFrom: ForwardedComment?

    struct Attachment: Hashable {
        let name: String
        let url: URL?
    }

    struct ForwardedComment: Hashable {
        let authorName: String?
        let timeCreated: Date?
        let contentHTML: String
    }
}

/// Bundle returned by `TaskService.fetchTaskComments` — task title + all comments
/// flat-loaded so the UI can render or export them in one pass.
struct TaskCommentsBundle {
    let taskName: String
    let humanNumber: Int?
    let comments: [MegaplanComment]
}
