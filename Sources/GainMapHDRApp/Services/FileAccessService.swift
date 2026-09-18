import Foundation
import ImageIO

actor FileAccessService {
    static let supportedExtensions: Set<String> = ["png", "tif", "tiff", "heic", "heif", "jpg", "jpeg", "avif", "jxl", "exr", "hdr"]
    private var scopes = Set<URL>()

    func importFiles(_ urls: [URL]) throws -> [URL] {
        var result: [URL] = []
        var newlyGranted: [URL] = []
        var completed = false
        defer {
            if !completed {
                for url in newlyGranted { url.stopAccessingSecurityScopedResource(); scopes.remove(url) }
            }
        }
        var seen = Set<URL>()
        for url in urls where url.isFileURL {
            try Task.checkCancellation()
            if !scopes.contains(url), url.startAccessingSecurityScopedResource() { scopes.insert(url); newlyGranted.append(url) }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                var scanError: (any Error)?
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in
                        scanError = error
                        return false
                    })
                while let candidate = enumerator?.nextObject() as? URL {
                    try Task.checkCancellation()
                    if Self.supportedExtensions.contains(candidate.pathExtension.lowercased()),
                       (try candidate.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true,
                       seen.insert(candidate.standardizedFileURL).inserted {
                        result.append(candidate.standardizedFileURL)
                    }
                }
                if let scanError { throw scanError }
            } else if values.isRegularFile == true,
                      Self.supportedExtensions.contains(url.pathExtension.lowercased()),
                      seen.insert(url.standardizedFileURL).inserted {
                result.append(url.standardizedFileURL)
            }
        }
        completed = true
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func retainAccess(to url: URL) {
        if !scopes.contains(url), url.startAccessingSecurityScopedResource() { scopes.insert(url) }
    }

    func releaseAccess() {
        scopes.forEach { $0.stopAccessingSecurityScopedResource() }
        scopes.removeAll()
    }

    func validate(input: URL, destination: URL) throws -> Int {
        let scopes = [input, destination.deletingLastPathComponent()].filter { $0.startAccessingSecurityScopedResource() }
        defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        guard fm.fileExists(atPath: input.path) else { throw ConversionFailure(kind: .input, detail: input.path) }
        guard fm.isReadableFile(atPath: input.path) else { throw ConversionFailure(kind: .permission, detail: input.path) }
        guard !fm.fileExists(atPath: destination.path) else {
            throw ConversionFailure(kind: .output, detail: L10n.text("output_exists") + " " + destination.lastPathComponent)
        }
        var isDirectory: ObjCBool = false
        let parent = destination.deletingLastPathComponent()
        guard fm.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ConversionFailure(kind: .output, detail: parent.path)
        }
        guard fm.isWritableFile(atPath: parent.path) else { throw ConversionFailure(kind: .permission, detail: parent.path) }
        guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0,
              width < 1_000_000, height < 1_000_000 else {
            // Core Image can support inputs for which ImageIO has no header reader.
            // The reference CLI remains the authority on decodability; budget conservatively.
            return 100_000_000
        }
        return width * height
    }
}

/// ImageIO only decodes a display-sized image for the selected input, off MainActor.
actor ThumbnailService {
    static let shared = ThumbnailService()
    private struct Entry { let url: URL; let modified: Date?; let image: CGImage }
    private var cache: [Entry] = []

    func image(for url: URL) throws -> CGImage? {
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let index = cache.firstIndex(where: { $0.url == url && $0.modified == modified }) {
            let entry = cache.remove(at: index)
            cache.append(entry)
            return entry.image
        }
        return try autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1200,
                kCGImageSourceShouldCacheImmediately: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            try Task.checkCancellation()
            cache.append(Entry(url: url, modified: modified, image: image))
            if cache.count > 6 { cache.removeFirst(cache.count - 6) }
            return image
        }
    }
}
