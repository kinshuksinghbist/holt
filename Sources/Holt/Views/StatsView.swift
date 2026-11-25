import Charts
import HoltCore
import SwiftUI

struct StatsView: View {
    let model: AppModel

    @State private var preset: StatsRangePreset = .thisWeek
    @State private var customFrom = Date.now.addingTimeInterval(-7 * 86400)
    @State private var customTo = Date.now
    @State private var heatmapMetric: HeatmapMetric = .focusMinutes
    @State private var report: StatsReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            rangeHeader
            if let report {
                verdictAndSummary(report)
                HStack(alignment: .top, spacing: 16) {
                    heatmapCard(report)
                        .frame(maxWidth: .infinity)
                    focusClockCard(report)
                        .frame(width: 280)
                }
                ribbonCard(report)
                hourlyBarCard(report)
                switchRiverCard(report)
                breakdownsRow(report)
                creativeSection(report)
            } else {
                ProgressView("Crunching numbers…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .onAppear { reload() }
        .onChange(of: preset) { _, _ in reload() }
        .onChange(of: customFrom) { _, _ in if preset == .custom { reload() } }
        .onChange(of: customTo) { _, _ in if preset == .custom { reload() } }
        .onChange(of: model.toneBand) { _, _ in reload() }
    }

    private var rangeHeader: some View {
        HStack(spacing: 12) {
            Picker("Range", selection: $preset) {
                ForEach(StatsRangePreset.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)

            if preset == .custom {
                DatePicker("From", selection: $customFrom, displayedComponents: .date)
                    .labelsHidden()
                Text("to").font(.caption).foregroundStyle(.secondary)
                DatePicker("To", selection: $customTo, displayedComponents: .date)
                    .labelsHidden()
            }

            Spacer()
            Button {
                reload()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func verdictAndSummary(_ r: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "quote.opening")
                    .foregroundStyle(.tertiary)
                Text(r.verdict)
                    .font(.callout.weight(.medium))
                Spacer()
                HStack(spacing: 4) {
                    Text("Score \(r.averageFocusScore)")
                        .font(.headline.monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .help(RollupEngine.scoreFormulaExplanation)
                }
            }

            HStack(spacing: 12) {
                StatTile(value: TimeFormat.duration(TimeInterval(r.totalFocusSeconds)), label: "focus", symbol: "flame.fill")
                StatTile(value: TimeFormat.duration(TimeInterval(r.totalDistractSeconds)), label: "distracted", symbol: "exclamationmark.triangle")
                StatTile(value: "\(r.sessionsDone)", label: "sessions done", symbol: "checkmark.circle")
                StatTile(value: "\(r.tasksDone)/\(r.tasksPlanned)", label: "tasks done", symbol: "checklist")
                StatTile(value: TimeFormat.duration(TimeInterval(r.youtubeEntertainmentSeconds)), label: "YouTube fun", symbol: "play.rectangle")
            }
        }
        .padding(14)
        .holtGlass(cornerRadius: 16)
    }

    private struct HeatCell: Identifiable {
        let id: String
        let weekday: Int
        let week: Int
        let color: Color
    }

    private func heatmapCard(_ r: StatsReport) -> some View {
        let cells = buildHeatmapCells(r.dailyRollups)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity heatmap").font(.headline)
                Spacer()
                Picker("Metric", selection: $heatmapMetric) {
                    ForEach(HeatmapMetric.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            if cells.isEmpty {
                Text("No daily rollups in this range yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
            } else {
                Chart(cells) { cell in
                    RectangleMark(
                        x: .value("Week", cell.week),
                        y: .value("Day", cell.weekday),
                        width: .ratio(0.84),
                        height: .ratio(0.84)
                    )
                    .cornerRadius(3)
                    .foregroundStyle(cell.color)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: [1, 3, 5]) { val in
                        if let wd = val.as(Int.self) {
                            AxisValueLabel {
                                Text(["", "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"][max(1, min(7, wd))])
                            }
                        }
                    }
                }
                .frame(height: 150)
            }
        }
        .padding(14)
        .holtGlass(cornerRadius: 16)
    }

    private func focusClockCard(_ r: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focus clock (24 h)").font(.headline)
            let nonZero = r.hourlyBuckets.filter { $0.focusSeconds > 0 }
            if nonZero.isEmpty {
                Text("No focus hours logged yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(r.hourlyBuckets) { bucket in
                    SectorMark(
                        angle: .value("Hour", 1),
                        innerRadius: .ratio(0.42),
                        angularInset: 1.5
                    )
                    .foregroundStyle(
                        bucket.focusSeconds > 0
                            ? Color.orange.opacity(0.25 + 0.75 * min(1.0, Double(bucket.focusSeconds) / 3600.0))
                            : Color.secondary.opacity(0.1)
                    )
                }
                .frame(height: 150)
            }
        }
        .padding(14)
        .holtGlass(cornerRadius: 16)
    }

    private func ribbonCard(_ r: StatsReport) -> some View {
        let segments = r.ribbonSegments
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("24-hour ribbon (\(r.toDay))").font(.headline)
                Spacer()
                HStack(spacing: 10) {
                    legendDot("Work", .orange)
                    legendDot("Break", .teal)
                    legendDot("Distracted", .red)
                    legendDot("Idle", .gray)
                }
                .font(.caption2)
            }

            Canvas { context, size in
                drawRibbon(context: &context, size: size, segments: segments)
            }
            .frame(height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Text("04:00")
                Spacer()
                Text("10:00")
                Spacer()
                Text("16:00")
                Spacer()
                Text("22:00")
                Spacer()
                Text("04:00")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .holtGlass(cornerRadius: 16)
    }

    private func hourlyBarCard(_ r: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus & distractions by hour").font(.headline)
            Chart {
                ForEach(r.hourlyBuckets) { b in
                    BarMark(
                        x: .value("Hour", b.hour),
                        y: .value("Focus min", Double(b.focusSeconds) / 60.0)
                    )
                    .foregroundStyle(.orange)
                    BarMark(
                        x: .value("Hour", b.hour),
                        y: .value("Distract min", -Double(b.distractSeconds) / 60.0)
                    )
                    .foregroundStyle(.red.opacity(0.75))
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 4, 8, 12, 16, 20])
            }
            .frame(height: 160)
        }
        .padding(14)
        .holtGlass(cornerRadius: 16)
    }

    private func switchRiverCard(_ r: StatsReport) -> some View {
        let edges = r.switchEdges
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Switch river (app transitions)").font(.headline)
                Spacer()
                Text("Most shifted from: \(r.mostShiftedFrom) · to: \(r.mostShiftedTo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if edges.isEmpty {
                Text("No app transitions recorded in this range.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Canvas { context, size in
                    drawSwitchRiver(context: &context, size: size, edges: edges)
                }
                .frame(height: 190)
            }
        }
        .padding(14)
        .holtGlass(cornerRadius: 16)
    }

