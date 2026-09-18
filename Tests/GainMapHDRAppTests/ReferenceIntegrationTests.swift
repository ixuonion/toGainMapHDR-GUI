import Foundation
import Testing
import ImageIO
import CryptoKit
import Darwin
@testable import GainMapHDRApp

private let runIntegration = ProcessInfo.processInfo.environment["GAINMAP_INTEGRATION"] == "1"
private let runBenchmark = ProcessInfo.processInfo.environment["GAINMAP_BENCHMARK"] == "1"

private func sampleURLs() throws -> [URL] {
    let path = try #require(ProcessInfo.processInfo.environment["GAINMAP_SAMPLES"], "Set GAINMAP_SAMPLES to a directory of test images")
    return try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)
        .filter { FileAccessService.supportedExtensions.contains($0.pathExtension.lowercased()) }.sorted { $0.path < $1.path }
}

private func compareImages(_ reference: URL, _ actual: URL) throws {
    let expectedData = try Data(contentsOf: reference)
    let actualData = try Data(contentsOf: actual)
    print("ENCODED_IDENTICAL \(expectedData == actualData)")
    #expect(SHA256.hash(data: expectedData) == SHA256.hash(data: actualData), "Complete encoded HEIC including all gain map pixels")
    let lhs = try #require(CGImageSourceCreateWithURL(reference as CFURL, nil))
    let rhs = try #require(CGImageSourceCreateWithURL(actual as CFURL, nil))
    let leftProperties = CGImageSourceCopyPropertiesAtIndex(lhs, 0, nil) as NSDictionary?
    let rightProperties = CGImageSourceCopyPropertiesAtIndex(rhs, 0, nil) as NSDictionary?
    #expect(leftProperties == rightProperties)
    let leftImage = try #require(CGImageSourceCreateImageAtIndex(lhs, 0, nil))
    let rightImage = try #require(CGImageSourceCreateImageAtIndex(rhs, 0, nil))
    #expect(leftImage.bitsPerComponent == rightImage.bitsPerComponent)
    #expect(leftImage.colorSpace == rightImage.colorSpace)
    let leftPixels = try #require(leftImage.dataProvider?.data) as Data
    let rightPixels = try #require(rightImage.dataProvider?.data) as Data
    #expect(SHA256.hash(data: leftPixels) == SHA256.hash(data: rightPixels), "Primary decoded pixels")
    for type in [kCGImageAuxiliaryDataTypeHDRGainMap, kCGImageAuxiliaryDataTypeISOGainMap] {
        let a = CGImageSourceCopyAuxiliaryDataInfoAtIndex(lhs, 0, type) as? [CFString: Any]
        let b = CGImageSourceCopyAuxiliaryDataInfoAtIndex(rhs, 0, type) as? [CFString: Any]
        #expect((a == nil) == (b == nil))
        #expect(a?[kCGImageAuxiliaryDataInfoDataDescription] as? NSDictionary == b?[kCGImageAuxiliaryDataInfoDataDescription] as? NSDictionary)
        #expect(a?[kCGImageAuxiliaryDataInfoData] as? Data == b?[kCGImageAuxiliaryDataInfoData] as? Data)
        if let a, let b,
           let am = a[kCGImageAuxiliaryDataInfoMetadata], let bm = b[kCGImageAuxiliaryDataInfoMetadata] {
            let axmp = CGImageMetadataCreateXMPData(am as! CGImageMetadata, nil) as Data?
            let bxmp = CGImageMetadataCreateXMPData(bm as! CGImageMetadata, nil) as Data?
            #expect(axmp == bxmp, "Serialized gain map metadata, not CF object identity")
        }
    }
}

