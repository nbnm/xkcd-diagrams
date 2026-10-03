# Bundled logo geometry

The library freezes vector geometry into the document format, renders it in black or white, and records its source. These assets identify the corresponding vendor systems within architecture diagrams; they are not the app's branding. Vendor marks belong to their respective owners. Retain the sources and review the vendors' asset terms before broader distribution.

| Entry | Source | Preparation |
| --- | --- | --- |
| T1A watermark | [Official site logo](https://t1a.com/images/t1a-LOGO.svg) | Retains the supplied wordmark path and renders it at 40% opacity; monochrome on light paper, light in Blueprint, Dark, and SecondStack |
| SecondStack | [Official site navigation](https://secondstack.ai/) | Retains the hand-cut mark, flattening its rotated rectangles into monochrome filled paths |
| LakeSentry | [Official logo SVG](https://lakesentry.io/logo.svg) | Retains the lighthouse symbol from the complete wordmark; crops its view box without changing geometry |
| 8FDE | [Official site navigation](https://8fde.ai/) | Retains the octopus mascot and glasses; resolves source CSS and freezes four-point strokes into filled outlines, keeping the filled pupils |
| Antares | [Official site navigation](https://getantares.io/) | Retains the complete seven-path wordmark |
| T1A platform | [Official logo SVG](https://t1a.com/images/t1a-LOGO.svg) | Uses the same supplied wordmark as the watermark, at full opacity in an editable box |
| AI Agent | `assets/ai-agent.svg` | App-authored robot glyph with an antenna, framed in an editable rounded box; strokes frozen into filled outlines |
| Databricks | [Company mark](https://www.databricks.com/sites/default/files/2024-10/Databricks-Logo-Icon.svg) | Retains the supplied path |
| OpenAI | [Official developer site wordmark](https://developers.openai.com/OpenAI_Developers.svg) | Retains the ten complete OpenAI contours preceding the separate Developers suffix |
| Anthropic | [Official site](https://www.anthropic.com/) | Freezes full wordmark geometry at the first frame of the navigation logo animation |
| Azure | [Official platform mark](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/acom_social_icon_azure) | Retains supplied paths and uses monochrome fills |
| AWS | [Official architecture page](https://aws.amazon.com/architecture/icons/) | Retains one copy of the navigation logo's three paths |
| Unity Catalog | [Databricks product symbol](https://www.databricks.com/sites/default/files/2024-12/logo-color-unity-catalog.svg) | Retains the complete circular symbol and omits the separate wordmark |
| Delta Lake | [Databricks product symbol](https://www.databricks.com/sites/default/files/2023-03/icon-orange_delta-lake.svg) | Retains the complete glyph; monochrome outline presentation |
| Azure Data Lake Storage, VM, Storage Account, SQL Database, Azure OpenAI | [Microsoft architecture icon collection](https://learn.microsoft.com/en-us/azure/architecture/icons/) | Freezes the selected SVG geometry from the July 2026 V24 collection; outline presentation preserves internal details |
| AWS S3, EC2, Lambda, RDS | [AWS architecture icon collection](https://aws.amazon.com/architecture/icons/) | Freezes the July 31, 2026 service glyphs, omitting category background tiles; outline presentation |

No downloads occur at runtime. Original product SVGs are retained in `assets/vendor/`. The reproducible maintainer tool is `scripts/assemble-library.py`; its first argument is a directory containing the company source files named in the script, and its optional second argument is the product SVG directory. Frozen geometry ships in `Sources/DiagramCore/Resources/library.json` and is embedded in documents when used.

The Azure Data Lake symbol comes from the collection's `10090-icon-service-Data-Lake-Storage-Gen1.svg` glyph. The preset identifies storage visually; it does not prescribe that service generation. Databricks Lakehouse reuses the Databricks company mark inside a database shape. OpenAI API and Claude API reuse their company identities; they do not introduce separate product logos.

The library has 34 presets: six generic presets including AI Agent, four document shapes (File, XLSX, PDF, DOCX), and 24 branded entries grouped by T1A, Databricks, Azure, AWS, OpenAI, and Anthropic. T1A has `secondstack`, `lakesentry`, `8fde`, `antares`, and `t1a`. AI Agent uses `ai-agent`, `type: agent`, and a rounded rectangle with its own frozen robot glyph. The renderer supports `solid` and `outline` asset presentation. All marks can render in black or white; Blueprint renders white marks on blue, Dark renders light gray marks on charcoal, and SecondStack uses off-white marks on near-black paper, without a backing tile. Small library previews use the same vector paths and shape geometry as the canvas.

To regenerate the T1A platform and AI Agent entries from the retained SVGs, run `python3 scripts/assemble-platform-library.py`. It compiles a temporary geometry helper using the app's SVG path parser and CoreGraphics, flattens source rotations and strokes, and updates only those six entries. The helper supports the self-contained SVG subset used by these sources and rejects unsupported elements; it does not resolve external entities. Existing vendor entries are preserved. The older vendor assembler also retains the added T1A and AI Agent entries. No network connection is needed for regeneration or app builds.

## Diagram watermark

The optional diagram watermark uses `assets/t1a-logo.svg`. Its frozen geometry is in `Sources/DiagramCore/Branding.swift` and requires no runtime download. It occupies a reserved footer at the bottom-right of canvas and exports, so it cannot overlap diagram content.

## Application icon

`assets/app-icon.png` is the generated source artwork; `packaging/AppIcon.icns` contains the macOS icon sizes. The icon depicts a friendly stick-figure draftsman drawing connected system boxes on a blue blueprint. Ubino's appearance has not yet been confirmed, so this is a provisional character interpretation.

Generated with the built-in `imagegen` tool in generate mode, with a transparent background. Prompt direction: a centered hand-drawn draftsman with a round unfilled head and black pencil, leaning over blue `#164A83` paper with white boxes and arrows, on an ivory rounded square; no text, no extra characters, and outlines readable at 32 px. The original output remains in the Codex generated-images directory; the copied source is the project artifact. `sips` resized the artwork for packaging, and `iconutil` assembled the `.icns` file.
