import AppKit
import SwiftUI

enum StudioLayout {
    static let headerHeight: CGFloat = 72
    static let footerHeight: CGFloat = 44
}

/// Production studio, preserving the approved demo layout.
@available(macOS 27, *)
struct StudioView: View {
    @Bindable var store: ConversionStore
    @State private var showsInspector = true
    @State private var showsSidebar = true
    @State private var showsDiagnostics = false

    var body: some View {
        HStack(spacing: 0) {
            if showsSidebar {
                StudioInputList(store: store)
                    .frame(width: 240)
                    .background(.bar)
                Divider()
            }
            VStack(spacing: 0) {
                StudioWorkspace(store: store)
                if showsDiagnostics {
                    Divider()
                    StudioDiagnostics(store: store)
                        .frame(height: 200)
                }
                Divider()
                StudioStatus(store: store)
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            if showsInspector {
                Divider()
                StudioInspector(store: store)
                    .frame(width: 320)
                    .background(.background.secondary)
            }
        }
        .navigationTitle("GainMapHDR")
        .navigationSubtitle(L10n.text("studio_subtitle"))
        .dropDestination(for: URL.self) { urls, _ in
            guard store.canImport else { return false }
            store.addInputURLs(urls)
            return !urls.isEmpty
        }
        .alert(L10n.text("failed"), item: $store.presentedError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in Text(message) }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { showsSidebar.toggle() } label: {
                    Label(L10n.text("demo_library"), systemImage: "sidebar.leading")
                }
                .help(L10n.text("demo_library"))
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button(L10n.text("add_images"), systemImage: "photo.badge.plus") { store.pickInputImages() }
                    Button(L10n.text("add_folder"), systemImage: "folder.badge.plus") { store.pickInputFolder() }
                } label: {
                    Label(L10n.text("demo_import"), systemImage: "plus")
                }
                .disabled(!store.canImport)
                .help(L10n.text("demo_import"))
                Button { showsDiagnostics.toggle() } label: {
                    Label(L10n.text("demo_diagnostics"), systemImage: "terminal")
                }
                .help(L10n.text("demo_diagnostics"))
                Button { showsInspector.toggle() } label: {
                    Label(L10n.text("demo_inspector"), systemImage: "sidebar.trailing")
                }
                .help(L10n.text("demo_inspector"))
            }
            .visibilityPriority(.low)
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    store.isConverting ? store.cancelConversion() : store.startConversion()
                } label: {
                    Label(L10n.text(store.isCancelling ? "cancelling" : store.isConverting ? "cancel" : store.settings.destinationChoice == .photosLibrary ? "photos_convert_save" : "demo_convert_all"),
                          systemImage: store.isConverting ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isCancelling || (!store.canConvert && !store.isConverting))
            }
            .visibilityPriority(ToolbarItemVisibilityPriority(higherThan: .high))
        }
    }
}

private struct StudioInputList: View {
    @Bindable var store: ConversionStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("demo_library")).font(.headline)
                Spacer()
                Text(store.inputs.count, format: .number).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: StudioLayout.headerHeight)
            Divider()
            List(selection: $store.selectedInputID) {
                ForEach(store.inputs) { input in
                    Label {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(input.displayName).lineLimit(1)
                            Text(input.directoryName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: "photo").foregroundStyle(.tint)
                    }
                    .padding(.vertical, 7)
                    .tag(input.id)
                    .contextMenu {
                        Button(L10n.text("remove")) { store.removeInput(id: input.id) }
                            .disabled(!store.canImport)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if store.inputs.isEmpty {
                    ContentUnavailableView(L10n.text("demo_no_inputs"), systemImage: "photo.on.rectangle",
                                           description: Text(L10n.text("demo_sidebar_hint")))
                }
            }
            Divider()
            HStack {
                Button { store.removeSelectedInput() } label: {
                    Label(L10n.text("remove"), systemImage: "minus")
                }
                .disabled(store.selectedInputID == nil || store.isConverting)
                Spacer()
                Button(L10n.text("clear_all")) { store.clearInputs() }
                    .disabled(store.inputs.isEmpty || store.isConverting)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .frame(height: StudioLayout.footerHeight)
        }
    }
}

private struct StudioWorkspace: View {
    @Bindable var store: ConversionStore

