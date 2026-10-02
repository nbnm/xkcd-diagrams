import SwiftUI
import DiagramCore

struct EditorView: View {
    @ObservedObject var store: EditorStore
    @Binding var appAppearance: AppAppearance
    @Environment(\.colorScheme) private var colorScheme
    @State private var search = ""
    @State private var expandedGroups: Set<String> = ["Documents", "Databricks"]
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 0) {
            if store.externalChange {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("The source file changed. Your edits are still in the app.")
                    Spacer(); Button("Reload", action: store.reloadExternal); Button("Save a Copy") { store.save(asCopy: true) }
                }.font(.system(size: 12)).padding(12).background(Color.orange.opacity(0.12))
                Divider()
            }
            HSplitView {
                library.frame(minWidth: 210, idealWidth: 230, maxWidth: 300)
                DiagramCanvas(store: store).frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                Inspector(store: store).frame(minWidth: 240, idealWidth: 260, maxWidth: 320)
            }
            Divider()
            HStack(spacing: 12) {
                Circle().fill(store.externalChange ? Color.orange : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                Text(store.status)
                Spacer()
                Text("\(store.document.nodes.count) systems · \(store.document.containers.count - 1) boundaries")
                Divider().frame(height: 12)
                Text(store.connecting ? (store.connectionStart == nil ? "Select the source" : "Select the destination") : "⌥ drag to pan · pinch to zoom")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: 30)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.document.title).font(.system(size: 13, weight: .semibold))
                    Text(store.url?.lastPathComponent ?? "Unsaved diagram").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            ToolbarItemGroup {
                Picker("Diagram style", selection: Binding(get: { store.document.theme.preset }, set: { value in store.mutate("Change diagram style") { $0.theme.preset = value } })) {
                    Text("Sketch").tag(ThemePreset.sketch); Text("Standard").tag(ThemePreset.standard); Text("Blueprint").tag(ThemePreset.blueprint); Text("Dark").tag(ThemePreset.dark)
                }.pickerStyle(.segmented).frame(width: 300)
                    .accessibilityLabel("Diagram style")
                    .help("Change the diagram and image exports; app appearance is controlled separately")
                Menu {
                    Button("Add Container", action: { store.addContainer() })
                    Button("Add Container Below Diagram", action: store.addContainerBelow)
                } label: { Label("Container", systemImage: "rectangle.dashed").labelStyle(.titleAndIcon) }
                  primaryAction: { store.addContainer() }
                    .help("Add a container (⇧⌘G), or use the menu to add a wide container below the diagram")
                ConnectorToolButton(store: store, toolbar: true).frame(width: 105, height: 28)
                Button(action: store.zoomOut) { Image(systemName: "minus.magnifyingglass") }
                    .disabled(!store.canZoomOut).help("Zoom out (⌘−)").accessibilityLabel("Zoom Out")
                Text("\(Int((store.zoomScale * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit()).frame(width: 40)
                    .accessibilityLabel("Zoom level").accessibilityValue("\(Int((store.zoomScale * 100).rounded())) percent")
                Button(action: store.zoomIn) { Image(systemName: "plus.magnifyingglass") }
                    .disabled(!store.canZoomIn).help("Zoom in (⌘+ or ⌘=)").accessibilityLabel("Zoom In")
                Button { store.fitRequest += 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("Fit to content (⌘0)").accessibilityLabel("Fit to Content")
                Button { store.sourceVisible = true } label: { Image(systemName: "curlybraces") }.help("Edit source")
                Button { store.save() } label: { Image(systemName: "square.and.arrow.down") }.help("Save (⌘S)")
                Menu {
                    Button("Export SVG…") { store.export("svg") }
                    Button("Export PNG…") { store.export("png") }
                    Button("Save JSON…") { store.save(asCopy: true) }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
            }
        }
        .sheet(isPresented: $store.sourceVisible) { SourceEditor(store: store) }
        .alert("Unable to apply change", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onReceive(poll) { _ in store.checkExternalChanges() }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LIBRARY").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.top, 22)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search library", text: $search).textFieldStyle(.plain)
            }.padding(8).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6)).padding(14)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    Button { store.addContainer() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.dashed").font(.system(size: 18)).frame(width: 28)
                            Text("Container").font(.system(size: 12, weight: .semibold)); Spacer()
                        }.foregroundStyle(.primary).padding(.vertical, 10).padding(.horizontal, 7).contentShape(Rectangle())
                    }.buttonStyle(.plain).onDrag { NSItemProvider(object: "__container" as NSString) }.help("Drag a container onto the canvas")
                    ConnectorToolButton(store: store).frame(maxWidth: .infinity).frame(height: 40)
                    Divider().padding(.vertical, 6)
                    Text("Shapes").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 7).padding(.vertical, 5)
                    ForEach(store.library.filter { $0.group == "Systems" && matches($0) }) { item in libraryRow(item) }
                    libraryGroup(Library.documentGroup).padding(.top, 10)
                    Text("Platforms").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 7).padding(.top, 16).padding(.bottom, 6)
                    ForEach(Library.groups, id: \.self) { group in
                        libraryGroup(group)
                    }
                }.padding(.horizontal, 12)
                Divider().padding(.vertical, 20)
                VStack(alignment: .leading, spacing: 8) {
                    Text("OUTLINE").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                    OutlineBranch(store: store, id: store.document.root, depth: 0)
                }.padding(.horizontal, 16)
            }
            Spacer(minLength: 0)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("App appearance").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Picker("App appearance", selection: $appAppearance) {
                    Label("Light", systemImage: "sun.max").tag(AppAppearance.light)
                    Label("Dark", systemImage: "moon").tag(AppAppearance.dark)
                }.pickerStyle(.segmented).labelsHidden()
                    .accessibilityLabel("App appearance")
                    .help("Change the interface only; your diagram style stays the same")
                Text("Drag systems into a boundary.\nContainers keep everything aligned.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(16)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private func matches(_ item: DiagramCore.LibraryItem) -> Bool { search.isEmpty || item.title.localizedCaseInsensitiveContains(search) || item.group.localizedCaseInsensitiveContains(search) }
    @ViewBuilder private func libraryGroup(_ group: String) -> some View {
        let items = store.library.filter { $0.group == group && matches($0) }
        if !items.isEmpty {
            DisclosureGroup(isExpanded: Binding(get: { !search.isEmpty || expandedGroups.contains(group) }, set: { v in if v { expandedGroups.insert(group) } else { expandedGroups.remove(group) } })) {
                ForEach(items) { item in libraryRow(item) }
            } label: { Text(group).font(.system(size: 12, weight: .medium)) }.padding(.horizontal, 7).padding(.vertical, 5)
        }
    }
    private func libraryRow(_ item: DiagramCore.LibraryItem) -> some View {
        Button { store.add(item) } label: {
            HStack(spacing: 10) {
                Image(nsImage: LibraryThumbnail.image(item, dark: colorScheme == .dark)).frame(width: 28, height: 24)
                Text(item.title).font(.system(size: 12)); Spacer()
            }.foregroundStyle(.primary).padding(.vertical, 7).padding(.horizontal, 7).contentShape(Rectangle())
        }.buttonStyle(.plain).onDrag { NSItemProvider(object: item.id as NSString) }.help("Drag onto the canvas, or click to add")
    }
}

