import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ConversionStore {
    var inputs: [ImageInput] = []
    var jobs: [ConversionJob] = []
    var settings = ConversionSettings()
    var selectedInputID: ImageInput.ID?
    var isAdvancedVisible = true
    var isCollectionExpanded = false
    var isConverting = false
    var progress: Double = 0
    var statusMessage = L10n.text("ready")
    var logText = L10n.text("no_backend_output")

    @ObservationIgnored private let backend: BackendConverting
    @ObservationIgnored private var conversionTask: Task<Void, Never>?
    @ObservationIgnored private var logLines: [String] = []
    @ObservationIgnored private var pendingLogLines: [String] = []
    @ObservationIgnored private var logFlushTask: Task<Void, Never>?
    @ObservationIgnored private var completedJobCount = 0

    init(backend: BackendConverting = BackendProcessService()) {
        self.backend = backend
    }

    var canConvert: Bool {
        !inputs.isEmpty && outputURL != nil && !isConverting
    }

    var outputURL: URL? {
        ConversionRequest(inputs: inputs, settings: settings).outputURL
    }

    var representativeConversionCommand: ConversionCommand? {
        ConversionRequest(inputs: inputs, settings: settings).representativeCommand()
    }

    var representativeCommand: String {
        representativeConversionCommand?.displayString ?? L10n.text("add_images_to_build_command")
    }

    var modeTitle: String {
        inputs.count > 1 ? L10n.text("batch_queue") : L10n.text("single_image")
    }

    var collectionSummaryTitle: String {
        String(format: L10n.text("images_selected"), inputs.count)
    }

    func pickInputImages() {
        addInputURLs(FilePanelService.pickImages())
    }

    func pickInputFolder() {
        guard let folder = FilePanelService.pickFolder(title: L10n.text("add_folder"), prompt: L10n.text("add_folder")) else { return }
        statusMessage = L10n.text("scanning_folder")

        Task { [weak self] in
            let urls = await Task.detached(priority: .userInitiated) {
                FilePanelService.imageFiles(in: folder)
            }.value
            guard let self else { return }
            self.addInputURLs(urls)
            if urls.isEmpty {
                self.statusMessage = L10n.text("ready")
            }
        }
    }

    func pickOutputFolder() {
        guard let folder = FilePanelService.pickFolder(title: L10n.text("choose_folder")) else { return }
        settings.destinationChoice = .custom
        settings.customDestination = folder
    }

    func addInputURLs(_ urls: [URL]) {
        let existing = Set(inputs.map(\.url))
        let newInputs = urls
            .filter { !existing.contains($0) }
            .map(ImageInput.init(url:))

        guard !newInputs.isEmpty else { return }

        withAnimation(.snappy(duration: 0.22)) {
            inputs.append(contentsOf: newInputs)
            selectedInputID = inputs.first?.id
            isCollectionExpanded = true
            statusMessage = readyMessage(for: inputs.count)
        }
    }

    func removeSelectedInput() {
        guard let selectedInputID else { return }
        removeInput(id: selectedInputID)
    }

    func removeInput(id: ImageInput.ID) {
        withAnimation(.snappy(duration: 0.18)) {
            inputs.removeAll { $0.id == id }
            if self.selectedInputID == id {
                self.selectedInputID = inputs.first?.id
            }
            statusMessage = inputs.isEmpty ? L10n.text("ready") : readyMessage(for: inputs.count)
        }
    }

    func clearInputs() {
        withAnimation(.snappy(duration: 0.2)) {
            inputs.removeAll()
            jobs.removeAll()
            selectedInputID = nil
            progress = 0
            completedJobCount = 0
            statusMessage = L10n.text("ready")
        }
    }

    func revealOutputFolder() {
        guard let outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    func startConversion() {
        guard canConvert else { return }
        settings.clampValues()
        let request = ConversionRequest(inputs: inputs, settings: settings)
        let workerCount = min(max(settings.concurrency, 1), inputs.count)
        jobs = inputs.map { ConversionJob(input: $0) }
        resetLogs()
        completedJobCount = 0
        isConverting = true
        progress = 0
        statusMessage = inputs.count == 1 ? L10n.text("converting_image") : String(format: L10n.text("converting_images"), inputs.count)

        conversionTask = Task { [weak self] in
            guard let self else { return }
            let queue = WorkQueue(request.inputs)

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<workerCount {
                    group.addTask {
                        while !Task.isCancelled {
                            guard let input = await queue.next() else { break }
                            await self.run(input: input, request: request)
                        }
                    }
                }
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.flushPendingLogs()
                self.isConverting = false
                self.progress = 1
                self.statusMessage = self.jobs.contains { if case .failed = $0.status { true } else { false } }
                    ? L10n.text("completed_with_errors")
                    : L10n.text("conversion_finished")
            }
        }
    }

    func cancelConversion() {
        conversionTask?.cancel()
        backend.cancel()
        for index in jobs.indices where jobs[index].status == .queued || jobs[index].status == .running {
            if updateJob(at: index, status: .cancelled) {
                markJobCompleted()
            }
        }
        flushPendingLogs()
        isConverting = false
        statusMessage = L10n.text("cancelled")
    }

    private func run(input: ImageInput, request: ConversionRequest) async {
        guard let command = request.command(for: input) else { return }
        _ = updateJob(for: input, status: .running)
        appendLog(String(format: L10n.text("starting_file"), input.displayName))

        do {
            try await backend.run(command: command) { [weak self] text in
                Task { @MainActor in
                    self?.enqueueLog(text)
                }
            }
            if updateJob(for: input, status: .finished) {
                markJobCompleted()
            }
            appendLog(String(format: L10n.text("finished_file"), input.displayName))
        } catch {
            if Task.isCancelled {
                if updateJob(for: input, status: .cancelled) {
                    markJobCompleted()
                }
            } else {
                if updateJob(for: input, status: .failed(error.localizedDescription)) {
                    markJobCompleted()
                }
                appendLog("\(input.displayName): \(error.localizedDescription)")
            }
        }
    }

    private func updateJob(for input: ImageInput, status: JobStatus) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.input.id == input.id }) else { return false }
        return updateJob(at: index, status: status)
    }

    private func updateJob(at index: Int, status: JobStatus) -> Bool {
        let wasTerminal = jobs[index].status.isTerminal
        jobs[index].status = status
        return !wasTerminal && status.isTerminal
    }

    private func readyMessage(for count: Int) -> String {
        count == 1 ? L10n.text("image_ready") : String(format: L10n.text("images_ready"), count)
    }

    private func resetLogs() {
        logFlushTask?.cancel()
        logFlushTask = nil
        pendingLogLines.removeAll()
        logLines.removeAll()
        logText = L10n.text("no_backend_output")
    }

    private func enqueueLog(_ text: String) {
        guard !text.isEmpty else { return }
        pendingLogLines.append(text)

        guard logFlushTask == nil else { return }
        logFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                self?.flushPendingLogs()
            }
        }
    }

    private func appendLog(_ text: String) {
        guard !text.isEmpty else { return }
        logLines.append(text)
        if logLines.count > 200 {
            logLines.removeFirst(logLines.count - 200)
        }
        logText = logLines.isEmpty ? L10n.text("no_backend_output") : logLines.joined(separator: "\n")
    }

    private func flushPendingLogs() {
        logFlushTask?.cancel()
        logFlushTask = nil
        guard !pendingLogLines.isEmpty else { return }
        appendLog(pendingLogLines.joined(separator: "\n"))
        pendingLogLines.removeAll(keepingCapacity: true)
    }

    private func markJobCompleted() {
        completedJobCount += 1
        updateProgressFromCompletedCount()
    }

    private func updateProgressFromCompletedCount() {
        guard !jobs.isEmpty else {
            progress = 0
            return
        }
        progress = Double(completedJobCount) / Double(jobs.count)
    }
}

private extension JobStatus {
    var isTerminal: Bool {
        switch self {
        case .finished, .failed, .cancelled:
            return true
        case .queued, .running:
            return false
        }
    }
}
