import SwiftUI
import AppKit

@main
struct PopoverPreview {
    @MainActor static func main() throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let monitor = Monitor()
        monitor.stop()
        monitor.data = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as! [String: Any]
        monitor.clock = Date(timeIntervalSince1970: number(monitor.data, "time"))
        let views: [MetricKind] = [.temperature, .memory, .network, .fans]
        for kind in views {
            let view = MetricPopover(kind: kind).environmentObject(monitor)
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 400, height: kind == .fans ? 291 : 501)
            let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                fatalError("Popover rendering failed")
            }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = bitmap.representation(using: .png, properties: [:])!
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent(kind.rawValue + ".png"))
            print("Rendered", kind.rawValue, hosting.frame.size)
        }
    }
}