    var body: some View {
        VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("demo_workspace")).font(.title2.bold())
                        Text(L10n.text("demo_workspace_hint"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("HEIC").font(.caption.bold()).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                }
                .padding(.horizontal, 24)
                .frame(height: StudioLayout.headerHeight)
                Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                if let input = store.inputs.first(where: { $0.id == store.selectedInputID }) {
                    StudioSourcePreview(input: input)
                } else {
                    StudioWelcome(store: store)
                }
                StudioRecipeSummary(settings: store.settings)
                if !store.jobs.isEmpty {
                    StudioQueue(jobs: store.jobs)
                }
            }
            .padding(24)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct StudioWelcome: View {
    let store: ConversionStore
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(L10n.text("demo_welcome")).font(.title2.weight(.semibold))
                Text(L10n.text("demo_welcome_hint"))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button(L10n.text("add_images")) { store.pickInputImages() }
                    .buttonStyle(.borderedProminent)
                Button(L10n.text("add_folder")) { store.pickInputFolder() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .disabled(!store.canImport)
            Text("HEIC · JPEG · PNG · TIFF · AVIF · JXL · EXR · HDR")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 310)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StudioSourcePreview: View {
    let input: ImageInput
    @State private var thumbnail: CGImage?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable().scaledToFit().padding(16)
                        .accessibilityLabel(input.displayName)
                } else if isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(L10n.text("demo_no_preview"), systemImage: "photo",
                                           description: Text(L10n.text("demo_no_preview_hint")))
                }
            }
            .frame(height: 310)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(input.displayName).font(.headline).lineLimit(1)
                    Text(L10n.text("demo_preview_note")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([input.url])
                } label: {
                    Image(systemName: "folder")
                }
                .help(L10n.text("demo_reveal_source"))
                .accessibilityLabel(L10n.text("demo_reveal_source"))
            }
        }
        .task(id: input.id) {
            thumbnail = nil
            isLoading = true
            let image = try? await ThumbnailService.shared.image(for: input.url)
            guard !Task.isCancelled else { return }
            thumbnail = image
            isLoading = false
        }
    }
}

private struct StudioRecipeSummary: View {
    let settings: ConversionSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("demo_recipe")).font(.headline)
            HStack(spacing: 0) {
                StudioMetric(title: L10n.text("output_mode"), value: settings.outputMode.title)
                Spacer(minLength: 12)
                StudioMetric(title: L10n.text("color_space"), value: settings.colorSpace.title)
                Spacer(minLength: 12)
                StudioMetric(title: L10n.text("bit_depth"), value: settings.effectiveBitDepth.title)
            }
            Text(L10n.text("demo_batch_note")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct StudioMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium))
        }
    }
}

private struct StudioQueue: View {
    let jobs: [ConversionJob]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("batch_queue")).font(.headline)
            LazyVStack(spacing: 0) {
                ForEach(jobs) { job in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(job.input.displayName).lineLimit(1)
                            Spacer()
                            StatusBadge(status: job.status)
                        }
                        if case .failed(let message) = job.status {
                            Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        }
                        Divider()
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }
}

private struct StudioStatus: View {
    let store: ConversionStore
    var body: some View {
        HStack(spacing: 12) {
            if store.isConverting {
                ConversionProgressBar(value: store.progress, isRunning: true)
                    .frame(width: 100)
            } else {
                Image(systemName: "circle.dotted").foregroundStyle(.secondary)
            }
            Text(store.statusMessage).lineLimit(1).help(store.statusMessage)
            Spacer()
            if !store.jobs.isEmpty {
                Text(store.progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Button(L10n.text("reveal_output"), systemImage: "folder") { store.revealOutputFolder() }
                .disabled(store.outputURL == nil)
                .labelStyle(.iconOnly)
                .help(L10n.text("reveal_output"))
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .frame(height: StudioLayout.footerHeight)
    }
}

private struct StudioDiagnostics: View {
    let store: ConversionStore
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.text("backend_command")).font(.headline)
                    Spacer()
                    Button(L10n.text("demo_copy"), systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.representativeCommand, forType: .string)
                    }
                    .disabled(store.representativeConversionCommand == nil)
                }
                ScrollView { CommandDisplayView(command: store.representativeConversionCommand, emptyMessage: store.representativeCommand) }
            }
            .padding(14).frame(minWidth: 180, maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("log")).font(.headline)
                ScrollView {
                    Text(store.logText).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14).frame(minWidth: 180, maxWidth: .infinity)
        }
    }
}
