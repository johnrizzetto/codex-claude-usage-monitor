import AppKit
import PaceCore

enum MenuBarMeter {
    static func color(for signal: PaceSignal) -> NSColor {
        switch signal {
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .red: return .systemRed
        case .unavailable: return .secondaryLabelColor
        }
    }
    /// A native, non-template image retains the pacing color in both menu bar appearances.
    static func image(used: Double?, expected: Double?, signal: PaceSignal) -> NSImage {
        let image = NSImage(size: NSSize(width: 38, height: 18), flipped: false) { _ in
            let bounds = NSRect(x: 1, y: 3, width: 36, height: 12)
            let outline = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            outline.fill()
            NSColor.labelColor.withAlphaComponent(0.5).setStroke()
            outline.lineWidth = 1
            outline.stroke()
            let color = color(for: signal)
            if let used, used.isFinite {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 2, yRadius: 2).addClip()
                color.withAlphaComponent(signal == .unavailable ? 0.4 : 1).setFill()
                NSRect(x: 3, y: 5, width: 32 * min(100, max(0, used)) / 100, height: 8).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            if let expected {
                let x = 3 + 32 * min(100, max(0, expected)) / 100
                NSColor.labelColor.withAlphaComponent(0.85).setFill()
                NSRect(x: min(34, x), y: 4, width: 1, height: 10).fill()
            } else {
                NSColor.secondaryLabelColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: 17, y: 7, width: 4, height: 4)).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Quota used, colored by pacing"
        return image
    }
}
