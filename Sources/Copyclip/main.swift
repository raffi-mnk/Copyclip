import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ClipboardStore()
    private let settings = AppSettings()
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = 0
    private var timer: Timer?
    private var statusItem: NSStatusItem!
    private var preferencesController: PreferencesWindowController?
    private var historyController: HistoryWindowController?
    private var aboutWindow: NSWindow?
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 22)
        updateStatusIcon()
        store.onChange = { [weak self] in self?.historyController?.reload() }
        store.enforceLimit(settings.historyLimit)
        menu.delegate = self
        statusItem.menu = menu
        lastChangeCount = pasteboard.changeCount
        updateMonitoring()
    }

    private func updateStatusIcon() {
        if let button = statusItem.button {
            let name = settings.privateModeEnabled ? "eye.slash" : "paperclip"
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Copyclip")?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            symbol?.isTemplate = true
            button.image = symbol
            button.imagePosition = .imageOnly
            button.toolTip = settings.privateModeEnabled ? "Copyclip — Private Mode" : "Copyclip"
        }
    }

    private func updateMonitoring() {
        timer?.invalidate()
        timer = nil
        guard !settings.privateModeEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        timer?.tolerance = 0.2
    }

    private func checkClipboard() {
        guard !settings.privateModeEnabled else { return }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        let source = NSWorkspace.shared.frontmostApplication
        guard !settings.ignores(bundleID: source?.bundleIdentifier) else { return }
        _ = store.capture(from: pasteboard, sourceBundleIdentifier: source?.bundleIdentifier,
                          sourceAppName: source?.localizedName,
                          maxItems: settings.historyLimit)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let heading = NSMenuItem(title: settings.privateModeEnabled ? "Private Mode — recording paused" : "Select a clip to add to your clipboard", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())

        if store.items.isEmpty {
            let empty = NSMenuItem(title: "No clips yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let pinned = store.pinnedItems
            let remaining = max(0, settings.menuLimit - pinned.count)
            let recent = Array(store.items.filter { !$0.isPinned }.prefix(remaining))
            var shortcutIndex = 0
            if !pinned.isEmpty {
                let label = NSMenuItem(title: "Pinned", action: nil, keyEquivalent: "")
                label.isEnabled = false
                menu.addItem(label)
                for item in pinned {
                    addClip(item, shortcutIndex: shortcutIndex, to: menu)
                    shortcutIndex += 1
                }
            }
            if !pinned.isEmpty && !recent.isEmpty { menu.addItem(.separator()) }
            for item in recent {
                addClip(item, shortcutIndex: shortcutIndex, to: menu)
                shortcutIndex += 1
            }
        }

        menu.addItem(.separator())
        let manage = NSMenuItem(title: "Clips Management…", action: #selector(showHistory), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)

        let privacy = NSMenuItem(title: "Private Mode", action: #selector(togglePrivateMode), keyEquivalent: "p")
        privacy.target = self
        privacy.state = settings.privateModeEnabled ? .on : .off
        menu.addItem(privacy)

        menu.addItem(.separator())
        let delete = NSMenuItem(title: "Delete All History…", action: #selector(deleteHistory), keyEquivalent: "")
        delete.target = self
        delete.isEnabled = !store.items.isEmpty
        menu.addItem(delete)
        menu.addItem(.separator())
        let preferences = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        let about = NSMenuItem(title: "About Copyclip", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Copyclip", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func addClip(_ item: ClipboardItem, shortcutIndex: Int, to menu: NSMenu) {
        let title = item.displayTitle.count > 48 ? String(item.displayTitle.prefix(47)) + "…" : item.displayTitle
        let entry = NSMenuItem(title: title, action: #selector(selectClip(_:)),
                               keyEquivalent: shortcutIndex < 10 ? String(shortcutIndex) : "")
        entry.target = self
        entry.representedObject = item.id.uuidString
        entry.toolTip = "Copied from \(item.sourceDisplayName)"
        if item.isPinned { entry.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned") }
        menu.addItem(entry)
    }

    @objc private func togglePrivateMode() {
        settings.privateModeEnabled.toggle()
        lastChangeCount = pasteboard.changeCount
        updateStatusIcon()
        updateMonitoring()
    }

    @objc private func selectClip(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let item = store.items.first(where: { $0.id.uuidString == idString }) else { return }
        store.restore(item, to: pasteboard)
        lastChangeCount = pasteboard.changeCount
    }

    @objc private func deleteHistory() {
        let alert = NSAlert()
        alert.messageText = "Delete all clipboard history?"
        alert.informativeText = "This removes saved clips from this Mac."
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { store.deleteAll() }
    }

    @objc private func showPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController(settings: settings) { [weak self] limit in
                self?.store.enforceLimit(limit)
            }
        }
        preferencesController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showHistory() {
        if historyController == nil {
            historyController = HistoryWindowController(store: store, historyLimit: { [weak self] in
                self?.settings.historyLimit ?? 0
            }) { [weak self] item in
                guard let self else { return }
                self.store.restore(item, to: self.pasteboard)
                self.lastChangeCount = self.pasteboard.changeCount
            }
        }
        historyController?.reload()
        historyController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyController?.focusSearch()
    }

    @objc private func showAbout() {
        if aboutWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "About Copyclip"
            let content = GlassStyle.prepare(window)
            GlassStyle.label("About Copyclip", in: content,
                             frame: NSRect(x: 32, y: 297, width: 350, height: 40),
                             size: 27, weight: .bold)
            GlassStyle.label("A little more room for what matters.", in: content,
                             frame: NSRect(x: 33, y: 272, width: 350, height: 20),
                             size: 13, color: .secondaryLabelColor)
            let card = GlassStyle.card(NSRect(x: 24, y: 30, width: 372, height: 224), in: content)
            let icon = NSImageView(frame: NSRect(x: 146, y: 125, width: 80, height: 80))
            icon.image = NSImage(named: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
            icon.imageScaling = .scaleProportionallyUpOrDown
            card.addSubview(icon)
            let title = GlassStyle.label("Copyclip", in: card,
                                         frame: NSRect(x: 24, y: 87, width: 324, height: 30),
                                         size: 22, weight: .bold)
            title.alignment = .center
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let subtitle = GlassStyle.label("Version \(version)  ·  Local clipboard history", in: card,
                                            frame: NSRect(x: 24, y: 61, width: 324, height: 19),
                                            size: 12, color: .secondaryLabelColor)
            subtitle.alignment = .center
            let detail = GlassStyle.label("Your clips stay on this Mac.", in: card,
                                          frame: NSRect(x: 24, y: 27, width: 324, height: 20), size: 13)
            detail.alignment = .center
            window.center()
            aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
