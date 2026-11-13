import Foundation

/// Appends diagnostics to ~/Library/Logs/Mercury.log (NSLog output is
/// redacted in the unified log, so this is the readable place for it).
enum DebugLog {
    static func write(_ message: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Mercury.log")
        let line = "\(Date()) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
