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
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/Copyclip" "$app_dir/Contents/MacOS/Copyclip"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

assets_dir="$project_dir/.build/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$assets_dir"
cp "$project_dir/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" "$assets_dir/Contents.json"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$project_dir/Resources/CopyclipLogo.png" \
        --out "$assets_dir/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -s format png -z "$doubled" "$doubled" "$project_dir/Resources/CopyclipLogo.png" \
        --out "$assets_dir/icon_${size}x${size}@2x.png" >/dev/null
done
xcrun actool --compile "$app_dir/Contents/Resources" --platform macosx \
    --minimum-deployment-target 13.0 --app-icon AppIcon \
    --output-partial-info-plist "$project_dir/.build/AssetInfo.plist" \
    "$project_dir/.build/Assets.xcassets" >/dev/null

print -n 'APPL????' > "$app_dir/Contents/PkgInfo"
codesign --force --sign - "$app_dir"
touch "$app_dir"
launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$launch_services" ]]; then
    "$launch_services" -f "$app_dir" >/dev/null 2>&1 || true
fi
echo "Built $app_dir"
