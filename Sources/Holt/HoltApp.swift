import AppKit
import HoltCore
import SwiftUI

@main
struct HoltApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Holt", id: WindowID.main) {
            MainWindowView(model: model)
        }
        .defaultSize(width: 900, height: 720)
    }
}

enum WindowID {
    static let main = "main"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.requestAuthorization()
    }
}
