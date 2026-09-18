import Foundation
import Testing
import ImageIO
import CoreGraphics
import Darwin
@testable import GainMapHDRApp

struct TestDirectory {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("GainMapTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func clean() { try? FileManager.default.removeItem(at: url) }
    func file(_ name: String) -> URL { url.appendingPathComponent(name) }
}

func makeImage(at url: URL, heic: Bool = false) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.25, green: 0.6, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, (heic ? "public.heic" : "public.png") as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

actor CopyBackend: BackendConverting {
    let fixture: URL
    let delay: Duration
    var active = 0
    var maximumActive = 0
    var launches = 0
    init(fixture: URL, delay: Duration = .milliseconds(5)) { self.fixture = fixture; self.delay = delay }
    func run(command: ConversionCommand, log: ConversionEventBuffer, inputID: UUID) async throws {
        active += 1; launches += 1; maximumActive = max(active, maximumActive)
        defer { active -= 1 }
        try await Task.sleep(for: delay)
        let suffixIndex = command.arguments.firstIndex(of: "-t")!
        let name = URL(fileURLWithPath: command.arguments[0]).deletingPathExtension().lastPathComponent + command.arguments[suffixIndex + 1] + ".heic"
        try FileManager.default.copyItem(at: fixture, to: URL(fileURLWithPath: command.arguments[1]).appendingPathComponent(name))
    }
}

@Suite("Backend lifecycle and scheduler", .serialized)
struct BackendTests {
    @Test func sourceParameterContract() throws {
        let input = ImageInput(url: URL(fileURLWithPath: "/tmp/照片 $(a)' x.heic"))
        for mode in OutputMode.allCases {
            var settings = ConversionSettings()
            settings.outputMode = mode
            settings.monochromeGainMap = true
            settings.subsampleGainMap = true
            let request = ConversionRequest(inputs: [input], settings: settings)
            let command = try #require(request.command(for: input))
            #expect(command.arguments.contains("-m") == (mode == .isoGainMap))
            #expect(command.arguments.last == (mode == .isoGainMap ? "-m" : "-H"))
            #expect(command.arguments[command.arguments.firstIndex(of: "-d")! + 1] == (mode == .pqHDR ? "10" : "8"))
            #expect(request.outputFile(for: input)?.lastPathComponent == "照片 $(a)' x-HDR.heic")
        }
        var settings = ConversionSettings()
        settings.toneMappingRatio = .nan; settings.maxHeadroom = .infinity
        settings.concurrency = -8; settings.clampValues()
        #expect(settings.toneMappingRatio == 3 && settings.maxHeadroom == 6 && settings.concurrency == 0)
        #expect(WorkerPolicy.count(requested: 0, inputCount: 500, physicalMemory: 16 * 1024 * 1024 * 1024) == 4)
        #expect(WorkerPolicy.count(requested: 8, inputCount: 500, largestPixelCount: 100_000_000, physicalMemory: 16 * 1024 * 1024 * 1024) == 1)
    }

    @Test func streamsUnicodeAndFinalOutput() async throws {
        let events = ConversionEventBuffer()
        let script = "import os; os.write(1,bytes([228,189])); os.write(1,bytes([160,229,165,189,10])); os.write(2,b'error-stream\\n'); os.write(1,b'last-without-newline')"
        try await BackendProcessService().run(command: .init(executable: "/usr/bin/python3", arguments: ["-c", script]), log: events, inputID: UUID())
        let log = await events.drain().log ?? ""
        #expect(log.contains("你好")); #expect(log.contains("error-stream")); #expect(log.contains("last-without-newline"))
    }

    @Test func logFloodIsBoundedAndDrained() async throws {
        let events = ConversionEventBuffer()
        let script = "import os; [(os.write(1,b'x'*1000+b'\\n'),os.write(2,b'e'*1000+b'\\n')) for _ in range(1500)]; os.write(1,b'END')"
        try await BackendProcessService().run(command: .init(executable: "/usr/bin/python3", arguments: ["-c", script]), log: events, inputID: UUID())
        let log = await events.drain().log ?? ""
        #expect(log.utf8.count <= 66_000); #expect(log.hasSuffix("END"))
    }

