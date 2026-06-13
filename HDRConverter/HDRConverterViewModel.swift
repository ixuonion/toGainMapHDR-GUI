import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class HDRConverterViewModel: ObservableObject, @unchecked Sendable {
    private static let maxSupportedConcurrentJobs = 2
    private static let estimatedWorkingSetPerJob: UInt64 = 4 * 1024 * 1024 * 1024
    @Published var inputFilePaths: [String] = [] {
        didSet {
            refreshInputFileMetadata()
            updateEffectiveConcurrentJobs()
        }
    }
    @Published var outputDirectory: String = ""
    @Published var outputFormat: OutputFormat = .isoGainMap {
        didSet {
            updateDerivedValues()
        }
    }
    @Published var fileFormat: FileFormat = .heic
    @Published var quality: Double = 0.85
    @Published var colorSpace: ColorSpace = .p3
    @Published var bitDepth: BitDepth = .eight
    @Published var toneMappingRatio: Double = 3.0
    @Published var maxHeadroom: Double = 6.0
    @Published var gainMapScaling: Double = 1.0
    @Published var monochrome: Bool = false
    @Published var isConverting: Bool = false
    @Published private(set) var isCancelling: Bool = false
    @Published var outputMessage: String?
    @Published var isSuccess: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentFile: String = ""
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var logs: [String] = []
    @Published var showLogs: Bool = false
    @Published var convertedFiles: [String] = []
    @Published var batchConcurrencyMode: BatchConcurrencyMode = .auto {
        didSet {
            updateEffectiveConcurrentJobs()
        }
    }
    @Published var manualConcurrentJobs: Int = 2 {
        didSet {
            let clamped = max(1, min(Self.maxSupportedConcurrentJobs, manualConcurrentJobs))
            if clamped != manualConcurrentJobs {
                manualConcurrentJobs = clamped
                return
            }
            updateEffectiveConcurrentJobs()
        }
    }
    @Published private(set) var effectiveConcurrentJobs: Int = 1
    @Published private(set) var hardwareSummary: String = ""
    @Published private(set) var queueStatusMessage: String = "等待开始"
    @Published private(set) var shouldDisableJpegOption: Bool = false
    
    private var startTime: Date?
    private var fileConversionTimes: [TimeInterval] = []
    private var inputFileSizes: [String: Int64] = [:]
    private var totalInputBytes: Int64 = 0
    private let fileManager = FileManager.default
    private let processInfo = ProcessInfo.processInfo
    private let runningTasksLock = NSLock()
    private let cancellationLock = NSLock()
    private var runningTasks: [UUID: Process] = [:]
    private var _cancelRequested = false
    private var cancelRequested: Bool {
        get {
            cancellationLock.lock()
            defer { cancellationLock.unlock() }
            return _cancelRequested
        }
        set {
            cancellationLock.lock()
            _cancelRequested = newValue
            cancellationLock.unlock()
        }
    }
    
    enum OutputFormat: String, CaseIterable, Sendable {
        case isoGainMap = "ISO Gain Map"
        case appleGainMap = "Apple Gain Map"
        case pqHDR = "PQ HDR"
        case hlgHDR = "HLG HDR"
        case sdr = "SDR"
    }
    
    enum FileFormat: String, CaseIterable, Sendable {
        case heic = "HEIC"
        case jpg = "JPEG"
    }
    
    enum ColorSpace: String, CaseIterable, Sendable {
        case srgb = "srgb"
        case p3 = "p3"
        case rec2020 = "rec2020"
    }
    
    enum BitDepth: Int, CaseIterable, Sendable {
        case eight = 8
        case ten = 10
    }
    
    enum BatchConcurrencyMode: String, CaseIterable, Sendable {
        case auto = "自动"
        case manual = "手动"
    }

    
    struct CommandPart: Identifiable {
        let id: String
        let type: CommandPartType
        let content: String
        let fullContent: String

        init(id: String, type: CommandPartType, content: String, fullContent: String) {
            self.id = id
            self.type = type
            self.content = content
            self.fullContent = fullContent
        }
    }
    
    enum CommandPartType {
        case executable
        case sourcePath
        case outputPath
        case parameterFlag
        case parameterValue

    }
    
    private struct ConversionSettings: Sendable {
        let outputDirectory: String
        let outputFormat: OutputFormat
        let fileFormat: FileFormat
        let quality: Double
        let colorSpace: ColorSpace
        let bitDepth: BitDepth
        let toneMappingRatio: Double
        let maxHeadroom: Double
        let gainMapScaling: Double
        let monochrome: Bool
        
        func buildArguments(for filePath: String) -> [String] {
            var arguments: [String] = [filePath, outputDirectory]
            
            arguments.append("-q")
            arguments.append(String(format: "%.2f", quality))
            
            arguments.append("-r")
            arguments.append(String(format: "%.1f", toneMappingRatio))
            
            arguments.append("-R")
            arguments.append(String(format: "%.1f", maxHeadroom))
            
            arguments.append("-c")
            arguments.append(colorSpace.rawValue)
            
            arguments.append("-d")
            arguments.append(String(bitDepth.rawValue))
            
            if fileFormat == .jpg {
                arguments.append("-j")
            }
            
            switch outputFormat {
            case .isoGainMap:
                if monochrome {
                    arguments.append("-m")
                }
            case .appleGainMap:
                arguments.append("-g")
                arguments.append("-H")
                arguments.append(String(format: "%.1f", gainMapScaling))
            case .pqHDR:
                arguments.append("-p")
            case .hlgHDR:
                arguments.append("-h")
            case .sdr:
                arguments.append("-s")
            }
            
            return arguments
        }
        
        func outputFilePath(for inputPath: String) -> String {
            let url = URL(fileURLWithPath: inputPath)
            let ext = fileFormat == .jpg ? "jpg" : "heic"
            let outputURL = URL(fileURLWithPath: outputDirectory)
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
                .appendingPathExtension(ext)
            return outputURL.path
        }
    }
    
    private struct ConversionResult: Sendable {
        let filePath: String
        let outputPath: String
        let success: Bool
        let duration: TimeInterval
        let output: String?
    }
    
    @Published var executablePath: String = ""
    @Published var runtimeStatus: RuntimeStatus
    
    init() {
        self.runtimeStatus = RuntimeStatus(executablePath: nil, missingResources: ["检测中..."])
        self.hardwareSummary = HDRConverterViewModel.makeHardwareSummary(processInfo: ProcessInfo.processInfo)
        updateDerivedValues()
        updateEffectiveConcurrentJobs()
        
        Task {
            let status = await RuntimeStatus.detectAsync()
            await MainActor.run {
                self.runtimeStatus = status
                self.executablePath = status.executablePath ?? ""
            }
        }
    }
    
    var canConvert: Bool {
        !inputFilePaths.isEmpty && !outputDirectory.isEmpty && runtimeStatus.isReady
    }
    
    var parsedCommandParts: [CommandPart] {
        guard let sampleFile = inputFilePaths.first else {
            return []
        }
        
        var parts: [CommandPart] = []

        func appendPart(type: CommandPartType, content: String, fullContent: String) {
            parts.append(CommandPart(
                id: "command-part-\(parts.count)",
                type: type,
                content: content,
                fullContent: fullContent
            ))
        }

        appendPart(type: .executable, content: "toGainMapHDR", fullContent: executablePath)
        appendPart(type: .sourcePath, content: abbreviatePath(sampleFile), fullContent: sampleFile)
        appendPart(type: .outputPath, content: abbreviatePath(outputDirectory), fullContent: outputDirectory)
        
        let args = buildArguments(for: sampleFile)
        var i = 2
        
        while i < args.count {
            let arg = args[i]
            if arg.starts(with: "-") {
                appendPart(type: .parameterFlag, content: arg, fullContent: arg)
                i += 1
                if i < args.count && !args[i].starts(with: "-") {
                    let valueArg = args[i]
                    appendPart(type: .parameterValue, content: valueArg, fullContent: valueArg)
                    i += 1
                }
            } else {
                i += 1
            }
        }
        
        return parts
    }
    
    var totalFileSize: String {
        ByteCountFormatter.string(fromByteCount: totalInputBytes, countStyle: .file)
    }
    
    var hasManyFiles: Bool {
        inputFilePaths.count > 20
    }
    
    var isIntelHardware: Bool {
        !isAppleSilicon
    }
    
    var concurrencyExplanation: String {
        let modeText = batchConcurrencyMode == .auto
            ? "自动模式会根据芯片、内存容量和文件数选择均衡并发。"
            : "手动模式直接限制同时处理的文件数。"
        let riskText: String
        switch batchConcurrencyMode {
        case .manual:
            riskText = "严格兼容模式最多同时处理 2 个文件。"
        case .auto:
            riskText = "大型 HDR 图像会占用数 GB 工作内存，因此不会直接按 CPU 核心数拉满。"
        }
        return modeText + riskText
    }
    
    func getFileExtension(for path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }
    
    func getFileSize(for path: String) -> String {
        if let size = inputFileSizes[path] {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        return "-"
    }
    
    var commandPreview: String {
        guard let sampleFile = inputFilePaths.first else {
            return "请先选择输入文件"
        }
        let args = buildArguments(for: sampleFile)
        return executablePath + " " + args.joined(separator: " ")
    }
    
    private var isAppleSilicon: Bool {
        Self.isAppleSiliconMachine
    }
    
    private static var isAppleSiliconMachine: Bool {
        sysctlIntValue(for: "hw.optional.arm64") == 1
    }
    
    private static func sysctlIntValue(for name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = name.withCString { cString in
            sysctlbyname(cString, &value, &size, nil, 0)
        }
        return result == 0 ? Int(value) : 0
    }
    
    private static func makeHardwareSummary(processInfo: ProcessInfo) -> String {
        let platform = isAppleSiliconMachine ? "Apple Silicon" : "Intel"
        return "\(platform) · CPU \(processInfo.processorCount) 核 · 当前可用 \(processInfo.activeProcessorCount) 核"
    }
    
    private func updateDerivedValues() {
        let newShouldDisableJpeg = outputFormat == .pqHDR || outputFormat == .hlgHDR
        if newShouldDisableJpeg != shouldDisableJpegOption {
            DispatchQueue.main.async { [weak self] in
                self?.shouldDisableJpegOption = newShouldDisableJpeg
                if newShouldDisableJpeg, self?.fileFormat == .jpg {
                    self?.fileFormat = .heic
                }
            }
        }
    }
    
    private func updateEffectiveConcurrentJobs() {
        let fileCount = inputFilePaths.count
        let concurrentJobs: Int
        let upperBound: Int
        switch batchConcurrencyMode {
        case .manual:
            concurrentJobs = manualConcurrentJobs
            upperBound = max(
                1,
                min(fileCount, Self.maxSupportedConcurrentJobs, manualMemoryLimit)
            )
        case .auto:
            concurrentJobs = recommendedConcurrentJobs(for: fileCount)
            upperBound = max(1, fileCount)
        }
        effectiveConcurrentJobs = min(max(1, concurrentJobs), upperBound)
    }
    
    func recommendedConcurrentJobs(for fileCount: Int) -> Int {
        guard fileCount > 1 else { return 1 }

        let usableMemory = UInt64(Double(processInfo.physicalMemory) * 0.6)
        let memoryLimit = max(1, Int(usableMemory / Self.estimatedWorkingSetPerJob))
        let hardwareLimit: Int

        if isAppleSilicon {
            hardwareLimit = processInfo.activeProcessorCount >= 8 ? 2 : 1
        } else {
            hardwareLimit = 1
        }

        return min(hardwareLimit, memoryLimit, fileCount)
    }

    private var manualMemoryLimit: Int {
        let usableMemory = UInt64(Double(processInfo.physicalMemory) * 0.75)
        return max(1, Int(usableMemory / Self.estimatedWorkingSetPerJob))
    }

    private func refreshInputFileMetadata() {
        var sizes: [String: Int64] = [:]
        var total: Int64 = 0

        for path in inputFilePaths {
            if let attributes = try? fileManager.attributesOfItem(atPath: path),
               let size = attributes[.size] as? NSNumber {
                let byteCount = size.int64Value
                sizes[path] = byteCount
                total += byteCount
            }
        }

        inputFileSizes = sizes
        totalInputBytes = total
    }
    
    private func abbreviatePath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents
        
        guard components.count > 5 else {
            return path
        }
        
        let first = components[1]
        let last = components.suffix(3).joined(separator: "/")
        return "/\(first)/.../\(last)"
    }
    
    func selectInputFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .tiff, .heic, .jpeg, UTType(filenameExtension: "avif"), UTType(filenameExtension: "jxl"), UTType(filenameExtension: "exr"), UTType(filenameExtension: "hdr")].compactMap { $0 }
        
        if panel.runModal() == .OK {
            let newPaths = panel.urls.map { $0.path }
            let existingPaths = Set(inputFilePaths)
            inputFilePaths.append(contentsOf: newPaths.filter { !existingPaths.contains($0) })
            
            if outputDirectory.isEmpty, let firstURL = panel.urls.first {
                outputDirectory = firstURL.deletingLastPathComponent().path
            }
        }
    }
    
    func removeInputFile(_ path: String) {
        inputFilePaths.removeAll { $0 == path }
    }
    
    func clearInputFiles() {
        inputFilePaths.removeAll()
    }
    
    func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url.path
        }
    }
    
    private func buildArguments(for filePath: String) -> [String] {
        makeConversionSettings().buildArguments(for: filePath)
    }
    
    private func makeConversionSettings() -> ConversionSettings {
        ConversionSettings(
            outputDirectory: outputDirectory,
            outputFormat: outputFormat,
            fileFormat: fileFormat,
            quality: quality,
            colorSpace: colorSpace,
            bitDepth: bitDepth,
            toneMappingRatio: toneMappingRatio,
            maxHeadroom: maxHeadroom,
            gainMapScaling: gainMapScaling,
            monochrome: monochrome
        )
    }
    
    func convert() {
        guard canConvert else { return }

        let settings = makeConversionSettings()
        let outputPaths = inputFilePaths.map { settings.outputFilePath(for: $0) }
        guard Set(outputPaths).count == outputPaths.count else {
            isSuccess = false
            outputMessage = "存在同名输入文件，将写入同一个输出路径。请分批转换。"
            return
        }
        
        updateEffectiveConcurrentJobs()
        cancelRequested = false
        isCancelling = false
        isConverting = true
        progress = 0
        currentFile = ""
        logs = []
        convertedFiles = []
        fileConversionTimes = []
        startTime = Date()
        queueStatusMessage = makeQueueStatusMessage(running: 0, total: inputFilePaths.count, completed: 0)
        
        let filePaths = inputFilePaths
        let executablePath = self.executablePath
        let concurrencyLimit = min(max(1, effectiveConcurrentJobs), filePaths.count)
        Task {
            await convertFiles(
                filePaths: filePaths,
                settings: settings,
                executablePath: executablePath,
                concurrencyLimit: concurrencyLimit
            )
        }
    }
    
    private func convertFiles(
        filePaths: [String],
        settings: ConversionSettings,
        executablePath: String,
        concurrencyLimit: Int
    ) async {
        let totalFiles = filePaths.count
        var nextIndex = 0
        var activeCount = 0
        var completedCount = 0
        
        func scheduleTask(for filePath: String, group: inout TaskGroup<ConversionResult>) async {
            activeCount += 1
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            await MainActor.run {
                self.currentFile = fileName
                self.addLog("正在处理: \(fileName)")
                self.queueStatusMessage = self.makeQueueStatusMessage(running: activeCount, total: totalFiles, completed: completedCount)
            }
            group.addTask { [self, settings] in
                await self.convertSingleFile(
                    filePath,
                    settings: settings,
                    executablePath: executablePath
                )
            }
        }
        
        await withTaskGroup(of: ConversionResult.self) { group in
            while nextIndex < totalFiles && activeCount < concurrencyLimit {
                let filePath = filePaths[nextIndex]
                nextIndex += 1
                await scheduleTask(for: filePath, group: &group)
            }
            
            while let result = await group.next() {
                activeCount = max(activeCount - 1, 0)
                completedCount += 1
                
                await MainActor.run {
                    self.handleConversionResult(
                        result,
                        completedCount: completedCount,
                        totalFiles: totalFiles,
                        activeCount: activeCount
                    )
                }
                
                while !cancelRequested && nextIndex < totalFiles && activeCount < concurrencyLimit {
                    let filePath = filePaths[nextIndex]
                    nextIndex += 1
                    await scheduleTask(for: filePath, group: &group)
                }
            }
        }
        
        await MainActor.run {
            self.isConverting = false
            self.isCancelling = false
            self.currentFile = ""
            self.queueStatusMessage = self.makeQueueStatusMessage(running: 0, total: totalFiles, completed: completedCount)
            self.logBatchSummary(completedCount: completedCount, totalFiles: totalFiles, concurrency: concurrencyLimit)
            
            if self.cancelRequested {
                self.isSuccess = false
                if self.convertedFiles.isEmpty {
                    self.outputMessage = "已取消转换"
                } else {
                    self.outputMessage = "已取消转换：已完成 \(self.convertedFiles.count)/\(totalFiles)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.askToDeleteConvertedFiles()
                    }
                }
                return
            }
            
            if self.convertedFiles.count == totalFiles {
                self.isSuccess = true
                self.outputMessage = "全部转换成功！共 \(self.convertedFiles.count) 个文件"
            } else if !self.convertedFiles.isEmpty {
                self.isSuccess = false
                self.outputMessage = "部分转换成功：\(self.convertedFiles.count)/\(totalFiles)"
            } else {
                self.isSuccess = false
                self.outputMessage = "转换失败"
            }
        }
    }
    
    private func convertSingleFile(
        _ filePath: String,
        settings: ConversionSettings,
        executablePath: String
    ) async -> ConversionResult {
        let startedAt = Date()
        let outputPath = settings.outputFilePath(for: filePath)
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            let taskID = UUID()
            let pipe = Pipe()
            let outputBuffer = ProcessOutputBuffer()
            
            task.executableURL = URL(fileURLWithPath: executablePath)
            task.arguments = settings.buildArguments(for: filePath)
            task.standardOutput = pipe
            task.standardError = pipe
            
            registerRunningTask(task, id: taskID)
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                outputBuffer.readAvailableData(from: handle)
            }
            
            task.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                outputBuffer.readToEnd(from: pipe.fileHandleForReading)
                let output = String(data: outputBuffer.data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.unregisterRunningTask(id: taskID)
                let outputExists = self.fileManager.fileExists(atPath: outputPath)
                continuation.resume(returning: ConversionResult(
                    filePath: filePath,
                    outputPath: outputPath,
                    success: process.terminationStatus == 0 && outputExists,
                    duration: Date().timeIntervalSince(startedAt),
                    output: output?.isEmpty == false ? output : nil
                ))
            }
            
            do {
                guard try runTaskUnlessCancelled(task) else {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    unregisterRunningTask(id: taskID)
                    continuation.resume(returning: ConversionResult(
                        filePath: filePath,
                        outputPath: outputPath,
                        success: false,
                        duration: Date().timeIntervalSince(startedAt),
                        output: nil
                    ))
                    return
                }
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                unregisterRunningTask(id: taskID)
                continuation.resume(returning: ConversionResult(
                    filePath: filePath,
                    outputPath: outputPath,
                    success: false,
                    duration: Date().timeIntervalSince(startedAt),
                    output: "错误: \(error.localizedDescription)"
                ))
            }
        }
    }

    private func runTaskUnlessCancelled(_ task: Process) throws -> Bool {
        cancellationLock.lock()
        defer { cancellationLock.unlock() }

        guard !_cancelRequested else { return false }
        try task.run()
        return true
    }
    
    private func handleConversionResult(
        _ result: ConversionResult,
        completedCount: Int,
        totalFiles: Int,
        activeCount: Int
    ) {
        let fileName = URL(fileURLWithPath: result.filePath).lastPathComponent
        
        if let output = result.output, !output.isEmpty {
            addLog("[\(fileName)] \(output)")
        }
        
        if result.success {
            convertedFiles.append(result.outputPath)
            addLog("✓ 完成: \(fileName) (\(String(format: "%.1f", result.duration))秒)")
            fileConversionTimes.append(result.duration)
        } else if cancelRequested {
            addLog("○ 已取消: \(fileName)")
        } else {
            addLog("✗ 失败: \(fileName)")
        }
        
        currentFile = fileName
        progress = Double(completedCount) / Double(totalFiles)
        updateEstimatedTimeRemaining(completedCount: completedCount, totalFiles: totalFiles)
        queueStatusMessage = makeQueueStatusMessage(running: activeCount, total: totalFiles, completed: completedCount)
    }
    
    func cancel() {
        guard isConverting, !isCancelling else { return }
        cancelRequested = true
        isCancelling = true
        queueStatusMessage = "正在取消..."
        terminateAllRunningTasks()
    }
    
    private func askToDeleteConvertedFiles() {
        let alert = NSAlert()
        alert.messageText = "是否删除已转换的文件？"
        alert.informativeText = "已成功转换 \(convertedFiles.count) 个文件，是否删除？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保留")
        alert.addButton(withTitle: "删除")
        
        if alert.runModal() == .alertSecondButtonReturn {
            deleteConvertedFiles()
        }
    }
    
    private func deleteConvertedFiles() {
        for file in convertedFiles {
            try? fileManager.removeItem(atPath: file)
            addLog("已删除: \(URL(fileURLWithPath: file).lastPathComponent)")
        }
        convertedFiles.removeAll()
    }
    
    private func registerRunningTask(_ task: Process, id: UUID) {
        runningTasksLock.lock()
        runningTasks[id] = task
        runningTasksLock.unlock()
    }
    
    private func unregisterRunningTask(id: UUID) {
        runningTasksLock.lock()
        runningTasks.removeValue(forKey: id)
        runningTasksLock.unlock()
    }
    
    private func terminateAllRunningTasks() {
        runningTasksLock.lock()
        let tasks = Array(runningTasks.values)
        runningTasksLock.unlock()
        
        for task in tasks where task.isRunning {
            task.terminate()
        }
    }
    
    private func updateEstimatedTimeRemaining(completedCount: Int, totalFiles: Int) {
        guard !fileConversionTimes.isEmpty else {
            estimatedTimeRemaining = 0
            return
        }
        
        let avgTime = fileConversionTimes.reduce(0, +) / Double(fileConversionTimes.count)
        let remainingFiles = max(totalFiles - completedCount, 0)
        estimatedTimeRemaining = avgTime * Double(remainingFiles) / Double(max(effectiveConcurrentJobs, 1))
    }
    
    private func makeQueueStatusMessage(running: Int, total: Int, completed: Int) -> String {
        let remaining = max(total - completed - running, 0)
        if cancelRequested {
            return "正在取消... 运行中 \(running) / 并发上限 \(effectiveConcurrentJobs) / 剩余 \(remaining)"
        }
        if total == 0 {
            return "等待开始"
        }
        return "运行中 \(running) / 并发上限 \(effectiveConcurrentJobs) / 剩余 \(remaining)"
    }
    
    private static let maxLogCount = 1000
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)")
        
        if logs.count > Self.maxLogCount {
            logs.removeFirst(logs.count - Self.maxLogCount)
        }
    }

    private func logBatchSummary(completedCount: Int, totalFiles: Int, concurrency: Int) {
        guard let startTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let throughput = elapsed > 0 ? Double(completedCount) / elapsed * 60 : 0
        addLog(
            "批次统计: 完成 \(completedCount)/\(totalFiles)，并发 \(concurrency)，"
            + "总耗时 \(String(format: "%.1f", elapsed)) 秒，"
            + "吞吐 \(String(format: "%.2f", throughput)) 张/分钟"
        )
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func readAvailableData(from handle: FileHandle) {
        lock.lock()
        let data = handle.availableData
        if !data.isEmpty {
            storage.append(data)
        }
        lock.unlock()
    }

    func readToEnd(from handle: FileHandle) {
        lock.lock()
        let data = handle.readDataToEndOfFile()
        if !data.isEmpty {
            storage.append(data)
        }
        lock.unlock()
    }
}