@Suite("Reference CLI integration", .serialized, .enabled(if: runIntegration))
struct ReferenceIntegrationTests {
    @Test func outputMatchesReferenceAcrossModes() async throws {
        let directory = try TestDirectory(); defer { if ProcessInfo.processInfo.environment["GAINMAP_KEEP_RESULTS"] != "1" { directory.clean() } }
        print("REFERENCE_DIRECTORY \(directory.url.path)")
        let samples = try sampleURLs()
        #expect(!samples.isEmpty)
        let input = ImageInput(url: try #require(samples.first))
        var variants: [ConversionSettings] = []
        for mode in OutputMode.allCases {
            var settings = ConversionSettings(); settings.outputMode = mode
            variants.append(settings)
        }
        var mono = ConversionSettings(); mono.monochromeGainMap = true; variants.append(mono)
        var half = ConversionSettings(); half.subsampleGainMap = true; variants.append(half)
        var custom = ConversionSettings(); custom.quality = 97; custom.colorSpace = .p3
        custom.bitDepth = .ten; custom.toneMappingRatio = 2.5; custom.maxHeadroom = 4.8; variants.append(custom)
        let selectedVariants = ProcessInfo.processInfo.environment["GAINMAP_REFERENCE_VARIANTS"]?.split(separator: ",").compactMap { Int($0) }
        for (index, variant) in variants.enumerated() {
            if let selectedVariants, !selectedVariants.contains(index) { continue }
            let reference = directory.file("reference-\(index)")
            let actual = directory.file("actual-\(index)")
            try FileManager.default.createDirectory(at: reference, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
            var settings = variant
            settings.backendExecutable = BundledBackend.executablePath
            settings.destinationChoice = .custom; settings.customDestination = reference
            let referenceRequest = ConversionRequest(inputs: [input], settings: settings)
            // The frozen Process runner invokes the unmodified CLI directly, no staging or validation layer.
            try await LegacyBackendProcessService().run(command: try #require(referenceRequest.command(for: input))) { _ in }
            settings.customDestination = actual
            let request = ConversionRequest(inputs: [input], settings: settings)
            let events = ConversionEventBuffer(inputs: [input])
            await ConversionScheduler().run(request, events: events)
            let update = await events.drain()
            #expect(update.statuses[input.id] == .finished, "\(update.log ?? "")")
            let actualFile = try #require(request.outputFile(for: input))
            let actualBytes = try Data(contentsOf: actualFile)
            var matchingReference = try #require(referenceRequest.outputFile(for: input))
            var matchedAttempt = 0
            // Some macOS ImageIO/Metal paths produce multiple bitstreams even in direct CLI runs.
            // Accept only byte identity with an independently produced reference, never a pixel tolerance.
            if try Data(contentsOf: matchingReference) != actualBytes {
                for attempt in 1...3 {
                    let repeated = directory.file("reference-repeat-\(index)-\(attempt)")
                    try FileManager.default.createDirectory(at: repeated, withIntermediateDirectories: true)
                    var repeatedSettings = settings; repeatedSettings.customDestination = repeated
                    let repeatedRequest = ConversionRequest(inputs: [input], settings: repeatedSettings)
                    try await LegacyBackendProcessService().run(command: try #require(repeatedRequest.command(for: input))) { _ in }
                    let repeatedFile = try #require(repeatedRequest.outputFile(for: input))
                    if try Data(contentsOf: repeatedFile) == actualBytes {
                        matchingReference = repeatedFile; matchedAttempt = attempt
                        print("UPSTREAM_VARIATION variant=\(index) matched-direct-repeat=\(attempt)")
                        break
                    }
                }
            }
            try compareImages(matchingReference, actualFile)
            print("REFERENCE_PROOF variant=\(index) matchedAttempt=\(matchedAttempt) sha256=\(SHA256.hash(data: actualBytes))")
            print("REFERENCE variant=\(index) mode=\(variant.outputMode.rawValue) pixels-and-metadata-match")
        }
    }

    @Test func realBatchAndCancelLeaveNoPartialOutput() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let inputs = try sampleURLs().map(ImageInput.init(url:))
        var settings = ConversionSettings(); settings.destinationChoice = .custom; settings.customDestination = directory.url
        let events = ConversionEventBuffer(inputs: inputs)
        await ConversionScheduler().run(.init(inputs: inputs, settings: settings), events: events)
        let update = await events.drain()
        #expect(update.statuses.count == inputs.count && update.statuses.values.allSatisfy { $0 == .finished })
        let cancelDirectory = directory.file("cancel")
        try FileManager.default.createDirectory(at: cancelDirectory, withIntermediateDirectories: true)
        settings.customDestination = cancelDirectory
        let request = ConversionRequest(inputs: inputs, settings: settings)
        let cancelledEvents = ConversionEventBuffer(inputs: inputs)
        let task = Task { await ConversionScheduler().run(request, events: cancelledEvents) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel(); await task.value
        #expect(try FileManager.default.contentsOfDirectory(atPath: cancelDirectory.path).allSatisfy { !$0.hasPrefix(".GainMapHDR-") })
        let statuses = await cancelledEvents.drain().statuses
        #expect(!statuses.values.contains(.running))
    }
}

private actor BaselineQueue {
    let inputs: [ImageInput]
    var index = 0
    init(_ inputs: [ImageInput]) { self.inputs = inputs }
    func next() -> ImageInput? {
        guard index < inputs.count else { return nil }
        defer { index += 1 }
        return inputs[index]
    }
}

@Suite("Batch benchmark", .serialized, .enabled(if: runBenchmark))
struct BatchBenchmark {
    @Test func compareFrozenRunnerAndScheduler() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let samples = try sampleURLs()
        #expect(!samples.isEmpty)
        let batchCount = Int(ProcessInfo.processInfo.environment["GAINMAP_BATCH_COUNT"] ?? "\(samples.count)") ?? samples.count
        let inputs = try (0..<batchCount).map { index in
            let source = samples[index % samples.count]
            if batchCount == samples.count { return ImageInput(url: source) }
            let url = directory.file("sample-\(index)." + source.pathExtension)
            try FileManager.default.copyItem(at: source, to: url)
            return ImageInput(url: url)
        }
        let largestPixels = samples.compactMap { url -> Int? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = info[kCGImagePropertyPixelWidth] as? Int,
                  let height = info[kCGImagePropertyPixelHeight] as? Int else { return nil }
            return width * height
        }.max() ?? 100_000_000
        var records: [[String: Any]] = []
        let repeats = Int(ProcessInfo.processInfo.environment["GAINMAP_BENCHMARK_REPEATS"] ?? "2") ?? 2
        for repeatIndex in 0..<repeats {
            for concurrency in (repeatIndex == 0 ? [1, 2, 4, 8] : [8, 4, 2, 1]) {
                for variant in (repeatIndex == 0 ? ["legacy", "scheduler"] : ["scheduler", "legacy"]) {
                    let output = directory.file("\(repeatIndex)-\(concurrency)-\(variant)")
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    var settings = ConversionSettings()
                    settings.backendExecutable = BundledBackend.executablePath
                    settings.concurrency = concurrency
                    settings.destinationChoice = .custom; settings.customDestination = output
                    let request = ConversionRequest(inputs: inputs, settings: settings)
                    let start = ContinuousClock.now
                    if variant == "legacy" {
                        let queue = BaselineQueue(inputs)
                        let backend = LegacyBackendProcessService()
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            for _ in 0..<concurrency {
                                group.addTask {
                                    while let input = await queue.next() {
                                        try await backend.run(command: request.command(for: input)!) { _ in }
                                    }
                                }
                            }
                            try await group.waitForAll()
                        }
                    } else {
                        let events = ConversionEventBuffer(inputs: inputs)
                        await ConversionScheduler().run(request, events: events)
                        let update = await events.drain()
                        #expect(update.statuses.count == inputs.count && update.statuses.values.allSatisfy { $0 == .finished }, "\(update.log ?? "")")
                    }
                    let elapsed = start.duration(to: .now)
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).count == batchCount)
                    let record: [String: Any] = ["repeat": repeatIndex, "workers": concurrency, "variant": variant,
                        "effectiveWorkers": variant == "legacy" ? concurrency : WorkerPolicy.count(requested: concurrency, inputCount: batchCount, largestPixelCount: largestPixels),
                        "images": batchCount, "seconds": seconds, "imagesPerSecond": Double(batchCount) / seconds]
                    records.append(record)
                    if let report = ProcessInfo.processInfo.environment["GAINMAP_BENCHMARK_REPORT"] {
                        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: report), options: .atomic)
                    }
                    print("BENCHMARK \(String(data: try JSONSerialization.data(withJSONObject: record, options: .sortedKeys), encoding: .utf8)!)")
                    try FileManager.default.removeItem(at: output)
                }
            }
        }
        if let report = ProcessInfo.processInfo.environment["GAINMAP_BENCHMARK_REPORT"] {
            try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: report))
        }
    }
}

