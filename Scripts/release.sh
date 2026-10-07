#!/bin/zsh
# Publishes a new version: ./Scripts/release.sh 1.3.0
# Needs notes for that version in CHANGELOG.md and the Sparkle signing key in your keychain.
set -euo pipefail

die() { echo "$1" >&2; exit 1; }

project_dir="${0:A:h:h}"
cd "$project_dir"
version="${1:-}"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "usage: ./Scripts/release.sh <version>, for example 1.3.0"
tag="v$version"
repo="raffi-mnk/Copyclip"
plist="$project_dir/Resources/Info.plist"
dmg="$project_dir/dist/Copyclip-$version.dmg"
url="https://github.com/$repo/releases/download/$tag/Copyclip-$version.dmg"

[[ "$(git branch --show-current)" == "main" ]] || die "Switch to the main branch first."
[[ -z "$(git status --porcelain)" ]] || die "Commit or stash your changes first."
git fetch origin --quiet --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "Pull or push first: main differs from GitHub."
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "$tag already exists."
notes=$(python3 Scripts/release_helper.py notes "$version" markdown)

# The build number only goes up; Sparkle compares it to decide what is newer.
build=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist") + 1 ))
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $version" -c "Set CFBundleVersion $build" "$plist"
trap 'echo "Release stopped. Undo local changes with: git checkout Resources/Info.plist appcast.xml" >&2' ERR

./Scripts/build-dmg.sh
sparkle_dir=$(./Scripts/fetch-sparkle.sh)
# Signs with the private key in your keychain; prints sparkle:edSignature="…" length="…".
signed=$("$sparkle_dir/bin/sign_update" "$dmg")
signature=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<< "$signed")
length=$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<< "$signed")
[[ -n "$signature" && -n "$length" ]] || die "sign_update did not return a signature: $signed"
python3 Scripts/release_helper.py add-item "$version" "$build" "$url" "$signature" "$length"

git add Resources/Info.plist appcast.xml
git commit -q -m "Release $version"
git tag -a "$tag" -m "Copyclip $version"
trap - ERR

# The appcast goes live when main is pushed, so publish the download first.
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    git push -q origin "$tag"
    gh release create "$tag" "$dmg" --repo "$repo" --title "Copyclip $version" --notes "$notes" --verify-tag
    git push -q origin main
    echo "Published Copyclip $version: https://github.com/$repo/releases/tag/$tag"
else
    cat <<EOF

Copyclip $version is built, signed, committed, and tagged. To publish it:

  1. git push origin $tag
  2. Open https://github.com/$repo/releases/new?tag=$tag
     Title: Copyclip $version
     Attach: $dmg
     Notes: the $version section of CHANGELOG.md
     Click "Publish release".
  3. git push origin main    (this makes the update visible to the app)

Install the GitHub CLI (brew install gh, then gh auth login) to do this automatically next time.
EOF
fi
