import AppKit
import HoltCore
import SwiftUI

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        // Standard menu bar label: an SF Symbol, plus the countdown while a session exists.
        HStack(spacing: 4) {
            Image(systemName: model.menuBarSymbol)
            if !model.menuBarTitle.isEmpty {
                Text(model.menuBarTitle).monospacedDigit()
            }
        }
        .onAppear { Diagnostics.log("menu bar label appeared") }
    }
}

/// The menu bar panel: today, the timer hero, tone and Holt's latest line.
struct PanelView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

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
        openWindow(id: id)
        NSApp.activate()
    }
}
