import Foundation
import CryptoKit
import Darwin

public enum DiagramFiles {
    /// Keep the temporary file beside its destination, including on external volumes.
    /// Foundation's atomic write can use a volume-level temporary directory outside
    /// the caller's permitted workspace. A same-directory rename stays atomic.
    public static func writeData(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: temporary) }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), let permissions = attributes[.posixPermissions] {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
        }
        guard rename(temporary.path, url.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
        }
    }
    public static func revision(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func read(_ url: URL) throws -> (Diagram, String) {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 16 * 1024 * 1024 else { throw DiagramError.message("Diagram exceeds the 16 MB file limit.") }
        let data = try Data(contentsOf: url); return (try Diagram.decode(data), revision(data))
    }
    /// Cooperating writers share an advisory lock; the revision also detects external file edits.
    @discardableResult public static func write(_ document: Diagram, to url: URL, expectedRevision: String? = nil, overwrite: Bool = false) throws -> String {
        let issues = Validator.validate(document); guard issues.isEmpty else { throw DiagramError.invalid(issues) }
        let lockURL = url.appendingPathExtension("lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw DiagramError.message("Cannot acquire the document write lock.") }
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw DiagramError.message("Cannot lock the document.") }
        let exists = FileManager.default.fileExists(atPath: url.path)
        if let expectedRevision {
            guard exists else { throw DiagramError.message("The file was removed outside this editor. Save a copy before writing.") }
            guard revision(try Data(contentsOf: url)) == expectedRevision else { throw DiagramError.message("The file changed outside this editor. Reload or save a copy before writing.") }
        } else if exists && !overwrite { throw DiagramError.message("File already exists. Supply its expected SHA-256 revision or explicitly allow overwrite.") }
        let data = try document.encoded()
        guard data.count <= 16 * 1024 * 1024 else { throw DiagramError.message("Document exceeds the 16 MB file limit. Reduce its content before saving.") }
        try writeData(data, to: url); return revision(data)
    }
}
