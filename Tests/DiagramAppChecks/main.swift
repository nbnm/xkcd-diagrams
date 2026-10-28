import AppKit
import DiagramCore

struct CheckFailure: Error { let message: String }
func expect(_ value: @autoclosure () throws -> Bool, line: UInt = #line) throws {
    if try !value() { throw CheckFailure(message: "Failed expectation at line \(line)") }
}
func fixture(_ title: String, at url: URL) throws {
    _ = try DiagramFiles.write(Diagram(title: title), to: url, overwrite: true)
}
func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("diagram-tab-checks-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
}

@MainActor func tabsKeepEditingHistorySelectionAndViewportSeparate() throws {
    let workspace = WorkspaceStore(defaults: nil, confirmClose: { _ in true }), first = workspace.activeStore
    first.selection = "lakehouse"; first.canvasViewport = CanvasViewport(zoom: 0.4, offset: CGPoint(x: -100, y: 85))
    first.mutate("Rename") { $0.title = "First diagram" }
    workspace.newTab()
    let second = workspace.activeStore
    second.mutate("Add") { d in d.nodes["a"] = Node(label: "Only in second"); d.containers[d.root]?.children = ["a"] }
    second.selection = "a"; second.canvasViewport = CanvasViewport(zoom: 1.5, offset: CGPoint(x: 15, y: 25))
    second.beginContainerPlacement(); workspace.select(first.id)
    try expect(workspace.tabs.count == 2 && !second.placingContainer)
    try expect(first.selection == "lakehouse" && first.canvasViewport?.zoom == 0.4 && first.canvasViewport?.offset.x == -100)
    workspace.activeStore.undo()
    try expect(first.document.title == "T1A Data Platform" && second.document.nodes["a"] != nil)
    workspace.select(second.id); workspace.activeStore.undo()
    try expect(second.document.nodes.isEmpty && first.document.nodes["lakehouse"] != nil)
    try expect(second.canvasViewport?.zoom == 1.5 && second.canvasViewport?.offset == CGPoint(x: 15, y: 25))
    workspace.activeStore.redo(); try expect(second.document.nodes["a"] != nil && first.canRedo)
}

@MainActor func openingFilesPreservesUnsavedTabsAndDeduplicatesPaths() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appendingPathComponent("a.diagram.json"), b = dir.appendingPathComponent("b.diagram.json")
    try fixture("A", at: a); try fixture("B", at: b)
    let workspace = WorkspaceStore(defaults: nil), original = workspace.activeStore
    original.mutate("Edit") { $0.title = "Unsaved work" }
    workspace.open(a); let aID = workspace.activeStore.id
    workspace.open(b); try expect(workspace.tabs.count == 3 && original.dirty && original.document.title == "Unsaved work")
    let alias = dir.appendingPathComponent("alias.json")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
    workspace.open(alias); try expect(workspace.tabs.count == 3 && workspace.activeStore.id == aID)
    let invalid = dir.appendingPathComponent("broken.json"); try Data("{}".utf8).write(to: invalid)
    workspace.open(invalid)
    try expect(workspace.tabs.count == 3 && workspace.activeStore.id == aID && workspace.activeStore.errorMessage != nil)
}

@MainActor func closingTabsHonorsCancelAndKeepsAValidActiveEditor() throws {
    var allowClose = false
    let workspace = WorkspaceStore(defaults: nil, confirmClose: { _ in allowClose }), first = workspace.activeStore
    first.mutate("Edit") { $0.title = "Keep me" }; workspace.newTab(); let second = workspace.activeStore
    workspace.closeTab(first.id)
    try expect(workspace.tabs.count == 2 && workspace.activeStore.id == second.id && first.dirty)
    allowClose = true; workspace.closeTab(first.id)
    try expect(workspace.tabs.count == 1 && workspace.activeStore.id == second.id)
    workspace.newTab(); let third = workspace.activeStore
    workspace.closeActiveTab(); try expect(workspace.activeStore.id == second.id && workspace.tabs.count == 1)
    workspace.closeActiveTab()
    try expect(workspace.tabs.count == 1 && workspace.activeStore.document.nodes.isEmpty)
    try expect(workspace.activeStore.id != second.id && workspace.activeStore.id != third.id)
    workspace.switchTab(by: 1); try expect(workspace.tabs.count == 1)
}

@MainActor func switchingTabsWrapsAndLeavesTheirDiagramsIntact() throws {
    let workspace = WorkspaceStore(defaults: nil), first = workspace.activeStore
    workspace.newTab(); let second = workspace.activeStore
    workspace.newTab(); let third = workspace.activeStore
    workspace.switchTab(by: 1); try expect(workspace.activeStore.id == first.id)
    workspace.switchTab(by: -1); try expect(workspace.activeStore.id == third.id)
    workspace.switchTab(by: -1); try expect(workspace.activeStore.id == second.id)
    workspace.select(UUID()); try expect(workspace.activeStore.id == second.id)
    try expect(first.document.nodes.count == 5 && second.document.nodes.isEmpty && third.document.nodes.isEmpty)
}

@MainActor func quittingChecksEveryDirtyTabAndCancelKeepsAllTabs() throws {
    var rejected: UUID?, requested: [UUID] = []
    let workspace = WorkspaceStore(defaults: nil, confirmClose: { tab in requested.append(tab.id); return tab.id != rejected })
    let first = workspace.activeStore
    first.mutate("Edit") { $0.title = "First" }; workspace.newTab()
    let second = workspace.activeStore; second.mutate("Edit") { $0.title = "Second" }
    rejected = first.id
    try expect(!workspace.confirmCloseAll() && workspace.tabs.count == 2)
    try expect(requested == [second.id, first.id])
    rejected = nil; requested = []
    try expect(workspace.confirmCloseAll() && Set(requested) == Set([first.id, second.id]))
    let count = requested.count; try expect(workspace.confirmCloseAll() && requested.count == count)
    first.mutate("New edit") { $0.title = "Changed again" }
    try expect(workspace.confirmCloseAll() && requested.count > count)
}

