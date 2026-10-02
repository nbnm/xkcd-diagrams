# macOS Enterprise Diagram App PRD Draft

Version 0.3 · October 2, 2026 · Product name: XKCD Diagrams · Folder: xkcd-diagrams

Build a macOS app for creating clear enterprise IT diagrams with a recognizable personal sketch style, a conventional standard theme, a blue-and-white Blueprint theme, and a charcoal Dark theme. People compose diagrams visually; agents create and update the same documents through a documented format and project skill. Containers, reusable system symbols, and predictable layout are central to the product.

**Latest confirmed changes:** name the app after its folder; add an icon of Ubino drawing blueprints (character appearance still needs a reference); add Blueprint with blue paper and white content; group vendor logos in expandable menus with Databricks and Azure product symbols; simplify generic systems and make previews match their actual geometry. Container must be prominent in the toolbar and library. Arrangement controls belong only to containers; changing arrangement must update attached connectors. The implementation resets affected endpoint sides and manual bends on a change to a horizontal or vertical stack, preserving unrelated connectors. The invisible root remains a container in the file model. Its Canvas placement control supports free placement, a horizontal row, a vertical column, or custom rows and columns. Free placement allows mixed top-level composition, including a wide monitoring container underneath the main diagram; containers continue to arrange their own contents independently.

**Product recommendation:** use a small, versioned JSON diagram format as the source of truth. The app and agent tools share its validation, layout, and rendering behavior. Treat Mermaid as a potential interchange option after the core workflow works.

This PRD defines the proposed first release, its document model, visual behavior, and acceptance criteria. Requirements stated by the user are distinguished from proposals and unresolved choices. It does not select a final implementation stack or provide a delivery estimate.

## User requirements and proposed defaults

| Area | User requirement | Proposed first release |
| --- | --- | --- |
| Platform | New macOS app | Local document app with macOS menus, shortcuts, and file handling |
| Purpose | Minimal enterprise IT system diagrams, tuned to personal definitions | Architecture, integration, deployment, and data flow diagrams |
| Creation | Drag and drop and agent skill; agents use files and a CLI | Visual editor plus file access, CLI, schema, and project skill |
| Structure | Boxes and containers that define contents and arrangement | Nested containers with horizontal, vertical, or free placement and optional allowed types |
| Visual identity | Sketch toggle independent of three color themes | Standard, Blueprint, and Dark colors, each with clean or signature sketch strokes |
| Styling | Primarily black or gray; adjustable fonts and line widths | Monochrome defaults, restrained controls, white or transparent export background |
| Assets | Vendor groups containing Databricks product logos, OpenAI, Anthropic, Azure, and AWS; black and white representations | Searchable expandable groups with monochrome variants, simple generic shapes, and custom SVG or PNG import |
| Representation | One teachable JSON-like format; Mermaid is a possibility | Strict JSON, published JSON Schema, stable IDs, and explicit layout intent |
| Export | Images and structured source | PNG, SVG, and the original JSON document |

**Confirmed first release decisions:** personal use with T1A conventions built in; containers automatically arrange their contents while the user positions containers and adjusts connectors; agents read and write diagram files through a CLI and project skill. The starter brands are Databricks, OpenAI, Anthropic, Azure, and AWS, with black and white representations and the product subset listed below. The implementation targets macOS 14 or later. Reference diagrams and Ubino's appearance remain to be confirmed.

## Problem and product goals

The product should remove repeated work: finding the same logos, drawing the same system boundaries, correcting spacing, and making every diagram look consistent. The user needs diagrams that communicate enterprise relationships while retaining an intentional, informal drawing style.

The visual editor and agent workflow must preserve each other's work. An agent should describe systems, relationships, and arrangement without inventing hundreds of drawing coordinates. A person should be able to refine that result without losing the structured representation.

The first release must achieve these outcomes:

