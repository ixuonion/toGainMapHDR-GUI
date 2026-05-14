import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class HDRConverterViewModel: ObservableObject, @unchecked Sendable {
    private static let maxSupportedConcurrentJobs = 40
    @Published var inputFilePaths: [String] = [] {
        didSet {
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
    @Published var performancePreference: PerformancePreference = .balanced {
        didSet {
            updateEffectiveConcurrentJobs()
        }
    }
    @Published var manualConcurrentJobs: Int = 4 {
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
    
    enum PerformancePreference: String, CaseIterable, Sendable {
        case efficient = "节能"
        case balanced = "均衡"
        case maxPerformance = "极速"
    }
    
    struct CommandPart: Identifiable {
        let id = UUID()
        let type: CommandPartType
        let content: String
        let fullContent: String
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
    
    let executablePath: String
    let runtimeStatus: RuntimeStatus
    
    init() {
        let runtimeStatus = RuntimeStatus.detect()
        self.runtimeStatus = runtimeStatus
        self.executablePath = runtimeStatus.executablePath ?? ""
        self.hardwareSummary = HDRConverterViewModel.makeHardwareSummary(processInfo: ProcessInfo.processInfo)
        updateDerivedValues()
        updateEffectiveConcurrentJobs()
    }
    
    var canConvert: Bool {
        !inputFilePaths.isEmpty && !outputDirectory.isEmpty && runtimeStatus.isReady
    }
    
    var parsedCommandParts: [CommandPart] {
        guard let sampleFile = inputFilePaths.first else {
            return []
        }
        
        var parts: [CommandPart] = []
        
        parts.append(CommandPart(type: .executable, content: "toGainMapHDR", fullContent: executablePath))
        parts.append(CommandPart(type: .sourcePath, content: abbreviatePath(sampleFile), fullContent: sampleFile))
        parts.append(CommandPart(type: .outputPath, content: abbreviatePath(outputDirectory), fullContent: outputDirectory))
        
        let args = buildArguments(for: sampleFile)
        var i = 2
        
        while i < args.count {
            let arg = args[i]
            if arg.starts(with: "-") {
                parts.append(CommandPart(type: .parameterFlag, content: arg, fullContent: arg))
                i += 1
                if i < args.count && !args[i].starts(with: "-") {
                    let valueArg = args[i]
                    parts.append(CommandPart(type: .parameterValue, content: valueArg, fullContent: valueArg))
                    i += 1
                }
            } else {
                i += 1
            }
        }
        
        return parts
    }
    
    var totalFileSize: String {
        var total: Int64 = 0
        for path in inputFilePaths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
    
    var hasManyFiles: Bool {
        inputFilePaths.count > 20
    }
    
    var isIntelHardware: Bool {
        !isAppleSilicon
    }
    
    var concurrencyExplanation: String {
        let modeText = batchConcurrencyMode == .auto ? "自动模式会直接使用 CPU 核心数作为并发数。" : "手动模式直接限制同时处理的文件数。"
        let riskText: String
        switch batchConcurrencyMode {
        case .manual:
            riskText = manualConcurrentJobs >= 6 ? "较高并发会增加功耗、内存压力，并且未必继续提速。" : "建议先从 2-4 并发开始观察吞吐和温度。"
        case .auto:
            riskText = "当前会忽略保守推荐逻辑，直接拉满到 CPU 核心数；文件数不足时则以文件数为准。"
        }
        return modeText + riskText
    }
    
    func getFileExtension(for path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }
    
    func getFileSize(for path: String) -> String {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
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
            upperBound = max(1, min(fileCount, Self.maxSupportedConcurrentJobs))
        case .auto:
            concurrentJobs = recommendedConcurrentJobs(for: fileCount)
            upperBound = max(1, fileCount)
        }
        effectiveConcurrentJobs = min(max(1, concurrentJobs), upperBound)
    }
    
    func recommendedConcurrentJobs(for fileCount: Int) -> Int {
        guard fileCount > 1 else { return 1 }
        return max(1, processInfo.processorCount)
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
            inputFilePaths.append(contentsOf: newPaths.filter { !inputFilePaths.contains($0) })
            
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
        
        updateEffectiveConcurrentJobs()
        cancelRequested = false
        isConverting = true
        progress = 0
        currentFile = ""
        logs = []
        convertedFiles = []
        fileConversionTimes = []
        startTime = Date()
        queueStatusMessage = makeQueueStatusMessage(running: 0, total: inputFilePaths.count, completed: 0)
        
        Task {
            await convertFiles()
        }
    }
    
    private func convertFiles() async {
        let filePaths = inputFilePaths
        let totalFiles = filePaths.count
        let settings = makeConversionSettings()
        let concurrencyLimit = min(max(1, effectiveConcurrentJobs), totalFiles)
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
                await self.convertSingleFile(filePath, settings: settings)
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
            self.currentFile = ""
            self.queueStatusMessage = self.makeQueueStatusMessage(running: 0, total: totalFiles, completed: completedCount)
            
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
    
    private func convertSingleFile(_ filePath: String, settings: ConversionSettings) async -> ConversionResult {
        let startedAt = Date()
        let outputPath = settings.outputFilePath(for: filePath)
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            let taskID = UUID()
            let pipe = Pipe()
            
            task.executableURL = URL(fileURLWithPath: executablePath)
            task.arguments = settings.buildArguments(for: filePath)
            task.standardOutput = pipe
            task.standardError = pipe
            
            registerRunningTask(task, id: taskID)
            
            task.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.unregisterRunningTask(id: taskID)
                continuation.resume(returning: ConversionResult(
                    filePath: filePath,
                    outputPath: outputPath,
                    success: process.terminationStatus == 0,
                    duration: Date().timeIntervalSince(startedAt),
                    output: output?.isEmpty == false ? output : nil
                ))
            }
            
            do {
                try task.run()
            } catch {
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
        guard isConverting else { return }
        cancelRequested = true
        isConverting = false
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
        estimatedTimeRemaining = avgTime * Double(remainingFiles)
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
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)")
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
}

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
