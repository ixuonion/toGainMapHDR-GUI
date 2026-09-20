import Foundation
import Photos
import Testing
@testable import GainMapHDRApp

private struct StubAuthorization: PhotoLibraryAuthorizing {
    let initial: PHAuthorizationStatus
    var response: @Sendable () async throws -> PHAuthorizationStatus = { .authorized }
    func status() -> PHAuthorizationStatus { initial }
    func request() async throws -> PHAuthorizationStatus { try await response() }
}

private actor RecordingPhotos: PhotoLibrarySaving {
    struct Import: Sendable {
        let file: URL
        let name: String
        let data: Data
    }
    var imports: [Import] = []
    var authorizations = 0
    let denied: Bool
    let hold: Bool
    let fail: Bool
    private var started = false
    private var finishWaiter: CheckedContinuation<Void, Never>?

    init(denied: Bool = false, hold: Bool = false, fail: Bool = false) {
        self.denied = denied; self.hold = hold; self.fail = fail
    }
    func authorize() throws {
        authorizations += 1
        if denied { throw PhotoLibraryFailure.denied }
    }
    func save(file: URL, originalFilename: String) async throws {
        try Task.checkCancellation()
        imports.append(Import(file: file, name: originalFilename, data: try Data(contentsOf: file)))
        started = true
        if hold { await withCheckedContinuation { finishWaiter = $0 } }
        // Model PhotoKit: commit completion is independent of the caller's cancellation.
        #expect(FileManager.default.fileExists(atPath: file.path))
        if fail || originalFilename.hasPrefix("bad") { throw PhotoLibraryFailure.importFailed("Test failure") }
    }
    func waitForImport() async throws {
        // Bound the wait so a broken encoder fails the test rather than hanging the suite.
        for _ in 0..<500 {
            if started { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw PhotoLibraryFailure.importFailed("Timed out waiting for test import")
    }
    func finishImport() { finishWaiter?.resume(); finishWaiter = nil }
}

private actor InvalidPhotoBackend: BackendConverting {
    var directories: [URL] = []
    func run(command: ConversionCommand, log: ConversionEventBuffer, inputID: UUID) throws {
        let directory = URL(fileURLWithPath: command.arguments[1])
        directories.append(directory)
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("input-HDR.heic"))
    }
}

@Suite("Photos output", .serialized)
struct PhotoLibraryTests {
    private func settings() -> ConversionSettings {
        var settings = ConversionSettings()
        settings.destinationChoice = .photosLibrary
        settings.concurrency = 1
        return settings
    }

    @Test(arguments: [PHAuthorizationStatus.authorized, .denied, .restricted, .limited])
    func existingAuthorizationDoesNotPrompt(status: PHAuthorizationStatus) async {
        let service = PhotoLibraryService(authorization: StubAuthorization(initial: status) {
            Issue.record("Existing permission must not prompt again")
            return .authorized
        })
        do {
            try await service.authorize()
            #expect(status == .authorized)
        } catch {
            #expect(status != .authorized)
            #expect(error.localizedDescription == L10n.text(status == .restricted ? "photos_restricted" : "photos_denied"))
        }
    }

    @Test(arguments: [PHAuthorizationStatus.authorized, .denied, .restricted])
    func firstAuthorizationUsesReturnedStatus(status: PHAuthorizationStatus) async {
        let service = PhotoLibraryService(authorization: StubAuthorization(initial: .notDetermined) { status })
        do { try await service.authorize(); #expect(status == .authorized) }
        catch { #expect(status != .authorized) }
    }

    @Test func cancellationDuringPermissionStopsWork() async {
        let task = Task {
            let service = PhotoLibraryService(authorization: StubAuthorization(initial: .notDetermined) {
                withUnsafeCurrentTask { $0?.cancel() }
                return .authorized
            })
            do { try await service.authorize(); Issue.record("Cancelled permission flow continued") }
            catch { #expect(error is CancellationError) }
        }
        await task.value
    }

    @Test func deniedBatchNeverLaunchesEncoder() async {
        let inputs = ["a", "b"].map { ImageInput(url: URL(fileURLWithPath: "/unused/\($0).tif")) }
        let backend = InvalidPhotoBackend()
        let photos = RecordingPhotos(denied: true)
        let events = ConversionEventBuffer(inputs: inputs)
        await ConversionScheduler(backend: backend, photos: photos).run(.init(inputs: inputs, settings: settings()), events: events)
        let update = await events.drain()
        #expect(update.finished)
        #expect(update.statuses.values.allSatisfy { if case .failed = $0 { true } else { false } })
        #expect(await backend.directories.isEmpty)
        #expect(await photos.imports.isEmpty)
        #expect(await photos.authorizations == 1)
    }

    @Test func batchSameNamesPreservesExactBytesAndCleansStaging() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let fixture = directory.file("fixture.heic"); try makeImage(at: fixture, heic: true)
        let bytes = try Data(contentsOf: fixture)
        let inputs = try ["a", "b"].map { folder in
            let parent = directory.file(folder)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            let url = parent.appendingPathComponent("同名.png")
            try makeImage(at: url)
            // A folder output collision must not affect Photos output.
            try Data("existing".utf8).write(to: parent.appendingPathComponent("同名-HDR.heic"))
            return ImageInput(url: url)
        }
        let photos = RecordingPhotos()
        let events = ConversionEventBuffer(inputs: inputs)
        var options = settings(); options.concurrency = 2
        await ConversionScheduler(backend: CopyBackend(fixture: fixture), photos: photos)
            .run(.init(inputs: inputs, settings: options), events: events)
        #expect(await events.drain().statuses.values.allSatisfy { $0 == .savedToPhotos })
        let imports = await photos.imports
        #expect(imports.count == 2)
        #expect(Set(imports.map(\.file)).count == 2)
        for item in imports {
            #expect(item.data == bytes)
            #expect(item.name == "同名-HDR.heic")
            #expect(!FileManager.default.fileExists(atPath: item.file.deletingLastPathComponent().path))
        }
        #expect(await photos.authorizations == 1)
    }

    @Test @MainActor func storeSupportsPhotosAndPartialFailure() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let fixture = directory.file("fixture.heic"); try makeImage(at: fixture, heic: true)
        let inputs = try ["good", "bad", "other"].map { name in
            let url = directory.file(name + ".png"); try makeImage(at: url); return url
        }
        let photos = RecordingPhotos()
        let store = ConversionStore(backend: CopyBackend(fixture: fixture), photos: photos)
        store.settings = settings()
        store.addInputURLs(inputs); await store.waitUntilImported()
        #expect(store.canConvert && store.outputURL == nil)
        #expect(store.representativeCommand == L10n.text("photos_command_note"))
        store.startConversion(); await store.waitUntilFinished()
        #expect(store.jobs.filter { $0.status == .savedToPhotos }.count == 2)
        #expect(store.jobs.filter { if case .failed = $0.status { true } else { false } }.count == 1)
        #expect(store.progress == 1 && !store.isConverting)
        #expect(store.statusMessage == String(format: L10n.text("photos_summary"), 2, 1, 0))
        #expect(store.presentedError != nil)
        for item in await photos.imports { #expect(!FileManager.default.fileExists(atPath: item.file.path)) }
        await store.shutdown()
    }

    @Test(arguments: [false, true])
    func cancelDuringCommitWaitsAndPreservesActualResult(fail: Bool) async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let fixture = directory.file("fixture.heic"); try makeImage(at: fixture, heic: true)
        let input = directory.file("input.png"); try makeImage(at: input)
        let inputs = (0..<3).map { _ in ImageInput(url: input) }
        let photos = RecordingPhotos(hold: true, fail: fail)
        let backend = CopyBackend(fixture: fixture)
        let scheduler = ConversionScheduler(backend: backend, photos: photos)
        let events = ConversionEventBuffer(inputs: inputs)
        let request = ConversionRequest(inputs: inputs, settings: settings())
        let task = Task { await scheduler.run(request, events: events) }
        try await photos.waitForImport()
        let staging = try #require(await photos.imports.first?.file)
        #expect(await events.drain().statuses[inputs[0].id] == .savingPhotos)
        task.cancel()
        #expect(FileManager.default.fileExists(atPath: staging.path))
        await photos.finishImport()
        await task.value
        let update = await events.drain()
        if fail { #expect({ if case .failed = update.statuses[inputs[0].id] { true } else { false } }()) }
        else { #expect(update.statuses[inputs[0].id] == .savedToPhotos) }
        #expect(inputs.dropFirst().allSatisfy { update.statuses[$0.id] == .cancelled })
        #expect(await backend.launches == 1)
        #expect(!FileManager.default.fileExists(atPath: staging.deletingLastPathComponent().path))
        #expect(update.finished)
    }

    @Test func invalidOutputNeverImportsAndCleansStaging() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let url = directory.file("input.png"); try makeImage(at: url)
        let input = ImageInput(url: url), photos = RecordingPhotos(), backend = InvalidPhotoBackend()
        let events = ConversionEventBuffer(inputs: [input])
        await ConversionScheduler(backend: backend, photos: photos).run(.init(inputs: [input], settings: settings()), events: events)
        #expect(await photos.imports.isEmpty)
        #expect({ if case .failed = $0 { true } else { false } }(await events.drain().statuses[input.id]))
        for folder in await backend.directories { #expect(!FileManager.default.fileExists(atPath: folder.path)) }
    }


    @Test @MainActor func singleImageSuccessFromReadOnlySource() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let parent = directory.file("readonly")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let input = parent.appendingPathComponent("input.png"); try makeImage(at: input)
        let fixture = directory.file("fixture.heic"); try makeImage(at: fixture, heic: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path) }
        let photos = RecordingPhotos()
        let store = ConversionStore(backend: CopyBackend(fixture: fixture), photos: photos)
        store.settings = settings()
        store.addInputURLs([input]); await store.waitUntilImported()
        store.startConversion(); await store.waitUntilFinished()
        #expect(store.jobs.first?.status == .savedToPhotos)
        #expect(store.statusMessage == String(format: L10n.text("photos_summary"), 1, 0, 0))
        #expect(store.progress == 1 && store.presentedError == nil)
        #expect(try await photos.imports.first?.data == Data(contentsOf: fixture))
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["input.png"])
        store.settings.destinationChoice = .custom
        #expect(!store.canConvert)
        await store.shutdown()
    }

    @Test func cancelledBeforeRunDoesNotRequestPermission() async {
        let photos = RecordingPhotos()
        let backend = InvalidPhotoBackend()
        let image = ImageInput(url: URL(fileURLWithPath: "/unused/input.png"))
        let events = ConversionEventBuffer(inputs: [image])
        let request = ConversionRequest(inputs: [image], settings: settings())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await ConversionScheduler(backend: backend, photos: photos).run(request, events: events)
        }
        await task.value
        #expect(await photos.authorizations == 0)
        #expect(await backend.directories.isEmpty)
        #expect(await events.drain().statuses[image.id] == .cancelled)
    }

    @Test func folderOutputNeverRequestsPhotoPermission() async throws {
        let directory = try TestDirectory(); defer { directory.clean() }
        let input = directory.file("input.png"); try makeImage(at: input)
        let fixture = directory.file("fixture.heic"); try makeImage(at: fixture, heic: true)
        let image = ImageInput(url: input), photos = RecordingPhotos(denied: true)
        let events = ConversionEventBuffer(inputs: [image])
        await ConversionScheduler(backend: CopyBackend(fixture: fixture), photos: photos)
            .run(.init(inputs: [image], settings: .init()), events: events)
        #expect(await events.drain().statuses[image.id] == .finished)
        #expect(await photos.authorizations == 0)
        #expect(try Data(contentsOf: directory.file("input-HDR.heic")) == Data(contentsOf: fixture))
    }
}