1. Create a useful architecture diagram from a small familiar library in minutes.
2. Express nested system boundaries and repeatable arrangement rules directly in the document.
3. Generate a valid diagram with an agent, refine it manually, and export it without conversion loss.
4. Switch between Standard, Blueprint, and Dark colors and independently toggle Sketch without rebuilding the diagram.
5. Make the signature style consistent across files, authors, and exports.

## Users and primary workflows

The first release is for the user's own architecture and engineering work, with T1A conventions built in. A coding or documentation agent is a second author of the same document. Sharing the app across T1A can follow the personal pilot; multiuser collaboration is outside the initial workflow.

### Create a diagram manually

Open a blank document or template. Drag a system symbol from the library, edit its label, and add a container. Place symbols inside it, choose horizontal or vertical arrangement, and connect systems using labeled arrows. Adjust typography or stroke width, then export a PNG or SVG and save the editable source.

### Create a diagram with an agent

The agent reads the project skill and available presets, writes a diagram file, validates it, and renders a preview. The user opens the file in the app, adjusts container placement or connector paths, and saves it. The agent later adds a system by stable ID while preserving unrelated edits.

### Reuse a visual convention

Save a system or container preset with its label pattern, symbol, appearance, and content rules. Use the preset in subsequent diagrams. Share a local profile containing definitions and templates with a project so an agent uses the same vocabulary and visual rules.

### Change presentation

Switch an existing diagram from Signature Sketch to Standard. Systems, containment, relationships, child order, and manual placement intent remain intact. Text is remeasured where fonts differ; resulting size changes must not hide content or invalidate connectors.

## First release scope

| Required for first release | Follow after the core workflow | Outside the initial product |
| --- | --- | --- |
| macOS visual editor and local files | Live MCP interface | Real time collaboration |
| Nodes, nested containers, connectors, text | Whole diagram automatic graph layout | Cloud account or required hosted service |
| Horizontal, vertical, free, and custom grid placement | Swimlane layouts | General illustration or photo editing |
| Three color themes with an independent Sketch toggle | Mermaid import and export | Built in chat or model hosting |
| Local logo and symbol library | PDF export | Full UML or BPMN conformance |
| Reusable presets and content rules | Collapsible containers | Windows, Linux, web, or iPad editor |
| PNG, SVG, and JSON export | Shared library management UI | Animated diagrams |
| CLI, schema, and project skill | Broader vendor asset packs | Automatic discovery of enterprise systems |
| Undo, autosave, and external edit handling | Additional diagram families | Arbitrary user scripts in documents |

The confirmed first release uses files and a CLI rather than a live app integration. Container arrangement is required; complete graph layout remains a later capability.

## Document model and source format

### Canonical representation

Use strict JSON for saved files and agent exchange. The file extension is to be chosen; `.diagram.json` is a working proposal. Publish a JSON Schema and a short semantic guide. Any convenience syntax considered later must compile into the same model.

The document represents meaning and layout intent rather than only drawing primitives. It contains:

- A schema version, stable document ID, title, and optional description.
- Nodes with stable IDs, semantic types, labels, shapes, optional asset references, and style overrides.
- Containers with labels, ordered child references, layout settings, and optional allowed child types.
- Connectors with stable IDs, endpoint references, direction, labels, line patterns, and routing settings.
- A root canvas containing top level elements.
- Theme settings and versioned profile or preset snapshots needed to reproduce the diagram.
- Asset data needed to render without fetching remote resources.
- Explicit manual placement, sizing, and connector waypoints where the author chooses them.

A node or container has exactly one parent, derived from container child lists. Child lists define meaningful order. Containment is acyclic; connectors may form cycles because enterprise systems can have reciprocal relationships. Connections between different containers are supported.

Keep temporary selection, zoom, and hover state separate from the semantic document. Do not store disposable computed coordinates for automatically arranged children as a second authoritative layout. Preserve user constraints and recompute derived geometry deterministically.

### Editing and compatibility rules

Opening and saving an unchanged file must preserve its normalized document content and IDs. Use stable serialization so routine saves do not create broad Git diffs. Arrays that encode child order retain their order.

