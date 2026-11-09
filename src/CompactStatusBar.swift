import AppKit
import SwiftUI

final class CompactStatusBar: NSObject, NSPopoverDelegate {
    private let monitor: Monitor
    private let foldItem: NSStatusItem
    private var items: [(MetricKind, NSStatusItem)] = []
    private let popover = NSPopover()
    private let defaults = UserDefaults.standard
    private var activeKind: MetricKind?
    private var outsideClickMonitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var windowObserver: NSObjectProtocol?

    init(monitor: Monitor) {
        self.monitor = monitor
        foldItem = NSStatusBar.system.statusItem(withLength: 26)
        super.init()
        foldItem.button?.target = self
        foldItem.button?.action = #selector(toggleFold)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        update()
    }

    func update() {
        var kinds: [MetricKind] = [.temperature, .fans]
        let options: [(String, MetricKind, Bool)] = [
            ("showBatteryInMenu", .battery, false),
            ("showMemoryInMenu", .memory, true),
            ("showStorageInMenu", .storage, false),
            ("showNetworkInMenu", .network, false)
        ]
        for (key, kind, fallback) in options {
            if defaults.object(forKey: key) as? Bool ?? fallback { kinds.append(kind) }
        }
        if kinds != items.map({ $0.0 }) {
            popover.close()
            items.forEach { NSStatusBar.system.removeStatusItem($0.1) }
            items = kinds.map { kind in
                let item = NSStatusBar.system.statusItem(withLength: kind.metric(data: [:]).width + 2)
                item.button?.target = self
                item.button?.action = #selector(showDetails(_:))
                item.button?.toolTip = "点击查看" + kind.title
                return (kind, item)
            }
        }
        let folded = defaults.bool(forKey: "menuMetricsFolded")
        let hint = folded ? "展开监控指标" : "折叠监控指标"
        foldItem.button?.image = foldIcon(folded: folded)
        foldItem.button?.toolTip = hint
        foldItem.button?.setAccessibilityLabel(hint)
        for (kind, item) in items {
            let metric = kind.metric(data: monitor.stale ? [:] : monitor.data)
            item.length = metric.width + 2
            item.button?.image = MenuBarRenderer.image(metrics: [metric])
            item.button?.setAccessibilityLabel(kind.title + "，" + metric.lines.joined(separator: "，"))
            item.isVisible = !folded
        }
    }

    private func foldIcon(folded: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 20), flipped: false) { _ in
            NSColor.black.setStroke()
            let pulse = NSBezierPath()
            pulse.lineWidth = 1.8
            pulse.lineCapStyle = .round
            pulse.lineJoinStyle = .round
            pulse.move(to: NSPoint(x: 1, y: 9))
            pulse.line(to: NSPoint(x: 4, y: 9))
            pulse.curve(to: NSPoint(x: 7, y: 14), controlPoint1: NSPoint(x: 5, y: 9), controlPoint2: NSPoint(x: 6, y: 14))
            pulse.curve(to: NSPoint(x: 10, y: 5), controlPoint1: NSPoint(x: 8, y: 14), controlPoint2: NSPoint(x: 9, y: 5))
            pulse.curve(to: NSPoint(x: 13, y: 12), controlPoint1: NSPoint(x: 11, y: 5), controlPoint2: NSPoint(x: 12, y: 12))
            pulse.curve(to: NSPoint(x: 16, y: 9), controlPoint1: NSPoint(x: 14, y: 12), controlPoint2: NSPoint(x: 15, y: 9))
            pulse.line(to: NSPoint(x: 17, y: 9))
            pulse.stroke()
            let arrow = NSBezierPath()
            arrow.lineWidth = 1.2
            arrow.lineCapStyle = .round
            arrow.move(to: NSPoint(x: folded ? 23 : 20, y: 7))
            arrow.line(to: NSPoint(x: folded ? 20 : 23, y: 10))
            arrow.line(to: NSPoint(x: folded ? 23 : 20, y: 13))
            arrow.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func toggleFold() {
        defaults.set(!defaults.bool(forKey: "menuMetricsFolded"), forKey: "menuMetricsFolded")
        popover.close()
        update()
    }

    @objc private func showDetails(_ sender: NSStatusBarButton) {
        guard let entry = items.first(where: { $0.1.button === sender }) else { return }
        if popover.isShown && activeKind == entry.0 {
            popover.close()
            return
        }
        popover.close()
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController = NSHostingController(rootView: MetricPopover(kind: entry.0).environmentObject(monitor))
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        activeKind = entry.0
        popover.contentViewController?.view.window?.makeKey()
        listenForDismissal()
    }

    private func listenForDismissal() {
        stopListening()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.popover.close()
        }
        deactivateObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            self?.popover.close()
        }
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let window = notification.object as? NSWindow else { return }
            if window !== self.popover.contentViewController?.view.window && window.level == .normal {
                self.popover.close()
            }
        }
    }

    private func stopListening() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver) }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        outsideClickMonitor = nil
        deactivateObserver = nil
        windowObserver = nil
    }

    func popoverDidClose(_ notification: Notification) {
        activeKind = nil
        stopListening()
    }

    deinit {
        stopListening()
    }
}

