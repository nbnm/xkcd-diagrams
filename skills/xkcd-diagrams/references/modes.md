# Free Drawing and Timeline

These are document modes in the same schema 1 `.diagram.json` format. Initialize a complete document with `diagram init <file> --mode drawing|timeline`; add `--example` to inspect a working example. Query `diagram schema` for the current schema. Validate, apply guarded writes, and render with the usual commands. Themes, sketch typography, PNG/SVG exports, and the optional T1A watermark work in every mode.

Keep the generated empty, free-layout root container. Neither mode uses nested containers or diagram connectors. Timeline documents have no nodes; Drawing nodes must use `shape: text` and appear in the root's `children` list. Omit unused mode payloads instead of using `null`. Existing files without `mode` remain diagrams.

## Free Drawing

Set `mode: drawing` and include `drawing`:

```json
{
  "strokes": [
    {
      "id": "underline",
      "points": [{ "x": 40, "y": 100 }, { "x": 100, "y": 102 }, { "x": 180, "y": 100 }],
      "strokeWidth": 2,
      "smoothing": 0.65
    }
  ],
  "smoothing": 0.65,
  "strokeWidth": 2
}
```

The document-level settings are defaults for new mouse strokes. Each stroke retains its own width and smoothing. Smoothing ranges from 0 to 1, with 0 retaining raw lines. It preserves mouse samples and endpoints; it does not add sketch wobble. Use 0.5–8 point widths, unique nonempty stroke IDs, and finite coordinates within ±100000. A stroke needs 1–20000 points, with at most 2000 strokes and 250000 total points. Files must fit the 16 MB save/read limit.

Text uses ordinary `nodes` with `type: text`, `shape: text`, a label, and a free `position`; add its ID to the root's children. Optional `fontSize` applies to that text item only. Pen strokes draw beneath text. Preserve authored raw samples when adjusting smoothing.

## Timeline

Set `mode: timeline` and include `timeline`:

```json
{
  "scale": "weeks",
  "tasks": [
    {
      "id": "design",
      "label": "Design",
      "start": "2026-10-26",
      "duration": 5,
      "progress": 0.4,
      "owner": "Architecture",
      "milestone": false,
      "dependencies": []
    },
    {
      "id": "review",
      "label": "Design approved",
      "start": "2026-10-31",
      "duration": 0,
      "progress": 0,
      "owner": "Delivery",
      "milestone": true,
      "dependencies": ["design"]
    }
  ]
}
```

Tasks are ordered rows; IDs must be unique across the document. Dates are strict Gregorian `YYYY-MM-DD` values between 1900 and 2200, independent of time zones. Duration is a count of calendar days, including weekends. A normal task lasts 1–3650 days and its inclusive finish is `start + duration - 1`. Milestones have `duration: 0` and a single date. Completion is a number from 0 to 1. `owner` is an editable string. Timescale is `days`, `weeks`, or `months`; it changes chart density, not task dates.

`dependencies` contains distinct predecessor task IDs, interpreted as visual finish-to-start links. Missing references, self-links, and cycles are invalid. Scheduling remains manual: changing a task does not move successors. Do not claim critical-path analysis, business-day calendars, resource leveling, or Microsoft Project file compatibility. When supplied dates conflict with a dependency, preserve the dates and explain the conflict unless the user asks to reschedule. At most 500 tasks and an overall ten-year span are supported. Deleting a task removes references to it from successors.
