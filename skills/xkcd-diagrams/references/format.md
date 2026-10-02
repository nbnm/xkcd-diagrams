# Diagram format

Schema 1 uses strict JSON. Query `diagram schema` for property types and bounds. IDs are keys of `nodes`, `containers`, and `connectors`; they are unique across those collections. Asset IDs occupy a separate namespace.

```json
{
  "schemaVersion": 1,
  "id": "integration",
  "title": "System integration",
  "theme": { "preset": "signature-sketch", "seed": 42 },
  "root": "canvas",
  "nodes": {
    "api": { "type": "api", "label": "API Gateway" },
    "worker": { "type": "service", "label": "Worker" },
    "db": { "type": "database", "label": "Database", "shape": "cylinder" }
  },
  "containers": {
    "canvas": { "layout": { "mode": "horizontal", "gap": 80 }, "children": ["api", "backend"] },
    "backend": { "label": "Backend", "layout": { "mode": "vertical" }, "children": ["worker", "db"], "allowedChildTypes": ["service", "database"] }
  },
  "connectors": {
    "request": { "from": { "element": "api", "side": "right" }, "to": { "element": "worker", "side": "left" }, "label": "HTTPS" },
    "storage": { "from": { "element": "worker", "side": "bottom" }, "to": { "element": "db", "side": "top" }, "label": "SQL" }
  },
  "assets": {}
}
```

Defaults: sketch theme, theme version 1, seed 42, stroke width 1.6, font size 16; container gap and padding 28; node rectangle and width 170 (document shapes default to a minimum 120 × 144); connector forward arrow, orthogonal routing, solid line, automatic endpoint sides. Sizes expand to fit text. Theme presets are `signature-sketch`, `standard`, `blueprint`, and `dark`. Default fonts are Chalkboard SE for Sketch, Helvetica for Standard and Dark, and Menlo for Blueprint unless `fontFamily` is provided. A supplied `fontFamily` applies to all styles; omit it to use style defaults. Sketch uses restrained, seeded pen variation on straight and curved shape outlines, boundaries, document details, and connectors. Saved routes and waypoints remain orthogonal; straight sections at bends and endpoints preserve 90-degree angles and perpendicular attachments. Logo geometry remains undistorted. Standard uses precise outlines. Switching styles preserves custom font and line-width choices. Blueprint uses sRGB blue `#0b3d91` paper with white ink, including logos, and a thin 20-point drafting grid with 100-point major lines. The grid also appears in PNG and SVG exports. Dark uses charcoal `#181818` paper and light gray ink, including logos, with the same colors in PNG and SVG. App appearance is a separate local Light/Dark preference and does not affect diagram JSON or image exports.

For a custom grid, use `layout.mode: grid` with `rows` and `columns` (1–32 each). Optional `layout.cells` maps direct child IDs to one-based `row`, `column`, `rowSpan`, and `columnSpan`; spans default to 1. Unassigned children fill vacant cells in child-list order. Assignments cannot overlap or extend beyond the configured grid. Tracks grow to fit content; containers stretch to fill their spanned cells while nodes retain their own size. A two-row grid with a wide monitoring band below three top-level systems uses:

```json
"canvas": {
  "layout": {
    "mode": "grid", "rows": 2, "columns": 3, "gap": 40,
    "cells": { "monitoring": { "row": 2, "column": 1, "columnSpan": 3 } }
  },
  "children": ["source", "platform", "application", "monitoring"]
}
```

Define those children as usual and give `monitoring` its own horizontal layout. Adding an item or expanding its span in the editor adds rows if needed; agent-authored files must declare sufficient rows explicitly. Grid dimensions and cell edits reset affected connector endpoints to `auto` and clear manual waypoints. Converting a grid to free placement materializes child positions and stretched container dimensions. Faint editor cell guides are excluded from exports.

