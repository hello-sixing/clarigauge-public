import AppKit

struct MenuBarMetric {
    let width: CGFloat
    let lines: [String]
}

func compactBytes(_ bytes: Double) -> String {
    let units = ["B", "K", "M", "G", "T", "P"]
    var value = max(0, bytes)
    var unit = 0
    while value >= 1024 && unit < units.count - 1 {
        value /= 1024
        unit += 1
    }
    let format = unit == 0 || value >= 100 ? "%.0f%@" : "%.1f%@"
    return String(format: format, value, units[unit])
}

enum MenuBarRenderer {
    static func image(metrics: [MenuBarMetric]) -> NSImage {
        let spacing: CGFloat = 8
        let width = metrics.reduce(0) { $0 + $1.width }
            + CGFloat(max(0, metrics.count - 1)) * spacing
        // MenuBarExtra reliably preserves an image's size, including multiline content.
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            var x: CGFloat = 0
            for (index, metric) in metrics.enumerated() {
                let stacked = metric.lines.count > 1
                let font = NSFont.monospacedSystemFont(ofSize: stacked ? 9.5 : 10.5, weight: .medium)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byClipping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: paragraph
                ]
                for (lineIndex, text) in metric.lines.enumerated() {
                    let y: CGFloat = stacked ? (lineIndex == 0 ? 11 : 0) : 3
                    let height: CGFloat = stacked ? 11 : 16
                    NSAttributedString(string: text, attributes: attributes)
                        .draw(in: NSRect(x: x, y: y, width: metric.width, height: height))
                }
                x += metric.width
                if index < metrics.count - 1 {
                    NSColor.black.withAlphaComponent(0.25).setFill()
                    NSRect(x: x + spacing / 2, y: 5, width: 0.5, height: 12).fill()
                    x += spacing
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
