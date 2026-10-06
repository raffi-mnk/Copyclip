import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ClipboardStore()
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = 0
    private var timer: Timer?
    private var statusItem: NSStatusItem!
    private var preferencesWindow: NSWindow?
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Copyclip")
            button.toolTip = "Copyclip"
        }
        menu.delegate = self
        statusItem.menu = menu
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    private func checkClipboard() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        _ = store.capture(from: pasteboard)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        checkClipboard()
        menu.removeAllItems()
        let heading = NSMenuItem(title: "Select the clip you want to add to your clipboard", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())

        if store.items.isEmpty {
            let empty = NSMenuItem(title: "No clips yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (index, item) in store.items.prefix(20).enumerated() {
                let title = item.preview.count > 48 ? String(item.preview.prefix(47)) + "…" : item.preview
                let entry = NSMenuItem(title: title, action: #selector(selectClip(_:)), keyEquivalent: index < 10 ? String(index) : "")
                entry.target = self
                entry.representedObject = item.id.uuidString
                menu.addItem(entry)
            }
            let more = NSMenuItem(title: "Search All History…", action: #selector(showHistory), keyEquivalent: "")
            more.target = self
            menu.addItem(more)
        }

        menu.addItem(.separator())
        let delete = NSMenuItem(title: "Delete All History…", action: #selector(deleteHistory), keyEquivalent: "")
        delete.target = self
        delete.isEnabled = !store.items.isEmpty
        menu.addItem(delete)
        menu.addItem(.separator())
        let preferences = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Copyclip", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
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
        if preferencesWindow == nil { preferencesWindow = makePreferencesWindow() }
        preferencesWindow?.center()
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePreferencesWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 190),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Copyclip Preferences"
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        let title = NSTextField(labelWithString: "Clipboard history")
        title.font = .boldSystemFont(ofSize: 16)
        title.frame = NSRect(x: 24, y: 132, width: 370, height: 24)
        content.addSubview(title)

        let detail = NSTextField(wrappingLabelWithString: "Clips are saved locally and remain available after Copyclip or your Mac restarts.")
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 24, y: 77, width: 370, height: 46)
        content.addSubview(detail)

        let login = NSButton(checkboxWithTitle: "Launch Copyclip at login", target: self, action: #selector(toggleLogin(_:)))
        login.frame = NSRect(x: 24, y: 34, width: 370, height: 26)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        content.addSubview(login)
        return window
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            sender.state = sender.state == .on ? .off : .on
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func showHistory() {
        let controller = HistoryWindowController(store: store) { [weak self] item in
            guard let self else { return }
            self.store.restore(item, to: self.pasteboard)
            self.lastChangeCount = self.pasteboard.changeCount
        }
        historyController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var historyController: HistoryWindowController?

    @objc private func quit() { NSApp.terminate(nil) }
}

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let store: ClipboardStore
    private let onSelect: (ClipboardItem) -> Void
    private var filtered: [ClipboardItem] = []
    private let table = NSTableView()

    init(store: ClipboardStore, onSelect: @escaping (ClipboardItem) -> Void) {
        self.store = store
        self.onSelect = onSelect
        self.filtered = store.items
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Clipboard History"
        super.init(window: window)
        buildUI()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let search = NSSearchField(frame: NSRect(x: 20, y: content.bounds.height - 54, width: content.bounds.width - 40, height: 30))
        search.placeholderString = "Search clips"
        search.delegate = self
        search.autoresizingMask = [.width, .minYMargin]
        content.addSubview(search)

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: content.bounds.width - 40, height: content.bounds.height - 88))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        table.headerView = nil
        table.rowHeight = 36
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(chooseSelected)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        scroll.documentView = table
        content.addSubview(scroll)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let search = obj.object as? NSSearchField else { return }
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = query.isEmpty ? store.items : store.items.filter { $0.preview.localizedCaseInsensitiveContains(query) }
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: filtered[row].preview)
        label.frame = NSRect(x: 8, y: 3, width: tableView.bounds.width - 16, height: 30)
        label.autoresizingMask = [.width]
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 14)
        return label
    }

    @objc private func chooseSelected() {
        guard table.selectedRow >= 0, table.selectedRow < filtered.count else { return }
        onSelect(filtered[table.selectedRow])
        close()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