Dragging an item to another container updates containment. Dragging within a stack changes child order; switching a stack to free placement materializes the current positions as explicit coordinates. Every structural action is reversible through undo.

Apply supported migrations explicitly and retain a recoverable original. An unsupported newer schema opens with a clear compatibility message and must not be silently rewritten. Defined extension metadata is preserved; unknown core fields produce validation feedback.

### Illustrative document

The following is a proposal demonstrating the desired authoring experience, not a finalized schema. Omitted appearance and sizing fields use documented defaults. Generic built in symbols require no external asset files.

```json
{
  "schemaVersion": 1,
  "id": "order-platform",
  "title": "Order platform",
  "theme": {
    "preset": "standard",
    "sketch": true,
    "version": 1,
    "seed": 42,
    "strokeWidth": 1.6
  },
  "root": "canvas",
  "nodes": {
    "gateway": {
      "type": "api",
      "label": "API Gateway",
      "shape": "rectangle"
    },
    "orders": {
      "type": "service",
      "label": "Order Service",
      "shape": "rectangle"
    },
    "store": {
      "type": "database",
      "label": "Order Database",
      "shape": "cylinder"
    }
  },
  "containers": {
    "canvas": {
      "layout": { "mode": "horizontal", "gap": 56 },
      "children": ["gateway", "backend"]
    },
    "backend": {
      "label": "Backend",
      "layout": { "mode": "vertical", "gap": 24, "padding": 24 },
      "allowedChildTypes": ["service", "database"],
      "children": ["orders", "store"]
    }
  },
  "connectors": {
    "request": {
      "from": { "element": "gateway", "side": "right" },
      "to": { "element": "orders", "side": "left" },
      "label": "HTTPS",
      "direction": "forward",
      "routing": "orthogonal"
    },
    "persistence": {
      "from": { "element": "orders", "side": "bottom" },
      "to": { "element": "store", "side": "top" },
      "label": "SQL",
      "direction": "forward",
      "routing": "orthogonal"
    }
  },
  "assets": {}
}
```

This describes a horizontal top level arrangement containing a vertically stacked backend. Connecting the gateway to a backend child must preserve the backend's vertical arrangement.

## Container and layout requirements

Containers are first class structural elements. Their boundaries communicate systems, deployment environments, teams, or logical groupings. An unrestricted container accepts any supported element. A preset may restrict child types, including whether nested containers are allowed; restrictions use type identifiers rather than label matching.

| Behavior | Required first release rule |
| --- | --- |
| Horizontal stack | Arrange children left to right in stored order with configurable gap and alignment |
| Vertical stack | Arrange children top to bottom in stored order with configurable gap and alignment |
| Custom grid | Configure 1–32 rows and columns, assign cells and row/column spans, and stretch containers across their cells; keep each container’s internal arrangement independent |
| Free placement | Persist child positions relative to the parent's content area |
| Nesting | Support horizontal and vertical containers inside each other; target at least five nesting levels |
| Sizing | Fit contents by default with padding and a dedicated header area |
| Explicit size | Honor minimum or requested size; expand or report insufficient space instead of clipping silently |
| Type rules | Highlight an invalid drop before commit and explain the allowed types |
| Reordering | Show an insertion position while dragging; update order when dropped |
| Moving a container | Move descendants together while preserving relative layout |
| External connections | Preserve arrangement rules when children connect outside the container |
| Label growth | Recalculate affected sizes and routes when text changes |
| Relayout | Provide an explicit command; avoid global rearrangement after unrelated edits |

First release automatic layout concerns ordered containers. Free root placement lets the user arrange entire groups in mixed rows and columns. Switching the root to free placement preserves the current element frames and connector paths. Provide Add Container Below Diagram to create a horizontal container underneath the existing top-level elements, aligned to their left edge and spanning their combined width; also allow an existing top-level container to be placed below its siblings. In a free or stacked canvas, these commands switch the canvas to free placement without rearranging the other groups. In a custom grid, keep grid placement and put the container in a new row spanning every column. Container width and height are optional minimum dimensions; the boundary expands to fit contents. Offer Fit to contents to remove explicit sizing. Complete graph layout is a separate capability and must not be implied by the term automatic layout.

