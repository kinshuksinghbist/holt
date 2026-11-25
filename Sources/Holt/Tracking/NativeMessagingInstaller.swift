import Foundation

enum NativeMessagingInstaller {
    static let hostName = "io.github.kinshuksinghbist.holt"
    static let firefoxExtensionId = "holt@kinshuksinghbist.github.io"

    struct BrowserTarget: Identifiable {
        let id: String
        let name: String
        let manifestDirectory: URL
        let isFirefox: Bool
    }

    static var hostExecutablePath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/holt-nm-host").path
    }

    static var targets: [BrowserTarget] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return [
            BrowserTarget(
                id: "firefox",
                name: "Firefox",
                manifestDirectory: appSupport.appendingPathComponent("Mozilla/NativeMessagingHosts", isDirectory: true),
                isFirefox: true
            ),
            BrowserTarget(
                id: "chrome",
                name: "Google Chrome",
                manifestDirectory: appSupport.appendingPathComponent("Google/Chrome/NativeMessagingHosts", isDirectory: true),
                isFirefox: false
            ),
            BrowserTarget(
                id: "brave",
                name: "Brave",
                manifestDirectory: appSupport.appendingPathComponent("BraveSoftware/Brave-Browser/NativeMessagingHosts", isDirectory: true),
                isFirefox: false
            ),
            BrowserTarget(
                id: "edge",
                name: "Microsoft Edge",
                manifestDirectory: appSupport.appendingPathComponent("Microsoft Edge/NativeMessagingHosts", isDirectory: true),
                isFirefox: false
            ),
            BrowserTarget(
                id: "arc",
                name: "Arc",
                manifestDirectory: appSupport.appendingPathComponent("Arc/User Data/NativeMessagingHosts", isDirectory: true),
                isFirefox: false
            ),
            BrowserTarget(
                id: "vivaldi",
                name: "Vivaldi",
                manifestDirectory: appSupport.appendingPathComponent("Vivaldi/NativeMessagingHosts", isDirectory: true),
                isFirefox: false
            ),
        ]
    }

    static func installAll(chromeExtensionId: String) throws -> [String] {
        var installed: [String] = []
        let cleanChromeId = chromeExtensionId.trimmingCharacters(in: .whitespacesAndNewlines)

        for target in targets {
            if !target.isFirefox && cleanChromeId.isEmpty {
                continue
            }
            try FileManager.default.createDirectory(at: target.manifestDirectory, withIntermediateDirectories: true)
            let manifestURL = target.manifestDirectory.appendingPathComponent("\(hostName).json")

            var payload: [String: Any] = [
                "name": hostName,
                "description": "Holt browser companion host",
                "path": hostExecutablePath,
                "type": "stdio",
            ]
            if target.isFirefox {
                payload["allowed_extensions"] = [firefoxExtensionId]
            } else {
                payload["allowed_origins"] = ["chrome-extension://\(cleanChromeId)/"]
            }

            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: manifestURL, options: .atomic)
            installed.append(target.name)
        }
        return installed
    }

    static func isFirefoxInstalled() -> Bool {
        guard let firefox = targets.first(where: { $0.isFirefox }) else { return false }
        let file = firefox.manifestDirectory.appendingPathComponent("\(hostName).json")
        return FileManager.default.fileExists(atPath: file.path)
    }
}
