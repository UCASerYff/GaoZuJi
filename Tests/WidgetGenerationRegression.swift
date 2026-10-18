import Foundation
import CoreGraphics
import ImageIO

func tF(_ zh: String, _ en: String) -> String { zh }

private struct TestFailure: Error { let message: String }

private final class ConcurrentResults: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [String] = []
    func record(_ value: String) { lock.lock(); failures.append(value); lock.unlock() }
    func values() -> [String] { lock.lock(); defer { lock.unlock() }; return failures }
}

@main struct WidgetGenerationRegression {
    static let sourceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw TestFailure(message: message) }
    }

    static func rejects(_ code: WidgetGenerationError, _ name: String, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch let error as WidgetGenerationError {
            try check(error == code, name + " has wrong error code: " + error.code)
            return
        }
        throw TestFailure(message: name + " was accepted")
    }

    static func png(width: Int = 32, height: Int = 24, seed: UInt32 = 1, noise: Bool = false) throws -> Data {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let pixels = context.data else {
            throw TestFailure(message: "fixture image context")
        }
        let bytes = pixels.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var state = seed
        for i in 0..<(width * height) {
            if noise { state ^= state << 13; state ^= state >> 17; state ^= state << 5 }
            bytes[i * 4] = UInt8(truncatingIfNeeded: state)
            bytes[i * 4 + 1] = UInt8(truncatingIfNeeded: state >> 8)
            bytes[i * 4 + 2] = UInt8(truncatingIfNeeded: state >> 16)
            bytes[i * 4 + 3] = 255
        }
        guard let image = context.makeImage() else { throw TestFailure(message: "fixture CGImage") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)
        else { throw TestFailure(message: "fixture PNG destination") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TestFailure(message: "fixture PNG encode") }
        return output as Data
    }

    static func generation(_ sequence: Int, image: Data) throws -> WidgetGeneration {
        var snapshot = FootprintWidgetSnapshot()
        snapshot.generatedAt = sourceDate.addingTimeInterval(Double(sequence))
        snapshot.sourceModifiedAt = sourceDate
        snapshot.cities = sequence == 0 ? 0 : 1
        snapshot.countries = sequence == 0 ? 0 : 1
        snapshot.china = sequence == 0 ? 0 : 1
        snapshot.chinaTotal = 370
        snapshot.continents = sequence == 0 ? 0 : 1
        snapshot.visits = sequence
        return try WidgetGeneration(sourceDigest: WidgetGeneration.digest(Data("source-\(sequence)".utf8)),
            sourceModifiedAt: sourceDate, appVersion: "4.02", appBuild: "3", snapshot: snapshot,
            chinaPNG: image, worldPNG: image, publishedAt: snapshot.generatedAt)
    }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("widget-generation-regression-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let store = WidgetGenerationStore(root: root)
        let current = root.appendingPathComponent(WidgetGenerationStore.currentFilename)
        let previous = root.appendingPathComponent(WidgetGenerationStore.previousFilename)
        let map = try png()
        let first = try generation(1, image: map)
        let second = try generation(2, image: try png(seed: 2))
        try rejects(.missing, "missing library") { _ = try store.load() }
        try check(!fm.fileExists(atPath: root.path), "read created a default library")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // Legacy split files never form an accepted complete generation.
        try WidgetGeneration.makeEncoder().encode(first.snapshot).write(to: root.appendingPathComponent("widget-snapshot.json"))
        try map.write(to: root.appendingPathComponent("widget-map-china.png"))
        try map.write(to: root.appendingPathComponent("widget-map-world.png"))
        try rejects(.missing, "legacy split fallback") { _ = try store.load() }

        try store.publish(first)
        let initial = try store.loadResult()
        try check(initial.source == "current" && initial.fallbackReason == nil, "first publication source")
        try check(initial.generation.generationID == first.generationID, "first generation identity")
        try check(!fm.fileExists(atPath: previous.path), "first publication invented a previous generation")
        try store.publish(second)
        try check(try store.load().generationID == second.generationID, "second publication")
        let savedPrevious = try WidgetGeneration.makeDecoder().decode(WidgetGeneration.self, from: Data(contentsOf: previous))
        try check(savedPrevious.generationID == first.generationID, "previous retained wrong generation")
        try check(try store.load().sourceModifiedAt == sourceDate, "publishing changed business time")

        let baseline = try Data(contentsOf: current)
        var malformed = second
        malformed.worldPNG = Data()
        malformed.worldDigest = WidgetGeneration.digest(malformed.worldPNG)
        try rejects(.invalidPNG, "missing world image") { try store.publish(malformed) }
        malformed = second; malformed.worldPNG = Data("not a PNG".utf8)
        malformed.worldDigest = WidgetGeneration.digest(malformed.worldPNG)
        try rejects(.invalidPNG, "corrupt image") { try store.publish(malformed) }
        malformed = second; malformed.worldPNG = map.prefix(map.count / 2)
        malformed.worldDigest = WidgetGeneration.digest(malformed.worldPNG)
        try rejects(.invalidPNG, "truncated real PNG") { try store.publish(malformed) }
        malformed = second; malformed.snapshot.visits += 1
        try rejects(.digestMismatch, "statistics digest mismatch") { try store.publish(malformed) }
        malformed = second; malformed.chinaDigest = String(repeating: "0", count: 64)
        try rejects(.digestMismatch, "map digest mismatch") { try store.publish(malformed) }
        malformed = second; malformed.schema = 2
        try rejects(.unsupportedSchema, "future generation schema") { try store.publish(malformed) }
        malformed = second; malformed.snapshot.schema = 2
        try rejects(.unsupportedSchema, "future statistics schema") { try store.publish(malformed) }
        malformed = second; malformed.sourceModifiedAt = sourceDate.addingTimeInterval(1)
        try rejects(.invalidDate, "different business times") { try store.publish(malformed) }
        malformed = second; malformed.snapshot.sourceModifiedAt = nil
        try rejects(.invalidDate, "missing business time") { try store.publish(malformed) }
        malformed = second; malformed.publishedAt = Date(timeIntervalSince1970: .infinity)
        try rejects(.invalidDate, "nonfinite publication time") { try store.publish(malformed) }
        malformed = second; malformed.snapshot.cities = -1
        try rejects(.invalidSnapshot, "negative statistics") { try store.publish(malformed) }
        malformed = second; malformed.sourceDigest = ""
        try rejects(.invalidIdentity, "missing source digest") { try store.publish(malformed) }
        malformed = second; malformed.generationID = "not-a-uuid"
        try rejects(.invalidIdentity, "invalid generation id") { try store.publish(malformed) }
        malformed = second; malformed.worldPNG = try png(width: 1001, height: 1000)
        malformed.worldDigest = WidgetGeneration.digest(malformed.worldPNG)
        try rejects(.invalidPNG, "oversized decoded raster") { try store.publish(malformed) }
        try check(try Data(contentsOf: current) == baseline, "validation failures modified current")

        for stage in [WidgetGenerationPublishStage.beforeStaging, .afterStaging, .beforeCommit] {
            let failing = WidgetGenerationStore(root: root, faultInjector: { point in
                if point == stage { throw WidgetGenerationError.outOfSpace }
            })
            try rejects(.outOfSpace, "simulated full disk") { try failing.publish(first) }
            try check(try Data(contentsOf: current) == baseline, "full disk damaged current")
            let cancelled = WidgetGenerationStore(root: root, faultInjector: { point in
                if point == stage { throw CancellationError() }
            })
            try rejects(.cancelled, "cancelled publication") { try cancelled.publish(first) }
            try check(try Data(contentsOf: current) == baseline, "cancellation damaged current")
            try check(try fm.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasSuffix(".tmp") }, "staging file leaked")
        }
        let cancellationStarted = DispatchSemaphore(value: 0)
        let cancellationFinished = DispatchSemaphore(value: 0)
        let cancellationResult = ConcurrentResults()
        let cancelledTask = Task.detached {
            cancellationStarted.signal()
            while !Task<Never, Never>.isCancelled { await Task.yield() }
            do {
                try store.publish(first)
                cancellationResult.record("publication accepted a cancelled task")
            } catch {
                if WidgetGenerationError.code(for: error) != WidgetGenerationError.cancelled.code {
                    cancellationResult.record("task cancellation returned wrong error")
                }
            }
            cancellationFinished.signal()
        }
        cancellationStarted.wait()
        cancelledTask.cancel()
        cancellationFinished.wait()
        try check(cancellationResult.values().isEmpty, "actual Task cancellation failed")
        try check(try Data(contentsOf: current) == baseline, "Task cancellation modified current")

        // Reestablish a distinct previous generation after deliberate commit failures.
        try store.publish(first); try store.publish(second)
        let previousBytes = try Data(contentsOf: previous)
        for broken in [Data("{broken".utf8), try WidgetGeneration.makeEncoder().encode({ () -> WidgetGeneration in
            var x = second; x.schema = 9; return x
        }())] {
            try broken.write(to: current, options: .atomic)
            let recovered = try store.loadResult()
            try check(recovered.source == "previous" && recovered.fallbackReason != nil, "fallback did not explain current rejection")
            try check(recovered.generation.generationID == first.generationID, "fallback mixed generation")
            try store.publish(second)
            try check(try Data(contentsOf: previous) == previousBytes, "invalid current replaced good previous")
        }
        try fm.removeItem(at: current)
        try check(try store.loadResult().source == "previous", "missing current did not use complete previous")
        try store.publish(second)
        let noFallbackRoot = root.appendingPathComponent("unreadable-input")
        try fm.createDirectory(at: noFallbackRoot, withIntermediateDirectories: true)
        let noFallback = WidgetGenerationStore(root: noFallbackRoot)
        let noFallbackCurrent = noFallbackRoot.appendingPathComponent(WidgetGenerationStore.currentFilename)
        try Data(repeating: 65, count: WidgetGenerationStore.maximumBytes + 1).write(to: noFallbackCurrent)
        try rejects(.oversized, "oversized file") { _ = try noFallback.load() }
        try Data("{}".utf8).write(to: noFallbackCurrent)
        try rejects(.invalidJSON, "incomplete object") { _ = try noFallback.load() }

        // Two full maps fit the pixel limit individually, but their complete JSON must also fit the byte limit.
        let noisyMap = try png(width: 1000, height: 1000, seed: 12345, noise: true)
        var oversized = try generation(3, image: noisyMap)
        oversized.worldPNG = try png(width: 1000, height: 1000, seed: 67890, noise: true)
        oversized.worldDigest = WidgetGeneration.digest(oversized.worldPNG)
        try check(try WidgetGeneration.makeEncoder().encode(oversized).count > WidgetGenerationStore.maximumBytes,
                  "oversized fixture unexpectedly compresses below limit")
        try rejects(.oversized, "oversized publication") { try store.publish(oversized) }
        try check(try store.load().generationID == second.generationID, "oversized publication replaced current")

        let generations = try (1...16).map { try generation($0, image: map) }
        let allowed = Set(generations.map(\.generationID) + [second.generationID])
        let concurrent = ConcurrentResults()
        DispatchQueue.concurrentPerform(iterations: 5) { worker in
            do {
                if worker < 2 {
                    for i in stride(from: worker, to: generations.count, by: 2) { try store.publish(generations[i]) }
                } else {
                    for _ in 0..<100 {
                        let loaded = try store.load()
                        try check(allowed.contains(loaded.generationID), "reader observed unknown generation")
                        try check(loaded.sourceDigest == WidgetGeneration.digest(Data("source-\(loaded.snapshot.visits)".utf8)),
                                  "reader observed mismatched statistics/source")
                        try check(loaded.chinaDigest == WidgetGeneration.digest(loaded.chinaPNG), "reader observed mismatched image")
                    }
                }
            } catch { concurrent.record(String(describing: error)) }
        }
        try check(concurrent.values().isEmpty, "concurrent readers/writers failed: " + concurrent.values().joined(separator: ","))
        let retained = try fm.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("widget-generation") }
        try check(Set(retained) == Set([WidgetGenerationStore.currentFilename, WidgetGenerationStore.previousFilename]),
                  "generation history grew beyond current and previous")
        // An authoritative, validated empty journal remains representable; missing files never become this value.
        try store.publish(generation(0, image: map))
        try check(try store.load().snapshot.visits == 0, "valid empty business dataset unsupported")
        print("WidgetGeneration regression passed: atomic swaps, concurrent readers/writers, validation, fallback, cancellation and disk failures")
    }
}
