import AppKit

@main
struct MenuBarLayoutCheck {
    static func main() throws {
        let kinds: [MetricKind] = [.temperature, .fans, .battery, .memory, .storage, .network]
        let small: [String: Any] = [
            "temperatures": [["celsius": 9.0]],
            "fans": [["rpm": 0.0], ["rpm": 0.0]],
            "battery": ["available": true, "percent": 9.0],
            "memory": ["used": 8.0 * 1024 * 1024 * 1024],
            "disk": ["free": 1024.0 * 1024],
            "rateUp": 0.0, "rateDown": 1024.0
        ]
        let large: [String: Any] = [
            "temperatures": [["celsius": 105.0]],
            "fans": [["rpm": 19999.0], ["rpm": 19999.0]],
            "battery": ["available": true, "percent": 100.0],
            "memory": ["used": 999.9 * 1024 * 1024 * 1024],
            "disk": ["free": 1023.9 * 1024 * 1024 * 1024],
            "rateUp": 999.9 * 1024 * 1024, "rateDown": 1023.9 * 1024 * 1024
        ]
        let short = kinds.map { $0.metric(data: small) }
        let long = kinds.map { $0.metric(data: large) }
        precondition(short.reduce(0) { $0 + $1.width } <= 226)
        for kind in kinds {
            let normal = kind.metric(data: small)
            precondition(normal.width == kind.metric(data: large).width)
            precondition(normal.width == kind.metric(data: [:]).width)
        }
        for metric in long {
            let font = NSFont.monospacedSystemFont(ofSize: metric.lines.count > 1 ? 9.5 : 10.5, weight: .medium)
            for line in metric.lines {
                precondition((line as NSString).size(withAttributes: [.font: font]).width <= metric.width, "Clipped reading: " + line)
            }
        }
        let first = MenuBarRenderer.image(metrics: short)
        let second = MenuBarRenderer.image(metrics: long)
        precondition(first.size == second.size, "Changing values changed menu bar width")
        precondition(first.size.height == 22)
        let empty = MenuBarRenderer.image(metrics: [MetricKind.network.metric(data: [:])])
        precondition(empty.size.width == 48, "Unavailable readings changed width")

        let preview = NSImage(size: NSSize(width: first.size.width + 24, height: 80), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            first.draw(at: NSPoint(x: 12, y: 46), from: .zero, operation: .sourceOver, fraction: 1)
            second.draw(at: NSPoint(x: 12, y: 12), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        let bitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("PASS: fixed width across value/unit changes, two-line network, unavailable readings")
    }
}
