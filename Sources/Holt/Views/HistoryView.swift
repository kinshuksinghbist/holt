import HoltCore
import SwiftUI

struct HistoryView: View {
    let model: AppModel

    @State private var displayedMonth: Date = Date()
    @State private var selectedDay: String = HoltDay.key(for: .now)
    @State private var activeDays: Set<String> = []
    @State private var dayTasks: [TaskItem] = []
    @State private var daySessions: [SessionRecord] = []
    @State private var dayNote: String = ""
    @State private var daySummary: DayStatsSummary?

    private let calendar = Calendar.current

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            calendarCard
                .frame(width: 310)
            dayDetailCard
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { reload() }
        .onChange(of: selectedDay) { _, _ in reloadDay() }
        .onChange(of: displayedMonth) { _, _ in reloadMonth() }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(monthTitle)
                    .font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
            }

            let weekdays = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdays, id: \.self) { wd in
                    Text(wd)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(monthCells) { cell in
                    if let key = cell.dayKey, let num = cell.dayNumber {
                        let isSelected = key == selectedDay
                        let hasActivity = activeDays.contains(key)
                        Button {
                            selectedDay = key
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(num)")
                                    .font(.caption.monospacedDigit())
                                Circle()
                                    .fill(hasActivity ? Color.orange : Color.clear)
                                    .frame(width: 4, height: 4)
                            }
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
        .padding(14)
        .holtGlass(cornerRadius: 16)
    }

    private var dayDetailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selectedDay)
                    .font(.title3.weight(.semibold))
                Spacer()
                if let summary = daySummary {
                    Text("\(TimeFormat.duration(TimeInterval(summary.focusSeconds))) focused · \(summary.sessionsCompleted) sessions · \(summary.tasksDone) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !dayNote.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scratchpad").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(dayNote).font(.callout)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .holtGlass(cornerRadius: 12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tasks (\(dayTasks.count))").font(.headline)
                if dayTasks.isEmpty {
                    Text("No tasks recorded on this day.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(dayTasks) { task in
                        HStack {
                            Text(task.status.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text(task.title).font(.callout)
                            Spacer()
                            if let reason = task.skipReason {
                                Text(reason).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(8)
                        .holtGlass(cornerRadius: 8)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sessions (\(daySessions.count))").font(.headline)
                if daySessions.isEmpty {
                    Text("No sessions recorded on this day.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(daySessions) { s in
                        HStack {
                            Text(s.kind.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.callout.weight(.medium))
                            Text("· \(TimeFormat.duration(TimeInterval(s.activeSec)))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(s.endReason ?? "active")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(8)
                        .holtGlass(cornerRadius: 8)
                    }
                }
            }
        }
        .padding(16)
        .holtGlass(cornerRadius: 16)
    }

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "LLLL yyyy"
        return fmt.string(from: displayedMonth)
    }

    private struct CalendarCell: Identifiable {
        let id: String
        let dayKey: String?
        let dayNumber: Int?
    }

    private var monthCells: [CalendarCell] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - 1
        var cells: [CalendarCell] = (0..<firstWeekday).map { CalendarCell(id: "empty-\($0)", dayKey: nil, dayNumber: nil) }
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        for day in range {
            let key = String(format: "%04d-%02d-%02d", y, m, day)
            cells.append(CalendarCell(id: key, dayKey: key, dayNumber: day))
        }
        return cells
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private func reload() {
        reloadMonth()
        reloadDay()
    }

    private func reloadMonth() {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        let prefix = String(format: "%04d-%02d-", comps.year ?? 2026, comps.month ?? 1)
        activeDays = (try? model.store.daysWithActivity(inMonthPrefix: prefix)) ?? []
    }

    private func reloadDay() {
        dayTasks = (try? model.store.fetchTasks(day: selectedDay)) ?? []
        daySessions = (try? model.store.fetchSessions(day: selectedDay)) ?? []
        dayNote = (try? model.store.fetchDayNote(day: selectedDay)) ?? ""
        daySummary = try? model.store.daySummary(day: selectedDay)
    }
}
