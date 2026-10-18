import Foundation
import AppKit
import CoreGraphics
import ImageIO

// Compile with WidgetExtension/{Models,WidgetData}.swift and Shared/{WidgetSnapshot,WidgetGeneration}.swift.
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
        try verifyGenerationReads(snapshot: snapshot)
        print("PASS Resident Widget: optional cache compatibility, resident metadata roundtrip, unchanged travel totals, clearing home, domestic/overseas map selection and image fallback")
    }

    static func verifyGenerationReads(snapshot: FootprintWidgetSnapshot) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("resident-widget-read-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetGenerationStore(root: directory)
        let sourceDate = Date(timeIntervalSince1970: 1_792_000_000)
        var firstSnapshot = snapshot
        firstSnapshot.sourceModifiedAt = sourceDate
        let first = try WidgetGeneration(sourceDigest: String(repeating: "a", count: 64), sourceModifiedAt: sourceDate, appVersion: "4.02", appBuild: "3", snapshot: firstSnapshot, chinaPNG: fixturePNG(), worldPNG: fixturePNG(), publishedAt: sourceDate.addingTimeInterval(10))
        try store.publish(first)
        let requestDate = sourceDate.addingTimeInterval(20)
        let firstRead = FootprintWidgetData.load(from: directory, reason: "timeline", family: "systemMedium", requestedAt: requestDate)
        precondition(firstRead.generationID == first.generationID && firstRead.readResult == "current")
        precondition(firstRead.sourceModifiedAt == sourceDate && firstRead.requestedAt == requestDate)
        precondition(firstRead.mapScope == "china" && firstRead.mapURL?.absoluteString == "gaozuji://map?scope=china")

        var secondSnapshot = firstSnapshot
        secondSnapshot.residentCountryID = "GBR"
        secondSnapshot.sourceModifiedAt = sourceDate.addingTimeInterval(30)
        let second = try WidgetGeneration(sourceDigest: String(repeating: "b", count: 64), sourceModifiedAt: sourceDate.addingTimeInterval(30), appVersion: "4.02", appBuild: "3", snapshot: secondSnapshot, chinaPNG: fixturePNG(), worldPNG: fixturePNG(), publishedAt: sourceDate.addingTimeInterval(40))
        try store.publish(second)
        let secondRead = FootprintWidgetData.load(from: directory, reason: "timeline", family: "systemMedium", requestedAt: requestDate)
        precondition(secondRead.generationID == second.generationID && secondRead.mapScope == "world")
        precondition(secondRead.mapURL?.absoluteString == "gaozuji://map?scope=world")

        try Data("corrupt current generation".utf8).write(to: directory.appendingPathComponent("widget-generation.json"), options: .atomic)
        let fallback = FootprintWidgetData.load(from: directory, reason: "timeline", family: "systemMedium", requestedAt: requestDate)
        precondition(fallback.generationID == first.generationID && fallback.readResult == "previous" && fallback.failureCode != nil)
        let receiptURL = directory.appendingPathComponent("widget-diagnostics/latest-timeline-systemMedium.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let receipt = try decoder.decode(WidgetReadReceipt.self, from: Data(contentsOf: receiptURL))
        precondition(receipt.generationID == first.generationID && receipt.result == "previous")
        precondition(receipt.sourceModifiedAt == sourceDate && receipt.publishedAt == first.publishedAt && receipt.requestedAt == requestDate)
        let receiptText = try String(contentsOf: receiptURL, encoding: .utf8)
        precondition(!receiptText.contains(firstSnapshot.residentCityName!) && !receiptText.contains(directory.path))
        for _ in 0..<3 { _ = FootprintWidgetData.load(from: directory, reason: "timeline", family: "systemMedium", requestedAt: requestDate) }
        let diagnostics = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("widget-diagnostics"), includingPropertiesForKeys: nil)
        precondition(diagnostics.count == 1)

        try Data("corrupt previous generation".utf8).write(to: directory.appendingPathComponent("widget-generation.previous.json"), options: .atomic)
        // A valid-looking legacy split snapshot must never mask failure of the atomic package.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(firstSnapshot).write(to: directory.appendingPathComponent("widget-snapshot.json"))
        let unavailable = FootprintWidgetData.load(from: directory, reason: "timeline", family: "systemMedium", requestedAt: requestDate)
        precondition(unavailable.snapshot == nil && unavailable.chinaMap == nil && unavailable.worldMap == nil)
        precondition(unavailable.failureCode != nil && unavailable.mapURL?.absoluteString == "gaozuji://map")
        print("PASS Widget Read: atomic generation, current/previous receipt, genuine source time, matching map links, bounded private-free diagnostics, invalid generation stays unavailable")
    }

    /// One-pixel encoded fixture; no application, window, or renderer is started.
    static func fixturePNG() throws -> Data {
        let pixels = Data([50, 90, 70, 255])
        let provider = CGDataProvider(data: pixels as CFData)!
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
