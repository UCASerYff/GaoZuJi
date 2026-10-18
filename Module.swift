import SwiftUI
import Foundation

public final class FootprintsBundleMarker: NSObject {}
enum FootprintsBundle {
    static let bundle = Bundle(for: FootprintsBundleMarker.self)
    static let defaults = UserDefaults(suiteName: ProcessInfo.processInfo.environment["GAOQINIANSAN_INTEGRATION_TEST"] == "1" ? "com.gaoseries.GaoZuJi.test.Footprints" : "com.gaoseries.GaoZuJi.Footprints") ?? .standard
}

@MainActor enum FootprintsRuntime {
    static let store = Store()
    /// 计算属性而非静态缓存：资源错误重试成功后能拿到按新 geography 构建的路径。
    static var atlasPaths: AtlasPaths { AtlasPaths(store.geography) }
}

public struct FootprintsModuleView: View {
    @ObservedObject private var store = FootprintsRuntime.store
    private let route: URL?
    private let routeRevision: Int
    @State private var handledRevision = 0
    public init(route: URL? = nil, routeRevision: Int = 0) {
        self.route = route
        self.routeRevision = routeRevision
    }
    public var body: some View {
        RootView().environmentObject(store)
            .environment(\.locale, Locale(identifier: GQNSLanguage.localeIdentifier))
            .onAppear(perform: handleRoute)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GaoSeries.footprints.game"))) { _ in store.section = "列车" }
            .onChange(of: routeRevision) { _, _ in handleRoute() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GaoSeries.footprints.new"))) { _ in store.editor = EditorRequest() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GaoSeries.footprints.search"))) { _ in
                store.section = "地图"
                NotificationCenter.default.post(name: .focusSearch, object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GaoSeries.footprints.undo"))) { _ in store.undo() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GaoSeries.footprints.export"))) { _ in store.exportBackup() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GaoSeries.footprints.import"))) { _ in store.restoreBackup() }
    }
    private func handleRoute() {
        guard routeRevision > handledRevision, let route, route.scheme == "gaozuji" else { return }
        handledRevision = routeRevision
        store.section = "地图"
        if route.host == "map" {
            let scope = URLComponents(url: route, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "scope" }?.value
            store.search = ""; store.year = 0; store.tripFilter = ""; store.selectedCity = nil
            if scope == "china" || scope == "world" { store.widgetMapScope = scope; store.widgetMapNavigationRevision &+= 1 }
        }
    }
}

/// V1.9：供主 app 设置中心嵌入的模块设置视图（无参初始化，自注入模块内 store 单例）。
/// 设置内容即模块内原「设置」页（SettingsPage）；语言跟随 UserDefaults `gqns.language`。
public struct FootprintsSettingsView: View {
    public init() {}
    public var body: some View {
        SettingsPage()
            .environmentObject(FootprintsRuntime.store)
            .environment(\.locale, Locale(identifier: GQNSLanguage.localeIdentifier))
    }
}

