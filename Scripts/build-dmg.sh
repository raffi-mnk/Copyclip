#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
"$project_dir/Scripts/build-app.sh"

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$project_dir/Resources/Info.plist")
volume_name="Copyclip"
work_dir="$project_dir/.build/dmg"
staging="$work_dir/staging"
dmg_path="$project_dir/dist/Copyclip-$version.dmg"
rm -rf "$work_dir"
mkdir -p "$staging/.background"

# Window background with install and first-launch steps, at 1x and 2x for Retina screens.
background_script="$project_dir/Scripts/dmg-background.swift"
logo="$project_dir/Resources/CopyclipLogo.png"
CLANG_MODULE_CACHE_PATH="$project_dir/.build/ClangCache" SWIFT_MODULE_CACHE_PATH="$project_dir/.build/ModuleCache" \
    swift "$background_script" "$work_dir/background.png" 1 "$version" "$logo"
CLANG_MODULE_CACHE_PATH="$project_dir/.build/ClangCache" SWIFT_MODULE_CACHE_PATH="$project_dir/.build/ModuleCache" \
    swift "$background_script" "$work_dir/background@2x.png" 2 "$version" "$logo"
tiffutil -cathidpicheck "$work_dir/background.png" "$work_dir/background@2x.png" \
    -out "$staging/.background/background.tiff" >/dev/null 2>&1

ditto "$project_dir/dist/Copyclip.app" "$staging/Copyclip.app"
ln -s /Applications "$staging/Applications"
cp "$project_dir/Resources/Read Me First.txt" "$staging/Read Me First.txt"

if [[ -d "/Volumes/$volume_name" ]]; then
    echo "Eject the mounted “$volume_name” volume first." >&2
    exit 1
fi
hdiutil create -srcfolder "$staging" -volname "$volume_name" -fs HFS+ -format UDRW -ov \
    "$work_dir/Copyclip-rw.dmg" >/dev/null
mount_dir=$(hdiutil attach "$work_dir/Copyclip-rw.dmg" -readwrite -noverify -noautoopen \
    | awk -F'\t' '/\/Volumes\// { print $NF }')
# Finder stores the window layout in the volume's .DS_Store. This needs permission to control Finder.
if ! osascript <<EOF
tell application "Finder"
    tell disk "$volume_name"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 840, 648}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 88
        set text size of viewOptions to 12
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Copyclip.app" of container window to {170, 160}
        set position of item "Applications" of container window to {470, 160}
        set position of item "Read Me First.txt" of container window to {545, 372}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
then
    echo "Warning: Finder layout was not applied (allow automation of Finder and run again)." >&2
fi

# hdiutil and Finder both drop .VolumeIcon.icns, so the disk icon is added after the layout is saved.
cp "$project_dir/Resources/Copyclip.icns" "$mount_dir/.VolumeIcon.icns"
SetFile -a C "$mount_dir" 2>/dev/null || true

sync
hdiutil detach "$mount_dir" >/dev/null
rm -f "$dmg_path"
hdiutil convert "$work_dir/Copyclip-rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg_path" >/dev/null
echo "Built $dmg_path"