struct RuntimeStatus {
    let executablePath: String?
    let missingResources: [String]

    var isReady: Bool {
        executablePath != nil && missingResources.isEmpty
    }

    var message: String {
        if isReady {
            return "运行时依赖已就绪"
        }

        var issues: [String] = []
        if executablePath == nil {
            issues.append("toGainMapHDR 可执行文件")
        }
        issues.append(contentsOf: missingResources)
        return "缺少运行时依赖：" + issues.joined(separator: "、")
    }

    static func detect(fileManager: FileManager = .default, bundle: Bundle = .main) -> RuntimeStatus {
        detectSync(fileManager: fileManager, bundle: bundle)
    }

    static func detectSync(fileManager: FileManager = .default, bundle: Bundle = .main) -> RuntimeStatus {
        let bundlePath = bundle.bundlePath
        let resourcePath = bundle.resourcePath ?? ""
        let macOSPath = "\(bundlePath)/Contents/MacOS"

        let executableCandidates = [
            "\(macOSPath)/toGainMapHDR",
            "\(resourcePath)/toGainMapHDR",
            "\(fileManager.currentDirectoryPath)/toGainMapHDR"
        ]

        let executablePath = executableCandidates.first {
            fileManager.isExecutableFile(atPath: $0)
        }

        let requiredResources = [
            "GainMapKernel.ci.metallib",
            "RGBGainMapKernel.ci.metallib"
        ]

        let searchDirectories = [
            macOSPath,
            resourcePath,
            fileManager.currentDirectoryPath
        ].filter { !$0.isEmpty }

        let missingResources = requiredResources.filter { resource in
            !searchDirectories.contains { directory in
                fileManager.fileExists(atPath: "\(directory)/\(resource)")
            }
        }

        return RuntimeStatus(executablePath: executablePath, missingResources: missingResources)
    }

    static func detectAsync(fileManager: FileManager = .default, bundle: Bundle = .main) async -> RuntimeStatus {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                let status = detectSync(fileManager: fileManager, bundle: bundle)
                continuation.resume(returning: status)
            }
        }
    }
}

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
