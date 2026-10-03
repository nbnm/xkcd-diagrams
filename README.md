# XKCD Diagrams

A native macOS diagram editor and CLI sharing one JSON document model, layout engine, and deterministic vector renderer. This is the first runnable implementation of [the PRD](PRD.md), targeting macOS 14 or later. It currently builds for the local machine's architecture.

## Build and run

Install Apple's command-line developer tools if needed. No third-party packages or network downloads are required to build.

```sh
./scripts/build-app.sh
open "dist/XKCD Diagrams.app"
```

The build creates the app and `dist/diagram`. The bundle is signed locally for development; it is not a notarized distribution build. `./scripts/build-app.sh debug` creates a faster debug build.

## Installation

### macOS app

Requires macOS 14 or later. To build from source, install Apple's command-line developer tools with `xcode-select --install` if they are not already installed, then run `./scripts/build-app.sh` from this repository's root.

Quit an existing installed copy before replacing it. Install the built app for your user account:

```sh
mkdir -p "$HOME/Applications"
ditto "dist/XKCD Diagrams.app" "$HOME/Applications/XKCD Diagrams.app"
open "$HOME/Applications/XKCD Diagrams.app"
```

Keep the repository's `dist/` directory in place for agent access to the CLI. `dist/diagram` uses the accompanying `XKCDDiagrams_DiagramCore.bundle` for its schema and symbol library; preserve both when moving the CLI to another directory.

### Codex skill

Build the CLI first, then copy the complete skill folder into your Codex user skills directory. Run these commands from the repository root; repeat the copy command to update an installed copy:

```sh
diagram_skill_root="${CODEX_HOME:-$HOME/.codex}/skills"
mkdir -p "$diagram_skill_root"
ditto "skills/xkcd-diagrams" "$diagram_skill_root/xkcd-diagrams"
XKCD_DIAGRAM_CLI="$PWD/dist/diagram" \
  "$diagram_skill_root/xkcd-diagrams/scripts/diagram.sh" help
```

The helper defaults to `/Volumes/Work/xkcd-diagrams/dist/diagram`. For another checkout location, set `XKCD_DIAGRAM_CLI` to the absolute executable path in the environment used to launch Codex. For example, start the Codex CLI from this repository with:

```sh
XKCD_DIAGRAM_CLI="$PWD/dist/diagram" codex
```

For the desktop app, which may not inherit your shell environment, edit the fallback path in the installed `scripts/diagram.sh` instead. Keep the assignment's `${XKCD_DIAGRAM_CLI:-...}` form and replace only the path after `:-`. Reapply that local path after copying a skill update.

The skill enables automatic invocation for diagram requests and can also be invoked explicitly as `$xkcd-diagrams`. It creates editable JSON diagrams and image previews using the app's CLI. Start a new message after installation; if the skill is not listed, restart Codex. Other agents can use the same complete skill folder in their supported skills directory, with the CLI path configured for that machine.

## Editor

The app opens a T1A data platform example. Use File → New Diagram for a blank canvas. Drag shapes and vendor symbols from the library into the canvas or a boundary, or click a library entry to add it. Container is the first library item and a labeled toolbar action. Its inspector controls horizontal, vertical, or free arrangement; individual systems have no arrangement controls. Drag within a stack to reorder it, or into another container to change ownership. Type rules block invalid drops.

Set **Canvas placement → Custom rows and columns** to define a grid with 1–32 rows and columns. Select an item and use Row, Column, Row span, and Column span to assign its cell. Drag between cells to move items; single-cell items swap when dropped onto one another. Containers stretch across their assigned spans while arranging their own contents. Unassigned items fill available cells in child order; adding items or increasing spans adds rows when needed. Grid changes reroute connectors. Add Container Below Diagram keeps a custom grid and creates a new full-width row below the other items. Faint cell guides appear only in the editor; PNG and SVG exports contain the diagram.

Set **Canvas placement → Free placement** in the inspector to mix top-level rows and columns while each container keeps its own arrangement. Switching from a row or column preserves current positions. Use **Container menu → Add Container Below Diagram** for a wide horizontal container under the whole diagram, or select an existing top-level container and choose **Place below diagram**. Container Width and Height set minimum dimensions; **Fit to contents** restores automatic sizing. Drag top-level items freely; connectors follow their new positions. These settings persist in JSON and image exports.

