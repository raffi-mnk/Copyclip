#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
build_dir="$project_dir/.build"
mkdir -p "$build_dir/ClangCache" "$build_dir/ModuleCache"
sparkle_dir=$("$project_dir/Scripts/fetch-sparkle.sh")

# Build an optimized slice for Apple silicon and Intel, then combine them into one universal binary.
slices=()
dwarf_files=()
for arch in arm64 x86_64; do
    rm -rf "$build_dir/Copyclip-$arch.dSYM"
    # Compile inside the build folder, where -g leaves its module files.
    mkdir -p "$build_dir/$arch"
    (cd "$build_dir/$arch" && CLANG_MODULE_CACHE_PATH="$build_dir/ClangCache" \
        SWIFT_MODULE_CACHE_PATH="$build_dir/ModuleCache" \
        swiftc -O -wmo -g -swift-version 5 -target "$arch-apple-macosx13.0" -Xlinker -dead_strip \
            -F "$sparkle_dir" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
            "$project_dir"/Sources/Copyclip/*.swift -o "$build_dir/Copyclip-$arch")
    slices+=("$build_dir/Copyclip-$arch")
    dwarf_files+=("$build_dir/Copyclip-$arch.dSYM/Contents/Resources/DWARF/Copyclip-$arch")
done
lipo -create "${slices[@]}" -output "$build_dir/Copyclip"

# Keep debug symbols next to the app so crash reports can be symbolicated, then strip them from the app.
dsym_dir="$project_dir/dist/Copyclip.app.dSYM"
rm -rf "$dsym_dir"
mkdir -p "$dsym_dir/Contents/Resources/DWARF"
cp "$build_dir/Copyclip-arm64.dSYM/Contents/Info.plist" "$dsym_dir/Contents/Info.plist"
lipo -create "${dwarf_files[@]}" -output "$dsym_dir/Contents/Resources/DWARF/Copyclip"

app_dir="$project_dir/dist/Copyclip.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/Copyclip" "$app_dir/Contents/MacOS/Copyclip"
strip -S -x "$app_dir/Contents/MacOS/Copyclip"
mkdir -p "$app_dir/Contents/Frameworks"
ditto "$sparkle_dir/Sparkle.framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
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
