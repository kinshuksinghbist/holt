import AppKit
import HoltCore
import SwiftUI

@main
struct HoltApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        // The main window is the first scene so SwiftUI opens it at launch and captures
        // `OpenWindowAction` for the AppKit status bar popover and reopen handler.
        Window("Holt", id: WindowID.main) {
            MainWindowView(model: model)
        }
        .defaultSize(width: 940, height: 760)

        Window("Holt Settings", id: WindowID.settings) {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let main = "main"
    static let settings = "settings"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.log("launched \(Diagnostics.version)")
        Notifier.shared.configure()
        StatusBarController.shared.install(model: AppModel.shared)
        AppModel.shared.startMonitoring()
        Task {
            try? await Task.sleep(for: .seconds(3))
            Diagnostics.logWindows("3s after launch")
        }
    }

    /// Opening Holt again (Finder, Spotlight, `open`) brings up the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Diagnostics.log("reopen (visible windows: \(flag))")
        AppModel.shared.showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.flushTrackingOnQuit()
    }
}

/// Tiny append-only log at ~/Library/Logs/Holt/holt.log for diagnosing launch problems.
@MainActor
enum Diagnostics {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Holt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("holt.log")
    }()

    static func log(_ message: String) {
        let line = "\(Date.now.ISO8601Format()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Records which windows exist (the menu bar item lives in an NSStatusBarWindow).
    static func logWindows(_ context: String) {
        let windows = NSApp.windows.map { window in
            "\(type(of: window)) visible=\(window.isVisible) frame=\(window.frame.integral)"
        }
        log("\(context): \(windows.count) windows — " + windows.joined(separator: "; "))
    }
}
