#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
source "$project_dir/scripts/environment.sh"
swift build --product XKCDDiagrams "${swift_options[@]}"
binary_dir="$(swift build --show-bin-path "${swift_options[@]}")"
# Compile the actual editor/workspace stores into a separate executable without launching the app.
xcrun swiftc -parse-as-library -swift-version 5 -module-name DiagramAppChecks \
    -I "$binary_dir/Modules" \
    Sources/DiagramApp/EditorStore.swift Sources/DiagramApp/WorkspaceStore.swift \
    Tests/DiagramAppChecks/main.swift "$binary_dir"/DiagramCore.build/*.o \
    -o "$binary_dir/DiagramAppChecks"
"$binary_dir/DiagramAppChecks"