    private func breakdownsRow(_ r: StatsReport) -> some View {
        HStack(alignment: .top, spacing: 14) {
            usageCard(title: "Top apps", items: r.topApps, empty: "No app usage yet.")
            usageCard(title: "Least used apps", items: r.leastApps, empty: "No minor apps yet.")
            usageCard(title: "Top websites", items: r.topSites, empty: "No website usage yet.")
        }
    }

    private func usageCard(title: String, items: [UsageBreakdownItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text(empty).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(6)) { item in
                    HStack {
                        Circle()
                            .fill(item.category == "productive" ? Color.green : (item.category == "distracting" ? Color.red : Color.gray))
                            .frame(width: 6, height: 6)
                        Text(item.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(TimeFormat.duration(TimeInterval(item.totalSeconds)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .holtGlass(cornerRadius: 16)
    }

    private func creativeSection(_ r: StatsReport) -> some View {
        let distractMin = Double(r.totalDistractSeconds) / 60.0
        let equivSessions = String(format: "%.1f", distractMin / 25.0)
        let equivFilms = String(format: "%.1f", distractMin / 110.0)
        let everestStr = String(format: "%.2f", r.everestProgress)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time exchange rate").font(.headline)
                    Text("\(Int(distractMin)) min of distractions = \(equivSessions) focus sessions = \(equivFilms) feature films.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .holtGlass(cornerRadius: 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Mountain log").font(.headline)
                    Text("\(r.mountainElevationMeters) m climbed · Everest ×\(everestStr)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .holtGlass(cornerRadius: 16)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 10)], spacing: 10) {
                creativeCard("Best focus hour", value: r.cards.bestFocusHour, symbol: "clock.badge.checkmark")
                creativeCard("Most dangerous app", value: r.cards.mostDangerousApp, symbol: "flame")
                creativeCard("Longest streak", value: "\(r.cards.longestStreakDays) days", symbol: "calendar.badge.checkmark")
                creativeCard("Fastest derailment", value: r.cards.fastestDerailment, symbol: "bolt.slash")
                creativeCard("Top time sink", value: r.cards.topTimeSink, symbol: "hourglass")
                creativeCard("Avoidance champion", value: r.cards.avoidanceChampion, symbol: "arrow.uturn.right")
                creativeCard("Comeback day", value: r.cards.comebackDay, symbol: "arrow.up.right")
            }
        }
    }

    private func creativeCard(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .holtGlass(cornerRadius: 12)
    }

    private func legendDot(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func buildHeatmapCells(_ rollups: [DailyRollupRecord]) -> [HeatCell] {
        let cal = Calendar.current
        let values: [Double] = rollups.map { r in
            switch heatmapMetric {
            case .focusMinutes: return Double(r.focusSec) / 60.0
            case .sessionsDone: return Double(r.sessionsDone)
            case .tasksDone: return Double(r.tasksDone)
            case .focusScore: return Double(r.focusScore)
            case .distractMinutes: return Double(r.distractSec) / 60.0
            }
        }
        let maxVal = max(1.0, values.max() ?? 1.0)
        let tint: Color = heatmapMetric == .distractMinutes ? .red : .orange

        return zip(rollups.indices, values).map { idx, val in
            let r = rollups[idx]
            let d = HoltDay.date(fromKey: r.day, calendar: cal) ?? Date()
            let wd = cal.component(.weekday, from: d)
            let week = idx / 7
            let intensity = min(1.0, val / maxVal)
            let color = val <= 0 ? Color.secondary.opacity(0.12) : tint.opacity(0.2 + 0.8 * intensity)
            return HeatCell(id: r.day, weekday: wd, week: week, color: color)
        }
    }

    private func reload() {
        let bounds = StatsQuery.dayBounds(
            preset: preset,
            customFrom: HoltDay.key(for: customFrom),
            customTo: HoltDay.key(for: customTo)
        )
        try? model.rollupEngine.recomputeDay(HoltDay.key(for: .now))
        report = try? model.statsQuery.report(fromDay: bounds.from, toDay: bounds.to, tone: model.toneBand)
    }
}

private func drawRibbon(context: inout GraphicsContext, size: CGSize, segments: [RibbonSegment]) {
    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.secondary.opacity(0.14)))
    for seg in segments {
        let x0 = (seg.startMinute / 1440.0) * size.width
        let x1 = (seg.endMinute / 1440.0) * size.width
        let rect = CGRect(x: x0, y: 0, width: max(2, x1 - x0), height: size.height)
        let color: Color
        switch seg.kind {
        case .work: color = .orange
        case .break: color = .teal
        case .idle: color = .gray
        case .distracted: color = .red
        }
        context.fill(Path(rect), with: .color(color.opacity(0.85)))
    }
}

private func drawSwitchRiver(context: inout GraphicsContext, size: CGSize, edges: [SwitchEdge]) {
    let sources = Array(Set(edges.map(\.fromApp))).sorted()
    let targets = Array(Set(edges.map(\.toApp))).sorted()
    guard !sources.isEmpty, !targets.isEmpty else { return }

    let leftX: CGFloat = 120
    let rightX: CGFloat = size.width - 120
    let maxCount = max(1, edges.map(\.count).max() ?? 1)

    func yPos(index: Int, total: Int) -> CGFloat {
        let step = size.height / CGFloat(total + 1)
        return step * CGFloat(index + 1)
    }

    for (idx, name) in sources.enumerated() {
        let y = yPos(index: idx, total: sources.count)
        context.draw(
            Text(name).font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: 6, y: y),
            anchor: .leading
        )
    }
    for (idx, name) in targets.enumerated() {
        let y = yPos(index: idx, total: targets.count)
        context.draw(
            Text(name).font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: size.width - 6, y: y),
            anchor: .trailing
        )
    }

    for edge in edges {
        guard let si = sources.firstIndex(of: edge.fromApp),
              let ti = targets.firstIndex(of: edge.toApp) else { continue }
        let y0 = yPos(index: si, total: sources.count)
        let y1 = yPos(index: ti, total: targets.count)
        let midX = (leftX + rightX) / 2
        var path = Path()
        path.move(to: CGPoint(x: leftX, y: y0))
        path.addCurve(
            to: CGPoint(x: rightX, y: y1),
            control1: CGPoint(x: midX, y: y0),
            control2: CGPoint(x: midX, y: y1)
        )
        let width = 1.5 + 8.0 * (CGFloat(edge.count) / CGFloat(maxCount))
        context.stroke(path, with: .color(.orange.opacity(0.38)), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
