import Foundation
import AppKit
func tF(_ zh: String, _ en: String) -> String { zh }

/// Explicit upgrade operation, not a GUI test: read an existing database and publish derived widget data.
@main struct PublishWidget {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            throw AppFailure("Usage: publish-widget <installed-app> <existing-data-root> <app-group-root>")
        }
        let app = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let dataRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let sharedRoot = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.gaoseries.GaoZuJi").isEmpty else {
            throw AppFailure("Close the main app before running the upgrade publisher")
        }
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == "com.gaoseries.GaoZuJi",
              let version = info?["CFBundleShortVersionString"] as? String,
              let build = info?["CFBundleVersion"] as? String,
              FileManager.default.fileExists(atPath: sharedRoot.path) else { throw AppFailure("Invalid installation or missing shared container") }
        let geographyURL = app.appendingPathComponent("Contents/Frameworks/Footprints.framework/Resources/Geography.json")
        let geography = try JSONDecoder().decode(Geography.self, from: Data(contentsOf: geographyURL))
        let repository = try Repository(root: dataRoot, readOnly: true)
        let journal = try repository.load()
        try repository.validate(journal, geography: geography)
        for attachment in journal.attachments {
            let bytes = try Data(contentsOf: repository.photoURL(attachment))
            guard bytes.count == attachment.size, digest(bytes) == attachment.sha256 else { throw AppFailure("Attachment verification failed; publication stopped") }
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.gaoseries.GaoZuJi").isEmpty,
              try WidgetSourceFingerprint.make(journal: repository.load(), geography: geography) == WidgetSourceFingerprint.make(journal: journal, geography: geography)
        else { throw AppFailure("The source changed during preparation; retry while the app is closed") }
        let changed = try WidgetPublisherCore.publish(journal: journal, geography: geography, root: sharedRoot,
            appVersion: version, appBuild: build)
        let generation = try WidgetGenerationStore(root: sharedRoot).load()
        let result: [String: Any] = ["published": changed, "generationID": generation.generationID,
            "sourceModifiedAt": ISO8601DateFormatter().string(from: generation.sourceModifiedAt),
            "publishedAt": ISO8601DateFormatter().string(from: generation.publishedAt),
            "sourceDigest": generation.sourceDigest, "cities": generation.snapshot.cities,
            "countries": generation.snapshot.countries, "visits": generation.snapshot.visits,
            "version": generation.appVersion, "build": generation.appBuild]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
