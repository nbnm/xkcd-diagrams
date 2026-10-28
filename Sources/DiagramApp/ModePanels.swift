import SwiftUI
import DiagramCore

struct ModeToolbox: View {
    @ObservedObject var store: EditorStore
    @Binding var appAppearance: AppAppearance
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.document.mode == .drawing ? "FREE DRAWING" : "TIMELINE").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary).padding(18)
            if store.document.mode == .drawing { drawingTools } else { timelineTools }
            Spacer(minLength: 0)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("App appearance").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Picker("App appearance", selection: $appAppearance) {
                    Label("Light", systemImage: "sun.max").tag(AppAppearance.light)
                    Label("Dark", systemImage: "moon").tag(AppAppearance.dark)
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("App appearance")
                Text("⌥ drag to pan · pinch to zoom\n⌘0 fits all content").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(16)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private var drawingTools: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(FreeDrawingTool.allCases, id: \.self) { tool in
                Button { store.chooseDrawingTool(tool) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tool.symbol).font(.system(size: 18)).frame(width: 26)
                        Text(tool.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(tool.key).font(.system(size: 11).monospaced()).foregroundStyle(.secondary)
                    }.padding(10).contentShape(Rectangle())
                        .background(store.drawingTool == tool ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).help("\(tool.title) — \(tool.key)").accessibilityLabel(tool.title + " tool")
            }
            Divider().padding(.vertical, 12)
            Text("PEN DEFAULTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack { Text("Line width"); Spacer(); Text(String(format: "%.1f", store.document.drawing?.strokeWidth ?? 2)).monospacedDigit() }.font(.system(size: 12))
            Slider(value: Binding(get: { store.document.drawing?.strokeWidth ?? 2 }, set: { v in store.mutate("Change pen width") { $0.drawing?.strokeWidth = v } }), in: 0.5...8).accessibilityLabel("Pen line width")
            HStack { Text("Smoothness"); Spacer(); Text("\(Int((store.document.drawing?.smoothing ?? 0.65) * 100))%").monospacedDigit() }.font(.system(size: 12))
            Slider(value: Binding(get: { store.document.drawing?.smoothing ?? 0.65 }, set: { v in store.mutate("Change pen smoothing") { $0.drawing?.smoothing = v } }), in: 0...1).accessibilityLabel("Pen smoothness")
            Text("Mouse strokes are smoothed as you draw. Select a stroke to refine its width or smoothness later.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            Divider().padding(.vertical, 12)
            Text("Click with Text to type on the canvas. ⌘Return finishes; Escape cancels. Double-click text to edit it.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
        }.padding(.horizontal, 14)
    }
    private var timelineTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { store.addTask() } label: { Label("Task", systemImage: "plus") }.help("Add task (N)").accessibilityLabel("Add Task")
                Button { store.addTask(milestone: true) } label: { Label("Milestone", systemImage: "diamond") }.help("Add milestone (M)").accessibilityLabel("Add Milestone")
            }.controlSize(.small)
            Picker("Timescale", selection: Binding(get: { store.document.timeline?.scale ?? .weeks }, set: { value in store.mutate("Change timescale") { $0.timeline?.scale = value } })) {
                ForEach(TimelineScale.allCases, id: \.self) { Text($0.title).tag($0) }
            }.accessibilityLabel("Timeline timescale")
            if store.document.timeline?.tasks.isEmpty == true {
                Button("Insert example timeline") {
                    store.mutate("Insert timeline example") { $0.timeline = .example() }; store.fitRequest += 1
                }.padding(.top, 8)
                Text("Create tasks and milestones, then set dates and predecessors in the inspector.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.document.timeline?.tasks ?? []) { task in
                        Button { store.selection = task.id } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: task.milestone ? "diamond" : "rectangle.split.3x1").frame(width: 18)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.label).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                    Text(task.milestone ? task.start : "\(task.duration)d · \(Int(task.progress * 100))% complete").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                .background(store.selection == task.id ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain).accessibilityLabel("Select task: " + task.label)
                    }
                }
            }
            Text("Calendar days, including weekends. Dependencies are visual links; dates stay under your control.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
        }.padding(.horizontal, 14)
    }
}

