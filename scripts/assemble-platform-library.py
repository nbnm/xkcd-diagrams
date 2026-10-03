#!/usr/bin/env python3
"""Freeze the retained T1A platform and AI Agent SVGs without network access."""
import json
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
destination = root / "Sources/DiagramCore/Resources/library.json"
with tempfile.TemporaryDirectory(prefix="diagram-platform-marks-") as work:
    work = Path(work)
    tool, output = work / "freeze-marks", work / "marks.json"
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(work / "module-cache"),
                    str(root / "Sources/DiagramCore/SVGPath.swift"),
                    str(root / "scripts/freeze-platform-marks.swift"), "-o", str(tool)], check=True)
    subprocess.run([str(tool), str(root), str(output)], check=True)
    entries = json.loads(output.read_text())
items = json.loads(destination.read_text())
identifiers = {item["id"] for item in entries}
items = [item for item in items if item["id"] not in identifiers]
agent = next(item for item in entries if item["id"] == "ai-agent")
items.insert(next(i for i, item in enumerate(items) if item["id"] == "actor"), agent)
items.extend(item for item in entries if item["id"] != "ai-agent")
destination.write_text(json.dumps(items, indent=2) + "\n")
print(f"Frozen five T1A platform marks and AI Agent; {len(items)} library entries")
