# Development

## Building

Requires macOS 13 or later and the Xcode command line tools. You can also open `Package.swift` in Xcode.

```sh
./Scripts/build-app.sh
open dist/Copyclip.app
```

The build script makes an optimized universal app (Apple silicon and Intel) at `dist/Copyclip.app`, with its debug symbols in `dist/Copyclip.app.dSYM` for reading crash reports. The dSYM contains local file paths, so it isn't shipped. Copy the app to `/Applications` to enable **Launch Copyclip at login**.

## Packaging

```sh
./Scripts/build-dmg.sh
```

This builds the app and packages it as `dist/Copyclip-<version>.dmg`, using the version in `Resources/Info.plist`. The disk image window shows how to install Copyclip and open it the first time, and includes `Resources/Read Me First.txt` with the same steps. The background is drawn by `Scripts/dmg-background.swift`. Arranging the window needs permission for your terminal to control Finder; without it the disk image is still built, with a warning.

Copyclip is signed ad hoc, not with an Apple Developer ID, so macOS blocks its first launch until the user clicks **Open Anyway** in Privacy & Security.

## Releasing

Updates are delivered with [Sparkle](https://sparkle-project.org). `Scripts/fetch-sparkle.sh` downloads the pinned Sparkle version into `.build` and checks its checksum; the build script embeds it in the app.

To publish a version:

1. Add a `## <version>` section to `CHANGELOG.md` and commit it.
2. Run `./Scripts/release.sh <version>`, for example `./Scripts/release.sh 1.3.0`.

The script sets the version and raises the build number in `Info.plist`, builds the disk image, signs it with the Sparkle key, adds it to `appcast.xml`, then commits and tags `v<version>`. With the GitHub CLI (`gh`) signed in, it also pushes the tag, creates the GitHub Release with the disk image, and pushes `main`; without it, it prints those steps. The app reads `appcast.xml` from `main`, so pushing `main` last makes the update visible only once the download exists.

### Signing key

Sparkle verifies each update with an EdDSA key. The private key is stored in the login keychain of the Mac that made it, and its public key is `SUPublicEDKey` in `Info.plist`. Keep a backup somewhere private, outside this repository:

```sh
.build/Sparkle-*/bin/generate_keys -x ~/Desktop/copyclip-sparkle-key.txt   # then move it to a password manager and delete the file
.build/Sparkle-*/bin/generate_keys -f copyclip-sparkle-key.txt             # imports it on another Mac
```

If the key is lost, existing installs can't verify new updates, and users have to download a new disk image by hand once.

Copyclip is signed ad hoc. Sparkle downloads updates itself, so they don't carry the quarantine flag and open without the first-launch Gatekeeper step.

## Storage

History is stored in `~/Library/Application Support/Copyclip`:

- `HistoryIndex.plist` lists clip IDs in order.
- `Clips/<id>.meta.plist` holds a clip's details: a preview of up to 2,000 characters, a text excerpt, a content hash, the source app, and the title and pin state. These stay in memory.
- `Clips/<id>.plist` holds the clipboard data. It is read only when a clip is restored or previewed, so memory use doesn't grow with history size.

Clips saved by earlier versions, including the single-file `History.plist`, are converted on first launch. Files are written individually on a background queue, so a new copy never rewrites the whole history.

Pinned clips always appear at the top of the menu and are never removed by the retention limit. Lowering the limit removes the oldest unpinned clips immediately. Editing a clip saves plain text and removes its formatting; renaming changes only its label.

## Clipboard monitoring

macOS has no clipboard-change notification, so Copyclip checks the pasteboard change count twice a second with timer tolerance, and stops checking entirely in Private Mode. Copies made while paused are skipped when recording resumes.

When a copy is recorded:

- Items marked concealed, transient, or auto-generated (`org.nspasteboard.*`) are skipped.
- File promises and legacy `CorePasteboardFlavorType` formats are not read, so source apps aren't asked to generate data that can't be restored later.
- TIFF copies of images that also come as PNG are dropped, and any single format larger than 32 MB is skipped.
- Ignored apps are matched against the app in the foreground when the change is detected, so copies made by background automation may not have a reliable source app.

## Tests

```sh
swiftc Sources/Copyclip/ClipboardStore.swift Tests/ClipboardStoreTests.swift -o /tmp/CopyclipStoreTests
/tmp/CopyclipStoreTests
```