Choose **Connector** in the toolbox or toolbar (⌘K), then drag from the source to the destination, or click each in turn. You can also drag the Connector toolbox item onto a source, then click a destination or drag from that source to it. Dropping the tool on empty canvas activates it so you can choose a source. A live right-angle preview highlights the destination; releasing on empty canvas or the source creates no connection and keeps the source ready for another attempt. Both systems and container boundaries can be connected; Escape on the canvas cancels. Connecting leaves item positions unchanged and creates one undoable edit. Every connector meets its source and destination edge at a right angle, with a short perpendicular approach before any bend. Click a connection or its label to edit arrows, endpoint sides, line pattern, and manual path points; manual points gain right-angle bends between them. Older `straight` routes also use this geometry. Changing a container to a horizontal or vertical stack resets affected connector sides and manual bends so connections follow the new arrangement; unrelated connections retain their settings. Select a system to edit its label, shape, width, and logo from a vendor-grouped picker. The Documents group contains File, XLSX, PDF, and DOCX. They keep a fixed 4:3 width-to-height ratio with folded corners, persistent format marks, and editable labels. Width changes and text or logo growth resize both dimensions together; the spreadsheet grid and document lines match their library previews. Queue uses a stack of message outlines, and library thumbnails use the same geometry as the canvas. Database labels and logos sit below the curved lid, with space above the lower outline; cylinders expand to fit wrapped text without covering their border.

Use **App appearance → Light / Dark** at the bottom of the library to choose the interface appearance. This preference is remembered across launches and applies to every diagram. It does not change the document, image exports, or undo history. The toolbar’s **Color theme** control selects Standard, Blueprint, Dark, SecondStack, or 8FDE. A separate **Sketch** toggle works with all five colors; both settings are saved in the diagram and used by image exports.

All five color themes support clean or sketch strokes. Sketch uses restrained, seeded pen variation on shape outlines, curved symbols, container boundaries, document details, and connectors. Connector bends and attachments retain straight sections and 90-degree angles. Turn Sketch off for precise outlines. Vendor marks stay undistorted in every combination. With **Style default**, Sketch uses Chalkboard SE; clean Standard, Dark, SecondStack, and 8FDE use Helvetica, and clean Blueprint uses Menlo. A custom Font choice applies to every combination and survives toggling Sketch. Dark uses charcoal paper (`#181818`) with light gray ink and logos. Blueprint uses saturated blue paper (`#0b3d91`), white ink and marks, and a thin drafting grid of 20-point squares with slightly stronger lines every 100 points. Its placement matches in the canvas, PNG, and SVG. Typography remains adjustable. With an item selected, **Selected text → Text size** changes only that shape’s label, container title, or connector label. **Use default text size** removes its override. Container title sizes do not propagate to children. With nothing selected, **Default text size** sets the document default for system labels; container and connector defaults stay at 14 and 12 points. Large labels expand their shapes, headers, or label backgrounds to stay readable, and connectors follow the resulting geometry. Select a shape, container, or connector to adjust its line width in its own inspector section; this affects that item alone. Use default removes its custom width. The width control is unavailable without a selection; existing diagrams retain their saved default width. The app name follows this project's folder name, and the app icon shows a stick-figure draftsman drawing a blueprint. That character is a provisional interpretation of Ubino.

