import AppKit

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
                                     NSSearchFieldDelegate, NSTextViewDelegate {
    private let store: ClipboardStore
    private let onCopy: (ClipboardItem) -> Void
    private let historyLimit: () -> Int
    private var filtered: [ClipboardItem] = []
    private let table = NSTableView()
    private let search = NSSearchField()
    private let detail = NSTextField(labelWithString: "")
    private let sourceDetail = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let textScroll = NSScrollView()
    private let imageView = NSImageView()
    private let copyButton = NSButton()
    private let saveButton = NSButton()
    private let deleteButton = NSButton()
    private let pinButton = NSButton()
    private let renameButton = NSButton()
    private let note = NSTextField(labelWithString: "")
    private var originalText: String?

    init(store: ClipboardStore, historyLimit: @escaping () -> Int,
         onCopy: @escaping (ClipboardItem) -> Void) {
        self.store = store
        self.historyLimit = historyLimit
        self.onCopy = onCopy
        self.filtered = store.items
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 550),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Clips Management"
        window.minSize = NSSize(width: 780, height: 430)
        super.init(window: window)
        buildUI()
        window.center()
        if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updateDetail()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func focusSearch() { window?.makeFirstResponder(search) }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let width = content.bounds.width
        let height = content.bounds.height

        search.frame = NSRect(x: 20, y: height - 54, width: width - 40, height: 30)
        search.placeholderString = "Search clips, names, or source apps"
        search.delegate = self
        search.autoresizingMask = [.width, .minYMargin]
        content.addSubview(search)

        let listScroll = NSScrollView(frame: NSRect(x: 20, y: 70, width: 300, height: height - 136))
        listScroll.autoresizingMask = [.height]
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .bezelBorder
        table.headerView = nil
        table.rowHeight = 37
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(copySelected)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.width = 296
        table.addTableColumn(column)
        listScroll.documentView = table
        content.addSubview(listScroll)

        detail.frame = NSRect(x: 340, y: height - 93, width: width - 360, height: 25)
        detail.autoresizingMask = [.width, .minYMargin]
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        content.addSubview(detail)

        sourceDetail.frame = NSRect(x: 340, y: height - 119, width: width - 360, height: 21)
        sourceDetail.autoresizingMask = [.width, .minYMargin]
        sourceDetail.font = .systemFont(ofSize: 12)
        sourceDetail.textColor = .secondaryLabelColor
        sourceDetail.lineBreakMode = .byTruncatingMiddle
        content.addSubview(sourceDetail)

        textScroll.frame = NSRect(x: 340, y: 145, width: width - 360, height: height - 280)
        textScroll.autoresizingMask = [.width, .height]
        textScroll.borderType = .bezelBorder
        textScroll.hasVerticalScroller = true
        textScroll.hasHorizontalScroller = false
        textView.isRichText = false
        textView.isEditable = false
        textView.font = .systemFont(ofSize: 14)
        textView.frame = NSRect(origin: .zero, size: textScroll.contentSize)
        textView.minSize = NSSize(width: 0, height: textScroll.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.delegate = self
        textScroll.documentView = textView
        content.addSubview(textScroll)

        imageView.frame = textScroll.frame
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = true
        content.addSubview(imageView)

        note.frame = NSRect(x: 340, y: 116, width: width - 360, height: 21)
        note.autoresizingMask = [.width]
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        content.addSubview(note)

        copyButton.title = "Copy to Clipboard"
        copyButton.target = self
        copyButton.action = #selector(copySelected)
        copyButton.frame = NSRect(x: 340, y: 70, width: 145, height: 30)
        content.addSubview(copyButton)

        saveButton.title = "Save Changes"
        saveButton.target = self
        saveButton.action = #selector(saveChanges)
        saveButton.frame = NSRect(x: 490, y: 70, width: 125, height: 30)
        content.addSubview(saveButton)

        deleteButton.title = "Delete Clip"
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        deleteButton.frame = NSRect(x: 620, y: 70, width: 110, height: 30)
        content.addSubview(deleteButton)

        pinButton.target = self
        pinButton.action = #selector(togglePin)
        pinButton.frame = NSRect(x: 340, y: 29, width: 135, height: 30)
        content.addSubview(pinButton)

        renameButton.title = "Rename…"
        renameButton.target = self
        renameButton.action = #selector(renameSelected)
        renameButton.frame = NSRect(x: 480, y: 29, width: 105, height: 30)
        content.addSubview(renameButton)

        let deleteAll = NSButton(title: "Delete All History…", target: self, action: #selector(deleteAllHistory))
        deleteAll.frame = NSRect(x: 20, y: 25, width: 165, height: 30)
        content.addSubview(deleteAll)
    }

    func reload() {
        let selectedID = selectedItem?.id
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = query.isEmpty ? store.items : store.items.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.preview.localizedCaseInsensitiveContains(query)
                || $0.sourceDisplayName.localizedCaseInsensitiveContains(query)
                || ($0.sourceBundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
        table.reloadData()
        if let selectedID, let index = filtered.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !filtered.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateDetail()
    }

    private var selectedItem: ClipboardItem? {
        guard table.selectedRow >= 0, table.selectedRow < filtered.count else { return nil }
        return filtered[table.selectedRow]
    }

    private func updateDetail() {
        guard let item = selectedItem else {
            detail.stringValue = "Select a clip to inspect it"
            sourceDetail.stringValue = ""
            textView.string = ""
            textView.isEditable = false
            imageView.isHidden = true
            textScroll.isHidden = false
            note.stringValue = ""
            copyButton.isEnabled = false
            saveButton.isEnabled = false
            deleteButton.isEnabled = false
            pinButton.isEnabled = false
            renameButton.isEnabled = false
            originalText = nil
            return
        }

        let date = DateFormatter.localizedString(from: item.copiedAt, dateStyle: .medium, timeStyle: .short)
        detail.stringValue = "Copied \(date)"
        if let name = item.sourceAppName, let bundleID = item.sourceBundleIdentifier {
            sourceDetail.stringValue = "Source: \(name)  ·  \(bundleID)"
        } else {
            sourceDetail.stringValue = "Source: \(item.sourceDisplayName)"
        }
        copyButton.isEnabled = true
        deleteButton.isEnabled = true
        pinButton.isEnabled = true
        pinButton.title = item.isPinned ? "Unpin from Menu" : "Pin to Menu"
        renameButton.isEnabled = true

        if let text = item.editableText {
            originalText = text
            textView.string = text
            textView.isEditable = true
            textScroll.isHidden = false
            imageView.isHidden = true
            note.stringValue = "Editing saves plain text and removes formatting from this clip."
            saveButton.isEnabled = false
        } else if let image = image(for: item) {
            originalText = nil
            imageView.image = image
            imageView.isHidden = false
            textScroll.isHidden = true
            note.stringValue = "This image can be copied or deleted."
            saveButton.isEnabled = false
        } else {
            originalText = nil
            textView.string = item.preview
            textView.isEditable = false
            textScroll.isHidden = false
            imageView.isHidden = true
            note.stringValue = "This clip can be copied or deleted."
            saveButton.isEnabled = false
        }
    }

    private func image(for item: ClipboardItem) -> NSImage? {
        let imageTypes = ["public.png", "public.tiff", "public.jpeg", "com.compuserve.gif"]
        for representation in item.representations where imageTypes.contains(representation.type) {
            if let image = NSImage(data: representation.data) { return image }
        }
        return nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filtered[row]
        let label = NSTextField(labelWithString: item.isPinned ? "📌  \(item.displayTitle)" : item.displayTitle)
        label.frame = NSRect(x: 8, y: 5, width: tableView.bounds.width - 16, height: 26)
        label.autoresizingMask = [.width]
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 13)
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateDetail() }
    func controlTextDidChange(_ obj: Notification) { reload() }

    func textDidChange(_ notification: Notification) {
        saveButton.isEnabled = selectedItem?.editableText != nil && textView.string != originalText
    }

    @objc private func copySelected() {
        guard let item = selectedItem else { return }
        onCopy(item)
    }

    @objc private func saveChanges() {
        guard let item = selectedItem, item.editableText != nil else { return }
        store.editText(id: item.id, to: textView.string)
    }

    @objc private func deleteSelected() {
        guard let item = selectedItem else { return }
        store.delete(id: item.id)
    }

    @objc private func togglePin() {
        guard let item = selectedItem else { return }
        store.setPinned(id: item.id, to: !item.isPinned)
        if item.isPinned { store.enforceLimit(historyLimit()) }
    }

    @objc private func renameSelected() {
        guard let item = selectedItem else { return }
        let alert = NSAlert()
        alert.messageText = "Rename clip"
        alert.informativeText = "This changes its label in the menu and history, not the copied content."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 25))
        field.stringValue = item.customTitle ?? item.preview
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.rename(id: item.id, to: field.stringValue)
    }

    @objc private func deleteAllHistory() {
        guard !store.items.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Delete all clipboard history?"
        alert.informativeText = "This removes every saved clip from this Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.deleteAll() }
    }
}
