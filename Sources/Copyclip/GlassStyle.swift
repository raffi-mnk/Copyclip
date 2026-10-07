import AppKit

private final class GlassBackdropOverlay: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.35).setFill()
        dirtyRect.fill()
    }
}

final class GlassWellView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let outline = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(roundedRect: outline, xRadius: 12, yRadius: 12)
        NSColor.controlBackgroundColor.withAlphaComponent(0.16).setFill()
        path.fill()
        path.lineWidth = 1.5
        NSColor.labelColor.withAlphaComponent(0.28).setStroke()
        path.stroke()
    }
}

final class GlassRowView: NSTableRowView {
    static func make(in tableView: NSTableView, owner: Any?) -> GlassRowView {
        let identifier = NSUserInterfaceItemIdentifier("GlassRow")
        if let existing = tableView.makeView(withIdentifier: identifier, owner: owner) as? GlassRowView {
            return existing
        }
        let view = GlassRowView()
        view.identifier = identifier
        return view
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        path.fill()
    }
}

enum GlassStyle {
    static func prepare(_ window: NSWindow) -> NSView {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear

        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        let frost = NSVisualEffectView(frame: content.bounds)
        frost.material = .underWindowBackground
        frost.blendingMode = .behindWindow
        frost.state = .active
        frost.autoresizingMask = [.width, .height]
        content.addSubview(frost)
        let tint = GlassBackdropOverlay(frame: content.bounds)
        tint.autoresizingMask = [.width, .height]
        content.addSubview(tint)
        window.contentView = content
        return content
    }

    static func card(_ frame: NSRect, in parent: NSView,
                     autoresizing: NSView.AutoresizingMask = []) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.style = .regular
            glass.cornerRadius = 18
            glass.autoresizingMask = autoresizing
            glass.contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
            parent.addSubview(glass)
            let content = NSView(frame: frame)
            content.autoresizingMask = autoresizing
            parent.addSubview(content)
            return content
        }

        let card = NSVisualEffectView(frame: frame)
        card.material = .popover
        card.blendingMode = .withinWindow
        card.state = .active
        card.autoresizingMask = autoresizing
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
        parent.addSubview(card)
        let content = NSView(frame: frame)
        content.autoresizingMask = autoresizing
        parent.addSubview(content)
        return content
    }

    @discardableResult
    static func label(_ text: String, in parent: NSView, frame: NSRect,
                      size: CGFloat = 13, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        parent.addSubview(label)
        return label
    }

    static func button(_ title: String, symbol: String? = nil,
                       target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
        }
        return button
    }

    static func primary(_ button: NSButton) {
        button.bezelColor = .controlAccentColor
        button.contentTintColor = .white
    }

    @discardableResult
    static func sectionLabel(_ text: String, in parent: NSView, frame: NSRect) -> NSTextField {
        let label = self.label(text.uppercased(), in: parent, frame: frame,
                               size: 10, weight: .semibold, color: .secondaryLabelColor)
        label.toolTip = text
        return label
    }
}
