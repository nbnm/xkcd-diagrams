#!/usr/bin/env python3
"""Freeze geometry from downloaded vendor sources. No network access during app builds.

Usage: python3 scripts/assemble-library.py /path/to/vendor-source-cache [product-svg-folder]
The cache contains files identified in docs/ASSETS.md. This script is a maintainer tool.
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

cache = Path(sys.argv[1])
destination = Path(__file__).resolve().parents[1] / "Sources/DiagramCore/Resources/library.json"
previous = json.loads(destination.read_text())
platforms = [item for item in previous if item["group"] == "T1A"]
items = [item for item in previous if item["id"] in ["service", "database", "queue", "file", "xlsx", "pdf", "docx", "actor", "text", "ai-agent"]]
for item in items:
    item["title"] = {"service": "System", "database": "Database", "queue": "Queue", "file": "File", "xlsx": "XLSX", "pdf": "PDF", "docx": "DOCX", "actor": "User", "text": "Text", "ai-agent": "AI Agent"}[item["id"]]
    if item["id"] == "queue": item["shape"] = "queue"
    if item["id"] in ["file", "xlsx", "pdf", "docx"]: item["group"] = "Documents"

def svg_asset(filename, name, source, contours=None, box=None):
    root = ET.fromstring((cache / filename).read_text())
    paths = [e.attrib["d"] for e in root.iter() if e.tag.split("}")[-1] == "path"]
    if any(e.attrib.get("transform") for e in root.iter()):
        raise ValueError("Source transforms must be flattened before assembly")
    if contours is not None:
        paths = [" ".join(re.findall(r"M[^M]+", paths[0])[:contours])]
    return {"name": name, "source": source,
            "viewBox": box or [float(v) for v in root.attrib["viewBox"].split()], "paths": paths}

def add(ident, title, asset, symbol, group=None, shape="rectangle", kind="service"):
    items.append(dict(id=ident, title=title, type=kind, shape=shape,
                      symbol=symbol, group=group or title, asset=asset))

add("databricks", "Databricks", svg_asset("databricks.svg", "Databricks",
    "https://www.databricks.com/sites/default/files/2024-10/Databricks-Logo-Icon.svg"), "square.3.layers.3d")
add("azure", "Azure", svg_asset("azure.svg", "Microsoft Azure",
    "https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/acom_social_icon_azure"), "cloud")
# The first ten complete contours are the separate OpenAI wordmark preceding Developers.
add("openai", "OpenAI", svg_asset("openai-developers-logo.svg", "OpenAI",
    "https://developers.openai.com/OpenAI_Developers.svg", contours=10, box=[0, 0, 82, 18]), "sparkle")
# The site contains a duplicate logo for the mobile navigation; retain one set only.
aws = svg_asset("aws-1.svg", "AWS", "https://aws.amazon.com/architecture/icons/")
aws["paths"] = aws["paths"][:3]
add("aws", "AWS", aws, "cloud")

# Freeze the first (full wordmark) frame of Anthropic's official navigation Lottie.
lottie = json.loads((cache / "anthropic-lottie.json").read_text())
compositions = {asset["id"]: asset for asset in lottie["assets"]}

def value(prop):
    if prop.get("a"):
        result = prop["k"][0]["s"]
        return result[0] if len(result) == 1 else result
    return prop.get("k", 0)

def translation(layer, layers):
    position = layer.get("ks", {}).get("p", {})
    if position.get("s"):
        x, y = value(position["x"]), value(position["y"])
    else:
        p = value(position) if position else [0, 0]
        x, y = p[0], p[1]
    if layer.get("parent") is not None:
        parent = next(l for l in layers if l.get("ind") == layer["parent"])
        px, py = translation(parent, layers)
        x, y = x + px, y + py
    return x, y

def shape_paths(shapes, offset):
    paths = []
    for shape in shapes:
        if shape["ty"] == "gr":
            paths.extend(shape_paths(shape["it"], offset))
        elif shape["ty"] == "sh":
            geometry = value(shape["ks"])
            vertices, incoming, outgoing = geometry["v"], geometry["i"], geometry["o"]
            def fmt(p): return f"{p[0] + offset[0]:.6f} {p[1] + offset[1]:.6f}"
            commands = ["M" + fmt(vertices[0])]
            count = len(vertices) if geometry["c"] else len(vertices) - 1
            for i in range(count):
                j = (i + 1) % len(vertices)
                a, b = vertices[i], vertices[j]
                if any(outgoing[i]) or any(incoming[j]):
                    c1 = [a[k] + outgoing[i][k] for k in range(2)]
                    c2 = [b[k] + incoming[j][k] for k in range(2)]
                    commands.append("C" + fmt(c1) + " " + fmt(c2) + " " + fmt(b))
                else:
                    commands.append("L" + fmt(b))
            if geometry["c"]: commands.append("Z")
            paths.append(" ".join(commands))
    return paths

paths = []
for composition in compositions.values():
    if not re.match(r"comp_[A-Z]_", composition["id"]) and not composition["id"].startswith("comp_Slash_"):
        continue
    layers = composition["layers"]
    for layer in layers:
        if layer.get("shapes"):
            paths.extend(shape_paths(layer["shapes"], translation(layer, layers)))
add("anthropic", "Anthropic", dict(name="Anthropic", source="https://www.anthropic.com/",
    viewBox=[0, 0, 143, 16], paths=[" ".join(paths)]), "asterisk")

products = Path(sys.argv[2]) if len(sys.argv) > 2 else destination.parents[3] / "assets/vendor"
number = r"[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?"

def translated_path(path, dx, dy):
    if dx == dy == 0: return path
    tokens = re.findall(r"[A-Za-z]|" + number, path)
    counts = dict(M=2, L=2, H=1, V=1, C=6, S=4, Q=4, T=2, A=7)
    output, index, command = [], 0, None
    while index < len(tokens):
        if tokens[index].isalpha():
            command = tokens[index]; output.append(command); index += 1
            if command.upper() == "Z": continue
        count = counts[command.upper()]
        values = list(map(float, tokens[index:index + count])); index += count
        if command.isupper():
            if command == "H": values[0] += dx
            elif command == "V": values[0] += dy
            elif command == "A": values[5] += dx; values[6] += dy
            else:
                values = [value + (dx if i % 2 == 0 else dy) for i, value in enumerate(values)]
        elif not output[:-1] and command == "m":
            raise ValueError("Translate a relative initial move through an absolute path first")
        output.extend(f"{v:.6g}" for v in values)
    return " ".join(output)

def product_asset(filename, name, source, outline=False, unity_symbol=False):
    root = ET.fromstring((products / filename).read_text())
    paths = []
    def walk(element, dx=0, dy=0):
        tag = element.tag.split("}")[-1]
        if tag in ["defs", "mask", "clipPath", "title"] or "Icon-Architecture-BG" in element.attrib.get("id", ""): return
        transform = element.attrib.get("transform")
        if transform:
            if not transform.startswith("translate("): raise ValueError(f"Unsupported transform in {filename}: {transform}")
            values = list(map(float, re.findall(number, transform)))
            dx += values[0]; dy += values[1] if len(values) > 1 else 0
        path = element.attrib.get("d") if tag == "path" else None
        if tag == "rect":
            x, y, w, h = [float(element.attrib.get(key, 0)) for key in ["x", "y", "width", "height"]]
            rx = min(w / 2, float(element.attrib.get("rx", 0))); ry = min(h / 2, float(element.attrib.get("ry", rx)))
            if rx and ry:
                path = f"M{x+rx} {y} H{x+w-rx} A{rx} {ry} 0 0 1 {x+w} {y+ry} V{y+h-ry} A{rx} {ry} 0 0 1 {x+w-rx} {y+h} H{x+rx} A{rx} {ry} 0 0 1 {x} {y+h-ry} V{y+ry} A{rx} {ry} 0 0 1 {x+rx} {y} Z"
            else: path = f"M{x} {y} H{x+w} V{y+h} H{x} Z"
        elif tag == "polygon":
            pairs = list(map(float, re.findall(number, element.attrib["points"])))
            path = "M" + " L".join(f"{pairs[i]} {pairs[i+1]}" for i in range(0, len(pairs), 2)) + " Z"
        if path: paths.append(translated_path(path, dx, dy))
        for child in element: walk(child, dx, dy)
    walk(root)
    box = [float(v) for v in root.attrib["viewBox"].split()]
    if unity_symbol: paths = paths[13:]; box = [0, 0, 26, 26]
    asset = dict(name=name, source=source, viewBox=box, paths=paths)
    if outline: asset["rendering"] = "outline"
    return asset

add("unity-catalog", "Unity Catalog", product_asset("unity-catalog.svg", "Unity Catalog", "https://www.databricks.com/sites/default/files/2024-12/logo-color-unity-catalog.svg", unity_symbol=True), "hexagon", group="Databricks")
add("delta-lake", "Delta Lake", product_asset("delta-lake.svg", "Delta Lake", "https://www.databricks.com/sites/default/files/2023-03/icon-orange_delta-lake.svg"), "triangle", group="Databricks", shape="cylinder", kind="database")
add("databricks-lakehouse", "Lakehouse", next(i["asset"] for i in items if i["id"] == "databricks"), "cylinder", group="Databricks", shape="cylinder", kind="database")
add("genie-agent", "Genie Agent", product_asset("genie-agent.svg", "Genie Agent", "https://www.databricks.com/sites/default/files/2026-05/icon-genie.svg"), "sparkles", group="Databricks", shape="roundedRectangle", kind="agent")
for ident, title, filename, shape, kind in [
    ("azure-data-lake", "Data Lake Storage", "azure-data-lake.svg", "cylinder", "database"),
    ("azure-vm", "Virtual Machine", "azure-vm.svg", "rectangle", "service"),
    ("azure-storage", "Storage Account", "azure-Storage-Accounts.svg", "cylinder", "database"),
    ("azure-sql", "SQL Database", "azure-sql.svg", "cylinder", "database"),
    ("azure-openai", "Azure OpenAI", "azure-openai.svg", "rectangle", "service"),
]:
    add(ident, title, product_asset(filename, title, "https://learn.microsoft.com/en-us/azure/architecture/icons/", outline=True), "cloud", group="Azure", shape=shape, kind=kind)
for ident, title, filename, shape, kind in [
    ("aws-s3", "Amazon S3", "aws-s3.svg", "cylinder", "database"),
    ("aws-ec2", "Amazon EC2", "aws-ec2.svg", "rectangle", "service"),
    ("aws-lambda", "Lambda", "aws-lambda.svg", "rectangle", "service"),
    ("aws-rds", "Amazon RDS", "aws-rds.svg", "cylinder", "database"),
]:
    add(ident, title, product_asset(filename, title, "https://aws.amazon.com/architecture/icons/"), "cloud", group="AWS", shape=shape, kind=kind)
add("openai-api", "OpenAI API", next(i["asset"] for i in items if i["id"] == "openai"), "sparkle", group="OpenAI")
add("claude-api", "Claude API", next(i["asset"] for i in items if i["id"] == "anthropic"), "asterisk", group="Anthropic")
items.extend(platforms)
destination.write_text(json.dumps(items, indent=2) + "\n")
print(f"Frozen {len(items)} library entries; retained T1A platform marks and AI Agent")