## Nodes connectors and labels

Provide a small initial shape set: rectangle, rounded rectangle, cylinder, message queue, a Documents group with File, XLSX, PDF, and DOCX folded sheets, person or actor symbol, and text annotation. Semantic types such as service, application, API, database, queue, and external system are independent of their shape and logo.

Connectors support plain lines, forward arrows, arrows at both ends, and solid or dashed patterns. All routes must meet their attachment edges at 90 degrees and use right-angle bends. Explicit endpoint sides, automatic sides, and manual waypoints must preserve this rule; waypoint coordinates stay stored as authored while the renderer adds the necessary bends. The legacy `straight` field remains readable for compatibility but renders with right-angle geometry. Arrowheads and labels must remain legible in all six color/stroke combinations.

Endpoints attach to nodes or container boundaries, with automatic or explicitly chosen sides. Moving an endpoint element updates the attachment. Routing should avoid unrelated nodes and labels, permit intentional boundary crossings, and expose manual waypoints when automatic routing is unsatisfactory. Preserve those waypoints in subsequent edits; warn if they create an unresolved collision.

When an element with attached connectors is deleted, show which connectors will also be removed and perform the change as one undoable action. Duplicating a container regenerates descendant IDs and remaps internal connectors; external connections are not copied by default.

Labels support multiline text, automatic wrapping, and an optional secondary description. Font family, size, and weight are configurable. Changing Text size with a shape, container, or connector selected affects only its label or title. Store a per-element `fontSize` override (10–36 points); container overrides do not propagate to children. Provide Use default text size to clear the override. With no selection, Default text size controls the document default for system labels. Preserve established title and connector defaults of 14 and 12 points in older files. Layout and image exports must use the same resolved sizes, expanding shapes, container headers, and connector label backgrounds as needed without clipping text. Default text is black or dark gray; relationship meaning must remain understandable without color.

## Signature visual style

### Independent color and stroke controls

Provide three color themes: Standard, Blueprint, and Dark. A separate Sketch toggle controls pen variation and the default handwriting font for all three themes. App appearance remains a separate local Light/Dark preference. Save color in `theme.preset` and the boolean in `theme.sketch`. New diagrams use Standard with Sketch on. Preserve existing appearance when reading older files: `signature-sketch` becomes Standard with Sketch on; older Standard, Blueprint, and Dark become Sketch off. Preserve custom fonts, line widths, seeds, element ordering, positions, and connector constraints when changing either setting.

### Signature Sketch

The intended character is a deliberate technical sketch: white space, restrained imperfections, simple boundaries, and readable handwritten typography. The xkcd reference expresses an aesthetic direction; the product's own preset needs concrete visual rules.

- Use black and gray strokes on Standard paper, white ink on Blueprint, and light gray ink on Dark; transparent export is optional.
- Keep geometry and spacing orderly; apply slight variation to strokes rather than randomizing the underlying layout.
- Limit wobble, overshoot, and repeated strokes so small symbols and arrowheads remain recognizable.
- Prefer outline containers and generous padding. Hatching is optional and off by default.
- Use a readable handwriting font as a proposed default, with a conventional font available.
- Avoid default gradients, shadows, ornamental effects, and arbitrary accent colors.
- Keep logos recognizable. Use monochrome assets where available, and retain their geometry rather than distorting the mark.

Sketch on and off must remain visibly different in each color theme at typical canvas zoom even when the same custom font is selected. Apply restrained pen variation to straight and curved symbol outlines, container boundaries, document detail lines, and connectors. Preserve shape vertices and side-center attachment tangents. Connector strokes must retain straight sections at bends and endpoints, preserving 90-degree bends and perpendicular attachments. Keep routing and manual waypoints unchanged, and logo geometry undistorted. A custom font applies to every combination; provide Style default to follow the Sketch and color settings.