For `free` placement, set an element's `position: { "x": 120, "y": 80 }` relative to its parent's content area. The layout engine derives absolute geometry. Stack containers use child order, rather than child positions. Moving a container preserves its descendants' relative arrangement. To mix top-level rows and columns, use `free` on the root, with explicit positions for each top-level item; each nested container retains its own independent horizontal or vertical stack.

Containers accept optional `width` and `height` (20–100000 points). These are minimum dimensions; children, padding, and the header may require a larger frame. Omit both for automatic sizing. A wide monitoring band underneath the main diagram uses a horizontal container with a position below the main groups and a width spanning them. For example, alongside existing top-level groups, add:

```json
"monitoring": {
  "label": "Monitoring",
  "layout": { "mode": "horizontal", "gap": 28, "padding": 28 },
  "position": { "x": 0, "y": 500 },
  "width": 1200,
  "children": ["metrics", "logs"]
}
```

Define those nodes, add `monitoring` to the root's `children`, and adjust its coordinates to clear the actual main diagram. The app's Add Container Below Diagram and Place below diagram commands derive this position and width from sibling frames, preserving their visible positions. If an existing root uses a stack, switching to free placement requires materializing its current child positions; changing only `mode` would use fallback coordinates.

Set the top-level `watermark: true` to include the official T1A logo in a reserved bottom-right footer in the canvas, PNG, and SVG. It defaults to `false` when omitted. The watermark uses monochrome ink at 40% opacity, automatically light in Blueprint and Dark, and survives save/reopen and theme changes. It does not change element positions or connector paths.

Node shapes: `rectangle`, `roundedRectangle`, `cylinder`, `queue`, `file`, `xlsx`, `pdf`, `docx`, `actor`, `text`. Queue draws three offset message outlines. The Documents group contains folded-sheet shapes `file`, `xlsx`, `pdf`, and `docx`. Use `type: file` for all four, choose the matching shape, and set a label such as `customers.xlsx`. XLSX has an X and spreadsheet grid; PDF has a PDF mark and document lines; DOCX has a W and document lines. These marks are independent of the editable label. Explicit width and height set the minimum size; sheets expand to fit labels below the format mark. Connector direction: `none`, `forward`, `both`; use `routing: orthogonal`. The legacy `straight` value remains readable but renders with right-angle geometry too. Endpoints: `auto`, `left`, `right`, `top`, `bottom`. All connectors enter and leave their attachment edges perpendicularly, including manual routes. A connection to an enclosing parent boundary approaches it from inside. Set `dashed: true` for dashed connections. A connector's `waypoints` are absolute document coordinates, as an ordered array of `{ "x": number, "y": number }` points between the attached endpoints. The renderer visits them with added right-angle bends without rewriting their stored coordinates.

Nodes, non-root containers, and connectors may each have `strokeWidth: 0.5` through `8`. This overrides `theme.strokeWidth` for that element alone. A container override does not propagate to children or attached connectors; a connector override includes its arrowheads. Omit the element field to restore the document default; do not use `null`. When asked to change a selected object’s line width, edit that object’s `strokeWidth` and preserve `theme.strokeWidth` and all other objects.

Assets contain `name`, optional `source`, `viewBox: [x, y, width, height]`, and an array of SVG path strings in `paths`. Optional `rendering` is `solid` (default) or `outline`, used for detailed service symbols whose interior lines need to remain visible. Full SVG markup is not accepted. Copy the complete asset from `diagram library list` into the document's `assets` map. Nodes reference it through `asset` and may choose `variant: black` or `white`. White variants receive a dark monochrome backing on light themes; Blueprint always uses white marks directly on blue; Dark uses light gray marks directly on charcoal. Saved black/white variant preferences are preserved when switching back to a light theme.

Saving an older or unsupported version fails; unknown fields fail rather than being silently removed. The CLI's diagnostics include `code`, `path`, and, where applicable, `element`. A failed validation or stale write exits with status 2. The `write` command's revision guard is mandatory.