    @Test func failuresAreCategorized() async throws {
        for (executable, arguments, expected) in [
            ("/nonexistent/backend", [], ConversionFailure.Kind.backendMissing),
            ("/usr/bin/python3", ["-c", "print('bad input'); exit(22)"], .unsupported),
            ("/usr/bin/false", [], .process)
        ] {
            do {
                try await BackendProcessService().run(command: .init(executable: executable, arguments: arguments), log: ConversionEventBuffer(), inputID: UUID())
                Issue.record("Expected failure")
            } catch let error as ConversionFailure { #expect(error.kind == expected) }
        }
    }

    @Test func cancelEscalatesAndReapsBeforeReturning() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let pidFile = directory.file("pid")
        let script = "import os,signal,time,sys; signal.signal(signal.SIGTERM,signal.SIG_IGN); open(sys.argv[1],'w').write(str(os.getpid())); time.sleep(60)"
        let task = Task {
            try await BackendProcessService().run(command: .init(executable: "/usr/bin/python3", arguments: ["-c", script, pidFile.path]), log: ConversionEventBuffer(), inputID: UUID())
        }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: pidFile.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)))
        let start = ContinuousClock.now
        task.cancel()
        do { try await task.value; Issue.record("Cancellation must throw") } catch { #expect(error is CancellationError) }
        #expect(start.duration(to: .now) < .seconds(5))
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }

    @Test func cancelledBeforeSpawn() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await BackendProcessService().run(command: .init(executable: "/usr/bin/true", arguments: []), log: ConversionEventBuffer(), inputID: UUID())
                Issue.record("Cancelled task launched")
            } catch { #expect(error is CancellationError) }
        }
        await task.value
    }

    @Test func repeatedProcessesCloseDescriptors() async throws {
        let before = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
        for _ in 0..<50 {
            try await BackendProcessService().run(command: .init(executable: "/usr/bin/true", arguments: []), log: ConversionEventBuffer(), inputID: UUID())
        }
        let after = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
        #expect(after <= before + 3)
    }

    @Test func importDeduplicatesAndSkipsDirectories() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        try makeImage(at: directory.file("a.png"))
        try FileManager.default.createDirectory(at: directory.file("folder.png"), withIntermediateDirectories: false)
        let service = FileAccessService()
        let files = try await service.importFiles([directory.url, directory.file("a.png")])
        #expect(files == [directory.file("a.png")])
        await service.releaseAccess()
    }

    @Test @MainActor func fiveHundredJobsAndCancellationState() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let input = directory.file("source.png"); try makeImage(at: input)
        let fixture = directory.file("fixture.heic"); try makeImage(at: fixture, heic: true)
        let backend = CopyBackend(fixture: fixture)
        let store = ConversionStore(backend: backend)
        let urls = try (0..<500).map { index in
            let url = directory.file("input-\(index).png")
            try FileManager.default.linkItem(at: input, to: url)
            return url
        }
        store.addInputURLs(urls)
        await store.waitUntilImported()
        #expect(store.inputs.count == 500)
        store.settings.concurrency = 4
        store.startConversion()
        await store.waitUntilFinished()
        #expect(store.jobs.count == 500 && store.jobs.allSatisfy { $0.status == .finished })
        #expect(await backend.maximumActive <= 4)
        #expect(store.progress == 1 && !store.isConverting)
        // Existing output is never replaced on retry.
        store.startConversion(); await store.waitUntilFinished()
        #expect(store.jobs.allSatisfy { if case .failed = $0.status { true } else { false } })
        #expect(await backend.launches == 500)
        await store.shutdown()
    }

    @Test @MainActor func cancelWaitsThenAllowsRestart() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let input = directory.file("source.png"); try makeImage(at: input)
        let fixture = directory.file("fixture.heic"); try makeImage(at: fixture, heic: true)
        let backend = CopyBackend(fixture: fixture, delay: .seconds(1))
        let store = ConversionStore(backend: backend)
        store.addInputURLs([input]); await store.waitUntilImported()
        store.startConversion()
        try await Task.sleep(for: .milliseconds(100))
        store.cancelConversion()
        #expect(store.isConverting && store.isCancelling && !store.canConvert)
        store.startConversion() // Must not replace an active generation.
        await store.waitUntilFinished()
        #expect(store.jobs.first?.status == .cancelled && store.progress == 0)
        #expect(await backend.active == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).allSatisfy { !$0.hasPrefix(".GainMapHDR-") })
        store.startConversion(); await store.waitUntilFinished()
        #expect(store.jobs.first?.status == .finished)
        await store.shutdown()
    }
}