Store a document seed and derive stable variation from each element ID and its geometry. Reopening or exporting an unchanged diagram must not produce a new sketch. Changing one node must not rerandomize unrelated elements. Manual hit testing uses clean geometry so imperfect strokes do not make selection difficult.

### Standard colors and clean strokes

Standard uses white paper and black or gray ink. With Sketch off, use clean outlines, precise corners and curves, and a conventional font. With Sketch on, retain these colors and apply the signature strokes and handwriting font. All themes share containment, ordering, endpoint attachment, and explicit layout constraints. Theme differences may change text dimensions, but should preserve authors' arrangement choices.

### Personal conventions

A profile stores theme defaults, vocabulary, node and container presets, asset selections, and starter templates. Ship a T1A profile in the first release; its detailed definitions remain to be specified. Definitions can include an environment that accepts deployment containers or a service group that arranges services vertically. Use T1A as the company name and 8FDE as the team name whenever those entities appear in presets or templates.

Preset use creates an editable snapshot in the document. Later profile changes affect new instances; updating existing instances requires an explicit command. This prevents a library update from silently changing old diagrams. Explicit local overrides take precedence over preset defaults.

### Blueprint

Use saturated blue paper (`#0b3d91`) with white boundaries, connectors, labels, and marks. Add a very thin drafting grid with 20-point squares and slightly stronger lines every 100 points, keeping the grid quieter than diagram strokes. Align it to document coordinates so it remains stable while panning and matches PNG and SVG exports. With Sketch off, a monospaced font is the default; Sketch on uses readable handwriting; font family and size remain configurable. Line width changes in the editor apply to the selected node, container boundary, or connector only, including a connector’s arrowheads. Each element can store its own width; omitted widths use the document default. Container stroke widths do not propagate to children. With no selection, hide the width control; provide a reset to the default for an explicit override. Vendor marks render directly in white on blue. Avoid adding decoration that competes with the architecture.

The signature style is accepted through a reference set: one simple integration, one nested deployment, and one denser data flow. Review all six color/stroke combinations at normal presentation size and after image export. The user must judge that the sketch treatment feels recognizable and intentional; a numerical roughness setting alone does not establish success.

### Dark theme

Use charcoal paper (`#181818`) with light gray lines, labels, and logos. Keep the same diagram model, container layouts, connectors, and export behavior. Use Helvetica with Sketch off and readable handwriting with Sketch on, unless the document specifies a font. App appearance is an independent Light/Dark preference. Every diagram style must work with either interface appearance. Preserve logo variant preferences when switching to other themes.

## Asset library and presets

The library supports search, categories, favorites, generic IT symbols, and frequently used logos. A library item has a stable ID, name, aliases, asset source, version, supported variants, and any necessary attribution.

The user has confirmed these starter families:

| Family | First release coverage |
| --- | --- |
| Databricks | Main company mark, Unity Catalog, Delta Lake, and a lakehouse preset |
| OpenAI | Company identity for nodes representing OpenAI services |
| Anthropic | Company identity for nodes representing Anthropic services |
| Azure | Platform identity, Data Lake Storage, VM, Storage Account, SQL Database, and Azure OpenAI |
| AWS | Platform identity, S3, EC2, Lambda, and RDS |
| Generic IT | System, database, queue, person, and text, plus a Documents group with File, XLSX, PDF, and DOCX; library previews match canvas shapes |

Every starter family must support black and white representations as a product requirement. Distinguish a black mark on a transparent background from a white mark on a transparent background; use black by default on white diagrams. Make the variant discoverable in the inspector, store the selection in the document, and preview white marks against a contrasting background. A variant is an asset choice, independent of sketch or standard theme.

Import SVG and PNG through the app. Prefer supplied monochrome assets; use carefully prepared variants where appropriate rather than indiscriminate threshold conversion. Preserve internal detail and recognizable geometry. Original color variants may also be available, but monochrome is the default. Do not require online downloads while authoring or exporting.

