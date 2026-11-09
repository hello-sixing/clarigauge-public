import SwiftUI

struct TrafficWindow {
    let start: Date
    let end: Date
    let apps: [[String: Any]]
    let history: [[String: Any]]
    let coverage: Double
    let hasSamples: Bool

    init(data: [String: Any], minutes: Int) {
        let seconds = Double(min(60, max(1, minutes)) * 60)
        let endTime = number(data, "time")
        let startTime = endTime - seconds
        start = Date(timeIntervalSince1970: startTime)
        end = Date(timeIntervalSince1970: endTime)
        hasSamples = data["trafficSamples"] != nil
        var totals: [String: [String: Any]] = [:]
        for sample in rows(data, "trafficSamples") {
            let time = number(sample, "t")
            if time <= startTime || time > endTime { continue }
            let name = string(sample, "name")
            var row = totals[name] ?? ["name": name, "down": 0.0, "up": 0.0]
            row["down"] = number(row, "down") + number(sample, "down")
            row["up"] = number(row, "up") + number(sample, "up")
            totals[name] = row
        }
        if hasSamples {
            apps = totals.values.sorted { number($0, "down") + number($0, "up") > number($1, "down") + number($1, "up") }
        } else {
            apps = minutes == 60 ? rows(data, "traffic") : []
        }
        history = rows(data, "history").filter { number($0, "time") > startTime && number($0, "time") <= endTime }
        let covered = rows(data, "coverageSamples").reduce(0.0) { sum, sample in
            let finish = number(sample, "t")
            let begin = finish - number(sample, "seconds")
            return sum + max(0, min(finish, endTime) - max(begin, startTime))
        }
        coverage = min(seconds, covered)
    }
}

struct TrafficWindowPicker: View {
    let data: [String: Any]
    @AppStorage("trafficWindowMinutes") private var minutes = 60
    @AppStorage("trafficWindowCustom") private var custom = false

    var body: some View {
        let window = TrafficWindow(data: data, minutes: minutes)
        VStack(alignment: .leading, spacing: 8) {
            Picker("统计时间", selection: Binding(
                get: { custom ? 0 : minutes },
                set: { value in
                    custom = value == 0
                    if value > 0 { minutes = value }
                }
            )) {
                ForEach([5, 15, 30, 60], id: \.self) { value in
                    Text("最近 \(value) 分钟").tag(value)
                }
                Text("自定义时长").tag(0)
            }
            if custom {
                Stepper("最近 \(minutes) 分钟", value: $minutes, in: 1...60)
            }
            if data["time"] != nil {
                Text(window.start.formatted(date: .omitted, time: .standard) + " — " +
                     window.end.formatted(date: .omitted, time: .standard))
                    .font(.caption).monospacedDigit()
                Text("网卡采样覆盖 \(Int(window.coverage / 60)) 分 \(Int(window.coverage) % 60) 秒")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !window.hasSamples {
                Text("等待新版应用流量样本，历史快照仅支持一小时汇总。")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("应用用量按 15 秒汇总，区间边缘可能少计最多 15 秒。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
