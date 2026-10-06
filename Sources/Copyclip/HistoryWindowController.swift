import AppKit

private final class ClipRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        path.fill()
    }
}

private final class ClipCellView: NSTableCellView {
    let titleField = NSTextField(labelWithString: "")
    let sourceField = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("ClipCell")
        titleField.frame = NSRect(x: 10, y: 26, width: 230, height: 19)
        titleField.autoresizingMask = [.width]
        titleField.lineBreakMode = .byTruncatingTail
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        addSubview(titleField)
        sourceField.frame = NSRect(x: 10, y: 8, width: 258, height: 16)
        sourceField.autoresizingMask = [.width]
        sourceField.lineBreakMode = .byTruncatingTail
        sourceField.font = .systemFont(ofSize: 11)
        sourceField.textColor = .secondaryLabelColor
        addSubview(sourceField)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
                                     NSSearchFieldDelegate, NSTextViewDelegate {
    private let store: ClipboardStore
    private let onCopy: (ClipboardItem) -> Void
    private let historyLimit: () -> Int
    private var filtered: [ClipboardItem] = []
    private var fittedTitleCache: [UUID: String] = [:]
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Clips Management"
        window.minSize = NSSize(width: 900, height: 570)
        super.init(window: window)
        buildUI()
        window.center()
        if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updateDetail()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func focusSearch() { window?.makeFirstResponder(search) }

    private func buildUI() {
        guard let window else { return }
        let content = GlassStyle.prepare(window)
        let width = content.bounds.width
        let height = content.bounds.height
        GlassStyle.label("Clips Management", in: content,
                         frame: NSRect(x: 32, y: height - 90, width: 570, height: 40),
                         size: 27, weight: .bold).autoresizingMask = [.minYMargin]
        GlassStyle.label("Find, organize, and reuse everything you copy.", in: content,
                         frame: NSRect(x: 33, y: height - 114, width: 570, height: 20),
                         size: 13, color: .secondaryLabelColor).autoresizingMask = [.minYMargin]

        let cardHeight = height - 163
        let listCard = GlassStyle.card(NSRect(x: 24, y: 24, width: 310, height: cardHeight),
                                       in: content, autoresizing: [.height])
        GlassStyle.sectionLabel("Your clips", in: listCard,
                                frame: NSRect(x: 20, y: cardHeight - 31, width: 250, height: 16))
            .autoresizingMask = [.minYMargin]
        search.frame = NSRect(x: 16, y: cardHeight - 76, width: 278, height: 34)
        search.placeholderString = "Search clips, names, or source apps"
        search.delegate = self
        search.autoresizingMask = [.minYMargin]
        listCard.addSubview(search)

        let listScroll = NSScrollView(frame: NSRect(x: 12, y: 58, width: 286, height: cardHeight - 143))
        listScroll.autoresizingMask = [.height]
        listScroll.hasVerticalScroller = true
        listScroll.verticalScrollElasticity = .none
        listScroll.horizontalScrollElasticity = .none
        listScroll.borderType = .noBorder
        listScroll.drawsBackground = false
        table.headerView = nil
        table.rowHeight = 54
        table.backgroundColor = .clear
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(copySelected)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.width = 282
        table.addTableColumn(column)
        listScroll.documentView = table
        listCard.addSubview(listScroll)

        let deleteAll = GlassStyle.button("Delete All History…", symbol: "trash", target: self,
                                          action: #selector(deleteAllHistory))
        deleteAll.frame = NSRect(x: 18, y: 16, width: 195, height: 32)
        listCard.addSubview(deleteAll)

        let previewWidth = width - 374
        let preview = GlassStyle.card(NSRect(x: 350, y: 24, width: previewWidth, height: cardHeight),
                                      in: content, autoresizing: [.width, .height])
        GlassStyle.sectionLabel("Clip preview", in: preview,
                                frame: NSRect(x: 24, y: cardHeight - 31, width: 320, height: 16))
            .autoresizingMask = [.minYMargin]
        detail.frame = NSRect(x: 24, y: cardHeight - 65, width: previewWidth - 48, height: 29)
        detail.autoresizingMask = [.width, .minYMargin]
        detail.font = .systemFont(ofSize: 20, weight: .semibold)
        detail.lineBreakMode = .byTruncatingMiddle
        preview.addSubview(detail)

        sourceDetail.frame = NSRect(x: 24, y: cardHeight - 89, width: previewWidth - 48, height: 20)
        sourceDetail.autoresizingMask = [.width, .minYMargin]
        sourceDetail.font = .systemFont(ofSize: 12)
        sourceDetail.textColor = .secondaryLabelColor
        sourceDetail.lineBreakMode = .byTruncatingMiddle
        preview.addSubview(sourceDetail)

        let editorFrame = NSRect(x: 20, y: 143, width: previewWidth - 40, height: cardHeight - 250)
        let editorWell = GlassWellView(frame: editorFrame)
        editorWell.autoresizingMask = [.width, .height]
        preview.addSubview(editorWell)
        textScroll.frame = editorFrame.insetBy(dx: 3, dy: 3)
        textScroll.autoresizingMask = [.width, .height]
        textScroll.borderType = .noBorder
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = true
        textScroll.verticalScrollElasticity = .none
        textScroll.hasHorizontalScroller = false
        textView.isRichText = false
        textView.isEditable = false
        textView.drawsBackground = false
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
        preview.addSubview(textScroll)

        imageView.frame = textScroll.frame
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = true
        preview.addSubview(imageView)

        note.frame = NSRect(x: 24, y: 116, width: previewWidth - 48, height: 19)
        note.autoresizingMask = [.width]
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        preview.addSubview(note)

        copyButton.title = "Copy to Clipboard"
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageLeading
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .large
        GlassStyle.primary(copyButton)
        copyButton.target = self
        copyButton.action = #selector(copySelected)
        copyButton.frame = NSRect(x: 20, y: 66, width: 170, height: 34)
        preview.addSubview(copyButton)

        saveButton.title = "Save Changes"
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .large
        saveButton.target = self
        saveButton.action = #selector(saveChanges)
        saveButton.frame = NSRect(x: 196, y: 66, width: 132, height: 34)
        preview.addSubview(saveButton)

        deleteButton.title = "Delete Clip"
        deleteButton.bezelStyle = .rounded
        deleteButton.controlSize = .large
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        deleteButton.frame = NSRect(x: 334, y: 66, width: 122, height: 34)
        preview.addSubview(deleteButton)

        pinButton.bezelStyle = .rounded
        pinButton.controlSize = .large
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        pinButton.frame = NSRect(x: 20, y: 20, width: 170, height: 34)
        preview.addSubview(pinButton)

        renameButton.title = "Rename…"
        renameButton.bezelStyle = .rounded
        renameButton.controlSize = .large
        renameButton.target = self
        renameButton.action = #selector(renameSelected)
        renameButton.frame = NSRect(x: 196, y: 20, width: 132, height: 34)
        preview.addSubview(renameButton)
    }

    func reload() {
        let selectedID = selectedItem?.id
        fittedTitleCache.removeAll(keepingCapacity: true)
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
            detail.stringValue = "Select a clip"
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
        detail.stringValue = item.displayTitle
        if let name = item.sourceAppName, let bundleID = item.sourceBundleIdentifier {
            sourceDetail.stringValue = "Copied \(date)  ·  \(name)  ·  \(bundleID)"
        } else {
            sourceDetail.stringValue = "Copied \(date)  ·  \(item.sourceDisplayName)"
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

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("ClipRow")
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? ClipRowView {
            return existing
        }
        let view = ClipRowView()
        view.identifier = identifier
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filtered[row]
        let identifier = NSUserInterfaceItemIdentifier("ClipCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ClipCellView
            ?? ClipCellView(frame: NSRect(x: 0, y: 0, width: 282, height: 54))
        if let cached = fittedTitleCache[item.id] {
            cell.titleField.stringValue = cached
        } else {
            let fullTitle = item.isPinned ? "📌  \(item.displayTitle)" : item.displayTitle
            let title = fittedTitle(fullTitle,
                                    font: cell.titleField.font ?? .systemFont(ofSize: 13, weight: .medium),
                                    width: 225)
            fittedTitleCache[item.id] = title
            cell.titleField.stringValue = title
        }
        cell.sourceField.stringValue = item.sourceDisplayName
        return cell
    }

    private func fittedTitle(_ title: String, font: NSFont, width: CGFloat) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let characters = Array(title.prefix(96))
        let clipped = String(characters)
        let hasMore = !title.dropFirst(96).isEmpty
        if !hasMore && (clipped as NSString).size(withAttributes: attributes).width <= width {
            return clipped
        }
        var lower = 0
        var upper = characters.count
        while lower < upper {
            let middle = (lower + upper + 1) / 2
            let candidate = String(characters.prefix(middle)) + "…"
            if (candidate as NSString).size(withAttributes: attributes).width <= width {
                lower = middle
            } else {
                upper = middle - 1
            }
        }
        return String(characters.prefix(lower)) + "…"
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
