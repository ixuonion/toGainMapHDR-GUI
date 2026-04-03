import Foundation
import SwiftUI
import UniformTypeIdentifiers

class HDRConverterViewModel: ObservableObject {
    @Published var inputFilePaths: [String] = []
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
    
    private var currentTask: Process?
    private var startTime: Date?
    private var fileConversionTimes: [TimeInterval] = []
    private let fileManager = FileManager.default
    
    enum OutputFormat: String, CaseIterable {
        case isoGainMap = "ISO Gain Map"
        case appleGainMap = "Apple Gain Map"
        case pqHDR = "PQ HDR"
        case hlgHDR = "HLG HDR"
        case sdr = "SDR"
    }
    
    enum FileFormat: String, CaseIterable {
        case heic = "HEIC"
        case jpg = "JPEG"
    }
    
    enum ColorSpace: String, CaseIterable {
        case srgb = "srgb"
        case p3 = "p3"
        case rec2020 = "rec2020"
    }
    
    enum BitDepth: Int, CaseIterable {
        case eight = 8
        case ten = 10
    }
    
    private let executablePath: String
    
    init() {
        let bundlePath = Bundle.main.bundlePath
        let possiblePaths = [
            "/Users/bytedance/toGainMapHDR/bin/toGainMapHDR",
            "\(bundlePath)/Contents/MacOS/toGainMapHDR",
            "\(bundlePath)/Contents/Resources/toGainMapHDR",
            "\(bundlePath)/toGainMapHDR",
            "\(Bundle.main.resourcePath ?? "")/toGainMapHDR"
        ]
        
        self.executablePath = possiblePaths.first { FileManager.default.fileExists(atPath: $0) } ?? ""
        // 初始化派生值
        updateDerivedValues()
    }
    
    var canConvert: Bool {
        !inputFilePaths.isEmpty && !outputDirectory.isEmpty && !executablePath.isEmpty
    }
    
    @Published private(set) var shouldDisableJpegOption: Bool = false
    
    private func updateDerivedValues() {
        // 当 outputFormat 变化时，更新相关的派生属性
        let newShouldDisableJpeg = outputFormat == .pqHDR || outputFormat == .hlgHDR
        if newShouldDisableJpeg != shouldDisableJpegOption {
            DispatchQueue.main.async { [weak self] in
                self?.shouldDisableJpegOption = newShouldDisableJpeg
                // 如果禁用了 JPEG 且当前选择了 JPEG，自动切换到 HEIC
                if newShouldDisableJpeg, self?.fileFormat == .jpg {
                    self?.fileFormat = .heic
                }
            }
        }
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
        var arguments: [String] = [filePath, outputDirectory]
        
        arguments.append("-q")
        arguments.append(String(format: "%.2f", quality))
        
        arguments.append("-r")
        arguments.append(String(format: "%.1f", toneMappingRatio))
        
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
    
    private func getOutputFilePath(for inputPath: String) -> String {
        let url = URL(fileURLWithPath: inputPath)
        let ext = fileFormat == .jpg ? "jpg" : "heic"
        let outputURL = URL(fileURLWithPath: outputDirectory)
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(ext)
        return outputURL.path
    }
    
    func convert() {
        guard canConvert else { return }
        
        isConverting = true
        progress = 0
        currentFile = ""
        logs = []
        convertedFiles = []
        fileConversionTimes = []
        startTime = Date()
        
        Task {
            await convertFiles()
        }
    }
    
    private func convertFiles() async {
        let totalFiles = inputFilePaths.count
        
        for (index, filePath) in inputFilePaths.enumerated() {
            guard isConverting else { break }
            
            await MainActor.run {
                currentFile = URL(fileURLWithPath: filePath).lastPathComponent
                addLog("正在处理: \(currentFile)")
            }
            
            let fileStart = Date()
            let success = await convertSingleFile(filePath)
            let fileTime = Date().timeIntervalSince(fileStart)
            
            await MainActor.run {
                if success {
                    let outputPath = getOutputFilePath(for: filePath)
                    convertedFiles.append(outputPath)
                    addLog("✓ 完成: \(currentFile) (\(String(format: "%.1f", fileTime))秒)")
                    fileConversionTimes.append(fileTime)
                } else {
                    addLog("✗ 失败: \(currentFile)")
                }
                
                progress = Double(index + 1) / Double(totalFiles)
                updateEstimatedTimeRemaining(currentIndex: index, total: totalFiles)
            }
        }
        
        await MainActor.run {
            isConverting = false
            currentFile = ""
            
            if convertedFiles.count == inputFilePaths.count {
                isSuccess = true
                outputMessage = "全部转换成功！共 \(convertedFiles.count) 个文件"
            } else if convertedFiles.count > 0 {
                isSuccess = false
                outputMessage = "部分转换成功：\(convertedFiles.count)/\(inputFilePaths.count)"
            } else {
                isSuccess = false
                outputMessage = "转换失败"
            }
        }
    }
    
    private func convertSingleFile(_ filePath: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let task = Process()
            currentTask = task
            task.executableURL = URL(fileURLWithPath: executablePath)
            task.arguments = buildArguments(for: filePath)
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)
                
                DispatchQueue.main.async {
                    if let output = output, !output.isEmpty {
                        self.addLog(output)
                    }
                }
                
                continuation.resume(returning: task.terminationStatus == 0)
            }
            
            do {
                try task.run()
            } catch {
                DispatchQueue.main.async {
                    self.addLog("错误: \(error.localizedDescription)")
                }
                continuation.resume(returning: false)
            }
        }
    }
    
    func cancel() {
        currentTask?.terminate()
        isConverting = false
        
        if !convertedFiles.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.askToDeleteConvertedFiles()
            }
        }
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
    
    private func updateEstimatedTimeRemaining(currentIndex: Int, total: Int) {
        guard !fileConversionTimes.isEmpty else {
            estimatedTimeRemaining = 0
            return
        }
        
        let avgTime = fileConversionTimes.reduce(0, +) / Double(fileConversionTimes.count)
        let remainingFiles = total - (currentIndex + 1)
        estimatedTimeRemaining = avgTime * Double(remainingFiles)
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)")
    }
}

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
