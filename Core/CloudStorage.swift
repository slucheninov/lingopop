import Foundation
import os

enum CloudStorage {

    private static let log = Logger(subsystem: "com.lingopop.app", category: "Cloud")

    static var rootURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudRoot = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: cloudRoot.path) else { return nil }
        let folder = cloudRoot.appendingPathComponent("LingoPop", isDirectory: true)
        return folder
    }

    static var isAvailable: Bool {
        rootURL != nil
    }

    static func ensureFolder() throws {
        guard let url = rootURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func fileURL(_ name: String) -> URL? {
        rootURL?.appendingPathComponent(name)
    }

    static func read(_ name: String) -> (data: Data, modified: Date)? {
        guard let url = fileURL(name), FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let modified = (attrs[.modificationDate] as? Date) ?? Date()
            return (data, modified)
        } catch {
            log.error("Cloud read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    static func write(_ name: String, data: Data) -> Date? {
        guard let url = fileURL(name) else { return nil }
        do {
            try ensureFolder()
            try data.write(to: url, options: .atomic)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs[.modificationDate] as? Date) ?? Date()
        } catch {
            log.error("Cloud write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func modificationDate(_ name: String) -> Date? {
        guard let url = fileURL(name), FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }
}
