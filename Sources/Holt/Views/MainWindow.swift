import HoltCore
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case history = "History"
    case stats = "Stats"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "checklist"
        case .history: "calendar"
        case .stats: "chart.bar.xaxis"
        }
    }
}

/// The full app: hero timer at top, tab switcher for Today, History, and Stats.
struct MainWindowView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var tab: MainTab = .today
    @State private var focusQuickAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.settings.showCoachMarks && model.settings.hasCompletedOnboarding {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.orange)
                        Text("Tip: Look for Holt's icon in your menu bar next to the clock, stretch the jelly to pick any duration, or press ⌃⌥Space anywhere.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Got it") { model.dismissCoachMarks() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(10)
                    .holtGlass(cornerRadius: 12)
                }

                HStack(alignment: .top, spacing: 20) {
                    TimerHero(model: model, compact: false)
                        .frame(maxWidth: 420)
                    VStack(alignment: .leading, spacing: 14) {
                        TodayCard(model: model)
                        ToneSlider(model: model)
                            .padding(14)
                            .holtGlass(cornerRadius: 16)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                Picker("Section", selection: $tab) {
                    ForEach(MainTab.allCases) { item in
                        Label(item.rawValue, systemImage: item.symbol).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                switch tab {
                case .today:
                    TodayView(model: model, focusQuickAdd: $focusQuickAdd)
                case .history:
                    HistoryView(model: model)
                case .stats:
                    StatsView(model: model)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 880, minHeight: 680)
        .onAppear {
            model.windowOpener = openWindow
            Diagnostics.log("main window appeared")
        }
        .sheet(isPresented: $model.isPlanSheetPresented) {
            PlanYourDaySheet(model: model)
        }
        .sheet(isPresented: $model.isOnboardingPresented) {
            OnboardingView(model: model)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    tab = .today
                    focusQuickAdd = true
                } label: {
                    Label("New Todo", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Quick add todo (⌘N)")

                Button {
                    model.openPlanYourDay()
                } label: {
                    Label("Plan day", systemImage: "sun.horizon")
                }
                .help("Plan your day")

                Button {
                    model.replayOnboardingTour()
                } label: {
                    Label("Tour", systemImage: "questionmark.circle")
                }
                .help("Replay onboarding tour")

                Button {
                    model.openWindow(WindowID.settings)
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
                StatTile(value: TimeFormat.duration(TimeInterval(model.todaySummary.focusSeconds)), label: "focused", symbol: "flame")
                StatTile(value: "\(model.todaySummary.sessionsCompleted)", label: "sessions done", symbol: "checkmark.circle")
                StatTile(value: "\(model.todaySummary.tasksDone)/\(model.todaySummary.tasksPlanned)", label: "todos done", symbol: "checklist")
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
        Item(id: "M3", title: "App & website tracking", symbol: "macwindow.on.rectangle"),
        Item(id: "M4", title: "On-device screen understanding", symbol: "text.viewfinder"),
        Item(id: "M5", title: "Stats, heatmap & Switch River", symbol: "chart.bar.xaxis"),
        Item(id: "M6", title: "Holt's reminders & auto-sessions", symbol: "bell.badge"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stats & tracking coming next").font(.headline)
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
