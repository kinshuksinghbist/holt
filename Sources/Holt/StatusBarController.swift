import AppKit
import HoltCore
import Observation
import SwiftUI

/// AppKit status bar item + popover hosting `PanelView`.
/// Used instead of SwiftUI `MenuBarExtra` so the menu bar icon stays reliably visible on macOS 26+.
@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private weak var model: AppModel?
    private var isObserving = false

    func install(model: AppModel) {
        self.model = model
        guard statusItem == nil else {
            updateAppearance()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "HoltStatusItem"
        item.isVisible = true
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        statusItem = item

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PanelView(model: model, closePanel: { [weak self] in
                self?.closePopover()
            })
        )

        updateAppearance()
        observeModel()

        let frame = item.button?.window?.frame.integral ?? .zero
        Diagnostics.log("statusItem installed: visible=\(item.isVisible) windowFrame=\(frame)")
    }

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func observeModel() {
        guard !isObserving else { return }
        isObserving = true
        scheduleNextObservation()
    }

    private func scheduleNextObservation() {
        guard let model else {
            isObserving = false
            return
        }
        withObservationTracking {
            _ = model.menuBarSymbol
            _ = model.menuBarTitle
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateAppearance()
                self.scheduleNextObservation()
            }
        }
    }

    private func updateAppearance() {
        guard let model, let button = statusItem?.button else { return }
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: model.menuBarSymbol, accessibilityDescription: "Holt")?
            .withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true
        button.image = image

        let title = model.menuBarTitle
        if title.isEmpty {
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
        } else {
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .regular) - 1, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            button.attributedTitle = NSAttributedString(string: " " + title, attributes: attrs)
            button.imagePosition = .imageLeading
        }
        button.toolTip = model.modeTitle
    }
}
