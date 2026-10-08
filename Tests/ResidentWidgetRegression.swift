import Foundation
import AppKit

// Compile with WidgetExtension/{Models,WidgetSnapshot,WidgetData}.swift.
@main struct ResidentWidgetRegression {
    static func main() throws {
        let city = City(id: "CHN-test", name: "常驻测试", english: "Home", aliases: "", countryID: "CHN", provinceID: "", province: "", continent: "Asia", longitude: 116, latitude: 40, isCustom: false)
        var journal = Journal()
        journal.residentCityID = city.id
        let snapshot = FootprintWidgetSnapshot.make(journal, cities: [city.id: city], countries: [:], chinaTotal: 1)
        precondition(snapshot.residentCityName == city.name && snapshot.residentCountryID == "CHN")
        precondition(snapshot.cities == 0 && snapshot.visits == 0 && snapshot.china == 0 && snapshot.countries == 0)

        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let encoded = try encoder.encode(snapshot)
        let roundtrip = try decoder.decode(FootprintWidgetSnapshot.self, from: encoded)
        precondition(roundtrip.residentCityName == city.name && roundtrip.residentCountryID == "CHN")
        let old = try encoder.encode(FootprintWidgetSnapshot())
        precondition(!String(decoding: old, as: UTF8.self).contains("residentCityName"))
        let oldDecoded = try decoder.decode(FootprintWidgetSnapshot.self, from: old)
        precondition(oldDecoded.residentCityName == nil && oldDecoded.residentCountryID == nil)

        let china = NSImage(size: NSSize(width: 1, height: 1)), world = NSImage(size: NSSize(width: 2, height: 2))
        precondition(FootprintWidgetData(snapshot: snapshot, chinaMap: china, worldMap: world).map === china)
        var overseas = snapshot
        overseas.residentCountryID = "GBR"
        overseas.china = 12
        precondition(FootprintWidgetData(snapshot: overseas, chinaMap: china, worldMap: world).map === world)
        precondition(FootprintWidgetData(snapshot: overseas, chinaMap: china, worldMap: nil).map === china)
        var legacy = snapshot
        legacy.residentCountryID = nil
        legacy.china = 1
        precondition(FootprintWidgetData(snapshot: legacy, chinaMap: china, worldMap: world).map === china)
        legacy.china = 0
        precondition(FootprintWidgetData(snapshot: legacy, chinaMap: china, worldMap: world).map === world)

        journal.visits = [Visit(cityID: city.id)]
        let visited = FootprintWidgetSnapshot.make(journal, cities: [city.id: city], countries: [:], chinaTotal: 1)
        precondition(visited.cities == 1 && visited.visits == 1 && visited.china == 1)
        journal.residentCityID = nil
        let cleared = FootprintWidgetSnapshot.make(journal, cities: [city.id: city], countries: [:], chinaTotal: 1)
        precondition(cleared.cities == visited.cities && cleared.visits == visited.visits && cleared.residentCityName == nil)
        print("PASS Resident Widget: optional cache compatibility, resident metadata roundtrip, unchanged travel totals, clearing home, domestic/overseas map selection and image fallback")
    }
}
