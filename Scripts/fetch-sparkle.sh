#!/bin/zsh
# Downloads the pinned Sparkle release into .build/Sparkle-<version> and prints that folder.
set -euo pipefail

version="2.10.0"
sha256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

project_dir="${0:A:h:h}"
sparkle_dir="$project_dir/.build/Sparkle-$version"
if [[ ! -d "$sparkle_dir/Sparkle.framework" ]]; then
    archive="$project_dir/.build/Sparkle-$version.tar.xz"
    mkdir -p "$project_dir/.build"
    curl -sfL -o "$archive" "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"
    if [[ "$(shasum -a 256 "$archive" | cut -d' ' -f1)" != "$sha256" ]]; then
        echo "Sparkle download does not match the expected checksum." >&2
        rm -f "$archive"
        exit 1
    fi
    rm -rf "$sparkle_dir"
    mkdir -p "$sparkle_dir"
    tar -xf "$archive" -C "$sparkle_dir"
    rm -f "$archive"
fi
echo "$sparkle_dir"
