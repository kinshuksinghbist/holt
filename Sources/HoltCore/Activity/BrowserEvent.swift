import Foundation

public struct BrowserTabEvent: Codable, Equatable, Sendable {
    public var browser: String
    public var url: String?
    public var domain: String?
    public var title: String?
    public var incognito: Bool
    public var ytVideoId: String?
    public var ytChannel: String?
    public var ytCategory: String?
    public var ts: Int64

    public init(
        browser: String,
        url: String? = nil,
        domain: String? = nil,
        title: String? = nil,
        incognito: Bool = false,
        ytVideoId: String? = nil,
        ytChannel: String? = nil,
        ytCategory: String? = nil,
        ts: Int64 = Int64(Date.now.timeIntervalSince1970)
    ) {
        self.browser = browser
        self.url = url
        self.domain = domain
        self.title = title
        self.incognito = incognito
        self.ytVideoId = ytVideoId
        self.ytChannel = ytChannel
        self.ytCategory = ytCategory
        self.ts = ts
    }

    public static func extractDomain(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static func extractYouTubeVideoId(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return nil }
        if host.contains("youtu.be") {
            let id = url.pathComponents.dropFirst().first
            return id?.isEmpty == false ? id : nil
        }
        if host.contains("youtube.com"),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                return v
            }
            if url.path.hasPrefix("/shorts/") {
                return url.pathComponents.dropFirst(2).first
            }
        }
        return nil
    }
}

public enum HoltSocketPaths {
    public static func socketURL() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Holt", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("holt.sock")
    }
}
