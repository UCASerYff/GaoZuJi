import SwiftUI
import AppKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 把最新足迹统计与迷你羊皮纸地图发布到 App Group 共享容器，供桌面小组件读取。
/// 发布失败不影响主库保存；小组件下次成功发布会拿到最新数据。
@MainActor enum WidgetExporter {
    /// 必须与 App.entitlements 和 Widget.entitlements 中的 App Group 一致。
    static let appGroupID = "5G96498KGJ.com.gaoseries.GaoZuJi"
    private static let chinaMapFile = "widget-map-china.png"
    private static let worldMapFile = "widget-map-world.png"
    private static let snapshotFile = "widget-snapshot.json"
    /// 小组件地图渲染尺寸。WidgetKit 归档时会按屏幕 scale 栅格化图片，
    /// 超过约 100 万像素会被静默丢弃导致小组件空白（V0.6 教训），
    /// 此尺寸 2x 归档约 55 万像素，留足余量且清晰度足够。
    private static let mapSize = CGSize(width: 460, height: 300)
    private static var cachedPaths: AtlasPaths?

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// 保存成功后调用。`onlyIfStale` 用于启动时补发：容器内已有鲜活快照则跳过渲染。
    static func publish(store: Store, onlyIfStale: Bool = false) {
        // 读取主资料失败时保留已有快照，不能把未加载状态当作空白资料发布。
        guard store.ready else { return }
        // 测试资料库隔离（GAOZUJI_DATA_DIR）时不污染真实小组件。
        guard ProcessInfo.processInfo.environment["GAOZUJI_DATA_DIR"] == nil else { return }
        guard let container = containerURL else { return }
        let snapshotURL = container.appendingPathComponent(snapshotFile)
        // 版本标记：升级后渲染样式可能变化（如 V0.5 的紧凑中国取景），版本不一致时强制重发。
        let markerURL = container.appendingPathComponent("widget-publisher-version.txt")
        let currentVersion = FootprintsBundle.bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let publishedVersion = try? String(contentsOf: markerURL, encoding: .utf8)
        if onlyIfStale, publishedVersion == currentVersion,
           let date = try? snapshotURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(date) < 24 * 3600 { return }
        let snapshot = FootprintWidgetSnapshot.make(store.journal, cities: store.cityIndex, countries: store.countries, chinaTotal: store.chinaTotal)
        do {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
        } catch { return }
        if cachedPaths == nil { cachedPaths = AtlasPaths(store.geography) }
        guard let paths = cachedPaths else { return }
        let visited = store.allVisitedIDs.compactMap { store.cityIndex[$0] }
        render(paths: paths, china: true, cities: visited, residentCity: store.residentCity, to: container.appendingPathComponent(chinaMapFile))
        render(paths: paths, china: false, cities: visited, residentCity: store.residentCity, to: container.appendingPathComponent(worldMapFile))
        try? currentVersion.write(to: markerURL, atomically: true, encoding: .utf8)
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
#endif
    }

    private static func render(paths: AtlasPaths, china: Bool, cities: [City], residentCity: City?, to url: URL) {
        let canvas = AtlasCanvas(paths: paths, china: china, cities: cities, selected: nil, showLabels: false, compactChina: china, residentCity: residentCity)
        let view = NSHostingView(rootView: canvas.frame(width: mapSize.width, height: mapSize.height))
        view.frame = CGRect(origin: .zero, size: mapSize)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url, options: .atomic)
    }
}
