import Foundation

@main
struct TrafficWindowCheck {
    static func main() {
        let snapshot: [String: Any] = [
            "time": 10000.0,
            "trafficSamples": [
                ["t": 9400.0, "name": "App A", "down": 10.0, "up": 1.0],
                ["t": 9700.0, "name": "App A", "down": 100.0, "up": 10.0],
                ["t": 9715.0, "name": "App A", "down": 20.0, "up": 2.0],
                ["t": 9990.0, "name": "App B", "down": 5.0, "up": 3.0],
                ["t": 10001.0, "name": "App B", "down": 999.0, "up": 999.0]
            ],
            "history": [["time": 9600.0], ["time": 9900.0]],
            "coverageSamples": [["t": 9710.0, "seconds": 20.0], ["t": 9990.0, "seconds": 5.0]]
        ]
        let five = TrafficWindow(data: snapshot, minutes: 5)
        precondition(five.apps.count == 2)
        precondition(number(five.apps[0], "down") == 20)
        precondition(five.history.count == 1)
        precondition(five.coverage == 15)
        let fifteen = TrafficWindow(data: snapshot, minutes: 15)
        precondition(number(fifteen.apps[0], "down") == 130)
        precondition(fifteen.history.count == 2)
        let custom = TrafficWindow(data: snapshot, minutes: 1)
        precondition(custom.apps.count == 1)
        precondition(string(custom.apps[0], "name") == "App B")
        let old: [String: Any] = ["time": 10000.0, "traffic": [["name": "Legacy", "down": 12.0]]]
        precondition(TrafficWindow(data: old, minutes: 60).apps.count == 1)
        precondition(TrafficWindow(data: old, minutes: 5).apps.isEmpty)
        print("PASS: selected time boundaries, custom minutes, app totals, curve filtering, clipped coverage and legacy snapshot")
    }
}
