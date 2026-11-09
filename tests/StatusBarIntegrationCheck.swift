import AppKit
import SwiftUI

@main
struct StatusBarIntegrationCheck {
    static func main() throws {
        _ = NSApplication.shared
        let monitor = Monitor()
        monitor.stop()
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacPulse/snapshot.json")
        monitor.data = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        monitor.clock = Date(timeIntervalSince1970: number(monitor.data, "time"))
        let status = CompactStatusBar(monitor: monitor)
        var result = try status.verifyLayout()
        let popovers = status.verifyPopoverBehavior()
        result["popoverChecks"] = popovers
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if !popovers.values.allSatisfy({ $0 }) { exit(1) }
    }
}
