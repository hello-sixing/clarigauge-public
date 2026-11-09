import SwiftUI
import Charts
import AppKit

func number(_ d: [String:Any], _ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
func string(_ d: [String:Any], _ k: String) -> String { d[k] as? String ?? "" }
func rows(_ d: [String:Any], _ k: String) -> [[String:Any]] { d[k] as? [[String:Any]] ?? [] }
func bytes(_ n: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(max(0,n)), countStyle: .binary) }
let mint = Color(red:0.38,green:0.89,blue:0.76)
let base = Color(red:0.055,green:0.07,blue:0.105)
let panel = Color(red:0.09,green:0.11,blue:0.15)

final class Monitor: ObservableObject {
    @Published var data: [String:Any] = [:]
    @Published var error = "正在连接本机采集器…"
    @Published var clock = Date()
    private var timer: Timer?
    private var child: Process?
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacPulse")
    init() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories:true, attributes:[.posixPermissions:0o700])
            guard let resources=Bundle.main.resourceURL else { return }
            if let icon = NSImage(contentsOf: resources.appendingPathComponent("AppIcon.icns")) {
                NSApplication.shared.applicationIconImage = icon
            }
            let process=Process()
            process.executableURL=resources.appendingPathComponent("python/bin/python3.12")
            process.arguments=["-E", "-s", "-S", "-B", resources.appendingPathComponent("collector.py").path,"--directory",directory.path,"--resources",resources.path]
            process.standardOutput=FileHandle.nullDevice; process.standardError=FileHandle.nullDevice
            try process.run(); child=process
        } catch { self.error="采集器启动失败：\(error.localizedDescription)" }
        timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in self?.refresh() }
        refresh()
    }
    func refresh() {
        clock=Date()
        do {
            let raw=try Data(contentsOf:directory.appendingPathComponent("snapshot.json"))
            if let value=try JSONSerialization.jsonObject(with:raw) as? [String:Any] { data=value;error="" }
        } catch { if child?.isRunning == false { self.error="采集器已停止，请重新打开应用" } }
        Delegate.statusBar?.update()
    }
    var stale: Bool { clock.timeIntervalSince1970-number(data,"time") > 15 }
    func stop() {
        timer?.invalidate()
        if let child, child.isRunning { child.terminate() }
    }
}
final class Delegate: NSObject, NSApplicationDelegate {
    static let monitor = Monitor()
    static var statusBar: CompactStatusBar?
    static var panel: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.statusBar = CompactStatusBar(monitor: Self.monitor)
    }
    func applicationWillTerminate(_ notification: Notification) { Self.monitor.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    static func showPanel() {
        if panel == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1230, height: 850),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "ClariGauge · 本机监控"
            window.contentViewController = NSHostingController(rootView: Dashboard().environmentObject(monitor))
            window.minSize = NSSize(width: 1080, height: 740)
            window.center()
            panel = NSWindowController(window: window)
        }
        panel?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#if !POPOVER_PREVIEW
@main
#endif
struct MacPulseApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    @StateObject var monitor=Delegate.monitor
    var body: some Scene {
        dashboard.defaultLaunchBehavior(.suppressed)
    }

    private var dashboard: some Scene {
        WindowGroup("ClariGauge · 本机监控",id:"main") {
            Dashboard().environmentObject(monitor)
                .frame(minWidth:1080,minHeight:740).preferredColorScheme(.dark)
        }.defaultSize(width:1230,height:850)
    }

}

struct MenuContent: View {
    @EnvironmentObject var m:Monitor
    @Binding var showBattery: Bool
    @Binding var showMemory: Bool
    @Binding var showStorage: Bool
    @Binding var showNetwork: Bool

