# Shared build paths stay on the system's local temporary filesystem.
# DIAGRAM_BUILD_DIR can override this for a persistent custom build directory.
project_key="$(printf '%s' "$project_dir" | shasum -a 256 | cut -c1-12)"
build_dir="${DIAGRAM_BUILD_DIR:-${TMPDIR:-/private/tmp}/xkcd-diagrams-$project_key}"
export CLANG_MODULE_CACHE_PATH="$build_dir/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/swift-cache"
swift_options=(--scratch-path "$build_dir/build" --cache-path "$build_dir/package-cache" --disable-sandbox)
