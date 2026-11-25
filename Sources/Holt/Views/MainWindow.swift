import HoltCore
import SwiftUI

/// The full app: timer hero on the left, today and Holt's feed on the right.
struct MainWindowView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Holt also lives in your menu bar — look for \(Image(systemName: "scope")) near the clock.",
                      systemImage: "menubar.arrow.up.rectangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 20) {
                    TimerHero(model: model, compact: false)
                        .frame(maxWidth: 440)
                    VStack(alignment: .leading, spacing: 16) {
                        TodayCard(model: model)
                        ToneSlider(model: model)
                            .padding(14)
                            .holtGlass(cornerRadius: 16)
                        HoltFeed(lines: model.feed)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                ComingNext()
            }
            .padding(24)
        }
        .frame(minWidth: 820, minHeight: 640)
        .onAppear {
            // Lets AppKit code (reopen) open windows through SwiftUI.
            model.windowOpener = openWindow
            Diagnostics.log("main window appeared")
        }
        .toolbar {
            ToolbarItem {
                Button {
                    openWindow(id: WindowID.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
    }
}

struct TodayCard: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today").font(.headline)
            HStack(spacing: 10) {
                StatTile(value: TimeFormat.duration(model.today.focusSeconds), label: "focused", symbol: "flame")
                StatTile(value: "\(model.today.sessionsCompleted)", label: "sessions done", symbol: "checkmark.circle")
                StatTile(value: "\(model.today.sessionsEndedEarly)", label: "ended early", symbol: "xmark.circle")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .holtGlass(cornerRadius: 16)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Everything Holt has said this session of the app, newest first.
struct HoltFeed: View {
    let lines: [HoltLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Holt says").font(.headline)
            if lines.isEmpty {
                Text("Nothing yet. Start a session and he'll have opinions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lines.suffix(8).reversed()) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(line.date, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Text(line.text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .holtGlass(cornerRadius: 16)
        .animation(.easeInOut(duration: 0.25), value: lines)
    }
}

struct ComingNext: View {
    private struct Item: Identifiable {
        let id: String
        let title: String
        let symbol: String
    }

    private let items = [
        Item(id: "M2", title: "Todos, lists & notes", symbol: "checklist"),
        Item(id: "M3", title: "App & website tracking", symbol: "macwindow.on.rectangle"),
        Item(id: "M4", title: "On-device screen understanding", symbol: "text.viewfinder"),
        Item(id: "M5", title: "Stats & heatmap", symbol: "chart.bar.xaxis"),
        Item(id: "M6", title: "Holt's reminders", symbol: "bell.badge"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coming next").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).foregroundStyle(.secondary).frame(width: 20)
                        Text(item.title).font(.callout)
                        Spacer()
                        Text(item.id).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .holtGlass(cornerRadius: 12)
                }
            }
        }
    }
}
