#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p "$project_dir/.build/ClangCache" "$project_dir/.build/ModuleCache"
CLANG_MODULE_CACHE_PATH="$project_dir/.build/ClangCache" \
SWIFT_MODULE_CACHE_PATH="$project_dir/.build/ModuleCache" \
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
    Sources/Copyclip/*.swift -o "$project_dir/.build/Copyclip"

app_dir="$project_dir/dist/Copyclip.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/Copyclip" "$app_dir/Contents/MacOS/Copyclip"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
print -n 'APPL????' > "$app_dir/Contents/PkgInfo"
codesign --force --sign - "$app_dir"
echo "Built $app_dir"
