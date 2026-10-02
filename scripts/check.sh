#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
source "$project_dir/scripts/environment.sh"
swift build --product DiagramChecks "${swift_options[@]}"
binary_dir="$(swift build --show-bin-path "${swift_options[@]}")"
"$binary_dir/DiagramChecks"
