import SwiftUI
import Charts

enum MetricKind: String {
    case temperature, fans, battery, memory, storage, network

    var title: String {
        switch self {
        case .temperature: return "温度传感器"
        case .fans: return "风扇转速"
        case .battery: return "电池"
        case .memory: return "内存占用"
        case .storage: return "磁盘空间"
        case .network: return "网络活动"
        }
    }

    func metric(data: [String: Any]) -> MenuBarMetric {
        switch self {
        case .temperature:
            let maximum = rows(data, "temperatures").map { number($0, "celsius") }.max()
            return MenuBarMetric(width: 36, lines: [maximum.map { String(format: "%.0f°C", $0) } ?? "—°C"])
        case .fans:
            let fans = rows(data, "fans")
            let speeds = fans.map { number($0, "rpm") }
            let lines: [String]
            if speeds.count == 2 {
                lines = speeds.map { String(format: "%.0f", $0) }
            } else {
                let heading = speeds.count > 2 ? "最高" : "风扇"
                lines = [heading, speeds.max().map { String(format: "%.0f", $0) } ?? "—"]
            }
            return MenuBarMetric(width: 36, lines: lines)
        case .battery:
            let battery = data["battery"] as? [String: Any] ?? [:]
            let percent = battery["available"] as? Bool == true ? "\(Int(number(battery, "percent")))%" : "—"
            return MenuBarMetric(width: 26, lines: ["电量", percent])
        case .memory:
            let used = (data["memory"] as? [String: Any])?["used"] as? Double
            return MenuBarMetric(width: 34, lines: ["内存", used.map(compactBytes) ?? "—"])
        case .storage:
            let free = (data["disk"] as? [String: Any])?["free"] as? Double
            return MenuBarMetric(width: 36, lines: ["磁盘余", free.map(compactBytes) ?? "—"])
        case .network:
            let up = (data["rateUp"] as? Double).map { compactBytes($0) + "/s" } ?? "—"
            let down = (data["rateDown"] as? Double).map { compactBytes($0) + "/s" } ?? "—"
            return MenuBarMetric(width: 48, lines: ["↑\(up)", "↓\(down)"])
        }
    }
}