The two brand themes take their palette from [SecondStack](https://secondstack.ai/) and [8FDE](https://8fde.ai/). **SecondStack** uses near-black paper (`#0b0d10`), charcoal system surfaces (`#14171b`), off-white text (`#f4f6f8`), and cyan (`#2fb5f4`) container titles, boundaries, and connectors. **8FDE** uses white paper and container backgrounds, `#0c6e85` object outlines and detail lines, dark navy text (`#111827`), and violet (`#5d4be8`) container titles, boundaries, and connectors. Body labels and vendor marks remain neutral; white marks on light paper retain a dark backing. Choose either in the Color theme menu, and use Sketch independently. The same palette is used in the canvas, PNG, and SVG. Agents select `theme.preset: "secondstack"` or `"8fde"`; custom fonts and per-item widths and text sizes are preserved.

Use the toolbar Zoom In and Zoom Out buttons or ⌘= and ⌘− to change the canvas scale by a factor of 1.25, from 20% to 300%. The toolbar shows the current percentage; zoom buttons stop at the limits. Button zoom stays centered on the viewport. Pinch or Command-scroll zooms around the pointer. Drag empty canvas or Option-drag to pan, and use ⌘0 to fit. Zoom changes only the view, leaving document geometry, exports, and undo history intact. Undo and redo support document edits. Deleting connected elements shows a confirmation sheet attached to the editor; the deletion and attached connectors can be restored together with Undo. Open or save JSON through File; saved documents autosave subsequent changes. External edits reload when the app is clean, or surface a conflict when local changes exist. JSON source editing validates before applying. Export SVG or PNG from the toolbar.

Enable **T1A watermark** in the Diagram appearance inspector to place the official logo in a reserved bottom-right footer on the canvas and PNG/SVG exports. The setting is saved per diagram and uses light ink in Blueprint, Dark, and SecondStack.

Older diagrams retain their appearance: `signature-sketch` opens as Standard with Sketch on; legacy Standard, Blueprint, and Dark open with Sketch off. Saving writes the color as `theme.preset` and the independent boolean as `theme.sketch`. New diagrams default to Standard with Sketch on.

## Agent and CLI workflow

```sh
dist/diagram init Examples/new.diagram.json --example
dist/diagram validate Examples/new.diagram.json --json
dist/diagram render Examples/new.diagram.json --format svg --output /tmp/diagram.svg
dist/diagram render Examples/new.diagram.json --format png --output /tmp/diagram.png --scale 2
dist/diagram schema
dist/diagram library list
```

For guarded edits, capture `dist/diagram revision <original>`, write and validate a candidate, then use `dist/diagram write <original> --from <candidate> --expect <revision>`. A stale revision fails without overwriting the source. Cooperating writers use a persistent sidecar `.lock` file; arbitrary tools that ignore the lock can still race, so agents should use the CLI's guarded write command.

The portable project skill is in [skills/xkcd-diagrams](skills/xkcd-diagrams/SKILL.md). See [Codex skill installation](#codex-skill) to install it for automatic diagram requests or explicit `$xkcd-diagrams` invocation. The workflow creates editable `.diagram.json` documents and PNG previews, supports SVG delivery, and uses guarded writes for existing files.

## Verification

```sh
./scripts/check.sh
```

The 61 regression checks run as a standalone Swift executable so they also work with command-line tools installations lacking a complete Swift Testing runtime. They verify document round trips, validation, containment, cross-boundary layout, conversion to free placement, deterministic SVG, PNG output, stale write rejection, vector parsing, deletion, bundled assets, a 200-node diagram, Blueprint colors and grid, Dark colors and logo contrast, queue geometry, File round trips and exports, locked 4:3 document sizing and text/logo clearance across layouts and styles, document format identity after renaming, optional watermark persistence and transparent exports, connector rerouting after arrangement changes, all attachment-side combinations, manual and legacy routes, curved database outlines, connections inside parent boundaries, departure bends before nearby systems, per-object line widths in saved files and exports, mixed top-level placement without shifting existing groups, full-width containers below the diagram, minimum container dimensions, custom grids and spans, cell swapping and growth, grid diagnostics and ownership cleanup, conversion from grids to free placement, drag previews matching saved connector routes without changing the document, visible Sketch/Standard differences at 50% zoom with a shared custom font across all symbol types, and bounded Sketch variation, seeded connector strokes, preserved connector bends and shape attachment tangents, database text/logo clearance across styles, font sizes, and thick outlines, legacy theme compatibility, strict sketch-toggle validation, all ten color/stroke combinations in saved files and image exports, individual text sizes, resets, validation, export parity, and large-label clearance, and source-inspired brand palettes with matching PNG/SVG colors and white-logo contrast, and portable T1A platform and AI Agent symbols across all styles.

## Current limits

This is an initial prototype, not the entire first release in the PRD. Routing uses simple orthogonal paths and does not yet avoid every obstacle; manual waypoints provide control. Automatic connector labels try to avoid system labels and node frames. Multiple selection, copy/paste, container duplication, reusable profile editing, autosave recovery after a process crash, and a native asset import UI remain to be implemented. Font size and family are configurable; weight controls are pending. Nested container layouts are supported, but full graph layout is outside the initial scope.

The library contains six generic presets (System, Database, Queue, AI Agent, Person, and Text), a Documents group with File, XLSX, PDF, and DOCX, and 24 branded presets in expandable T1A, Databricks, Azure, AWS, OpenAI, and Anthropic groups. T1A contains SecondStack, LakeSentry, 8FDE, Antares, and T1A logo boxes. AI Agent is an editable rounded box with a robot glyph and `type: agent`. The CLI library IDs for the new presets are `secondstack`, `lakesentry`, `8fde`, `antares`, `t1a`, and `ai-agent`. Databricks includes its main mark, Unity Catalog, Delta Lake, and a lakehouse preset; Azure includes Data Lake Storage, VM, Storage Account, SQL Database, and Azure OpenAI; AWS includes S3, EC2, Lambda, and RDS. OpenAI and Anthropic API presets reuse their company identities. Marks support black and white presentation, with light ink automatically used in Blueprint, Dark, and SecondStack. Geometry and provenance are documented in [docs/ASSETS.md](docs/ASSETS.md).

## Source organization

`DiagramCore` contains the model, semantic validation, layout, glyph outlines, seeded strokes, exports, library, and guarded file writes. `DiagramApp` contains the SwiftUI workspace, AppKit canvas, and editor state. `DiagramCLI` provides the headless interface. `Tests/DiagramChecks` contains regression checks. The schema and frozen library are bundled resources under `Sources/DiagramCore/Resources`.
