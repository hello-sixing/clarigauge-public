import SwiftUI

struct NetworkAddresses: View {
    let data: [String: Any]

    var body: some View {
        let info = data["networkInfo"] as? [String: Any] ?? [:]
        let interfaces = rows(info, "interfaces")
        VStack(alignment: .leading, spacing: 8) {
            Text("本机网络地址").font(.subheadline.bold())
            if interfaces.isEmpty {
                Text(info["error"] as? String ?? "等待已连接网卡的地址")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(interfaces.enumerated()), id: \.offset) { _, interface in
                Text(string(interface, "name") + (interface["primary"] as? Bool == true ? " · 当前默认接口" : ""))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(interface["ipv4"] as? [String] ?? [], id: \.self) { address in
                    addressRow("IPv4", address)
                }
                ForEach(interface["ipv6"] as? [String] ?? [], id: \.self) { address in
                    addressRow("IPv6", address)
                }
            }
        }
    }

    private func addressRow(_ family: String, _ address: String) -> some View {
        HStack(alignment: .top) {
            Text(family).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
            Text(address).textSelection(.enabled).fontDesign(.monospaced)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.font(.caption)
    }
}
