import Foundation
import AppKit

/// 小组件数据：解码主 App 发布到 App Group 的快照与迷你地图。
/// 全部字段容错解码，旧版本快照缺失字段时也能显示。
struct FootprintWidgetData {
    static let appGroupID = "5G96498KGJ.com.gaoseries.GaoZuJi"

    let snapshot: FootprintWidgetSnapshot?
    let chinaMap: NSImage?
    let worldMap: NSImage?

    static let empty = FootprintWidgetData(snapshot: nil, chinaMap: nil, worldMap: nil)

    /// 常驻城市优先决定范围，确保海外常驻地点不会被中国视图隐藏。
    /// 未设置常驻城市时沿用已有足迹范围。
    var map: NSImage? {
        if let country = snapshot?.residentCountryID {
            return country == "CHN" ? (chinaMap ?? worldMap) : (worldMap ?? chinaMap)
        }
        if let snapshot, snapshot.china > 0, let chinaMap { return chinaMap }
        return worldMap ?? chinaMap
    }

    private static func load(from directory: URL) -> FootprintWidgetData? {
        let snapshotURL = directory.appendingPathComponent("widget-snapshot.json")
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(FootprintWidgetSnapshot.self, from: data) else { return nil }
        return FootprintWidgetData(
            snapshot: snapshot,
            chinaMap: NSImage(contentsOf: directory.appendingPathComponent("widget-map-china.png")),
            worldMap: NSImage(contentsOf: directory.appendingPathComponent("widget-map-world.png"))
        )
    }

    static func load() -> FootprintWidgetData {
        // 小组件运行在沙箱中，只读主 App 镜像到 App Group 容器的快照；
        // ad-hoc 签名安装没有共享容器，小组件显示空状态，下次打开主 App 后恢复。
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
              let data = load(from: container) else {
            return .empty
        }
        return data
    }
}