struct OutlineBranch: View {
    @ObservedObject var store: EditorStore
    let id: String
    let depth: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if depth > 0 {
                Button { store.select(id) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: store.document.containers[id] != nil ? "rectangle.dashed" : "square")
                        Text(store.document.label(of: id)).lineLimit(1)
                    }.font(.system(size: 11)).foregroundStyle(store.selection == id ? Color.accentColor : .primary)
                        .padding(.leading, CGFloat(max(0, depth - 1)) * 10).padding(.vertical, 3)
                }.buttonStyle(.plain)
            }
            if let container = store.document.containers[id] {
                ForEach(container.children, id: \.self) { child in OutlineBranch(store: store, id: child, depth: depth + 1) }
            }
        }
    }
}

struct Inspector: View {
    @ObservedObject var store: EditorStore
    @State private var waypointText = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("INSPECTOR").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                Text(store.selectionLabel).font(.system(size: 17, weight: .semibold)).lineLimit(3)
                Divider()
                if let id = store.selection, store.document.nodes[id] != nil { node(id) }
                else if let id = store.selection, store.document.connectors[id] != nil { connector(id) }
                else if let id = store.selection, store.document.containers[id] != nil, id != store.document.root { container(id) }
                else {
                    section("Diagram") {
                        TextField("Title", text: Binding(get: { store.document.title }, set: { v in store.mutate("Edit title") { $0.title = v } })).textFieldStyle(.roundedBorder)
                    }
                }
                Divider()
                section("Canvas placement") {
                    Picker("Top-level items", selection: Binding(get: { store.document.containers[store.document.root]?.layout.mode ?? .free }, set: store.setCanvasLayout)) {
                        Text("Free placement").tag(LayoutMode.free)
                        Text("Horizontal row").tag(LayoutMode.horizontal)
                        Text("Vertical column").tag(LayoutMode.vertical)
                        Text("Custom rows and columns").tag(LayoutMode.grid)
                    }
                    if store.document.containers[store.document.root]?.layout.mode == .grid {
                        gridDimensions(store.document.root)
                        Text("Select an item to choose its row, column, and span. Drag between cells to move or swap items.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    } else {
                        Text("Free placement lets you mix rows and columns. Each container arranges its own contents.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    if let id = store.selection, let parent = store.document.parent(of: id), store.document.containers[parent]?.layout.mode == .grid { gridCellControls(id, parent: parent) }
                    Button("Add container below diagram", action: store.addContainerBelow).buttonStyle(.borderless)
                }
                Divider()
                section("Diagram appearance") {
                    Picker("Font", selection: Binding(get: { store.document.theme.fontFamily ?? "Automatic" }, set: { value in store.mutate("Change font") { $0.theme.fontFamily = value == "Automatic" ? nil : value } })) {
                        Text("Style default").tag("Automatic")
                        Text("Chalkboard").tag("ChalkboardSE-Regular")
                        Text("Helvetica").tag("Helvetica")
                        Text("Menlo").tag("Menlo-Regular")
                    }
                    if store.document.theme.fontFamily != nil {
                        Text("Custom fonts apply to every style. Choose Style default for each style’s own font.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    Stepper("Text size  \(Int(store.document.theme.fontSize))", value: Binding(get: { store.document.theme.fontSize }, set: { v in store.mutate("Change text size") { $0.theme.fontSize = v } }), in: 10...36)
                    Toggle("T1A watermark", isOn: Binding(get: { store.document.watermark }, set: { v in store.mutate("Change watermark") { $0.watermark = v } }))
                        .toggleStyle(.checkbox)
                        .help("Add the T1A logo to the bottom-right corner of the diagram and image exports")
                }
                if store.selection != nil {
                    Divider()
                    Button("Delete Selection", role: .destructive, action: store.deleteSelection).buttonStyle(.borderless)
                }
            }.padding(20).font(.system(size: 12))
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.system(size: 12, weight: .semibold)); content() }
    }
    private func lineWidthControl(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Line width"); Spacer(); Text(String(format: "%.1f", store.document.strokeWidth(for: id))).foregroundStyle(.secondary) }
            Slider(value: Binding(get: { store.document.strokeWidth(for: id) }, set: { value in
                guard store.selection == id else { return }
                store.mutate("Change line width", coalescingKey: "stroke-\(id)") { try DiagramEditing.setStrokeWidth(value, element: id, document: &$0) }
            }), in: 0.5...8, step: 0.1)
                .help("Change only this selected object's line width")
            Button("Use default") {
                guard store.selection == id else { return }
                store.mutate("Reset line width", coalescingKey: "reset-stroke-\(id)") { try DiagramEditing.setStrokeWidth(nil, element: id, document: &$0) }
            }.buttonStyle(.borderless).font(.system(size: 11)).disabled(store.document.strokeWidthOverride(for: id) == nil)
        }.id(id)
    }
    private func node(_ id: String) -> some View {
        // SwiftUI may evaluate a retained binding after this item has been removed.
        // Keep its last displayed value until the old inspector is discarded.
        let snapshot = store.document.nodes[id] ?? Node()
        let current = store.document.nodes[id] ?? snapshot
        return section("System") {
            TextField("Label", text: Binding(get: { store.document.nodes[id]?.label ?? "" }, set: { v in store.mutate("Edit label") { $0.nodes[id]?.label = v } })).textFieldStyle(.roundedBorder)
            Picker("Shape", selection: Binding(get: { store.document.nodes[id]?.shape ?? snapshot.shape }, set: { v in store.mutate("Change shape") { $0.nodes[id]?.shape = v } })) {
                ForEach(Shape.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Stepper("Width  \(Int(current.width ?? current.shape.defaultWidth))", value: Binding(get: { let node = store.document.nodes[id] ?? snapshot; return node.width ?? node.shape.defaultWidth }, set: { v in store.mutate("Resize system") { $0.nodes[id]?.width = v } }), in: 80...600, step: 10)
            Picker("Logo", selection: Binding(get: { store.document.nodes[id]?.asset ?? "__none" }, set: { value in
                store.mutate("Change logo") { d in
                    if value == "__none" { d.nodes[id]?.asset = nil; d.nodes[id]?.variant = nil }
                    else if let item = store.library.first(where: { $0.id == value }), let asset = item.asset { d.assets[value] = asset; d.nodes[id]?.asset = value }
                }
            })) {
                Text("None").tag("__none")
                if let key = snapshot.asset, !store.library.contains(where: { $0.id == key }) { Text(store.document.assets[key]?.name ?? key).tag(key) }
                ForEach(Library.groups, id: \.self) { group in
                    Section(group) { ForEach(store.library.filter { $0.group == group && $0.asset != nil }) { item in Text(item.title).tag(item.id) } }
                }
            }
            if store.document.nodes[id]?.asset != nil {
                if store.scene.palette.lightInk { Text(store.document.theme.preset == .blueprint ? "Blueprint renders marks in white." : "Dark renders marks in light gray.").font(.system(size: 11)).foregroundStyle(.secondary) }
                else { Picker("Mark", selection: Binding(get: { store.document.nodes[id]?.variant ?? .black }, set: { v in store.mutate("Change logo variant") { $0.nodes[id]?.variant = v } })) {
                    Text("Black").tag(LogoVariant.black); Text("White").tag(LogoVariant.white)
                }.pickerStyle(.segmented) }
            }
            if let parent = store.document.parent(of: id) { Text("Inside \(store.document.label(of: parent))").foregroundStyle(.secondary) }
            if current.shape != .text { lineWidthControl(id) }
        }
    }
    private func container(_ id: String) -> some View {
        section(id == store.document.root ? "Diagram" : "Container") {
            TextField("Title", text: Binding(get: { id == store.document.root ? store.document.title : store.document.containers[id]?.label ?? "" }, set: { v in store.mutate("Edit title") { if id == $0.root { $0.title = v } else { $0.containers[id]?.label = v } } })).textFieldStyle(.roundedBorder)
            Picker("Arrange", selection: Binding(get: { store.document.containers[id]?.layout.mode ?? .free }, set: { v in store.mutate("Change arrangement") { try DiagramEditing.setLayout(v, container: id, document: &$0) } })) {
                Text("Horizontal").tag(LayoutMode.horizontal); Text("Vertical").tag(LayoutMode.vertical); Text("Free").tag(LayoutMode.free); Text("Custom grid").tag(LayoutMode.grid)
            }
            if store.document.containers[id]?.layout.mode == .grid { gridDimensions(id) }
            Stepper("Spacing  \(Int(store.document.containers[id]?.layout.gap ?? 28))", value: Binding(get: { store.document.containers[id]?.layout.gap ?? 28 }, set: { v in store.mutate("Change spacing") { $0.containers[id]?.layout.gap = v } }), in: 0...100, step: 4)
            Stepper("Padding  \(Int(store.document.containers[id]?.layout.padding ?? 28))", value: Binding(get: { store.document.containers[id]?.layout.padding ?? 28 }, set: { v in store.mutate("Change padding") { $0.containers[id]?.layout.padding = v } }), in: 0...100, step: 4)
            containerSizeControl(id)
            if store.document.parent(of: id) == store.document.root {
                Button("Place below diagram", action: store.placeSelectedContainerBelow).buttonStyle(.borderless)
                    .help("Keep other top-level items in place and make this container span their width underneath")
            }
            if let types = store.document.containers[id]?.allowedChildTypes { Text("Accepts: \(types.joined(separator: ", "))").foregroundStyle(.secondary) }
            Text("Drag items to reorder a stack, or choose Free to position them individually. Changing to a stack reroutes connections and resets manual bends.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            lineWidthControl(id)
        }
    }
    private func gridDimensions(_ id: String) -> some View {
        let layout = store.document.containers[id]?.layout ?? ContainerLayout(mode: .grid)
        let columns = layout.columns ?? 3, rows = layout.rows ?? 2
        return VStack(alignment: .leading, spacing: 8) {
            Stepper("Rows  \(rows)", value: Binding(get: { store.document.containers[id]?.layout.rows ?? rows }, set: { value in store.configureGrid(id, rows: value, columns: store.document.containers[id]?.layout.columns ?? columns) }), in: 1...32)
            Stepper("Columns  \(columns)", value: Binding(get: { store.document.containers[id]?.layout.columns ?? columns }, set: { value in store.configureGrid(id, rows: store.document.containers[id]?.layout.rows ?? rows, columns: value) }), in: 1...32)
        }
    }
    private func gridCellControls(_ id: String, parent: String) -> some View {
        let container = store.document.containers[parent] ?? Container()
        let plan = try? GridLayout.plan(container, id: parent), cell = plan?.cells[id] ?? GridCell()
        func currentCell() -> GridCell {
            guard let current = store.document.containers[parent], let currentPlan = try? GridLayout.plan(current, id: parent) else { return cell }
            return currentPlan.cells[id] ?? cell
        }
        func binding(_ keyPath: WritableKeyPath<GridCell, Int>) -> Binding<Int> {
            Binding(get: { currentCell()[keyPath: keyPath] }, set: { value in
                var updated = currentCell()
                updated[keyPath: keyPath] = value
                store.setGridCell(updated, element: id)
            })
        }
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Selected item’s cell").font(.system(size: 12, weight: .medium))
            Stepper("Row  \(cell.row)", value: binding(\.row), in: 1...(plan?.rows ?? 2))
            Stepper("Column  \(cell.column)", value: binding(\.column), in: 1...(plan?.columns ?? 3))
            Stepper("Row span  \(cell.rowSpan)", value: binding(\.rowSpan), in: 1...max(1, (plan?.rows ?? 2) - cell.row + 1))
            Stepper("Column span  \(cell.columnSpan)", value: binding(\.columnSpan), in: 1...max(1, (plan?.columns ?? 3) - cell.column + 1))
        }.id(id)
    }
    private func containerSizeControl(_ id: String) -> some View {
        let snapshot = store.scene.layout.frames[id]?.size ?? CGSize(width: 210, height: 130)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Width").frame(width: 46, alignment: .leading)
                TextField("Width", value: Binding(get: { store.document.containers[id]?.width ?? store.scene.layout.frames[id]?.width ?? snapshot.width }, set: { value in
                    guard store.selection == id else { return }
                    store.mutate("Resize container", coalescingKey: "width-\(id)") { $0.containers[id]?.width = value }
                }), format: .number.precision(.fractionLength(0))).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Height").frame(width: 46, alignment: .leading)
                TextField("Height", value: Binding(get: { store.document.containers[id]?.height ?? store.scene.layout.frames[id]?.height ?? snapshot.height }, set: { value in
                    guard store.selection == id else { return }
                    store.mutate("Resize container", coalescingKey: "height-\(id)") { $0.containers[id]?.height = value }
                }), format: .number.precision(.fractionLength(0))).textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Fit to contents") {
                    guard store.selection == id else { return }
                    store.mutate("Fit container to contents", coalescingKey: "fit-\(id)") { $0.containers[id]?.width = nil; $0.containers[id]?.height = nil }
                }.buttonStyle(.borderless).disabled(store.document.containers[id]?.width == nil && store.document.containers[id]?.height == nil)
            }
            Text("Minimum size in points; expands to fit its contents.").font(.system(size: 11)).foregroundStyle(.secondary)
        }.id(id)
    }
    private func connector(_ id: String) -> some View {
        let snapshot = store.document.connectors[id]
        return section("Connection") {
            TextField("Label", text: Binding(get: { store.document.connectors[id]?.label ?? "" }, set: { v in store.mutate("Edit connection label") { $0.connectors[id]?.label = v } })).textFieldStyle(.roundedBorder)
            Text("\(store.document.label(of: snapshot?.from.element ?? "")) → \(store.document.label(of: snapshot?.to.element ?? ""))").foregroundStyle(.secondary)
            Picker("Arrows", selection: Binding(get: { store.document.connectors[id]?.direction ?? snapshot?.direction ?? .forward }, set: { v in store.mutate("Change arrow") { $0.connectors[id]?.direction = v } })) {
                Text("Forward").tag(Direction.forward); Text("Both").tag(Direction.both); Text("None").tag(Direction.none)
            }
            Text("Right-angle path · perpendicular attachments").font(.system(size: 11)).foregroundStyle(.secondary)
            lineWidthControl(id)
            Toggle("Dashed line", isOn: Binding(get: { store.document.connectors[id]?.dashed ?? snapshot?.dashed ?? false }, set: { v in store.mutate("Change line pattern") { $0.connectors[id]?.dashed = v } }))
            Picker("Source side", selection: Binding(get: { store.document.connectors[id]?.from.side ?? snapshot?.from.side ?? .auto }, set: { v in store.mutate("Change attachment") { $0.connectors[id]?.from.side = v } })) {
                ForEach(Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Destination side", selection: Binding(get: { store.document.connectors[id]?.to.side ?? snapshot?.to.side ?? .auto }, set: { v in store.mutate("Change attachment") { $0.connectors[id]?.to.side = v } })) {
                ForEach(Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Text("Manual path points").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("x,y; x,y", text: $waypointText).textFieldStyle(.roundedBorder)
                .onChange(of: id, initial: true) { _, id in waypointText = (store.document.connectors[id]?.waypoints ?? []).map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: "; ") }
                .onSubmit {
                    let points = waypointText.split(separator: ";").compactMap { segment -> Point? in
                        let pair = segment.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        guard pair.count == 2, let x = Double(pair[0]), let y = Double(pair[1]) else { return nil }; return Point(x: x, y: y)
                    }
                    guard points.count == waypointText.split(separator: ";").count else { store.errorMessage = "Use coordinates in the form x,y; x,y."; return }
                    store.mutate("Adjust connection path") { $0.connectors[id]?.waypoints = points.isEmpty ? nil : points }
                }
        }
    }
}

struct SourceEditor: View {
    @ObservedObject var store: EditorStore
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Diagram Source").font(.title2.bold()); Spacer(); Text("JSON · Schema 1").foregroundStyle(.secondary) }
            Text("The canvas and agents use this same document. Changes are applied only after validation.").foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(size: 12, design: .monospaced)).scrollContentBackground(.hidden).padding(10).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            if let message { ScrollView { Text(message).foregroundStyle(.red).font(.system(size: 11)).textSelection(.enabled) }.frame(maxHeight: 90) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Apply Changes") {
                do { let d = try Diagram.decode(Data(text.utf8)); store.mutate("Apply source") { $0 = d }; dismiss() }
                catch { message = error.localizedDescription }
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 780, height: 640).onAppear { text = String(data: (try? store.document.encoded()) ?? Data(), encoding: .utf8) ?? "" }
    }
}