struct MetricPopover: View {
    let kind: MetricKind
    @EnvironmentObject var m: Monitor
    @AppStorage("trafficWindowMinutes") private var trafficMinutes = 60
    @AppStorage("showBatteryInMenu") private var showBattery = false
    @AppStorage("showMemoryInMenu") private var showMemory = true
    @AppStorage("showStorageInMenu") private var showStorage = false
    @AppStorage("showNetworkInMenu") private var showNetwork = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(kind.title).font(.headline)
                Spacer()
                Text(m.stale ? "数据已过期" : "每 5 秒刷新")
                    .font(.caption).foregroundStyle(m.stale ? Color.orange : Color.secondary)
            }
            if m.stale {
                Text("等待新数据，以下为上次读数。").font(.caption).foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch kind {
                    case .temperature: temperatureDetails
                    case .fans: fanDetails
                    case .memory: memoryDetails
                    case .network: networkDetails
                    case .storage: storageDetails
                    case .battery: batteryDetails
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 4)
            }.frame(height: kind == .temperature || kind == .memory || kind == .network ? 390 : 180)
            Divider()
            Menu("显示与操作") {
                MenuContent(showBattery: $showBattery, showMemory: $showMemory,
                            showStorage: $showStorage, showNetwork: $showNetwork)
            }.menuStyle(.borderlessButton)
        }.padding(18).frame(width: 400)
    }

    private func reading(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).lineLimit(2).textSelection(.enabled)
            Spacer(minLength: 10)
            Text(value).monospacedDigit().fixedSize()
        }.font(.callout)
    }

    private var temperatureDetails: some View {
        let sensors = rows(m.data, "temperatures")
        let thermal = Int(number(m.data, "thermal"))
        let states = ["正常", "轻度热压力", "严重热压力", "临界热压力"]
        return VStack(alignment: .leading, spacing: 12) {
            reading("系统热状态", m.data["thermal"] == nil ? "不可用" : states[min(3, max(0, thermal))])
            ForEach(["CPU", "GPU"], id: \.self) { group in
                let maximum = sensors.filter { $0["group"] as? String == group }
                    .map { number($0, "celsius") }.max()
                reading(group + " 最高温区", maximum.map { String(format: "%.1f °C", $0) } ?? "不可用")
            }
            Text("顶部显示全部传感器中的最高温度").font(.caption).foregroundStyle(.secondary)
            ForEach(["CPU", "GPU", "其他传感器"], id: \.self) { group in
                let members = sensors.filter { ($0["group"] as? String ?? "其他传感器") == group }
                    .sorted { number($0, "celsius") > number($1, "celsius") }
                Divider()
                Text(group).font(.subheadline.bold())
                if members.isEmpty {
                    Text("暂无可识别读数").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(members.enumerated()), id: \.offset) { _, sensor in
                    VStack(alignment: .leading, spacing: 3) {
                        reading(sensor["label"] as? String ?? string(sensor, "sensor"), String(format: "%.1f °C", number(sensor, "celsius")))
                        if sensor["label"] != nil {
                            Text(string(sensor, "sensor")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("CPU/GPU 为型号对应的温区读数。其余传感器保留硬件名称。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var fanDetails: some View {
        VStack(spacing: 12) {
            ForEach(Array(rows(m.data, "fans").enumerated()), id: \.offset) { _, fan in
                reading(string(fan, "sensor"), String(format: "%.0fRPM", number(fan, "rpm")))
            }
            if rows(m.data, "fans").isEmpty { Text("暂无风扇读数").foregroundStyle(.secondary) }
            Divider()
            if let app = fanControlURL {
                Button {
                    NSWorkspace.shared.open(app)
                } label: {
                    Label("打开 Macs Fan Control 调节风扇", systemImage: "fan")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .contentShape(Rectangle())
                }.buttonStyle(.borderedProminent)
            } else {
                Text("未找到已安装的 Macs Fan Control").foregroundStyle(.secondary)
            }
        }
    }

    private var fanControlURL: URL? {
        let identifier = "com.crystalidea.macsfancontrol"
        if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return registered
        }
        let directories = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities")
        ]
        return directories.map { $0.appendingPathComponent("Macs Fan Control.app") }
            .first { Bundle(url: $0)?.bundleIdentifier == identifier }
    }

    private var memoryDetails: some View {
        let memory = m.data["memory"] as? [String: Any] ?? [:]
        return VStack(alignment: .leading, spacing: 12) {
            if memory.isEmpty { Text("等待内存读数").foregroundStyle(.secondary) }
            reading("已用 / 总量", "\(bytes(number(memory, "used"))) / \(bytes(number(memory, "total")))")
            ProgressView(value: min(1, number(memory, "used") / max(1, number(memory, "total"))))
            reading("应用内存", bytes(number(memory, "app")))
            reading("有线内存", bytes(number(memory, "wired")))
            reading("压缩内存", bytes(number(memory, "compressed")))
            Divider()
            Text("应用占用 · RSS").font(.subheadline.bold())
            ForEach(Array(rows(m.data, "apps").prefix(20).enumerated()), id: \.offset) { _, app in
                reading(string(app, "name"), bytes(number(app, "memory")))
            }
            Text("RSS 包含共享页，各应用之和可能超过系统已用内存。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var networkDetails: some View {
        let window = TrafficWindow(data: m.data, minutes: trafficMinutes)
        return VStack(alignment: .leading, spacing: 12) {
            reading("↓ 实时下行", m.data["rateDown"] == nil ? "等待采样" : bytes(number(m.data, "rateDown")) + "/s")
            reading("↑ 实时上行", m.data["rateUp"] == nil ? "等待采样" : bytes(number(m.data, "rateUp")) + "/s")
            NetworkAddresses(data: m.data)
            if let error = m.data["networkError"] as? String { Text(error).font(.caption).foregroundStyle(.orange) }
            TrafficWindowPicker(data: m.data)
            Chart {
                ForEach(Array(window.history.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("时间", Date(timeIntervalSince1970: number(point, "time"))), y: .value("KiB/s", number(point, "down") / 1024), series: .value("方向", "下行"))
                        .foregroundStyle(by: .value("方向", "下行"))
                    LineMark(x: .value("时间", Date(timeIntervalSince1970: number(point, "time"))), y: .value("KiB/s", number(point, "up") / 1024), series: .value("方向", "上行"))
                        .foregroundStyle(by: .value("方向", "上行"))
                }
            }.frame(height: 100)
            Text("最近 \(trafficMinutes) 分钟应用流量").font(.subheadline.bold())
            Text("每行按下行 / 上行显示，代理与应用的流量可能重复。").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(window.apps.prefix(20).enumerated()), id: \.offset) { _, app in
                reading(string(app, "name"), "\(bytes(number(app, "down"))) / \(bytes(number(app, "up")))")
            }
        }
    }

    private var storageDetails: some View {
        let disk = m.data["disk"] as? [String: Any] ?? [:]
        return VStack(spacing: 12) {
            reading("总空间", bytes(number(disk, "total")))
            reading("已使用", bytes(number(disk, "used")))
            reading("可用空间", bytes(number(disk, "free")))
        }
    }

    private var batteryDetails: some View {
        let battery = m.data["battery"] as? [String: Any] ?? [:]
        return VStack(spacing: 12) {
            if battery["available"] as? Bool == true {
                reading("电量", String(format: "%.0f%%", number(battery, "percent")))
                reading("电源状态", battery["charging"] as? Bool == true ? "充电中" : battery["external"] as? Bool == true ? "已接电源" : "使用电池")
                reading("循环次数", "\(Int(number(battery, "cycles")))")
            } else { Text("无内置电池或读数不可用") }
        }
    }
}
