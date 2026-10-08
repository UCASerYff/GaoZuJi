import Foundation
import SQLite3

func tF(_ zh: String, _ en: String) -> String { zh }

/// The exact journal fields exported before resident cities were introduced.
private struct PreviousJournal: Encodable {
    var schema: Int
    var datasetVersion: String
    var visits: [Visit]
    var trips: [Trip]
    var customCities: [City]
    var attachments: [Attachment]
    var modifiedAt: Date
    var train: TrainState?

    init(_ journal: Journal, includeTrain: Bool = true) {
        schema = journal.schema; datasetVersion = journal.datasetVersion
        visits = journal.visits; trips = journal.trips; customCities = journal.customCities
        attachments = journal.attachments; modifiedAt = journal.modifiedAt
        train = includeTrain ? journal.train : nil
    }
}

private struct PreviousBackup: Encodable {
    var format = "GaoZuJi.backup"
    var version = 1
    var appVersion = "4.0"
    var createdAt: Date
    var journal: PreviousJournal
    var journalDigest: String
    var photos: [PhotoPayload]
}

@main struct ResidentCityRegression {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw AppFailure("FAIL: \(message)") }
    }

    static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch { return }
        throw AppFailure("FAIL: accepted \(message)")
    }

    static func city(_ id: String, _ country: String, _ lon: Double, _ lat: Double, custom: Bool = false) -> City {
        City(id: id, name: id, english: id, aliases: "", countryID: country,
             provinceID: "", province: "", continent: country == "CHN" ? "亚洲" : "欧洲",
             longitude: lon, latitude: lat, isCustom: custom)
    }

    static func metricSignature(_ journal: Journal, cities: [String: City], year: Int? = nil, tripID: String? = nil) -> String {
        let m = Metrics.compute(journal, cities: cities, year: year, tripID: tripID)
        return "\(m.cities)|\(m.countries)|\(m.china)|\(m.visits)|\(m.trips)|\(m.continents.sorted())|\(m.newCities)|\(m.newCountries)|\(m.revisits)"
    }

    static func replaceMeta(at root: URL, bytes: Data) throws {
        var db: OpaquePointer?
        guard sqlite3_open(root.appendingPathComponent("footprints.sqlite").path, &db) == SQLITE_OK else {
            throw AppFailure("Could not open fixture database")
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE items SET payload=? WHERE kind='meta' AND id='main'", -1, &stmt, nil) == SQLITE_OK else {
            throw AppFailure("Could not prepare legacy metadata")
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = bytes.withUnsafeBytes { sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32(bytes.count), transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE, sqlite3_changes(db) == 1 else {
            throw AppFailure("Could not replace legacy metadata")
        }
    }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("resident-city-regression-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let repositoryRoot = root.appendingPathComponent("Repository")
        let repo = try Repository(root: repositoryRoot)
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let beijing = city("beijing", "CHN", 116.4, 39.9)
        let shanghai = city("shanghai", "CHN", 121.5, 31.2)
        let custom = city("custom-paris", "FRA", 2.35, 48.85, custom: true)
        let geography = Geography(countries: [
            Country(id: "CHN", name: "中国", english: "China", continent: "亚洲"),
            Country(id: "FRA", name: "法国", english: "France", continent: "欧洲")
        ], cities: [beijing, shanghai], world: [], china: [])
        let cities = Dictionary(uniqueKeysWithValues: [beijing, shanghai, custom].map { ($0.id, $0) })
        let photoBytes = Data("existing attachment bytes must survive migration".utf8)
        let photoID = "5F69C7E2-49E3-442B-9416-5EC89AEB259D"
        let photo = Attachment(id: photoID, filename: photoID + ".jpg", sha256: digest(photoBytes), size: photoBytes.count)
        var original = Journal()
        original.modifiedAt = date
        original.customCities = [custom]
        original.attachments = [photo]
        original.trips = [Trip(id: "trip", name: "旧旅行", note: "旅行笔记", createdAt: date)]
        original.visits = [Visit(id: "visit", cityID: beijing.id,
            date: VisitDate(precision: .year, year: 2020), tripID: "trip", note: "原来的旅行回忆",
            photoIDs: [photoID], createdAt: date, modifiedAt: date)]
        _ = TrainEngine.settle(&original.train, journal: original)
        TrainEngine.prepare(&original.train, cities: [beijing, shanghai])
        try check(TrainEngine.depart(state: &original.train, destination: shanghai, now: date), "fixture departs")
        // Match the established ISO-8601 storage precision before checking equality.
        original = try decoder.decode(Journal.self, from: encoder.encode(original))
        try repo.validate(original, geography: geography)
        try photoBytes.write(to: repo.photoURL(photo))

        // A previous release's JSON and SQLite rows must load without adding a visit.
        let oldJSON = try encoder.encode(PreviousJournal(original))
        let decoded = try decoder.decode(Journal.self, from: oldJSON)
        try check(decoded == original && decoded.residentCityID == nil, "old journal defaults to no resident city")
        try check(try encoder.encode(decoded) == oldJSON, "nil residence preserves old digest encoding")
        try repo.save(original)
        var oldMeta = original
        oldMeta.visits = []; oldMeta.trips = []; oldMeta.customCities = []; oldMeta.attachments = []
        try replaceMeta(at: repositoryRoot, bytes: encoder.encode(PreviousJournal(oldMeta)))
        let upgraded = try repo.load()
        try repo.validate(upgraded, geography: geography)
        try check(upgraded == original, "SQLite upgrade preserves records and active train journey")
        try check(try Data(contentsOf: repo.photoURL(photo)) == photoBytes, "SQLite upgrade preserves attachment")

        // Setting, changing and clearing only changes optional metadata, including custom cities.
        for selection in [Optional(shanghai.id), Optional(custom.id), Optional(beijing.id), nil] {
            var updated = original
            updated.residentCityID = selection
            try repo.validate(updated, geography: geography)
            try repo.save(updated)
            let reloaded = try Repository(root: repositoryRoot).load()
            try check(reloaded == updated, "resident-city selection persists across reopening: \(selection ?? "nil")")
            try check(reloaded.visits == original.visits && reloaded.train == original.train, "residence does not manufacture visits or alter train state")
            for filter in [(nil as Int?, nil as String?), (2020, nil), (nil, "trip"), (2021, nil)] {
                try check(metricSignature(reloaded, cities: cities, year: filter.0, tripID: filter.1) ==
                          metricSignature(original, cities: cities, year: filter.0, tripID: filter.1), "filtered travel metrics remain unchanged")
            }
            var train = reloaded.train
            try check(TrainEngine.settle(&train, journal: reloaded) == 0 && train == original.train, "residence grants no supplies or duplicate rewards")
        }
        var empty = Journal(); empty.residentCityID = shanghai.id
        var emptyTrain = TrainState()
        try check(TrainEngine.settle(&emptyTrain, journal: empty) == 0 && emptyTrain == TrainState(), "residence alone grants no reward")
        try check(Metrics.compute(empty, cities: cities).cities == 0 && empty.visits.isEmpty, "residence alone does not count as a visited city")
        for invalid in ["missing-city", "", " "] {
            var invalidJournal = original; invalidJournal.residentCityID = invalid
            try rejects("invalid residence \(invalid)") { try repo.validate(invalidJournal, geography: geography) }
        }
        var missingCustom = original; missingCustom.residentCityID = custom.id; missingCustom.customCities = []
        try rejects("removed custom resident city") { try repo.validate(missingCustom, geography: geography) }

        // Both old backup generations remain readable; new exports authenticate the residence.
        let payloads = [PhotoPayload(attachment: photo, data: photoBytes)]
        for includeTrain in [true, false] {
            let previous = PreviousJournal(original, includeTrain: includeTrain)
            let backup = PreviousBackup(appVersion: includeTrain ? "4.0" : "3.46", createdAt: date,
                journal: previous, journalDigest: digest(try encoder.encode(previous)), photos: payloads)
            let url = root.appendingPathComponent(includeTrain ? "previous.footprintsbackup" : "legacy.footprintsbackup")
            try encoder.encode(backup).write(to: url)
            let inspected = try repo.inspectBackup(url, geography: geography)
            var expected = original
            if !includeTrain { expected.train = TrainState() }
            try check(inspected.journal == expected && inspected.journal.residentCityID == nil, "previous full backup accepted")
            // An added valid residence must not sneak through the legacy digest fallback.
            var tampered = inspected; tampered.journal.residentCityID = shanghai.id
            let tamperedURL = root.appendingPathComponent("tampered-old.footprintsbackup")
            try encoder.encode(tampered).write(to: tamperedURL)
            try rejects("resident city appended to an old backup") { _ = try repo.inspectBackup(tamperedURL, geography: geography) }
        }
        var selected = original; selected.residentCityID = custom.id
        let newURL = root.appendingPathComponent("new.footprintsbackup")
        try repo.makeBackup(selected).write(to: newURL)
        let inspected = try repo.inspectBackup(newURL, geography: geography)
        try check(inspected.journal == selected, "new backup preserves custom residence")
        for alteration in [Optional(shanghai.id), nil] {
            var tampered = inspected; tampered.journal.residentCityID = alteration
            let url = root.appendingPathComponent("tampered-new.footprintsbackup")
            try encoder.encode(tampered).write(to: url)
            try rejects("modified or removed residence in new backup") { _ = try repo.inspectBackup(url, geography: geography) }
        }
        var unauthenticated = inspected; unauthenticated.journalDigest = ""
        let emptyDigestURL = root.appendingPathComponent("empty-digest.footprintsbackup")
        try encoder.encode(unauthenticated).write(to: emptyDigestURL)
        try rejects("empty digest when legacy fallback is ineligible") { _ = try repo.inspectBackup(emptyDigestURL, geography: geography) }
        var badType = try JSONSerialization.jsonObject(with: oldJSON) as! [String: Any]
        badType["residentCityID"] = 42
        try rejects("wrong residence JSON type") {
            _ = try decoder.decode(Journal.self, from: JSONSerialization.data(withJSONObject: badType))
        }
        try repo.restore(inspected, current: original)
        try check(try repo.load() == selected, "restoring full backup persists residence and progress")
        try check(try Data(contentsOf: repo.photoURL(photo)) == photoBytes, "restore retains attachment bytes")
        let safetyCopies = try fm.contentsOfDirectory(at: repositoryRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "footprintsbackup" }
        try check(safetyCopies.count == 1, "restore retains a safety backup")
        let safety = try repo.inspectBackup(safetyCopies[0], geography: geography)
        try check(safety.journal == original, "restore safety backup retains original journal")

        print("PASS Resident city: old JSON/SQLite migration; set/change/clear persistence; built-in/custom validation; old/new backup compatibility and tamper rejection; unchanged visits, metrics, train rewards, journey and attachments; restore with safety copy")
    }
}