#if STATUSBAR_CHECK
extension CompactStatusBar {
    func verifyPopoverBehavior() -> [String: Bool] {
        let original = defaults.object(forKey: "menuMetricsFolded")
        defer {
            popover.close()
            if let original { defaults.set(original, forKey: "menuMetricsFolded") }
            else { defaults.removeObject(forKey: "menuMetricsFolded") }
            update()
        }
        defaults.set(false, forKey: "menuMetricsFolded")
        update()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        let first = items[0]
        let second = items[1]
        showDetails(first.1.button!)
        let opened = popover.isShown && activeKind == first.0
        let firstAnchor = popover.positioningRect == first.1.button!.bounds
        showDetails(second.1.button!)
        let switched = popover.isShown && activeKind == second.0
            && popover.positioningRect == second.1.button!.bounds
        showDetails(second.1.button!)
        let toggled = !popover.isShown && activeKind == nil
        showDetails(first.1.button!)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        let dismissed = !popover.isShown
        let cleaned = outsideClickMonitor == nil && deactivateObserver == nil && windowObserver == nil
        return ["opened": opened, "firstAnchor": firstAnchor, "switched": switched,
                "sameClickClosed": toggled, "deactivationClosed": dismissed, "listenersRemoved": cleaned]
    }

    func verifyLayout() throws -> [String: Any] {
        let original = defaults.object(forKey: "menuMetricsFolded")
        defer {
            if let original { defaults.set(original, forKey: "menuMetricsFolded") }
            else { defaults.removeObject(forKey: "menuMetricsFolded") }
            update()
        }
        defaults.set(false, forKey: "menuMetricsFolded")
        update()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        var result: [String: Any] = [:]
        var widths: [[String: Any]] = []
        for (kind, item) in items {
            precondition(item.length == kind.metric(data: monitor.data).width + 2)
            precondition(item.isVisible)
            widths.append(["metric": kind.rawValue, "nativeWidth": item.length])
        }
        result["items"] = widths
        result["expandedWidth"] = items.reduce(foldItem.length) { $0 + $1.1.length }
        result["foldIconWidth"] = foldItem.length
        result["iconUsesVectorTemplate"] = foldItem.button?.image?.isTemplate == true
        toggleFold()
        precondition(items.allSatisfy { !$0.1.isVisible })
        precondition(foldItem.isVisible)
        result["foldedWidth"] = foldItem.length
        toggleFold()
        precondition(items.allSatisfy { $0.1.isVisible })
        result["foldRestorePassed"] = true
        return result
    }
}
#endif
