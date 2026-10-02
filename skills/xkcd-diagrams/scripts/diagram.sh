#!/bin/sh
set -eu

# Keep discovery independent of the diagram project's working directory.
diagram_cli=${XKCD_DIAGRAM_CLI:-/Volumes/Work/xkcd-diagrams/dist/diagram}
if [ ! -f "$diagram_cli" ] || [ ! -x "$diagram_cli" ]; then
    printf '%s\n' "XKCD Diagrams CLI is unavailable: $diagram_cli" \
        'Build the app CLI or set XKCD_DIAGRAM_CLI to its executable path.' >&2
    exit 127
fi

exec "$diagram_cli" "$@"
