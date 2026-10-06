import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let settings: AppSettings
    private let onHistoryLimitChanged: (Int) -> Void
    private let menuPopup = NSPopUpButton()
    private let historyPopup = NSPopUpButton()
    private let table = NSTableView()
    private let removeButton = NSButton()
    private let loginButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No apps ignored yet")

    init(settings: AppSettings, onHistoryLimitChanged: @escaping (Int) -> Void) {
        self.settings = settings
        self.onHistoryLimitChanged = onHistoryLimitChanged
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 650),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Copyclip Preferences"
        super.init(window: window)
        buildUI()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let window else { return }
        let content = GlassStyle.prepare(window)
        GlassStyle.label("Preferences", in: content, frame: NSRect(x: 32, y: 562, width: 500, height: 39),
                         size: 27, weight: .bold)
        GlassStyle.label("Make your clipboard work the way you do.", in: content,
                         frame: NSRect(x: 33, y: 536, width: 500, height: 22),
                         size: 13, color: .secondaryLabelColor)

        let general = GlassStyle.card(NSRect(x: 24, y: 345, width: 532, height: 170), in: content)
        GlassStyle.sectionLabel("History limits", in: general, frame: NSRect(x: 24, y: 137, width: 300, height: 17))
        GlassStyle.label("Clips shown in menu", in: general, frame: NSRect(x: 24, y: 98, width: 250, height: 23),
                         size: 14, weight: .medium)
        menuPopup.frame = NSRect(x: 308, y: 91, width: 200, height: 32)
        for count in AppSettings.menuLimitChoices {
            menuPopup.addItem(withTitle: "\(count) clips")
            menuPopup.lastItem?.tag = count
        }
        menuPopup.selectItem(withTag: settings.menuLimit)
        menuPopup.target = self
        menuPopup.action = #selector(menuLimitChanged)
        general.addSubview(menuPopup)

        GlassStyle.label("Clips kept in history", in: general, frame: NSRect(x: 24, y: 55, width: 250, height: 23),
                         size: 14, weight: .medium)
        historyPopup.frame = NSRect(x: 308, y: 48, width: 200, height: 32)
        for count in AppSettings.historyLimitChoices {
            historyPopup.addItem(withTitle: count == 0 ? "Unlimited" : "\(count) clips")
            historyPopup.lastItem?.tag = count
        }
        historyPopup.selectItem(withTag: settings.historyLimit)
        historyPopup.target = self
        historyPopup.action = #selector(historyLimitChanged)
        general.addSubview(historyPopup)

        GlassStyle.label("Lowering the limit removes the oldest unpinned clips.", in: general,
                         frame: NSRect(x: 25, y: 17, width: 480, height: 18),
                         size: 11, color: .secondaryLabelColor)

        let ignored = GlassStyle.card(NSRect(x: 24, y: 128, width: 532, height: 200), in: content)
        GlassStyle.sectionLabel("Ignored apps", in: ignored, frame: NSRect(x: 24, y: 168, width: 300, height: 17))
        GlassStyle.label("Copies made in these apps are not saved to history.", in: ignored,
                         frame: NSRect(x: 24, y: 144, width: 480, height: 20),
                         size: 12, color: .secondaryLabelColor)

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 53, width: 492, height: 82))
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10
        table.headerView = nil
        table.rowHeight = 30
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.width = 488
        table.addTableColumn(column)
        scroll.documentView = table
        ignored.addSubview(scroll)

        emptyLabel.frame = NSRect(x: 36, y: 84, width: 460, height: 20)
        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.isHidden = !settings.ignoredApps.isEmpty
        ignored.addSubview(emptyLabel)

        let addButton = GlassStyle.button("Add App…", symbol: "plus", target: self, action: #selector(addApp))
        addButton.frame = NSRect(x: 20, y: 13, width: 118, height: 31)
        ignored.addSubview(addButton)
        removeButton.title = "Remove"
        removeButton.bezelStyle = .rounded
        removeButton.controlSize = .large
        removeButton.target = self
        removeButton.action = #selector(removeApp)
        removeButton.frame = NSRect(x: 144, y: 13, width: 98, height: 31)
        removeButton.isEnabled = false
        ignored.addSubview(removeButton)

        let startup = GlassStyle.card(NSRect(x: 24, y: 32, width: 532, height: 80), in: content)
        GlassStyle.sectionLabel("Startup", in: startup, frame: NSRect(x: 24, y: 54, width: 300, height: 16))
        loginButton.title = "Launch Copyclip at login"
        loginButton.setButtonType(.switch)
        loginButton.target = self
        loginButton.action = #selector(toggleLogin)
        loginButton.frame = NSRect(x: 24, y: 18, width: 360, height: 28)
        loginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
        startup.addSubview(loginButton)
    }

    @objc private func menuLimitChanged() { settings.menuLimit = menuPopup.selectedTag() }

    @objc private func historyLimitChanged() {
        settings.historyLimit = historyPopup.selectedTag()
        onHistoryLimitChanged(settings.historyLimit)
    }

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to ignore"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if settings.addIgnoredApp(at: url) {
            table.reloadData()
            emptyLabel.isHidden = !settings.ignoredApps.isEmpty
        }
        else {
            let alert = NSAlert()
            alert.messageText = "This app cannot be ignored"
            alert.informativeText = "Choose a macOS app with a bundle identifier."
            alert.runModal()
        }
    }

    @objc private func removeApp() {
        let apps = settings.ignoredApps
        guard table.selectedRow >= 0, table.selectedRow < apps.count else { return }
        settings.removeIgnoredApp(bundleID: apps[table.selectedRow].bundleID)
        table.reloadData()
        emptyLabel.isHidden = !settings.ignoredApps.isEmpty
        removeButton.isEnabled = false
    }

    @objc private func toggleLogin() {
        do {
            if loginButton.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginButton.state = loginButton.state == .on ? .off : .on
            NSAlert(error: error).runModal()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { settings.ignoredApps.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = settings.ignoredApps[row]
        let label = NSTextField(labelWithString: "\(app.name)  ·  \(app.bundleID)")
        label.frame = NSRect(x: 8, y: 3, width: tableView.bounds.width - 16, height: 20)
        label.autoresizingMask = [.width]
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = table.selectedRow >= 0
    }
}
