// Renders the DMG window background: swift dmg-background.swift <output.png> <scale> <version> <logo.png>
// Layout values are in points from the top-left, matching the icon positions in build-dmg.sh.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 5, let scale = Double(arguments[2]) else {
    print("usage: dmg-background.swift <output.png> <scale> <version> <logo.png>")
    exit(1)
}
let version = arguments[3]
let logo = NSImage(contentsOfFile: arguments[4])
let width = 640.0, height = 500.0

guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale),
                                    pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
bitmap.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high

/// Converts top-left based coordinates to AppKit's bottom-left coordinates.
func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> NSRect {
    NSRect(x: x, y: height - y - h, width: w, height: h)
}

func point(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: x, y: height - y) }

func attributed(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                color: NSColor = NSColor(white: 0.1, alpha: 1),
                alignment: NSTextAlignment = .left, kern: CGFloat = 0) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineSpacing = 2
    return NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style,
        .kern: kern
    ])
}

/// Draws wrapped text and returns the height it used.
@discardableResult
func draw(_ string: NSAttributedString, in frame: NSRect) -> Double {
    string.draw(with: frame, options: [.usesLineFragmentOrigin])
    return string.boundingRect(with: NSSize(width: frame.width, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin]).height
}

func withShadow(blur: CGFloat, y: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: -y)
    shadow.shadowColor = NSColor(red: 0.1, green: 0.2, blue: 0.45, alpha: alpha)
    shadow.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

let ink = NSColor(red: 0.08, green: 0.1, blue: 0.16, alpha: 1)
let secondary = NSColor(red: 0.36, green: 0.4, blue: 0.48, alpha: 1)
let accent = NSColor(red: 0.13, green: 0.42, blue: 1.0, alpha: 1)
let accentLight = NSColor(red: 0.3, green: 0.75, blue: 1.0, alpha: 1)

// Background: a cool light gradient with a soft blue glow behind the icons.
NSGradient(starting: NSColor(red: 0.985, green: 0.99, blue: 1.0, alpha: 1),
           ending: NSColor(red: 0.9, green: 0.925, blue: 0.97, alpha: 1))?
    .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)
NSGradient(colors: [accentLight.withAlphaComponent(0.28), accent.withAlphaComponent(0.08),
                    accent.withAlphaComponent(0)])?
    .draw(fromCenter: point(320, 165), radius: 0, toCenter: point(320, 165), radius: 300, options: [])

// Header: logo and title centered together, version in the corner.
let title = attributed("Install Copyclip", size: 24, weight: .bold, color: ink)
let titleWidth = title.size().width
let logoSize = 40.0, gap = 10.0
let headerX = (width - logoSize - gap - titleWidth) / 2
logo?.draw(in: rect(headerX, 20, logoSize, logoSize))
draw(title, in: rect(headerX + logoSize + gap, 25, titleWidth + 4, 32))
draw(attributed("Drag Copyclip onto the Applications folder.", size: 13, color: secondary, alignment: .center),
     in: rect(0, 64, width, 20))

let versionText = attributed("v\(version)", size: 11, weight: .semibold, color: accent)
let versionWidth = versionText.size().width + 18
let versionPill = NSBezierPath(roundedRect: rect(width - versionWidth - 18, 18, versionWidth, 22),
                               xRadius: 11, yRadius: 11)
accent.withAlphaComponent(0.1).setFill()
versionPill.fill()
draw(versionText, in: rect(width - versionWidth - 9, 21.5, versionWidth, 16))

// White platforms behind the app (x 170) and Applications (x 470) icons keep their labels readable.
for centerX in [170.0, 470.0] {
    let platform = NSBezierPath(roundedRect: rect(centerX - 75, 98, 150, 142), xRadius: 26, yRadius: 26)
    withShadow(blur: 18, y: 6, alpha: 0.14) {
        NSColor(white: 1, alpha: 0.82).setFill()
        platform.fill()
    }
    NSColor(white: 1, alpha: 0.9).setStroke()
    platform.lineWidth = 1
    platform.stroke()
}

// Curved dashed arrow from the app to Applications.
let start = point(262, 168), control = point(320, 128), end = point(374, 162)
let curve = NSBezierPath()
curve.move(to: start)
curve.curve(to: end, controlPoint1: control, controlPoint2: control)
curve.lineWidth = 3.5
curve.lineCapStyle = .round
curve.setLineDash([2, 8], count: 2, phase: 0)
accent.setStroke()
curve.stroke()
let dx = end.x - control.x, dy = end.y - control.y
let length = (dx * dx + dy * dy).squareRoot()
let ux = dx / length, uy = dy / length
let tip = NSPoint(x: end.x + ux * 10, y: end.y + uy * 10)
let head = NSBezierPath()
head.move(to: tip)
head.line(to: NSPoint(x: end.x - ux * 6 - uy * 9, y: end.y - uy * 6 + ux * 9))
head.line(to: NSPoint(x: end.x - ux * 6 + uy * 9, y: end.y - uy * 6 - ux * 9))
head.close()
head.lineJoinStyle = .round
head.lineWidth = 2
accent.setFill()
accent.setStroke()
head.fill()
head.stroke()

// First-launch card.
let card = NSBezierPath(roundedRect: rect(24, 262, width - 48, 218), xRadius: 18, yRadius: 18)
withShadow(blur: 22, y: 8, alpha: 0.1) {
    NSColor(white: 1, alpha: 0.88).setFill()
    card.fill()
}
NSColor(white: 1, alpha: 1).setStroke()
card.lineWidth = 1
card.stroke()

if let shield = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 17, weight: .semibold)) {
    let tinted = NSImage(size: shield.size, flipped: false) { bounds in
        shield.draw(in: bounds)
        accent.set()
        bounds.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: rect(46, 282, shield.size.width, shield.size.height))
}
draw(attributed("Opening Copyclip for the first time", size: 15, weight: .semibold, color: ink),
     in: rect(74, 282, 400, 22))
draw(attributed("Copyclip isn’t notarized by Apple, so macOS blocks its first launch.",
                size: 12, color: secondary),
     in: rect(48, 308, 420, 36))
let steps = [
    "Open Copyclip from Applications. When macOS says it can’t verify Copyclip, click Done.",
    "Open System Settings › Privacy & Security.",
    "Scroll down, click Open Anyway next to “Copyclip”, and confirm."
]
var stepY = 338.0
for (number, step) in steps.enumerated() {
    let badge = NSBezierPath(ovalIn: rect(48, stepY, 22, 22))
    NSGradient(starting: accentLight, ending: accent)?.draw(in: badge, angle: -60)
    draw(attributed("\(number + 1)", size: 11.5, weight: .bold, color: .white, alignment: .center),
         in: rect(48, stepY + 3.5, 22, 16))
    let used = draw(attributed(step, size: 12.5, color: ink), in: rect(80, stepY + 2, 380, 40))
    stepY += max(22, used) + 10
}
draw(attributed("You only need to do this once. Copyclip then lives in your menu bar.",
                size: 11.5, color: secondary),
     in: rect(48, stepY + 2, 420, 18))

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: arguments[1]))
