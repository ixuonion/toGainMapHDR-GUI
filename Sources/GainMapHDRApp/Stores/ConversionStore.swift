import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ConversionStore {
    private(set) var inputs: [ImageInput] = []
    private(set) var jobs: [ConversionJob] = []
    var settings = ConversionSettings()
    var selectedInputID: ImageInput.ID?
    var isAdvancedVisible = true
    var isCollectionExpanded = false
    private(set) var isConverting = false
    private(set) var isCancelling = false
    private(set) var isImporting = false
    private(set) var progress: Double = 0
    private(set) var statusMessage = L10n.text("ready")
    private(set) var logText = L10n.text("no_backend_output")
    var presentedError: String?

    @ObservationIgnored private let scheduler: ConversionScheduler
    @ObservationIgnored private let files = FileAccessService()
    @ObservationIgnored private var conversionTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var jobIndices: [UUID: Int] = [:]
    @ObservationIgnored private var lastOutputURL: URL?
    @ObservationIgnored private var pendingInputURLs: [URL] = []

    init(backend: any BackendConverting = BackendProcessService()) {
        scheduler = ConversionScheduler(backend: backend)
    }

    var canConvert: Bool { !inputs.isEmpty && outputURL != nil && !isConverting && !isImporting }
    var canImport: Bool { !isConverting && !isImporting }
    var outputURL: URL? { ConversionRequest(inputs: inputs, settings: settings).outputURL }
    var representativeConversionCommand: ConversionCommand? {
        ConversionRequest(inputs: inputs, settings: settings).representativeCommand()
    }
    var representativeCommand: String { representativeConversionCommand?.displayString ?? L10n.text("add_images_to_build_command") }
    var modeTitle: String { L10n.text(inputs.count > 1 ? "batch_queue" : "single_image") }
    var collectionSummaryTitle: String { String(format: L10n.text("images_selected"), inputs.count) }

    func pickInputImages() {
        guard canImport else { return }
        isImporting = true
        importTask = Task {
            let urls = await FilePanelService.pickImages()
            await performImport(urls)
        }
    }

    func pickInputFolder() {
        guard canImport else { return }
        isImporting = true
        importTask = Task {
            let folder = await FilePanelService.pickFolder(title: L10n.text("add_folder"), prompt: L10n.text("add_folder"))
            await performImport(folder.map { [$0] } ?? [])
        }
    }

    func pickOutputFolder() {
        guard canImport else { return }
        isImporting = true
        importTask = Task {
            if let folder = await FilePanelService.pickFolder(), !Task.isCancelled {
                await files.retainAccess(to: folder)
                settings.destinationChoice = .custom
                settings.customDestination = folder
            }
            finishImport()
        }
    }

    /// Shared entry point for native panels, Finder open events, and Transferable drops.
    func addInputURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard !isConverting else { presentedError = L10n.text("import_while_converting"); return }
        if isImporting { pendingInputURLs.append(contentsOf: urls); return }
        isImporting = true
        importTask = Task { await performImport(urls) }
    }

    private func performImport(_ urls: [URL]) async {
        if !urls.isEmpty { statusMessage = L10n.text("scanning_folder") }
        defer { finishImport() }
        do {
            let imported = try await files.importFiles(urls)
            try Task.checkCancellation()
            var existing = Set(inputs.map(\.url))
            let additions = imported.filter { existing.insert($0).inserted }.map(ImageInput.init(url:))
            inputs.append(contentsOf: additions)
            if selectedInputID == nil { selectedInputID = inputs.first?.id }
            isCollectionExpanded = true
            statusMessage = readyMessage
        } catch {
            statusMessage = Task.isCancelled ? L10n.text("cancelled") : error.localizedDescription
            if !Task.isCancelled { presentedError = error.localizedDescription }
        }
    }

    private func finishImport() {
        isImporting = false
        importTask = nil
        let pending = pendingInputURLs
        pendingInputURLs.removeAll()
        if !Task.isCancelled { addInputURLs(pending) }
    }

    func removeSelectedInput() { if let selectedInputID { removeInput(id: selectedInputID) } }
    func removeInput(id: ImageInput.ID) {
        guard canImport else { return }
        inputs.removeAll { $0.id == id }
        if selectedInputID == id { selectedInputID = inputs.first?.id }
        statusMessage = readyMessage
    }

    func clearInputs() {
        guard canImport else { return }
        inputs.removeAll(); jobs.removeAll(); jobIndices.removeAll()
        selectedInputID = nil
        progress = 0
        statusMessage = readyMessage
        // Retain the explicitly chosen output grant while releasing all source grants.
        let destination = settings.customDestination
        isImporting = true
        importTask = Task {
            await files.releaseAccess()
            if let destination { await files.retainAccess(to: destination) }
            finishImport()
        }
    }

    func revealOutputFolder() {
        guard let url = lastOutputURL ?? outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func startConversion() {
        guard canConvert else { return }
        settings.clampValues()
        let request = ConversionRequest(inputs: inputs, settings: settings)
        jobs = inputs.map { ConversionJob(input: $0) }
        jobIndices = Dictionary(uniqueKeysWithValues: jobs.enumerated().map { ($0.element.input.id, $0.offset) })
        let events = ConversionEventBuffer(inputs: inputs)
        logText = L10n.text("no_backend_output")
        isConverting = true
        isCancelling = false
        lastOutputURL = request.outputURL
        progress = 0
        statusMessage = L10n.text("converting_image")
        let scheduler = self.scheduler
        conversionTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await scheduler.run(request, events: events) }
                while !Task.isCancelled {
                    let update = await events.drain()
                    apply(update)
                    if update.finished { break }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                }
                if Task.isCancelled { group.cancelAll() }
                await group.waitForAll()
            }
            apply(await events.drain())
            for index in jobs.indices where jobs[index].status == .queued || jobs[index].status == .running {
                jobs[index].status = .cancelled
            }
            let cancelled = jobs.contains { $0.status == .cancelled }
            isConverting = false
            isCancelling = false
            conversionTask = nil
            let failed = jobs.contains { if case .failed = $0.status { true } else { false } }
            statusMessage = L10n.text(cancelled ? "cancelled" : failed ? "completed_with_errors" : "conversion_finished")
        }
    }

    func cancelConversion() {
        guard isConverting, !isCancelling else { return }
        isCancelling = true
        statusMessage = L10n.text("cancelling")
        conversionTask?.cancel()
    }

    func waitUntilFinished() async { await conversionTask?.value }
    func waitUntilImported() async { while let task = importTask { await task.value } }

    func shutdown() async {
        pendingInputURLs.removeAll()
        importTask?.cancel()
        cancelConversion()
        await importTask?.value
        await conversionTask?.value
        await files.releaseAccess()
    }

    private func apply(_ update: ConversionUpdate) {
        for (id, status) in update.statuses {
            if let index = jobIndices[id] { jobs[index].status = status }
        }
        if let log = update.log { logText = log }
        let completed = jobs.reduce(0) { count, job in
            switch job.status { case .finished, .failed: count + 1; default: count }
        }
        progress = jobs.isEmpty ? 0 : Double(completed) / Double(jobs.count)
        if !isCancelling { statusMessage = String(format: L10n.text("batch_progress"), completed, jobs.count) }
    }

    private var readyMessage: String {
        inputs.isEmpty ? L10n.text("ready") : inputs.count == 1 ? L10n.text("image_ready") : String(format: L10n.text("images_ready"), inputs.count)
    }
}