private struct EmptyBackend: BackendConverting {
    func run(command: ConversionCommand, log: ConversionEventBuffer, inputID: UUID) async throws {}
}

@Suite("File safety", .serialized)
struct FileSafetyTests {
    @Test func successfulExitWithoutImageIsFailure() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let input = directory.file("source.png"); try makeImage(at: input)
        let image = ImageInput(url: input)
        let events = ConversionEventBuffer(inputs: [image])
        await ConversionScheduler(backend: EmptyBackend()).run(.init(inputs: [image], settings: .init()), events: events)
        let status = await events.drain().statuses[image.id]
        #expect({ if case .failed = status { true } else { false } }())
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == ["source.png"])
    }

    @Test func duplicateDestinationsDoNotRace() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let fixture = directory.file("fixture.heic"); try makeImage(at: fixture, heic: true)
        var inputs: [ImageInput] = []
        for folder in ["a", "b"] {
            let parent = directory.file(folder)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            let input = parent.appendingPathComponent("same.png"); try makeImage(at: input)
            inputs.append(ImageInput(url: input))
        }
        var settings = ConversionSettings(); settings.destinationChoice = .custom; settings.customDestination = directory.url
        let backend = CopyBackend(fixture: fixture)
        let events = ConversionEventBuffer(inputs: inputs)
        await ConversionScheduler(backend: backend).run(.init(inputs: inputs, settings: settings), events: events)
        let statuses = await events.drain().statuses
        #expect(statuses[inputs[0].id] == .finished)
        #expect({ if case .failed = statuses[inputs[1].id] { true } else { false } }())
        #expect(await backend.launches == 1)
    }

    @Test @MainActor func burstOpenEventsAreNotDropped() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let first = directory.file("first.png"), second = directory.file("second.png")
        try makeImage(at: first); try makeImage(at: second)
        let store = ConversionStore()
        store.addInputURLs([first]); store.addInputURLs([second]); store.addInputURLs([first])
        await store.waitUntilImported()
        #expect(Set(store.inputs.map(\.url)) == Set([first, second]))
        await store.shutdown()
    }

    @Test func missingInputAndDeniedExecutableAreDistinct() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        do {
            _ = try await FileAccessService().validate(input: directory.file("missing.tif"), destination: directory.file("out.heic"))
            Issue.record("Missing input accepted")
        } catch let failure as ConversionFailure { #expect(failure.kind == .input) }
        let executable = directory.file("not-executable")
        try Data("test".utf8).write(to: executable)
        do {
            try await BackendProcessService().run(command: .init(executable: executable.path, arguments: []), log: ConversionEventBuffer(), inputID: UUID())
            Issue.record("Non-executable file accepted")
        } catch let failure as ConversionFailure { #expect(failure.kind == .permission) }
    }
}

@Suite("Atomic output publication")
struct OutputPublicationTests {
    @Test func competingPublishersNeverOverwrite() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let destination = directory.file("output.heic")
        let sources = try (0..<32).map { index in
            let file = directory.file("source-\(index)")
            try Data("candidate-\(index)".utf8).write(to: file)
            return file
        }
        let winners = await withTaskGroup(of: Int?.self, returning: [Int].self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    do { try OutputPublisher.publish(source, to: destination); return index }
                    catch { return nil }
                }
            }
            var winners: [Int] = []
            for await result in group { if let result { winners.append(result) } }
            return winners
        }
        #expect(winners.count == 1)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "candidate-\(try #require(winners.first))")
    }
}
