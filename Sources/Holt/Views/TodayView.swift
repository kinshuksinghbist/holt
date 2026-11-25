import HoltCore
import SwiftUI

struct TodayView: View {
    @Bindable var model: AppModel
    @Binding var focusQuickAdd: Bool

    @State private var selectedListId: Int64? = nil
    @State private var quickTitle = ""
    @State private var quickPriority = 0
    @State private var quickRecurrence: TaskRecurrence = .none
    @State private var quickListId: Int64? = nil
    @State private var showNewList = false
    @State private var newListName = ""
    @State private var newListIcon = "folder.fill"
    @State private var newListColor = "#6366F1"
    @State private var skipTarget: TaskItem?
    @State private var skipReason = ""
    @State private var editingTask: TaskItem?
    @State private var sessionNoteText = ""
    @FocusState private var quickAddFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            todosColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
            notesAndFeedColumn
                .frame(width: 340, alignment: .topLeading)
        }
        .onChange(of: focusQuickAdd) { _, newValue in
            if newValue {
                quickAddFocused = true
                focusQuickAdd = false
            }
        }
        .sheet(item: $skipTarget) { task in
            skipSheet(for: task)
        }
        .sheet(item: $editingTask) { task in
            EditTaskSheet(task: task, lists: model.lists) { updated in
                model.updateTask(updated)
            }
        }
        .popover(isPresented: $showNewList) {
            newListPopover
        }
    }

    private var todosColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Lists filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    listChip(id: nil, title: "All", symbol: "tray.2.fill", colorHex: "#64748B")
                    ForEach(model.lists) { list in
                        listChip(
                            id: list.id,
                            title: list.name,
                            symbol: list.icon ?? "list.bullet",
                            colorHex: list.color ?? "#6366F1"
                        )
                    }
                    Button {
                        showNewList = true
                    } label: {
                        Label("New list", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Quick add bar
            HStack(spacing: 8) {
                TextField("Add a todo for today (⌘N)…", text: $quickTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($quickAddFocused)
                    .onSubmit { submitQuickAdd() }

                Picker("", selection: Binding(
                    get: { quickListId ?? selectedListId ?? model.lists.first?.id ?? Int64(1) },
                    set: { quickListId = $0 }
                )) {
                    ForEach(model.lists) { list in
                        Text(list.name).tag(list.id ?? Int64(0))
                    }
                }
                .labelsHidden()
                .frame(width: 105)

                Picker("", selection: $quickPriority) {
                    Text("Normal").tag(0)
                    Text("Medium").tag(1)
                    Text("High").tag(2)
                }
                .labelsHidden()
                .frame(width: 85)

                Picker("", selection: $quickRecurrence) {
                    ForEach(TaskRecurrence.allCases, id: \.self) { rec in
                        Text(rec.title).tag(rec)
                    }
                }
                .labelsHidden()
                .frame(width: 90)

                Button("Add") { submitQuickAdd() }
                    .buttonStyle(.borderedProminent)
                    .disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .holtGlass(cornerRadius: 14)

            if model.pendingSessionNoteId != nil {
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.secondary)
                    TextField("Session finished — what did you do?", text: $sessionNoteText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            model.submitSessionNote(sessionNoteText)
                            sessionNoteText = ""
                        }
                    Button("Save") {
                        model.submitSessionNote(sessionNoteText)
                        sessionNoteText = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Dismiss") {
                        model.dismissSessionNotePrompt()
                        sessionNoteText = ""
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(10)
                .holtGlass(cornerRadius: 12)
            }

            // Task list
            if filteredTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No todos here yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .holtGlass(cornerRadius: 14)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredTasks) { task in
                        taskRow(task)
                    }
                }
            }
        }
    }

    private var notesAndFeedColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Today's scratchpad").font(.headline)
                    Spacer()
                    Text("Auto-saved").font(.caption2).foregroundStyle(.tertiary)
                }
                TextEditor(text: Binding(
                    get: { model.dayNote },
                    set: { model.saveDayNote($0) }
                ))
                .font(.callout)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(14)
            .holtGlass(cornerRadius: 16)

            if !model.sessionNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session log").font(.headline)
                    ForEach(model.sessionNotes.prefix(5)) { note in
                        Text("• \(note.body)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .holtGlass(cornerRadius: 16)
            }

            HoltFeed(lines: model.feed)
        }
    }

    private var filteredTasks: [TaskItem] {
        guard let selectedListId else { return model.todayTasks }
        return model.todayTasks.filter { $0.listId == selectedListId }
    }

    private func listChip(id: Int64?, title: String, symbol: String, colorHex: String) -> some View {
        let isSelected = selectedListId == id
        return Button {
            selectedListId = id
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func taskRow(_ task: TaskItem) -> some View {
        let rootId = task.rootId ?? task.id ?? 0
        let meta = model.chainMeta[rootId]
        let listName = model.lists.first(where: { $0.id == task.listId })?.name
        let isSelected = model.selectedTask?.id == task.id

        return HStack(alignment: .top, spacing: 10) {
            Button {
                let next: TaskStatus = task.taskStatus == .done ? .todo : .done
                if let id = task.id { model.setTaskStatus(taskId: id, status: next) }
            } label: {
                Image(systemName: statusSymbol(task.taskStatus))
                    .foregroundStyle(statusColor(task.taskStatus))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle done for \(task.title)")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.callout.weight(.medium))
                        .strikethrough(task.taskStatus == .done || task.taskStatus == .abandoned)
                        .foregroundStyle(task.taskStatus.isTerminal ? .secondary : .primary)
                    if task.priority > 0 {
                        Text(task.priority == 2 ? "High" : "Med")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background((task.priority == 2 ? Color.red : Color.orange).opacity(0.18), in: Capsule())
                            .foregroundStyle(task.priority == 2 ? .red : .orange)
                    }
                    if task.taskStatus == .doing {
                        Text("DOING")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    if isSelected && !task.taskStatus.isTerminal {
                        Text("ACTIVE")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }

                HStack(spacing: 8) {
                    if let listName {
                        Text(listName).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let meta, meta.daysCarried > 0 {
                        Text("carried \(meta.daysCarried)d")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if let meta, meta.skipCount > 0 {
                        Text("skipped \(meta.skipCount)×")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    if let meta, meta.focusSeconds > 0 {
                        Text(TimeFormat.duration(TimeInterval(meta.focusSeconds)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if task.taskRecurrence != .none {
                        Label(task.taskRecurrence.title, systemImage: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let reason = task.skipReason, !reason.isEmpty {
                        Text("(\(reason))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if !task.taskStatus.isTerminal {
                    Button(task.taskStatus == .doing ? "Focus" : "Do") {
                        if let id = task.id {
                            model.setTaskStatus(taskId: id, status: .doing)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button("Skip") {
                        skipReason = ""
                        skipTarget = task
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                Menu {
                    Button("Edit…") { editingTask = task }
                    if task.taskStatus != .todo {
                        Button("Mark Todo") {
                            if let id = task.id { model.setTaskStatus(taskId: id, status: .todo) }
                        }
                    }
                    if task.taskStatus != .abandoned {
                        Button("Abandon") {
                            if let id = task.id { model.setTaskStatus(taskId: id, status: .abandoned) }
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        if let id = task.id { model.deleteTask(id: id) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(10)
        .holtGlass(cornerRadius: 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if !task.taskStatus.isTerminal {
                model.selectedTaskId = task.id
            }
        }
    }

    private func submitQuickAdd() {
        let trimmed = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targetList = quickListId ?? selectedListId ?? model.lists.first?.id
        model.quickAddTask(
            title: trimmed,
            listId: targetList,
            priority: quickPriority,
            recurrence: quickRecurrence
        )
        quickTitle = ""
        quickPriority = 0
        quickRecurrence = .none
    }

    private func skipSheet(for task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skip '\(task.title)'")
                .font(.headline)
            TextField("Why are you skipping it? (Holt remembers)", text: $skipReason)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { skipTarget = nil }
                Button("Skip task") {
                    if let id = task.id {
                        model.setTaskStatus(taskId: id, status: .skipped, skipReason: skipReason.isEmpty ? nil : skipReason)
                    }
                    skipTarget = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private var newListPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New list").font(.headline)
            TextField("List name", text: $newListName)
                .textFieldStyle(.roundedBorder)
            Picker("Icon", selection: $newListIcon) {
                Label("Folder", systemImage: "folder.fill").tag("folder.fill")
                Label("Briefcase", systemImage: "briefcase.fill").tag("briefcase.fill")
                Label("Book", systemImage: "book.fill").tag("book.fill")
                Label("Star", systemImage: "star.fill").tag("star.fill")
                Label("Wrench", systemImage: "wrench.fill").tag("wrench.fill")
            }
            HStack {
                Spacer()
                Button("Cancel") { showNewList = false }
                Button("Create") {
                    model.createList(name: newListName, color: newListColor, icon: newListIcon)
                    newListName = ""
                    showNewList = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func statusSymbol(_ status: TaskStatus) -> String {
        switch status {
        case .todo: "circle"
        case .doing: "circle.inset.filled"
        case .done: "checkmark.circle.fill"
        case .skipped: "arrow.uturn.right.circle"
        case .abandoned: "xmark.circle"
        }
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .todo: .secondary
        case .doing: .orange
        case .done: .green
        case .skipped: .yellow
        case .abandoned: .red
        }
    }
}

private struct EditTaskSheet: View {
    @State var task: TaskItem
    let lists: [TaskList]
    let onSave: (TaskItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit task").font(.headline)
            TextField("Title", text: $task.title)
                .textFieldStyle(.roundedBorder)
            TextField("Notes", text: Binding(
                get: { task.notes ?? "" },
                set: { task.notes = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            TextField("Link (URL or file path)", text: Binding(
                get: { task.link ?? "" },
                set: { task.link = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            HStack {
                Picker("List", selection: Binding(
                    get: { task.listId ?? lists.first?.id ?? Int64(1) },
                    set: { task.listId = $0 }
                )) {
                    ForEach(lists) { list in
                        Text(list.name).tag(list.id ?? Int64(0))
                    }
                }
                Picker("Priority", selection: $task.priority) {
                    Text("Normal").tag(0)
                    Text("Medium").tag(1)
                    Text("High").tag(2)
                }
                Picker("Repeat", selection: Binding(
                    get: { task.taskRecurrence },
                    set: { task.taskRecurrence = $0 }
                )) {
                    ForEach(TaskRecurrence.allCases, id: \.self) { rec in
                        Text(rec.title).tag(rec)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(task)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
    }
}
