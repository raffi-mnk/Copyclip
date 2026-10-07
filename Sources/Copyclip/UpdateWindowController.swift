import AppKit

/// The glass window that shows each step of an update: a header, an optional body, and buttons.
final class UpdateWindowController: NSWindowController, NSWindowDelegate {
    struct Action {
        let title: String
        var isPrimary = false
        var isCancel = false
        /// Places the button on the left, away from the main choices.
        var alignsLeft = false
        let handler: () -> Void
    }

    enum Body {
        case none
        /// Release notes as HTML.
        case notes(String)
        /// Progress from 0 to 1, or nil while the length of the step is unknown.
        case progress(Double?, String)
    }

    private static let width: CGFloat = 480
    private var actions: [Action] = []
    private var onClose: (() -> Void)?
    private var container: NSView?
    private var progressIndicator: NSProgressIndicator?
    private var progressLabel: NSTextField?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Copyclip Update"
        super.init(window: window)
        _ = GlassStyle.prepare(window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Replaces the window's contents and brings it forward. `onClose` runs if the user closes the window.
    func show(title: String, message: String, body: Body = .none, actions: [Action], onClose: (() -> Void)? = nil) {
        guard let window, let content = window.contentView else { return }
        container?.removeFromSuperview()
        progressIndicator = nil
        progressLabel = nil
        self.actions = actions
        self.onClose = onClose

        let width = Self.width
        let bodyHeight: CGFloat
        switch body {
        case .none: bodyHeight = 0
        case .notes: bodyHeight = 262
        case .progress: bodyHeight = 64
        }
        let bodyY: CGFloat = actions.isEmpty ? 24 : 72
        let headerY = bodyHeight > 0 ? bodyY + bodyHeight + 20 : bodyY
        let height = headerY + 64 + 38

        // Grow or shrink from the top edge so the window doesn't jump between steps.
        let top = window.isVisible ? window.frame.maxY : nil
        let origin = top.map { NSPoint(x: window.frame.minX, y: $0 - height) } ?? window.frame.origin
        window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)),
                        display: true, animate: window.isVisible)

        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
        container = view

        let icon = NSImageView(frame: NSRect(x: 24, y: headerY, width: 64, height: 64))
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(icon)
        GlassStyle.label(title, in: view, frame: NSRect(x: 104, y: headerY + 34, width: width - 128, height: 24),
                         size: 17, weight: .bold)
        let messageField = NSTextField(wrappingLabelWithString: message)
        messageField.frame = NSRect(x: 104, y: headerY - 2, width: width - 128, height: 34)
        messageField.font = .systemFont(ofSize: 12)
        messageField.textColor = .secondaryLabelColor
        messageField.cell?.truncatesLastVisibleLine = true
        view.addSubview(messageField)

        let bodyFrame = NSRect(x: 20, y: bodyY, width: width - 40, height: bodyHeight)
        switch body {
        case .none:
            break
        case .notes(let html):
            addNotes(html, in: GlassStyle.card(bodyFrame, in: view))
        case .progress(let value, let label):
            addProgress(in: GlassStyle.card(bodyFrame, in: view))
            updateProgress(value, label: label)
        }
        addButtons(to: view, width: width)

        if !window.isVisible { window.center() }
        showWindow(nil)
        // A menu bar app isn't active, so bring it forward or the window opens behind other apps.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updateProgress(_ value: Double?, label: String) {
        guard let progressIndicator else { return }
        progressIndicator.isIndeterminate = value == nil
        if let value {
            progressIndicator.doubleValue = min(max(value, 0), 1)
        } else {
            progressIndicator.startAnimation(nil)
        }
        progressLabel?.stringValue = label
    }

    /// Closes the window without running its close handler.
    func dismiss() {
        onClose = nil
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        let handler = onClose
        onClose = nil
        handler?()
    }

    private func addNotes(_ html: String, in card: NSView) {
        GlassStyle.sectionLabel("What's new", in: card,
                                frame: NSRect(x: 18, y: card.bounds.height - 30, width: 300, height: 16))
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 8, width: card.bounds.width - 16,
                                                height: card.bounds.height - 44))
        scroll.hasVerticalScroller = true
        scroll.verticalScrollElasticity = .none
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let textView = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 2)
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(Self.notes(from: html))
        scroll.documentView = textView
        card.addSubview(scroll)
    }

    private func addProgress(in card: NSView) {
        let indicator = NSProgressIndicator(frame: NSRect(x: 20, y: 34, width: card.bounds.width - 40, height: 12))
        indicator.style = .bar
        indicator.minValue = 0
        indicator.maxValue = 1
        card.addSubview(indicator)
        progressIndicator = indicator
        progressLabel = GlassStyle.label("", in: card, frame: NSRect(x: 20, y: 12, width: card.bounds.width - 40, height: 16),
                                         size: 11, color: .secondaryLabelColor)
    }

    private func addButtons(to view: NSView, width: CGFloat) {
        var right = width - 20
        var left: CGFloat = 20
        // The primary action goes on the far right, as in standard macOS dialogs.
        for (index, action) in actions.enumerated().reversed() {
            let button = GlassStyle.button(action.title, target: self, action: #selector(buttonPressed(_:)))
            button.tag = index
            if action.isPrimary {
                GlassStyle.primary(button)
                button.keyEquivalent = "\r"
            } else if action.isCancel {
                button.keyEquivalent = "\u{1b}"
            }
            let buttonWidth = max(96, button.intrinsicContentSize.width + 16)
            if action.alignsLeft {
                button.frame = NSRect(x: left, y: 20, width: buttonWidth, height: 32)
                left += buttonWidth + 8
            } else {
                right -= buttonWidth
                button.frame = NSRect(x: right, y: 20, width: buttonWidth, height: 32)
                right -= 8
            }
            view.addSubview(button)
        }
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag].handler()
    }

    /// Renders the appcast's release notes, which release_helper.py writes as <p> and <ul><li> with <b> and <code>.
    static func notes(from html: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = matches(of: "<(li|p)>(.*?)</\\1>", in: html)
        for (index, block) in blocks.enumerated() {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 6
            var text = inline(block[2])
            if block[1] == "li" {
                // A hanging indent keeps wrapped lines aligned after the bullet.
                style.headIndent = 16
                style.tabStops = [NSTextTab(textAlignment: .left, location: 16)]
                let bullet = NSMutableAttributedString(string: "•\t", attributes: [.font: NSFont.systemFont(ofSize: 13)])
                bullet.append(text)
                text = bullet
            }
            if index < blocks.count - 1 { text.append(NSAttributedString(string: "\n")) }
            text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
            result.append(text)
        }
        if blocks.isEmpty { result.append(inline(html)) }
        result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: result.length))
        return result
    }

    private static func inline(_ html: String) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for part in matches(of: "<(b|code)>(.*?)</\\1>|([^<]+)|<[^>]*>", in: html) {
            let font: NSFont
            switch part[1] {
            case "b": font = .systemFont(ofSize: 13, weight: .semibold)
            case "code": font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            default: font = .systemFont(ofSize: 13)
            }
            let text = part[1].isEmpty ? part[3] : part[2]
            result.append(NSAttributedString(string: unescape(text), attributes: [.font: font]))
        }
        return result
    }

    /// Returns each match's capture groups, with "" for groups that didn't take part.
    private static func matches(of pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            (0..<match.numberOfRanges).map { group in
                let range = match.range(at: group)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
        }
    }

    private static func unescape(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#x27;", "'"), ("&#39;", "'"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
