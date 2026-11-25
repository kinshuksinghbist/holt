import AppKit
import HoltCore
import SwiftUI

/// The menu bar panel: today, the timer hero, tone and Holt's latest line.
struct PanelView: View {
    let model: AppModel
    var closePanel: (@MainActor () -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            header
            TimerHero(model: model, compact: true)
            ToneSlider(model: model)
            if let line = model.lastLine {
                HoltQuote(text: line)
            }
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Holt").font(.headline)
                Text(model.todaySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            IconButton(symbol: "gearshape", help: "Settings") { open(WindowID.settings) }
            IconButton(symbol: "macwindow", help: "Open Holt") { open(WindowID.main) }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.sessionHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .keyboardShortcut("q")
        }
    }

    private func open(_ id: String) {
        closePanel?()
        model.openWindow(id)
    }
}
