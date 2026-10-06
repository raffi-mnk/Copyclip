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

    init(settings: AppSettings, onHistoryLimitChanged: @escaping (Int) -> Void) {
        self.settings = settings
        self.onHistoryLimitChanged = onHistoryLimitChanged
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Copyclip Preferences"
        super.init(window: window)
        buildUI()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        addLabel("General", x: 24, y: 426, width: 470, height: 25, bold: true, to: content)
        addLabel("Choose how much appears in the menu and how much stays on this Mac.",
                 x: 24, y: 399, width: 470, height: 20, to: content).textColor = .secondaryLabelColor

        addLabel("Clips shown in menu", x: 24, y: 355, width: 240, height: 22, to: content)
        menuPopup.frame = NSRect(x: 285, y: 348, width: 205, height: 30)
        for count in AppSettings.menuLimitChoices {
            menuPopup.addItem(withTitle: "\(count) clips")
            menuPopup.lastItem?.tag = count
        }
        menuPopup.selectItem(withTag: settings.menuLimit)
        menuPopup.target = self
        menuPopup.action = #selector(menuLimitChanged)
        content.addSubview(menuPopup)

        addLabel("Clips kept in history", x: 24, y: 309, width: 240, height: 22, to: content)
        historyPopup.frame = NSRect(x: 285, y: 302, width: 205, height: 30)
        for count in AppSettings.historyLimitChoices {
            historyPopup.addItem(withTitle: count == 0 ? "Unlimited" : "\(count) clips")
            historyPopup.lastItem?.tag = count
        }
        historyPopup.selectItem(withTag: settings.historyLimit)
        historyPopup.target = self
        historyPopup.action = #selector(historyLimitChanged)
        content.addSubview(historyPopup)

        let explanation = addLabel("Lowering this limit removes the oldest unpinned clips.",
                                   x: 24, y: 275, width: 470, height: 19, to: content)
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .secondaryLabelColor

        addLabel("Ignored apps", x: 24, y: 239, width: 470, height: 24, bold: true, to: content)
        let ignoredDetail = addLabel("Copies made in these apps are not saved to history.",
                                     x: 24, y: 216, width: 470, height: 18, to: content)
        ignoredDetail.textColor = .secondaryLabelColor

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 88, width: 466, height: 119))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        table.headerView = nil
        table.rowHeight = 26
        table.dataSource = self
        table.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.width = 460
        table.addTableColumn(column)
        scroll.documentView = table
        content.addSubview(scroll)

        let addButton = NSButton(title: "Add App…", target: self, action: #selector(addApp))
        addButton.frame = NSRect(x: 24, y: 52, width: 100, height: 28)
        content.addSubview(addButton)
        removeButton.title = "Remove"
        removeButton.target = self
        removeButton.action = #selector(removeApp)
        removeButton.frame = NSRect(x: 128, y: 52, width: 90, height: 28)
        removeButton.isEnabled = false
        content.addSubview(removeButton)

        loginButton.title = "Launch Copyclip at login"
        loginButton.setButtonType(.switch)
        loginButton.target = self
        loginButton.action = #selector(toggleLogin)
        loginButton.frame = NSRect(x: 24, y: 17, width: 280, height: 24)
        loginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
        content.addSubview(loginButton)
    }

    @discardableResult
    private func addLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                          bold: Bool = false, to content: NSView) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: width, height: height)
        if bold { label.font = .boldSystemFont(ofSize: 15) }
        content.addSubview(label)
        return label
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
        if settings.addIgnoredApp(at: url) { table.reloadData() }
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
