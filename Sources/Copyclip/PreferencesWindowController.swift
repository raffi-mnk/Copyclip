import AppKit
import ServiceManagement
import UniformTypeIdentifiers

private final class IgnoredAppCellView: NSTableCellView {
    let iconView = NSImageView()
    let nameField = NSTextField(labelWithString: "")
    let bundleField = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("IgnoredAppCell")
        iconView.frame = NSRect(x: 12, y: 8, width: 30, height: 30)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        nameField.frame = NSRect(x: 52, y: 24, width: frame.width - 64, height: 18)
        nameField.autoresizingMask = [.width]
        nameField.lineBreakMode = .byTruncatingTail
        nameField.font = .systemFont(ofSize: 13, weight: .medium)
        addSubview(nameField)
        bundleField.frame = NSRect(x: 52, y: 6, width: frame.width - 64, height: 16)
        bundleField.autoresizingMask = [.width]
        bundleField.lineBreakMode = .byTruncatingMiddle
        bundleField.font = .systemFont(ofSize: 11)
        bundleField.textColor = .secondaryLabelColor
        addSubview(bundleField)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class PreferencesWindowController: NSWindowController, NSWindowDelegate,
                                         NSTableViewDataSource, NSTableViewDelegate {
    private let settings: AppSettings
    private let onHistoryLimitChanged: (Int) -> Void
    private let menuPopup = NSPopUpButton()
    private let historyPopup = NSPopUpButton()
    private let table = NSTableView()
    private let removeButton = NSButton()
    private let loginButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No apps ignored yet")
    private var iconCache: [String: NSImage] = [:]

    init(settings: AppSettings, onHistoryLimitChanged: @escaping (Int) -> Void) {
        self.settings = settings
        self.onHistoryLimitChanged = onHistoryLimitChanged
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 700),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Copyclip Preferences"
        super.init(window: window)
        window.delegate = self
        buildUI()
        window.center()
    }

    // Login items can be changed in System Settings, so re-read the status whenever the window comes forward.
    func windowDidBecomeKey(_ notification: Notification) { syncLoginButton() }

    private func syncLoginButton() {
        loginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let window else { return }
        let content = GlassStyle.prepare(window)
        GlassStyle.label("Preferences", in: content, frame: NSRect(x: 32, y: 612, width: 500, height: 39),
                         size: 27, weight: .bold)
        GlassStyle.label("Make your clipboard work the way you do.", in: content,
                         frame: NSRect(x: 33, y: 586, width: 500, height: 22),
                         size: 13, color: .secondaryLabelColor)

        let general = GlassStyle.card(NSRect(x: 24, y: 395, width: 532, height: 170), in: content)
        GlassStyle.sectionLabel("History limits", in: general, frame: NSRect(x: 24, y: 137, width: 300, height: 17))
        GlassStyle.label("Clips shown in menu", in: general, frame: NSRect(x: 24, y: 98, width: 250, height: 18),
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

        GlassStyle.label("Clips kept in history", in: general, frame: NSRect(x: 24, y: 55, width: 250, height: 18),
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

        let ignored = GlassStyle.card(NSRect(x: 24, y: 128, width: 532, height: 250), in: content)
        GlassStyle.sectionLabel("Ignored apps", in: ignored, frame: NSRect(x: 24, y: 217, width: 300, height: 17))
        GlassStyle.label("Copies made in these apps are not saved to history.", in: ignored,
                         frame: NSRect(x: 24, y: 194, width: 480, height: 20),
                         size: 12, color: .secondaryLabelColor)

        let scroll = NSScrollView(frame: NSRect(x: 12, y: 56, width: 508, height: 130))
        scroll.hasVerticalScroller = true
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        table.headerView = nil
        table.style = .plain
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.rowHeight = 46
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        scroll.documentView = table
        table.sizeLastColumnToFit()
        ignored.addSubview(scroll)

        emptyLabel.frame = NSRect(x: 36, y: 111, width: 460, height: 20)
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

        let startup = GlassStyle.card(NSRect(x: 24, y: 26, width: 532, height: 86), in: content)
        GlassStyle.sectionLabel("Startup", in: startup, frame: NSRect(x: 24, y: 53, width: 300, height: 17))
        loginButton.title = "Launch Copyclip at login"
        loginButton.setButtonType(.switch)
        loginButton.target = self
        loginButton.action = #selector(toggleLogin)
        loginButton.frame = NSRect(x: 24, y: 18, width: 360, height: 28)
        syncLoginButton()
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
        let service = SMAppService.mainApp
        do {
            if loginButton.state == .on { try service.register() }
            else { try service.unregister() }
        } catch {
            syncLoginButton()
            NSAlert(error: error).runModal()
            return
        }
        syncLoginButton()
        // Registering can succeed while macOS still waits for the user to allow the item in System Settings.
        guard service.status == .requiresApproval else { return }
        let alert = NSAlert()
        alert.messageText = "Allow Copyclip to open at login"
        alert.informativeText = "macOS needs your approval. Turn on Copyclip in Login Items in System Settings."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { settings.ignoredApps.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = settings.ignoredApps[row]
        let identifier = NSUserInterfaceItemIdentifier("IgnoredAppCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? IgnoredAppCellView
            ?? IgnoredAppCellView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 46))
        cell.iconView.image = icon(for: app.bundleID)
        cell.nameField.stringValue = app.name
        cell.bundleField.stringValue = app.bundleID
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        GlassRowView.make(in: tableView, owner: self)
    }

    private func icon(for bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        iconCache[bundleID] = icon
        return icon
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = table.selectedRow >= 0
    }
}
