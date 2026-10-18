import Foundation
import SQLite3

func tF(_ zh: String, _ en: String) -> String { zh }

@main struct RepositorySafetyRegression {
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw AppFailure("FAIL: " + message) }
    }

    static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch { return }
        throw AppFailure("FAIL: accepted " + message)
    }

    static func open(_ path: URL, _ operation: (OpaquePointer) throws -> Void) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path.path, &handle) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            throw AppFailure("Could not open fixture")
        }
        defer { sqlite3_close(db) }
        try operation(db)
    }

    static func run(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw AppFailure(String(cString: sqlite3_errmsg(db))) }
    }

    static func writeMeta(_ db: OpaquePointer, _ bytes: Data, id: String = "main") throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO items(kind,id,payload) VALUES('meta',?,?)", -1, &statement, nil) == SQLITE_OK else { throw AppFailure("Could not prepare fixture") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, id, -1, transient)
        _ = bytes.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(bytes.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AppFailure("Could not save fixture") }
    }

    static func fixture(_ root: URL, table: String? = "CREATE TABLE items(kind TEXT,id TEXT,payload BLOB)", metas: [(String, Data)] = []) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("footprints.sqlite")
        try open(file) { db in
            if let table { try run(db, table) }
            for (id, bytes) in metas { try writeMeta(db, bytes, id: id) }
        }
        return file
    }

    static func rejectedWithoutChanging(_ root: URL, _ label: String) throws {
        let database = root.appendingPathComponent("footprints.sqlite")
        let before = try Data(contentsOf: database)
        let contents = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        try rejects(label) { _ = try Repository(root: root) }
        try check(try Data(contentsOf: database) == before, label + " preserves original database bytes")
        try check(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == contents,
                  label + " creates no supporting files or directories")
    }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("footprints-repository-safety-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        var oldJournal = Journal(); oldJournal.modifiedAt = date
        let oldBytes = try encoder.encode(oldJournal)

        // Publishing an upgrade snapshot needs an existing library and must never bootstrap it.
        let readOnlyMissing = root.appendingPathComponent("read-only-missing")
        try rejects("read-only missing library") { _ = try Repository(root: readOnlyMissing, readOnly: true) }
        try check(!fm.fileExists(atPath: readOnlyMissing.path), "read-only opening creates no directory")
        let readOnlyRoot = root.appendingPathComponent("read-only-valid")
        let readOnlyFile = try fixture(readOnlyRoot, metas: [("main", oldBytes)])
        let readOnlyBytes = try Data(contentsOf: readOnlyFile)
        let readOnlyRepo = try Repository(root: readOnlyRoot, readOnly: true)
        try check(try readOnlyRepo.load() == oldJournal, "read-only loading retains data")
        try readOnlyRepo.validate(oldJournal, geography: Geography(countries: [], cities: [], world: [], china: []))
        try rejects("read-only save") { try readOnlyRepo.save(oldJournal) }
        try rejects("read-only snapshot") { try readOnlyRepo.dailySnapshot(oldJournal) }
        let readOnlyBackup = Backup(journal: oldJournal, journalDigest: digest(oldBytes), photos: [])
        try rejects("read-only restore") { try readOnlyRepo.restore(readOnlyBackup, current: oldJournal) }
        try check(try Data(contentsOf: readOnlyFile) == readOnlyBytes, "read-only operations preserve database bytes")
        try check(try fm.contentsOfDirectory(atPath: readOnlyRoot.path) == ["footprints.sqlite"], "read-only operations create no supporting files or directories")

        // Only nonexistent roots and explicitly empty directories qualify as first use.
        for alreadyExists in [false, true] {
            let newRoot = root.appendingPathComponent(alreadyExists ? "new-empty" : "new-missing")
            if alreadyExists { try fm.createDirectory(at: newRoot, withIntermediateDirectories: true) }
            let first = try Repository(root: newRoot)
            let firstJournal = try first.load()
            try check(firstJournal.schema == 1 && firstJournal.visits.isEmpty, "first use creates a valid journal")
            let second = try Repository(root: newRoot)
            try check(try second.load() == firstJournal, "new metadata persists without manufacturing another modification time")
        }
        for evidence in ["Photos", "Snapshots", "footprints.sqlite-wal", ".DS_Store", "existing-note.txt"] {
            let dataRoot = root.appendingPathComponent("missing-" + evidence.replacingOccurrences(of: ".", with: "_"))
            try fm.createDirectory(at: dataRoot, withIntermediateDirectories: true)
            let marker = dataRoot.appendingPathComponent(evidence)
            if ["Photos", "Snapshots"].contains(evidence) { try fm.createDirectory(at: marker, withIntermediateDirectories: true) }
            else { try Data("do not overwrite".utf8).write(to: marker) }
            try rejects("missing database beside " + evidence) { _ = try Repository(root: dataRoot) }
            try check(!fm.fileExists(atPath: dataRoot.appendingPathComponent("footprints.sqlite").path), "refusal does not manufacture a blank database")
            try check(try fm.contentsOfDirectory(atPath: dataRoot.path) == [evidence], "existing evidence retained")
        }

        // Physically invalid, semantically incomplete, and unsupported stores remain untouched.
        for (label, bytes) in [("zero", Data()), ("corrupt", Data("not a SQLite database".utf8))] {
            let dataRoot = root.appendingPathComponent(label)
            try fm.createDirectory(at: dataRoot, withIntermediateDirectories: true)
            try bytes.write(to: dataRoot.appendingPathComponent("footprints.sqlite"))
            try rejectedWithoutChanging(dataRoot, label)
        }
        let noTable = root.appendingPathComponent("no-items-table")
        _ = try fixture(noTable, table: "CREATE TABLE other(value TEXT)")
        try rejectedWithoutChanging(noTable, "missing items table")
        let noMeta = root.appendingPathComponent("no-meta")
        _ = try fixture(noMeta)
        try rejectedWithoutChanging(noMeta, "missing metadata")
        let wrongMeta = root.appendingPathComponent("wrong-meta-id")
        _ = try fixture(wrongMeta, metas: [("other", oldBytes)])
        try rejectedWithoutChanging(wrongMeta, "wrong metadata identity")
        let duplicates = root.appendingPathComponent("duplicate-meta")
        _ = try fixture(duplicates, metas: [("main", oldBytes), ("main", oldBytes)])
        try rejectedWithoutChanging(duplicates, "duplicate metadata")
        for (label, text) in [
            ("empty-meta", "{}"),
            ("missing-time", "{\"schema\":1}"),
            ("missing-schema", "{\"modifiedAt\":\"2020-09-13T12:26:40Z\"}"),
            ("null-time", "{\"schema\":1,\"modifiedAt\":null}"),
            ("new-schema", "{\"schema\":999,\"modifiedAt\":\"2020-09-13T12:26:40Z\"}"),
            ("wrong-time-type", "{\"schema\":1,\"modifiedAt\":42}")
        ] {
            let dataRoot = root.appendingPathComponent(label)
            _ = try fixture(dataRoot, metas: [("main", Data(text.utf8))])
            try rejectedWithoutChanging(dataRoot, label)
        }

        // Old metadata retains its real timestamp; the optional new field is digest compatible.
        let validRoot = root.appendingPathComponent("valid-old")
        _ = try fixture(validRoot, metas: [("main", oldBytes)])
        let repo = try Repository(root: validRoot)
        let loaded = try repo.load()
        try check(loaded.modifiedAt == date && loaded.footprintModifiedAt == nil, "old library retains its source time")
        try check(try encoder.encode(loaded) == oldBytes, "old encoding is unchanged when footprint time is absent")
        var edited = loaded
        edited.footprintModifiedAt = date.addingTimeInterval(60)
        edited.modifiedAt = date.addingTimeInterval(120)
        try repo.save(edited)
        try check(try repo.load() == edited, "footprint and overall modification times persist independently")
        var trainOnly = edited; trainOnly.modifiedAt = date.addingTimeInterval(180); trainOnly.train.materials = 3; trainOnly.train.lifetimeMaterials = 3
        try repo.save(trainOnly)
        let afterTrain = try repo.load()
        try check(afterTrain.footprintModifiedAt == edited.footprintModifiedAt, "train update retains footprint timestamp")

        // A later external schema change must not be erased by an already-open repository.
        try open(validRoot.appendingPathComponent("footprints.sqlite")) { db in
            try run(db, "DELETE FROM items")
            var future = trainOnly; future.schema = 999
            try writeMeta(db, encoder.encode(future))
        }
        try rejects("writing over a future schema after opening") { try repo.save(edited) }
        try rejects("future schema remains present after failed save") { _ = try repo.load() }

        // Legacy digest fallback must not ignore an appended footprint timestamp.
        let backupRoot = root.appendingPathComponent("backups")
        let backupRepo = try Repository(root: backupRoot)
        let geography = Geography(countries: [], cities: [], world: [], china: [])
        let oldObject = try JSONSerialization.jsonObject(with: oldBytes) as! [String: Any]
        var legacyObject = oldObject; legacyObject.removeValue(forKey: "train")
        let legacyBytes = try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys, .withoutEscapingSlashes])
        let legacyJournal = try decoder.decode(Journal.self, from: legacyBytes)
        let legacy = Backup(journal: legacyJournal, journalDigest: digest(legacyBytes), photos: [])
        let backupURL = root.appendingPathComponent("legacy.footprintsbackup")
        try encoder.encode(legacy).write(to: backupURL)
        _ = try backupRepo.inspectBackup(backupURL, geography: geography)
        var tampered = legacy; tampered.journal.footprintModifiedAt = date.addingTimeInterval(60)
        try encoder.encode(tampered).write(to: backupURL)
        try rejects("unauthenticated footprint timestamp in legacy backup") { _ = try backupRepo.inspectBackup(backupURL, geography: geography) }
        let newURL = root.appendingPathComponent("new.footprintsbackup")
        try backupRepo.makeBackup(edited).write(to: newURL)
        let newBackup = try backupRepo.inspectBackup(newURL, geography: geography)
        try check(newBackup.journal.footprintModifiedAt == edited.footprintModifiedAt, "new backups authenticate footprint time")
        var removed = newBackup; removed.journal.footprintModifiedAt = nil
        try encoder.encode(removed).write(to: newURL)
        try rejects("removed footprint timestamp in new backup") { _ = try backupRepo.inspectBackup(newURL, geography: geography) }

        print("PASS Repository safety: read-only loading without writes or creation; explicit first use; missing/corrupt/empty/new-schema rejection without mutation; mandatory unique metadata; late-schema overwrite protection; real source times and legacy/new backup authentication")
    }
}