@Suite("Real application load", .enabled(if: ProcessInfo.processInfo.environment["GAINMAP_STRESS"] == "1"))
struct RealApplicationLoadTests {
    @Test @MainActor func storeAndThumbnailsStayResponsive() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let originals = try sampleURLs()
        let count = Int(ProcessInfo.processInfo.environment["GAINMAP_STRESS_COUNT"] ?? "100") ?? 100
        let store = ConversionStore()
        // APFS clones give distinct regular files without duplicating or modifying the private TIFF data.
        let inputs = try (0..<count).map { index in
            let url = directory.file("load-\(index)." + originals[index % originals.count].pathExtension)
            let source = originals[index % originals.count]
            if clonefile(source.path, url.path, 0) != 0 {
                try FileManager.default.copyItem(at: source, to: url)
            }
            return url
        }
        store.addInputURLs(inputs); await store.waitUntilImported()
        #expect(store.inputs.count == count)
        store.settings.destinationChoice = .custom
        store.settings.customDestination = directory.url
        store.startConversion()
        var ticks = 0
        var longestGap = Duration.zero
        var previous = ContinuousClock.now
        while store.isConverting {
            try await Task.sleep(for: .milliseconds(10))
            let now = ContinuousClock.now
            longestGap = max(longestGap, previous.duration(to: now)); previous = now; ticks += 1
            if ticks.isMultiple(of: 50) {
                let url = inputs[(ticks / 50) % inputs.count]
                store.selectedInputID = store.inputs.first { $0.url == url }?.id
                async let thumbnail = ThumbnailService.shared.image(for: url)
                _ = try await thumbnail
                // Thumbnail work suspends this probe; measure only the next MainActor wakeup.
                previous = .now
            }
        }
        await store.waitUntilFinished()
        #expect(store.jobs.allSatisfy { $0.status == .finished })
        #expect(longestGap < .milliseconds(250), "MainActor wakeup delay: \(longestGap)")
        print("LOAD images=\(count) ticks=\(ticks) longestMainActorGap=\(longestGap)")
        await store.shutdown()
    }
}
