import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = HDRConverterViewModel()
    
    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("HDR 转换器")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.selectInputFiles()
                            }
                        } label: {
                            Label("添加文件", systemImage: "plus")
                        }
                    }
                }
        }
        .frame(minWidth: 680, idealWidth: 780, maxWidth: .infinity, minHeight: 680, idealHeight: 780, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.isConverting) {
            conversionProgressView
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                headerView
                    .padding()
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 20) {
                        fileSelectionSection
                        commandPreviewSection
                        outputSettingsSection
                        advancedSettingsSection
                        convertButtonSection
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.inputFilePaths.count)
                }
            }
            
            if let outputMessage = viewModel.outputMessage {
                Divider()
                outputMessageView(outputMessage)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.outputMessage != nil)
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text("HDR Gain Map 转换器")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            Text("将 HDR 图像转换为 Gain Map HDR 格式")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var fileSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("输入文件")
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.inputFilePaths.count) 个文件")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                
                if !viewModel.inputFilePaths.isEmpty {
                    Text(viewModel.totalFileSize)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.selectInputFiles()
                        }
                    } label: {
                        Label("添加文件", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.clearInputFiles()
                        }
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.inputFilePaths.isEmpty)
                    
                    Spacer()
                }
                
                if !viewModel.inputFilePaths.isEmpty {
                    if viewModel.hasManyFiles {
                        fileListViewCompact
                            .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
                    } else {
                        fileListViewDetailed
                            .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
                    }
                }
                
                Divider()
                
                HStack {
                    Text("输出位置")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextField("", text: $viewModel.outputDirectory)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    
                    Button {
                        viewModel.selectOutputDirectory()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
    
    private var fileListViewDetailed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.inputFilePaths, id: \.self) { path in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .lineLimit(1)
                                .font(.body)
                            
                            Text("\(viewModel.getFileExtension(for: path).uppercased()) · \(viewModel.getFileSize(for: path))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.removeInputFile(path)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 180)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    
    private var fileListViewCompact: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc.fill")
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.inputFilePaths.count) 个文件已选择")
                            .font(.subheadline)
                    }
                    Text(viewModel.totalFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.clearInputFiles()
                    }
                } label: {
                    Label("全部移除", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            Text("提示：由于文件数量较多，仅显示摘要信息。您可以点击\"添加文件\"继续添加，或点击\"全部移除\"清空列表。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    
    private var commandPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("命令预览")
                    .font(.headline)
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(viewModel.commandPreview, forType: .string)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.inputFilePaths.isEmpty)
            }
            
            ScrollView(.horizontal) {
                Text(viewModel.commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
    
    private var outputSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("输出设置")
                .font(.headline)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("输出格式")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("输出格式", selection: $viewModel.outputFormat) {
                        Text("ISO Gain Map HDR").tag(HDRConverterViewModel.OutputFormat.isoGainMap)
                        Text("Apple Gain Map HDR").tag(HDRConverterViewModel.OutputFormat.appleGainMap)
                        Text("PQ HDR").tag(HDRConverterViewModel.OutputFormat.pqHDR)
                        Text("HLG HDR").tag(HDRConverterViewModel.OutputFormat.hlgHDR)
                        Text("SDR").tag(HDRConverterViewModel.OutputFormat.sdr)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Divider()
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("文件格式")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $viewModel.fileFormat) {
                            Text("HEIC").tag(HDRConverterViewModel.FileFormat.heic)
                            Text("JPEG").tag(HDRConverterViewModel.FileFormat.jpg)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(viewModel.shouldDisableJpegOption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("图像质量")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Slider(value: $viewModel.quality, in: 0.1...1.0)
                            Text(String(format: "%.0f%%", viewModel.quality * 100))
                                .frame(width: 50, alignment: .trailing)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
    
    private var advancedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("高级设置")
                .font(.headline)
            
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("色彩空间")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $viewModel.colorSpace) {
                            Text("sRGB").tag(HDRConverterViewModel.ColorSpace.srgb)
                            Text("P3").tag(HDRConverterViewModel.ColorSpace.p3)
                            Text("Rec. 2020").tag(HDRConverterViewModel.ColorSpace.rec2020)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("位深度")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $viewModel.bitDepth) {
                            Text("8-bit").tag(HDRConverterViewModel.BitDepth.eight)
                            Text("10-bit").tag(HDRConverterViewModel.BitDepth.ten)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("SDR 映射比")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("", value: $viewModel.toneMappingRatio, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("(≥1.0)")
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
                
                if viewModel.outputFormat == .appleGainMap {
                    Divider()
                        .transition(.opacity)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gain Map 缩放")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Slider(value: $viewModel.gainMapScaling, in: 1.0...2.0, step: 0.1)
                            Text(String(format: "%.1f", viewModel.gainMapScaling))
                                .frame(width: 45, alignment: .trailing)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                        removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9))
                    ))
                }
                
                if viewModel.outputFormat == .isoGainMap {
                    Divider()
                        .transition(.opacity)
                    Toggle("单色 Gain Map", isOn: $viewModel.monochrome)
                        .toggleStyle(.switch)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                            removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9))
                        ))
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
    
    private var convertButtonSection: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                viewModel.convert()
            }
        }) {
            Label("转换", systemImage: "wand.and.stars")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!viewModel.canConvert)
    }
    
    private func outputMessageView(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(viewModel.isSuccess ? .green : .red)
            
            Text(message)
                .font(.body)
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.outputMessage = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(viewModel.isSuccess ? Color.green.opacity(0.1) : Color.red.opacity(0.1),
                   in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    private var conversionProgressView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("正在转换...")
                    .font(.headline)
                
                if !viewModel.currentFile.isEmpty {
                    Text(viewModel.currentFile)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, 8)
            
            VStack(spacing: 12) {
                ProgressView(value: viewModel.progress)
                
                HStack {
                    Text(String(format: "%.0f%%", viewModel.progress * 100))
                        .font(.subheadline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    
                    Spacer()
                    
                    if viewModel.estimatedTimeRemaining > 0 {
                        Text(formatTime(viewModel.estimatedTimeRemaining))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            VStack(spacing: 16) {
                Toggle("显示日志", isOn: $viewModel.showLogs)
                    .toggleStyle(.switch)
                
                Button("取消") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.cancel()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            
            if viewModel.showLogs {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.logs, id: \.self) { log in
                            Text(log)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .padding(8)
                }
                .frame(height: 180)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95))
                ))
            }
        }
        .frame(width: 520)
        .padding()
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.showLogs)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        if time < 60 {
            return String(format: "剩余 %.0f 秒", time)
        } else {
            let minutes = Int(time / 60)
            let seconds = Int(time.truncatingRemainder(dividingBy: 60))
            return "剩余 \(minutes) 分 \(seconds) 秒"
        }
    }
}
