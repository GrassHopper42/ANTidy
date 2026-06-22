import AppKit
import Foundation

enum FullDiskAccessChecker {
    static func isLikelyGranted() -> Bool {
        let protectedProbeURLs = [
            FileSystemTools.homePath("Library/Safari"),
            FileSystemTools.homePath("Library/Mail"),
            FileSystemTools.homePath("Library/Application Support/com.apple.TCC/TCC.db")
        ]

        for url in protectedProbeURLs {
            if canRead(url) {
                return true
            }
        }
        return false
    }

    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func canRead(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }

        if isDirectory.boolValue {
            return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            try? handle.close()
            return true
        } catch {
            return false
        }
    }
}
