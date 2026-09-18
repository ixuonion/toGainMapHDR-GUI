import Foundation
import Darwin

/// Publish within the destination filesystem without exposing a partially encoded file.
enum OutputPublisher {
    static func publish(_ source: URL, to destination: URL) throws {
        // Native exclusive rename also works on volumes that do not support hard links.
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                renamex_np(sourcePath!, destinationPath!, UInt32(RENAME_EXCL))
            }
        }
        guard result != 0 else { return }
        let code = errno
        if code == ENOTSUP {
            // Some filesystems implement hard links but not exclusive rename.
            try FileManager.default.linkItem(at: source, to: destination)
            return
        }
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
