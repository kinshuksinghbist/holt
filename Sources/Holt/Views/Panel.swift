import AppKit
import HoltCore
import SwiftUI

/// The menu bar panel: today, timer hero, current task picker, quick add, tone and Holt's latest line.
struct PanelView: View {
    let model: AppModel
    var closePanel: (@MainActor () -> Void)? = nil
    @State private var quickTitle = ""
    @State private var sessionNoteText = ""

    var body: some View {
        VStack(spacing: 10) {
            header
            TimerHero(model: model, compact: true)
            taskPickerRow
            if model.pendingSessionNoteId != nil {
                sessionNoteBanner
            }
            quickAddRow
            ToneSlider(model: model)
            if let line = model.lastLine {
                HoltQuote(text: line)
            }
            footer
        }
        .padding(14)
        .frame(width: 350)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Holt").font(.headline)
                Text(model.todaySummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            IconButton(symbol: "gearshape", help: "Settings") { open(WindowID.settings) }
            IconButton(symbol: "macwindow", help: "Open Holt") { open(WindowID.main) }
        }
    }

    private var taskPickerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
                .font(.caption)
            Menu {
                Button("No task") { model.selectedTaskId = nil }
                Divider()
                ForEach(model.undoneTodayTasks) { task in
                    Button {
                        model.selectedTaskId = task.id
                    } label: {
                        HStack {
                            Text(task.title)
                            if task.id == model.selectedTask?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(model.selectedTask?.title ?? "Pick a task for this session")
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(model.selectedTask == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .holtGlass(cornerRadius: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Current task")
        }
    }

    private var sessionNoteBanner: some View {
        HStack(spacing: 6) {
            TextField("What did you get done?", text: $sessionNoteText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { submitNote() }
            Button("Save") { submitNote() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button {
                model.dismissSessionNotePrompt()
                sessionNoteText = ""
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(8)
        .holtGlass(cornerRadius: 10)
    }

    private var quickAddRow: some View {
        HStack(spacing: 6) {
            TextField("Quick add todo…", text: $quickTitle)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { addQuick() }
            Button {
                addQuick()
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Add todo")
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

    private func addQuick() {
        let trimmed = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.quickAddTask(title: trimmed)
        quickTitle = ""
    }

    private func submitNote() {
        model.submitSessionNote(sessionNoteText)
        sessionNoteText = ""
    }

    private func open(_ id: String) {
        closePanel?()
        model.openWindow(id)
    }
}
