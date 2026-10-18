import Foundation
import ImageIO
func tF(_ zh: String, _ en: String) -> String { zh }
@main struct WidgetPublisherRegression {
    static func main() throws {
        func require(_ predicate: @autoclosure () throws -> Bool) throws { let value = try predicate(); precondition(value) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("footprint-publisher-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let china = Country(id: "CHN", name: "China", english: "China", continent: "Asia")
        let france = Country(id: "FRA", name: "France", english: "France", continent: "Europe")
        let a = City(id: "a", name: "A", english: "A", aliases: "", countryID: "CHN", provinceID: "a", province: "", continent: "Asia", longitude: 116, latitude: 40, isCustom: false)
        let b = City(id: "b", name: "B", english: "B", aliases: "", countryID: "FRA", provinceID: "b", province: "", continent: "Europe", longitude: 2, latitude: 48, isCustom: false)
        func region(_ c: City) -> GeoRegion {
            GeoRegion(id: c.id, name: c.name, countryID: c.countryID, provinceID: c.provinceID, cityID: c.id,
                rings: [[[c.longitude-2,c.latitude-2],[c.longitude+2,c.latitude-2],[c.longitude+2,c.latitude+2],[c.longitude-2,c.latitude+2],[c.longitude-2,c.latitude-2]]])
        }
        let geography = Geography(countries: [china,france], cities: [a,b], world: [region(a),region(b)], china: [region(a)])
        var journal = Journal(); journal.modifiedAt = date
        journal.visits = [Visit(id: "one", cityID: a.id, createdAt: date, modifiedAt: date)]
        func publish(_ value: Journal, now: Date = date.addingTimeInterval(60), version: String = "4.02") throws -> Bool {
            try WidgetPublisherCore.publish(journal: value, geography: geography, root: root, appVersion: version, appBuild: "3", now: now)
        }
        let storage = WidgetGenerationStore(root: root)
        try require(try publish(journal))
        let first = try storage.load()
        try require(first.snapshot.cities == 1 && first.snapshot.countries == 1 && first.sourceModifiedAt == date)
        try require(!(try publish(journal, now: date.addingTimeInterval(10 * 86400)))); try require(try storage.load().generationID == first.generationID)
        var trainOnly = journal; trainOnly.train.materials = 1; trainOnly.modifiedAt = date.addingTimeInterval(3600)
        try require(!(try publish(trainOnly))); try require(try storage.load().sourceModifiedAt == date)
        journal.visits.append(Visit(id: "two", cityID: b.id, createdAt: date, modifiedAt: date))
        journal.footprintModifiedAt = date.addingTimeInterval(120)
        try require(try publish(journal)); let two = try storage.load()
        try require(two.snapshot.cities == 2 && two.snapshot.countries == 2 && two.snapshot.continents == 2)
        try require(first.worldDigest != two.worldDigest)
        journal.visits.reverse(); try require(!(try publish(journal)))
        journal.visits = [Visit(id: "one", cityID: b.id, createdAt: date, modifiedAt: date.addingTimeInterval(180))]
        journal.footprintModifiedAt = date.addingTimeInterval(180)
        try require(try publish(journal)); let edited = try storage.load()
        try require(edited.snapshot.china == 0 && edited.snapshot.cities == 1 && edited.chinaDigest != first.chinaDigest)
        journal.visits = []; journal.footprintModifiedAt = date.addingTimeInterval(240)
        try require(try publish(journal)); let removed = try storage.load()
        try require(removed.snapshot.visits == 0 && removed.snapshot.cities == 0)
        journal.residentCityID = a.id; try require(try publish(journal)); let home = try storage.load()
        try require(home.snapshot.cities == 0 && home.snapshot.residentCityName == "A" && home.chinaDigest != removed.chinaDigest)
        journal.residentCityID = b.id; try require(try publish(journal)); let abroad = try storage.load()
        try require(abroad.snapshot.residentCountryID == "FRA" && abroad.worldDigest != home.worldDigest)
        journal.residentCityID = nil; try require(try publish(journal))
        let beforeFailure = try storage.load()
        do {
            _ = try WidgetPublisherCore.publish(journal: journal, geography: Geography(countries: [],cities: [],world: [],china: []), root: root, appVersion: "4.02", appBuild: "3")
            fatalError("Accepted missing geography")
        } catch {}
        var broken = geography
        broken.world.append(GeoRegion(id: "broken", name: "broken", countryID: "CHN", provinceID: "", cityID: "", rings: [[[1, 1], [2], [3, 3]]]))
        do {
            _ = try WidgetPublisherCore.publish(journal: journal, geography: broken, root: root, appVersion: "4.02", appBuild: "3")
            fatalError("Accepted partially corrupt geography")
        } catch {}
        try require(try storage.load().generationID == beforeFailure.generationID)
        try require(try publish(journal, version: "4.03")); let upgrade = try storage.load()
        try require(upgrade.sourceModifiedAt == journal.footprintModifiedAt)
        print("PASS Publisher: add/edit/delete/home scope; both map hashes tied to metrics; no-change and train-only idempotency; stable source time across day/month/timezone-independent Date; upgrade republish; render failure preserves last group")
    }
}
