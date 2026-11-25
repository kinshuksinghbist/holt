import HoltCore
import SwiftUI

struct PlanYourDaySheet: View {
    let model: AppModel
    @State private var skipReasons: [Int64: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan your day")
                        .font(.title2.weight(.semibold))
                    Text("Yesterday's leftovers survived the night. Decide what comes with you.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Later") { model.isPlanSheetPresented = false }
                    .buttonStyle(.borderless)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.planPreview.leftovers.isEmpty {
                        Text("Unfinished from earlier")
                            .font(.headline)
                        ForEach(model.planPreview.leftovers) { task in
                            leftoverRow(task)
                        }
                    }

                    if !model.planPreview.dueRecurring.isEmpty {
                        Text("Recurring due today")
                            .font(.headline)
                            .padding(.top, 4)
                        ForEach(model.planPreview.dueRecurring) { rec in
                            HStack {
                                Image(systemName: "repeat")
                                    .foregroundStyle(.secondary)
                                Text(rec.title)
                                    .font(.callout)
                                Spacer()
                                Text(rec.recurrence.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .holtGlass(cornerRadius: 10)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)

            HStack {
                Button("Ignore leftovers") {
                    model.planFinishAndStartDay(keepRemaining: false)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Keep all & start day") {
                    model.planFinishAndStartDay(keepRemaining: true)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func leftoverRow(_ task: TaskItem) -> some View {
        let taskId = task.id ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.callout.weight(.medium))
                    Text("From \(task.day)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Keep") { model.planKeepLeftover(task) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Skip") {
                    model.planSkipLeftover(task, reason: skipReasons[taskId])
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Drop", role: .destructive) { model.planDropLeftover(task) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            TextField("Optional skip reason…", text: Binding(
                get: { skipReasons[taskId] ?? "" },
                set: { skipReasons[taskId] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
        }
        .padding(10)
        .holtGlass(cornerRadius: 12)
    }
}
