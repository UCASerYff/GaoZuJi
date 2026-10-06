import WidgetKit

struct FootprintWidgetEntry: TimelineEntry {
    let date: Date
    let data: FootprintWidgetData
}

struct FootprintWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FootprintWidgetEntry {
        FootprintWidgetEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (FootprintWidgetEntry) -> Void) {
        completion(FootprintWidgetEntry(date: Date(), data: FootprintWidgetData.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FootprintWidgetEntry>) -> Void) {
        let now = Date()
        let entry = FootprintWidgetEntry(date: now, data: FootprintWidgetData.load())
        // 跨天后统计措辞保持准确；主 App 保存后也会主动 reloadAllTimelines()。
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let nextDay = FootprintWidgetEntry(date: midnight, data: entry.data)
        completion(Timeline(entries: [entry, nextDay], policy: .after(now.addingTimeInterval(15 * 60))))
    }
}
