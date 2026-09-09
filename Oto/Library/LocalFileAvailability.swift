import Darwin
import Foundation

/// Check metadata before coordinating a content read, which can otherwise hydrate
/// an iCloud placeholder. A fresh URL avoids cached download-status values.
enum LocalFileAvailability {
    static func requireDownloaded(at url: URL) throws {
        let freshURL = URL(fileURLWithPath: url.path)
        let values = try freshURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        var info = stat()
        let result = freshURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return lstat(path, &info)
        }
        guard result == 0 else { throw CocoaError(.fileReadNoSuchFile) }
        try requireDownloaded(isUbiquitous: values.isUbiquitousItem == true,
                              status: values.ubiquitousItemDownloadingStatus,
                              isDataless: info.st_flags & UInt32(SF_DATALESS) != 0)
    }

    static func requireDownloaded(isUbiquitous: Bool, status: URLUbiquitousItemDownloadingStatus?, isDataless: Bool) throws {
        // Require the complete current iCloud version: a stale local copy can
        // cause the coordinator to fetch a newer version before granting access.
        guard !isDataless, !isUbiquitous || status == .current else {
            throw LibraryError.fileNotDownloaded
        }
    }
}
