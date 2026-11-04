import Foundation

enum WorkspacePage {
    case knowledge
    case deals
    case tasks

    var path: String {
        switch self {
        case .knowledge: return "/knowledge/"
        case .deals: return "/deals/list/"
        case .tasks: return "/task/"
        }
    }
}

enum WorkspaceAddress {
    static func page(_ page: WorkspacePage, domain: String) -> URL? {
        guard let origin = origin(from: domain) else { return nil }
        return URL(string: origin + page.path)
    }

    static func taskCard(id: String, domain: String) -> URL? {
        guard !id.isEmpty, let origin = origin(from: domain) else { return nil }
        return URL(string: origin + "/task/\(id)/card/")
    }

    static func resolve(link: URL, domain: String) -> URL? {
        if link.scheme != nil, link.host != nil { return link }
        guard link.path.hasPrefix("/"), let origin = origin(from: domain) else { return nil }
        // URL.path отбрасывает завершающий слэш; percentEncodedPath его сохраняет.
        let path = URLComponents(url: link, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? link.path
        return URL(string: origin + path)
    }

    static func diagnosticText() -> String {
        APILogger.getLogContent()
    }

    private static func origin(from domain: String) -> String? {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), let host = url.host, let scheme = url.scheme else { return nil }
        return "\(scheme)://\(host)"
    }
}