    var body: some View {
        Text(m.stale ? "等待实时数据" : "菜单栏显示最高传感器温度与各风扇转速")
        Button("打开监控面板") { Delegate.showPanel() }
        Menu("菜单栏显示") {
            Toggle("电量", isOn:$showBattery)
            Toggle("内存占用", isOn:$showMemory)
            Toggle("磁盘剩余空间", isOn:$showStorage)
            Toggle("实时上下行", isOn:$showNetwork)
        }
        Divider()
        Button("退出 ClariGauge") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
final class DashboardState: ObservableObject {
    @Published var selection="总览"
    @Published var search=""
}
struct Dashboard: View {
    @EnvironmentObject var m:Monitor
    @StateObject var ui=DashboardState()
    @AppStorage("trafficWindowMinutes") private var trafficMinutes = 60
    private var trafficWindow: TrafficWindow { TrafficWindow(data: m.data, minutes: trafficMinutes) }
    let pages=[("总览","square.grid.2x2"),("内存与进程","memorychip"),("应用流量","network"),("Codex 对话","bubble.left.and.bubble.right"),("传感器","thermometer.medium")]
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:28) {
                HStack { Image(nsImage: NSApplication.shared.applicationIconImage).resizable().scaledToFit().frame(width:32,height:32);Text("ClariGauge").font(.title2.bold()) }.padding(.top,28)
                Text("这台 Mac 的实时状态").font(.caption).foregroundStyle(.secondary)
                VStack(spacing:8) { ForEach(pages,id:\.0) { p in
                    Button { ui.selection=p.0;ui.search="" } label: {
                        HStack(spacing:12) { Image(systemName:p.1).frame(width:20);Text(p.0);Spacer() }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13).background(ui.selection==p.0 ? mint.opacity(0.13):Color.clear).clipShape(RoundedRectangle(cornerRadius:12))
                            .contentShape(Rectangle())
                            .foregroundStyle(ui.selection==p.0 ? mint:Color.secondary)
                    }.buttonStyle(.plain)
                } }
                Spacer()
                VStack(alignment:.leading,spacing:9) {
                    Label(m.stale ? "数据未就绪 / 已过期":"本机采集中",systemImage:m.stale ? "exclamationmark.circle":"circle.fill").foregroundStyle(m.stale ? Color.orange:mint)
                    Text("每 5 秒刷新 · 本地保存\n关闭窗口后继续采集\n菜单栏退出可停止").font(.caption).foregroundStyle(.secondary).lineSpacing(5)
                }
                .padding(.bottom,24)
            }.padding(.horizontal,20).frame(width:195).background(panel.opacity(0.65))
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:8) {
                            Text(ui.selection).font(.system(size:30,weight:.bold))
                            Text(subtitle).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(m.clock,style:.time).monospacedDigit().foregroundStyle(.secondary).padding(.top,10)
                    }
                    if !m.error.isEmpty { notice(m.error) }
                    if m.stale && !m.data.isEmpty { notice("以下是上次采样，已超过 15 秒。请检查采集器状态。") }
                    switch ui.selection {
                    case "内存与进程": memoryPage
                    case "应用流量": trafficPage
                    case "Codex 对话": codexPage
                    case "传感器": sensorsPage
                    default: overview
                    }
                    let errors=m.data["errors"] as? [String] ?? []
                    if !errors.isEmpty { notice(errors.joined(separator:"\n")) }
                }.padding(30)
            }
        }.background(base)
    }
    var subtitle:String {
        switch ui.selection {
        case "内存与进程":return "系统内存概况，以及每个应用与子进程的占用"
        case "应用流量":return "滚动 \(trafficMinutes) 分钟 · 实际覆盖 \(Int(trafficWindow.coverage/60)) 分钟 · 未运行期间不补算"
        case "Codex 对话":return "对话实际 token 用量与网络归属能力"
        case "传感器":return "硬件实测 · 只读温度与风扇转速"
        default:return "电量、内存、存储与网络，一眼掌握。"
        }
    }
    func notice(_ text:String)->some View { Text(text).font(.callout).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading).padding(14).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:12)) }
    func card(_ title:String,_ icon:String,_ value:String,_ detail:String,_ fraction:Double?=nil)->some View {
        VStack(alignment:.leading,spacing:15) {
            Label(title,systemImage:icon).foregroundStyle(.secondary)
            Text(value).font(.system(size:28,weight:.semibold,design:.rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            if let fraction { ProgressView(value:min(1,max(0,fraction))).tint(mint) }
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(minHeight:28,alignment:.top)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(20).background(panel).clipShape(RoundedRectangle(cornerRadius:18))
    }
    var overview:some View {
        let mem=m.data["memory"] as? [String:Any] ?? [:]
        let disk=m.data["disk"] as? [String:Any] ?? [:]
        let battery=m.data["battery"] as? [String:Any] ?? [:]
        let temps=rows(m.data,"temperatures");let fans=rows(m.data,"fans")
        let temp=temps.map{number($0,"celsius")}.max()
        return VStack(spacing:20) {
            HStack(spacing:14) {
                card("电量","battery.75percent",battery["available"] as? Bool == true ? "\(Int(number(battery,"percent")))%":(battery.isEmpty ? "不可用":"无内置电池"),battery["available"] as? Bool != true ? "台式 Mac 使用外接电源":battery["charging"] as? Bool == true ? "正在充电":(battery["external"] as? Bool == true ? "已接电源":"使用电池"),number(battery,"percent")/100)
                card("内存使用","memorychip",mem.isEmpty ? "不可用":bytes(number(mem,"used")),"共 \(bytes(number(mem,"total")))",number(mem,"used")/max(1,number(mem,"total")))
                card("存储占用","internaldrive",disk.isEmpty ? "不可用":bytes(number(disk,"used")),"可用 \(bytes(number(disk,"free")))",number(disk,"used")/max(1,number(disk,"total")))
            }
            HStack(spacing:14) {
                card("最高传感器温度","thermometer.medium",temp.map{String(format:"%.1f °C",$0)} ?? "不可用","\(temps.count) 个传感器 · 不代表特定 CPU 核心")
                card("风扇转速","fan",fans.isEmpty ? "不可用":fans.map{String(format:"%.0f",number($0,"rpm"))}.joined(separator:" / "),fans.isEmpty ? "无可用转速读数":"RPM · \(fans.count) 个风扇")
                card("实时下行","arrow.down",m.data["rateDown"] == nil ? "等待采样":bytes(number(m.data,"rateDown"))+"/s","上行 \(bytes(number(m.data,"rateUp")))/s · 物理网卡")
            }
            chart
            HStack(alignment:.top,spacing:20) {
                VStack(alignment:.leading,spacing:14) { Text("内存占用最高").font(.headline)
                    ForEach(Array(rows(m.data,"apps").prefix(5).enumerated()),id:\.offset) { _,r in line(string(r,"name"),bytes(number(r,"memory"))) }
                }.padding(20).frame(maxWidth:.infinity,alignment:.topLeading).background(panel).clipShape(RoundedRectangle(cornerRadius:18))
                VStack(alignment:.leading,spacing:14) { Text("最近 \(trafficMinutes) 分钟流量").font(.headline)
                    ForEach(Array(trafficWindow.apps.prefix(5).enumerated()),id:\.offset) { _,r in line(string(r,"name"),bytes(number(r,"down")+number(r,"up"))) }
                    if rows(m.data,"traffic").isEmpty { Text("正在积累流量样本…").foregroundStyle(.secondary) }
                }.padding(20).frame(maxWidth:.infinity,alignment:.topLeading).background(panel).clipShape(RoundedRectangle(cornerRadius:18))
            }
        }
    }
    func line(_ name:String,_ value:String)->some View { HStack { Text(name).lineLimit(1);Spacer();Text(value).monospacedDigit().foregroundStyle(mint) } }
    var chart:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("网络活动").font(.headline);Spacer();Text("物理网卡 · 最近 \(trafficMinutes) 分钟").font(.caption).foregroundStyle(.secondary) }
            Chart {
                ForEach(Array(trafficWindow.history.enumerated()),id:\.offset) { _,p in
                    LineMark(x:.value("时间",Date(timeIntervalSince1970:number(p,"time"))),y:.value("KiB/s",number(p,"down")/1024),series:.value("方向","下行")).foregroundStyle(by:.value("方向","下行"))
                    LineMark(x:.value("时间",Date(timeIntervalSince1970:number(p,"time"))),y:.value("KiB/s",number(p,"up")/1024),series:.value("方向","上行")).foregroundStyle(by:.value("方向","上行"))
                }
            }.chartForegroundStyleScale(["下行":mint,"上行":Color.blue]).chartYScale(domain: .automatic(includesZero:true)).frame(height:170)
            Text("单位 KiB/s；不累计代理转发的重复字节。休眠或退出期间没有样本。").font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(panel).clipShape(RoundedRectangle(cornerRadius:18))
    }
    var memoryPage:some View {
        let mem=m.data["memory"] as? [String:Any] ?? [:]
        return VStack(alignment:.leading,spacing:20) {
            HStack(spacing:14) {
                card("应用内存","app",bytes(number(mem,"app")),"匿名页减去可清除页")
                card("有线内存","lock",bytes(number(mem,"wired")),"系统锁定的内存")
                card("压缩内存","archivebox",bytes(number(mem,"compressed")),"压缩器实际占用")
            }
            TextField("搜索应用",text:$ui.search).textFieldStyle(.roundedBorder)
            Text("下表按 RSS 驻留内存统计，包含共享页，因此各应用之和不等于系统已用内存。展开查看 PID。").font(.caption).foregroundStyle(.secondary)
            VStack(spacing:12) {
                ForEach(Array(rows(m.data,"apps").filter{ui.search.isEmpty || string($0,"name").localizedCaseInsensitiveContains(ui.search)}.enumerated()),id:\.offset) { _,r in
                    DisclosureGroup {
                        ForEach(Array(rows(r,"processes").enumerated()),id:\.offset) { _,p in
                            line("PID \(Int(number(p,"pid"))) · \(string(p,"name"))",bytes(number(p,"memory"))).font(.caption).padding(.vertical,4)
                        }
                    } label: { line("\(string(r,"name"))  ·  \(Int(number(r,"count"))) 个进程",bytes(number(r,"memory"))) }.padding(13).background(panel).clipShape(RoundedRectangle(cornerRadius:10))
                }
            }
        }
    }
    var trafficPage:some View {
        VStack(alignment:.leading,spacing:20) {
            NetworkAddresses(data: m.data)
            TrafficWindowPicker(data: m.data)
            chart
            let proxy=trafficWindow.apps.filter { r in ["clash","mihomo"].contains { string(r,"name").lowercased().contains($0) } }
            HStack(spacing:14) {
                card("Clash 代理下行","arrow.down.circle",bytes(proxy.reduce(0){$0+number($1,"down")}),"最近 \(trafficMinutes) 分钟 · 代理进程统计")
                card("Clash 代理上行","arrow.up.circle",bytes(proxy.reduce(0){$0+number($1,"up")}),"最近 \(trafficMinutes) 分钟 · 不与应用重复相加")
                card("Clash 代理合计","network",bytes(proxy.reduce(0){$0+number($1,"down")+number($1,"up")}),proxy.isEmpty ? "尚无代理流量样本":"Clash / Mihomo")
            }
            if let error=m.data["networkError"] as? String { notice(error) }
            Text("Clash 等代理会再次接收应用流量，排行可分别查看，但不可相加。应用重启建立新基线；连接关闭可能使计数回退，因此排行是已观测流量下界。").font(.callout).foregroundStyle(.secondary)
            TextField("搜索应用",text:$ui.search).textFieldStyle(.roundedBorder)
            HStack { Text("应用").frame(maxWidth:.infinity,alignment:.leading);Text("下行 / 上行").frame(width:190);Text("合计").frame(width:100) }.foregroundStyle(.secondary)
            ForEach(Array(trafficWindow.apps.filter{ui.search.isEmpty || string($0,"name").localizedCaseInsensitiveContains(ui.search)}.enumerated()),id:\.offset) { _,r in
                HStack { Text(string(r,"name")).frame(maxWidth:.infinity,alignment:.leading);Text("\(bytes(number(r,"down"))) / \(bytes(number(r,"up")))").frame(width:190);Text(bytes(number(r,"down")+number(r,"up"))).foregroundStyle(mint).frame(width:100) }.monospacedDigit().padding(14).background(panel).clipShape(RoundedRectangle(cornerRadius:10))
            }
        }
    }
    var codexPage:some View {
        VStack(alignment:.leading,spacing:20) {
            notice("对话级网络字节暂不可归属。Codex 多个对话共享进程与连接；这里的 token 是用量记录，不是流量估算。")
            let traffic=rows(m.data,"traffic").filter{string($0,"name").lowercased().contains("codex")}
            card("Codex 共享流量","network",bytes(traffic.reduce(0){$0+number($1,"down")+number($1,"up")}),"最近 60 分钟已观测 · 未归属到对话")
            if let error=m.data["codexError"] as? String { notice(error) }
            Text("最近一小时活跃对话 · token 增量来自本地日志；日志截断、首次基线及压缩重置可能导致少计。未读取到用量时显示 0，不代表没有网络活动。").font(.callout).foregroundStyle(.secondary)
            ForEach(Array(rows(m.data,"conversations").enumerated()),id:\.offset) { _,r in
                VStack(alignment:.leading,spacing:10) {
                    HStack { Text(string(r,"title")).font(.headline).lineLimit(2);Spacer();Text("\(Int(number(r,"recentTokens"))).tokens".replacingOccurrences(of:".tokens",with:" tokens")).foregroundStyle(mint) }
                    HStack { Text(String(string(r,"id").suffix(12)));Spacer();Text("网络流量：未归属") }.font(.caption).foregroundStyle(.secondary)
                }.padding(18).background(panel).clipShape(RoundedRectangle(cornerRadius:12))
            }
            if rows(m.data,"conversations").isEmpty { Text("没有读取到最近一小时的本地对话记录。").foregroundStyle(.secondary) }
        }
    }
    var sensorsPage:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(spacing:14) {
                ForEach(Array(rows(m.data,"fans").enumerated()),id:\.offset) { _,r in card(string(r,"sensor"),"fan",String(format:"%.0f RPM",number(r,"rpm")),number(r,"rpm")==0 ? "当前停转":"硬件实时读数") }
            }
            if rows(m.data,"fans").isEmpty { notice("没有读到风扇转速；可能是无风扇设备，或系统未开放传感器。") }
            Text("温度传感器").font(.title2.bold())
            Text("保留硬件名称与 SMC 键名，不将未知传感器标成 CPU / GPU 核心。").foregroundStyle(.secondary)
            ForEach(Array(rows(m.data,"temperatures").sorted{number($0,"celsius")>number($1,"celsius")}.enumerated()),id:\.offset) { _,r in
                line(string(r,"sensor"),String(format:"%.1f °C",number(r,"celsius"))).padding(14).background(panel).clipShape(RoundedRectangle(cornerRadius:10))
            }
        }
    }
}