Asset acquisition should begin with [Databricks' press kit](https://www.databricks.com/company/newsroom/press-kit), [OpenAI's brand resources](https://openai.com/brand/), and the official [Azure architecture icon collection](https://learn.microsoft.com/en-us/azure/architecture/icons/). These are source references, not a completed asset inventory; Anthropic and AWS sources and each product's available variants still need to be checked during library assembly.

Saved documents capture assets needed for portable rendering, including custom assets. Small vector assets can be embedded in the JSON; a package alternative for larger libraries is an implementation decision. A recipient with the same app and CLI version must not need the author's private library to render a saved file.

Missing or invalid assets produce a named placeholder and diagnostic. An explicitly requested final export fails until repaired, unless the user or CLI explicitly allows placeholders. Asset imports must ignore active content and remote references.

## macOS editor requirements

Use a focused workspace: asset and preset library on the left, diagram canvas in the center, and a contextual inspector on the right. The inspector exposes only properties relevant to the selection. Keep Color theme, the separate Sketch toggle, save, and export actions readily accessible. Each appearance change supports its own undo and redo. Provide a separate App appearance control with Light and Dark options at the bottom of the library. Remember this preference across launches and document changes; changing it must not affect diagram JSON, exports, dirty state, or undo history.

Required interactions include drag and drop, selection and multiselection, pan and zoom, fit to content, snapping guides, resize, duplicate, delete, keyboard nudging, and connector creation. Provide standard macOS undo and redo, copy and paste, Open, Save, Save As, and Export. Support trackpad navigation and keyboard access to common authoring tasks.

Provide Zoom In and Zoom Out in the toolbar and Diagram menu, with ⌘= and ⌘− shortcuts and a live percentage readout. Step by a factor of 1.25 within 20%–300%, keeping the viewport center anchored; disable the corresponding button at each limit. Preserve pinch and Command-scroll zoom around the pointer and Fit to Content (⌘0). Zoom is editor state and must not change the document, exported geometry, dirty state, or undo history.

Show Connector immediately beside Container in the toolbox and as a labeled toolbar action. Selecting it enters connection mode; dragging from one endpoint to another or clicking the two endpoints creates a connector. The tool itself can be dragged onto a source to begin, or onto empty canvas to activate connection mode. Show a live right-angle preview and highlight valid destinations. Reject self-connections, the invisible root, and connector lines as endpoints. Releasing on empty canvas creates no connector; Escape cancels. Connector gestures must preserve object positions and create one undoable edit.

For custom canvas placement, show Rows and Columns controls and per-selected-item Row, Column, Row span, and Column span controls. Use one-based indices. Provide faint editor-only cell guides and drag-to-cell placement; swapping single-cell items preserves their assignments. Allow adding rows to fit new items and spans, reject overlapping or out-of-bounds source assignments, and preserve the last valid document after a failed edit. Save layout mode, dimensions, and child-ID cell assignments in JSON.

An outline shows container hierarchy and supports selecting deeply nested elements. A source view exposes the JSON and diagnostics. Applying valid source changes is an undoable action; invalid source remains editable without replacing the last valid diagram.

Autosave to local files and recover interrupted work. Detect external changes: reload automatically when the editor is clean; when it contains unsaved edits, offer a comparison and an explicit way to keep either version or save a copy. Never overwrite agent changes silently.

## Agent skill and CLI requirements

The first release ships a portable project skill, a published schema, representative examples, and a CLI. The CLI works without an open app window or interaction. Its command names below are proposals.

| Command | Expected behavior |
| --- | --- |
| `diagram schema` | Return the supported schema and version |
| `diagram library list` | List preset and asset IDs with metadata |
| `diagram validate file.diagram.json --json` | Return structural and semantic diagnostics with element IDs and field paths |
| `diagram render file.diagram.json --format svg` | Render using the same layout, assets, and theme behavior as the app |
| `diagram inspect file.diagram.json --json` | Summarize systems, containers, relationships, and layout intent |

Validation covers uniqueness, endpoint existence, single parent ownership, containment cycles, permitted child types, numeric bounds, unsupported settings, and assets. Errors identify the element and JSON path and suggest a specific repair. Rendering must not silently omit invalid elements.

The skill teaches an agent to inspect existing files, use stable IDs, select documented presets, describe layout through containers, validate, render a preview, and make focused updates. It includes examples for a simple integration, nested deployment, and horizontal and vertical arrangements.

Agents edit files without UI automation. File updates must be atomic and guard against a changed source revision so concurrent edits do not overwrite each other. The implementation may provide a guarded write command or a documented helper; this behavior is required even if the command surface changes.

Agents and people should render a diagram locally without requiring a model subscription. A live MCP server can later expose the same operations and, if requested, coordinate with the open document rather than introducing another document model.

## Export requirements

PNG export supports resolution or scale selection, white or transparent background, content bounds, and configurable margins. SVG export preserves vector shapes and embeds assets. Font handling must be explicit: embed when permitted or convert glyphs to paths for a portable output; selectable text can be an alternative with declared font requirements.

Save and export the complete JSON representation with its assets, theme settings, presets, and manual constraints. Image export is a view of the document, while JSON retains editability.

App and CLI exports use the same rendering pipeline and crop rules. Export a whole document in the first release; exporting a selection and PDF can follow later.

Offer an optional T1A logo watermark in the Appearance inspector. Save its enabled state with each document; default it off. Render the official monochrome mark at 40% opacity in a reserved bottom-right footer on the canvas and PNG/SVG exports, with light ink in Blueprint and Dark. Keep it clear of systems, containers, labels, and connectors.

## Format and implementation decisions

| Option | Assessment | Proposed decision |
| --- | --- | --- |
| Custom semantic JSON | Can directly encode content rules, ordered containers, presets, assets, and manual overrides | Canonical document model; keep it small and publish the schema |
| Mermaid | Supports subgraphs and connections, but its documented flowchart behavior can ignore a subgraph's direction when children link outside | Evaluate a limited converter later, with explicit reporting of lost information |
| Excalidraw document | Its published JSON stores canvas elements, app state, and image files; useful reference for drawing representation | Evaluate rendering and interaction ideas; do not assume it supplies the required semantic container contract |

The Mermaid limitation is documented in [Mermaid flowcharts](https://mermaid.js.org/syntax/flowchart.html#direction-in-subgraphs). The Excalidraw representation is described in its [JSON documentation](https://docs.excalidraw.com/docs/codebase/json-schema/). The choice of custom JSON is a product recommendation based on this app's requirements, not a claim that other tools cannot be extended.

Prefer a native macOS document shell and a reusable engine for validation, layout, and rendering. Compare a native vector implementation with an embedded web renderer in a short technical spike. Rough.js is a candidate for sketch rendering because it supports SVG and Canvas primitives and seeded variation; selecting it remains an engineering decision. See the [Rough.js overview](https://roughjs.com/) and [seed option](https://github.com/rough-stuff/rough/wiki#seed).

Choose the stack based on evidence: macOS interaction quality, shared headless rendering, typography and asset portability, deterministic output, maintenance cost, and licensing fit. Do not decide solely from the appearance of a demo. Pin renderer and preset versions to make reproducibility meaningful.

## Quality targets and acceptance criteria

The numerical targets below are proposed goals, to be measured on a recorded Apple silicon Mac configuration during the prototype. They are not existing performance claims.

| Area | Acceptance criterion |
| --- | --- |
| Basic authoring | A first time user creates a 10 node diagram with two containers and labeled connectors and exports it within 10 minutes after a short introduction |
| Agent handoff | An agent creates a valid file; the user moves a container and edits labels; an agent then adds a node while preserving the earlier edits |
| Container behavior | Nested horizontal and vertical stacks retain their order and alignment when connected to outside elements |
| Type rules | A disallowed drop is blocked with a useful message; the equivalent JSON produces a matching validation error |
| Round trip | An unchanged document survives app open and save with no normalized semantic or layout changes and no regenerated IDs |
| Theme switching | All themes show the same systems, containment, and relationships without clipped labels or disconnected endpoints |
| Signature style | The user accepts the three representative diagrams as consistent with the intended personal style |
| Determinism | Repeated renders with identical document, assets, fonts, and engine versions produce identical normalized SVG; PNG output is visually identical |
| Local editing stability | Editing one node preserves unaffected sketch strokes, explicit positions, and manually routed connectors |
| Portable assets | A saved diagram renders offline on another installation without access to the original user's library |
| Starter logos | Databricks, OpenAI, Anthropic, Azure, and AWS are discoverable; chosen starter assets have legible black and white variants that survive save, reopen, and both image exports |
| App and CLI parity | Their SVG geometry, label placement, and visual styles match under identical export settings |
| Conflicts and recovery | External edits, interrupted writes, and invalid source do not cause silent data loss; undo restores structural edits |
| Validation | Invalid endpoint, cyclic containment, missing asset, and unsupported version fixtures produce useful diagnostics |
| Responsiveness | At 200 nodes, 300 connectors, and five container levels, common editing feedback appears within 100 ms at the 95th percentile |
| File and export speed | The same fixture opens within 2 seconds and exports a typical SVG or PNG within 3 seconds, excluding first process startup |
| Accessibility | Common tasks are available from the keyboard; inspectors and hierarchy have accessible labels; meaning is not dependent on color |

The offline workflow includes creating, opening, validating, editing, and exporting diagrams. No account is required for these operations. Documents are never uploaded by the app or CLI as part of the core workflow.

## Delivery sequence

1. **Product and style definition.** Use the confirmed personal audience, file and CLI workflow, and container arrangement scope. Choose the starter product icons and agree on the reference diagrams, theme rules, and T1A vocabulary.
2. **Format and renderer spike.** Render the same nested example in all six color/stroke combinations from JSON. Demonstrate seeded strokes, a connection crossing a container boundary, portable text and logos, and headless export. Select the implementation stack from these results.
3. **Complete editing workflow.** Build local file handling, manual composition, containers, connectors, inspection, undo, source validation, and image export.
4. **Agent workflow.** Ship CLI commands, schema, example documents, and the project skill. Verify a complete agent to app to agent handoff and external edit handling.
5. **Personal pilot.** Produce real architecture diagrams, measure the proposed targets, and refine the style and library. Broader distribution, MCP, and full graph layout follow only if they serve the pilot's needs.

These are dependency milestones, not calendar commitments. Estimate delivery after the renderer spike and scope decisions.

## Risks and unresolved decisions

| Risk or decision | Product response |
| --- | --- |
| Sketch effects overpower technical readability | Bound variation and approve real diagrams at normal viewing size |
| Manual and automatic layout fight each other | Make layout mode explicit, preserve manual constraints, and keep relayout an intentional action |
| Routing across nested boundaries becomes complex | Verify it early with representative diagrams and provide manual waypoints |
| Custom format grows into a drawing language | Limit the first schema to systems, containers, relationships, assets, and layout intent |
| Fonts or assets render differently elsewhere | Capture document dependencies and test portable exports |
| Agent updates erase a person's refinement | Stable IDs, focused edits, guarded writes, and visible conflict handling |
| Starter logo library becomes a large catalog project | Cover the five confirmed vendor families, beginning with a short product subset and generic symbols |
| Platform support and distribution are undefined | Select minimum macOS version and hardware support for the user's machines; public distribution is outside the initial scope |

Remaining product details:

1. Which Databricks products and Azure or AWS services are used most often and should come first in the library?
2. Which existing diagrams or visual references should define the exact stroke treatment and default handwriting font?
3. Which T1A node types, container rules, and starter templates should be included beyond generic IT definitions?
4. What minimum macOS version and hardware must be supported on the user's machines?

The confirmed scope is sufficient to start a format and renderer prototype. Use a provisional readable handwriting font and generic symbols until the reference style and exact product icon subset are selected.
