# Copyclip

A small clipboard history app for the macOS menu bar. Everything you copy is kept on your Mac, ready to paste again.

- Recent clips in the menu bar, with ⌘0–⌘9 shortcuts
- Pin, rename, edit, and search clips in **Clips Management**
- Keeps text, rich text, images, and files with their original formatting
- **Private Mode** to pause recording, and a list of apps to ignore

Requires macOS 13 or later, on Apple silicon or Intel.

## Install

1. Download the latest `Copyclip-<version>.dmg` from [Releases](https://github.com/raffi-mnk/Copyclip/releases/latest).
2. Open it and drag Copyclip into **Applications**.
3. Open Copyclip. Because it isn't notarized by Apple, macOS blocks the first launch: click **Done**, then go to **System Settings › Privacy & Security** and click **Open Anyway**.

Copyclip appears as a paperclip in the menu bar. To start it automatically, turn on **Launch Copyclip at login** in Preferences.

## Privacy

Your clipboard history never leaves your Mac. Copyclip has no analytics, no accounts, and no sync.

Its only network connection is the update check. If you allow it, Copyclip downloads [`appcast.xml`](appcast.xml), a list of versions, from GitHub once a day. Like any download, GitHub sees your IP address and Copyclip's version. Nothing else is sent. Turn it off in Preferences, or check by hand with **Check for Updates…** in the menu.

Your history is stored in `~/Library/Application Support/Copyclip`, protected by your macOS login (and FileVault, if it's on). Items that password managers mark as concealed are never recorded. **Delete All History…** in the menu removes everything.

## Build from source

```sh
./Scripts/build-app.sh   # dist/Copyclip.app
./Scripts/build-dmg.sh   # dist/Copyclip-<version>.dmg
```

Requires the Xcode command line tools. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for how it works and how to run the tests.

## License

Source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md): free to read, build, and use for noncommercial purposes, but not to sell or use commercially. Copyright (c) 2026 raffi-mnk.