struct ModeInspector: View {
    @ObservedObject var store: EditorStore
    @FocusState private var nameFocused: Bool
    private var selectedTask: TimelineTask? { store.document.timeline?.tasks.first { $0.id == store.selection } }
    private var selectedStroke: InkStroke? { store.document.drawing?.strokes.first { $0.id == store.selection } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("INSPECTOR").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                if let task = selectedTask { taskInspector(task) }
                else if let stroke = selectedStroke { strokeInspector(stroke) }
                else if let id = store.selection, store.document.nodes[id] != nil { textInspector(id) }
                else {
                    Text(store.document.mode.title).font(.title3.weight(.semibold))
                    TextField("Title", text: Binding(get: { store.document.title }, set: { value in store.mutate("Rename document") { $0.title = value } })).textFieldStyle(.roundedBorder)
                    Text(store.document.mode == .drawing ? "Draw with the mouse or choose Text to type anywhere. Use Select to move a mark." : "Select a task to edit its dates, completion, owner, and predecessors.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                }
                Divider()
                Text("Document appearance").font(.system(size: 12, weight: .semibold))
                Picker("Font", selection: Binding(get: { store.document.theme.fontFamily ?? "" }, set: { value in store.mutate("Change font") { $0.theme.fontFamily = value.isEmpty ? nil : value } })) {
                    Text("Style default").tag(""); Text("Helvetica").tag("Helvetica"); Text("Menlo").tag("Menlo"); Text("Chalkboard SE").tag("ChalkboardSE-Regular")
                }
                if store.document.mode == .drawing {
                    Stepper("Default text size  \(Int(store.document.theme.fontSize))", value: Binding(get: { store.document.theme.fontSize }, set: { v in store.mutate("Change default text size") { $0.theme.fontSize = v } }), in: 10...36, step: 1)
                }
                Toggle("T1A watermark", isOn: Binding(get: { store.document.watermark }, set: { value in store.mutate("Toggle watermark") { $0.watermark = value } }))
                if store.selection != nil { Divider(); Button("Delete Selection", role: .destructive, action: store.deleteSelection) }
            }.font(.system(size: 12)).padding(18)
        }.onChange(of: store.labelEditRequest) { _, _ in nameFocused = true }
    }
    @ViewBuilder private func taskInspector(_ task: TimelineTask) -> some View {
        Text(task.milestone ? "Milestone" : "Task").font(.title3.weight(.semibold))
        TextField("Task name", text: Binding(get: { store.document.timeline?.tasks.first { $0.id == task.id }?.label ?? "" }, set: { v in store.editTask(task.id) { $0.label = v } }), axis: .vertical).textFieldStyle(.roundedBorder).accessibilityLabel("Task name").focused($nameFocused)
        DatePicker("Start", selection: Binding(get: { TimelineDate.parse(task.start)! }, set: { date in store.editTask(task.id, action: "Change task start") { $0.start = TimelineDate.string(date) } }), in: TimelineDate.parse("1900-01-01")!...TimelineDate.parse("2200-12-31")!, displayedComponents: .date).environment(\.timeZone, TimelineDate.calendar.timeZone).accessibilityLabel("Task start date")
        if !task.milestone {
            Stepper("Duration  \(task.duration) days", value: Binding(get: { task.duration }, set: { value in store.editTask(task.id, action: "Change duration") { $0.duration = value } }), in: 1...3650).accessibilityLabel("Task duration")
            DatePicker("Finish", selection: Binding(get: { TimelineDate.parse(task.finish)! }, set: { date in store.editTask(task.id, action: "Change task finish") { $0.duration = TimelineDate.distance($0.start, TimelineDate.string(date)) + 1 } }), in: TimelineDate.parse(task.start)!...TimelineDate.parse("2200-12-31")!, displayedComponents: .date).environment(\.timeZone, TimelineDate.calendar.timeZone).accessibilityLabel("Task finish date")
            HStack { Text("Complete"); Spacer(); Text("\(Int(task.progress * 100))%").monospacedDigit() }
            Slider(value: Binding(get: { task.progress }, set: { value in store.editTask(task.id, action: "Change progress") { $0.progress = value } }), in: 0...1, step: 0.01).accessibilityLabel("Task completion")
        }
        TextField("Owner / team", text: Binding(get: { task.owner }, set: { v in store.editTask(task.id) { $0.owner = v } })).textFieldStyle(.roundedBorder).accessibilityLabel("Task owner")
        Toggle("Milestone", isOn: Binding(get: { task.milestone }, set: { value in store.editTask(task.id, action: "Change task type") { $0.milestone = value; $0.duration = value ? 0 : 1 } }))
        Divider()
        Text("Predecessors").fontWeight(.semibold)
        ForEach((store.document.timeline?.tasks ?? []).filter { $0.id != task.id }) { other in
            Toggle(other.label, isOn: Binding(get: { task.dependencies.contains(other.id) }, set: { value in
                store.editTask(task.id, action: "Change predecessors") { t in if value { t.dependencies.append(other.id) } else { t.dependencies.removeAll { $0 == other.id } } }
            })).toggleStyle(.checkbox).help("Finish-to-start link. Dates are edited manually; cycles are rejected.")
        }
        if let conflict = store.document.timeline?.tasks.first(where: { task.dependencies.contains($0.id) && $0.finish >= task.start }) {
            Text("Starts before \(conflict.label) finishes. Adjust the dates if this link is a scheduling constraint.").font(.system(size: 11)).foregroundStyle(.orange)
        }
        HStack {
            Button { store.reorderTask(task.id, by: -1) } label: { Label("Up", systemImage: "arrow.up") }
            Button { store.reorderTask(task.id, by: 1) } label: { Label("Down", systemImage: "arrow.down") }
        }.controlSize(.small)
    }
    @ViewBuilder private func strokeInspector(_ stroke: InkStroke) -> some View {
        Text("Pen stroke").font(.title3.weight(.semibold))
        Text("Line width  \(String(format: "%.1f", stroke.strokeWidth))").monospacedDigit()
        Slider(value: Binding(get: { stroke.strokeWidth }, set: { value in editStroke(stroke.id, "Change stroke width") { $0.strokeWidth = value } }), in: 0.5...8).accessibilityLabel("Selected stroke line width")
        Text("Smoothness  \(Int(stroke.smoothing * 100))%").monospacedDigit()
        Slider(value: Binding(get: { stroke.smoothing }, set: { value in editStroke(stroke.id, "Smooth stroke") { $0.smoothing = value } }), in: 0...1).accessibilityLabel("Selected stroke smoothness")
        Text("Changes apply to this stroke only. Original mouse points are preserved.").font(.system(size: 11)).foregroundStyle(.secondary)
    }
    @ViewBuilder private func textInspector(_ id: String) -> some View {
        Text("Text").font(.title3.weight(.semibold))
        TextField("Text", text: Binding(get: { store.document.nodes[id]?.label ?? "" }, set: { v in store.mutate("Edit text", coalescingKey: id) { $0.nodes[id]?.label = v } }), axis: .vertical).textFieldStyle(.roundedBorder).accessibilityLabel("Drawing text")
        Stepper("Text size  \(Int(store.document.fontSize(for: id)))", value: Binding(get: { store.document.fontSize(for: id) }, set: { v in store.mutate("Change text size", coalescingKey: id) { $0.nodes[id]?.fontSize = v } }), in: 10...36, step: 1)
        Button("Edit on canvas") { store.labelEditRequest += 1 }
    }
    private func editStroke(_ id: String, _ action: String, _ edit: (inout InkStroke) -> Void) {
        store.mutate(action, coalescingKey: action + id) { d in
            if let index = d.drawing?.strokes.firstIndex(where: { $0.id == id }) { edit(&d.drawing!.strokes[index]) }
        }
    }
}