@MainActor func savedTabSessionRestoresSelectionAndSkipsInvalidPaths() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appendingPathComponent("a.diagram.json"), b = dir.appendingPathComponent("b.diagram.json")
    try fixture("A", at: a); try fixture("B", at: b)
    let suite = "diagram-tabs-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set([a.path, b.path, a.path, dir.appendingPathComponent("missing.json").path], forKey: "openDiagramTabs")
    defaults.set(a.standardizedFileURL.resolvingSymlinksInPath().path, forKey: "selectedDiagramTab")
    let workspace = WorkspaceStore(defaults: defaults)
    try expect(workspace.tabs.count == 2 && workspace.activeStore.document.title == "A")
    workspace.switchTab(by: 1)
    let restored = WorkspaceStore(defaults: defaults)
    try expect(restored.tabs.count == 2 && restored.activeStore.document.title == "B")
    restored.closeActiveTab()
    try expect(WorkspaceStore(defaults: defaults).tabs.count == 1)
}

@MainActor func savedFilesCannotCollideAndInactiveTabsDetectExternalEdits() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appendingPathComponent("a.diagram.json"), b = dir.appendingPathComponent("b.diagram.json")
    try fixture("A", at: a); try fixture("B", at: b)
    let workspace = WorkspaceStore(defaults: nil)
    workspace.open(a); let first = workspace.activeStore
    workspace.open(b); let second = workspace.activeStore
    try expect(first.canSaveTo?(a) == true && first.canSaveTo?(b) == false)
    first.url = b; let bytes = try Data(contentsOf: b)
    try expect(!first.save() && first.errorMessage != nil)
    try expect(try Data(contentsOf: b) == bytes)
    first.url = a; workspace.select(first.id)
    try fixture("External B", at: b); workspace.checkExternalChanges()
    try expect(second.document.title == "External B" && first.document.title == "A")
    second.mutate("Local edit") { $0.title = "Local B" }
    try fixture("Another external B", at: b); workspace.checkExternalChanges()
    try expect(second.externalChange && second.document.title == "Local B")
    workspace.select(second.id); try expect(workspace.activeStore.externalChange)
    first.stopAutosave(); second.stopAutosave()
}

@MainActor func discardingClosedTabsCancelsPendingAutosave() async throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("a.diagram.json"); try fixture("Saved original", at: file)
    let workspace = WorkspaceStore(defaults: nil, confirmClose: { _ in true })
    workspace.open(file); let store = workspace.activeStore, bytes = try Data(contentsOf: file)
    store.mutate("Unsaved edit") { $0.title = "Discard this" }
    workspace.closeTab(store.id)
    try await Task.sleep(for: .seconds(1))
    try expect(try Data(contentsOf: file) == bytes)
}

@main struct DiagramAppChecks {
    @MainActor static func main() async {
        let checks: [(String, @MainActor () async throws -> Void)] = [
            ("modesKeepDocumentsSeparateAndNewTabsInheritMode", { try modesKeepDocumentsSeparateAndNewTabsInheritMode() }),
            ("freeDrawingMouseGesturesAreAtomicAndEditable", { try freeDrawingMouseGesturesAreAtomicAndEditable() }),
            ("inlineTextCommitsOnceAndCancelsWithoutCreatingItems", { try inlineTextCommitsOnceAndCancelsWithoutCreatingItems() }),
            ("timelineMouseMoveResizeAndReorderKeepDatesConsistent", { try timelineMouseMoveResizeAndReorderKeepDatesConsistent() }),
            ("modeClipboardUsesFreshIDsAndPreservesOtherItems", { try modeClipboardUsesFreshIDsAndPreservesOtherItems() }),
            ("modeFilesRestoreAndSwitchingCommitsPendingText", { try modeFilesRestoreAndSwitchingCommitsPendingText() }),
            ("tabsKeepEditingHistorySelectionAndViewportSeparate", { try tabsKeepEditingHistorySelectionAndViewportSeparate() }),
            ("openingFilesPreservesUnsavedTabsAndDeduplicatesPaths", { try openingFilesPreservesUnsavedTabsAndDeduplicatesPaths() }),
            ("closingTabsHonorsCancelAndKeepsAValidActiveEditor", { try closingTabsHonorsCancelAndKeepsAValidActiveEditor() }),
            ("switchingTabsWrapsAndLeavesTheirDiagramsIntact", { try switchingTabsWrapsAndLeavesTheirDiagramsIntact() }),
            ("quittingChecksEveryDirtyTabAndCancelKeepsAllTabs", { try quittingChecksEveryDirtyTabAndCancelKeepsAllTabs() }),
            ("savedTabSessionRestoresSelectionAndSkipsInvalidPaths", { try savedTabSessionRestoresSelectionAndSkipsInvalidPaths() }),
            ("savedFilesCannotCollideAndInactiveTabsDetectExternalEdits", { try savedFilesCannotCollideAndInactiveTabsDetectExternalEdits() }),
            ("discardingClosedTabsCancelsPendingAutosave", discardingClosedTabsCancelsPendingAutosave)
        ]
        var failures = 0
        for (name, check) in checks {
            do { try await check(); print("PASS  \(name)") }
            catch { failures += 1; print("FAIL  \(name): \(error)") }
        }
        print("\(checks.count - failures)/\(checks.count) app checks passed")
        if failures > 0 { exit(1) }
    }
}
