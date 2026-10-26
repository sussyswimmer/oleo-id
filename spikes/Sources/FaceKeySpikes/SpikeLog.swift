import Foundation

/// Minimal logger shared by the spikes.
///
/// Writes timestamped lines to stdout and appends them to
/// `~/Library/Logs/FaceKeySpikes/<spike>-<yyyy-MM-dd>.log`, so evidence survives
/// even when the spike is launched as a background `.app` with no attached console
/// (for example on `screensDidWakeNotification`).
///
/// Security rule 1/2: this logger only ever records counts, timings and scalar
/// statistics. It must never be handed a password, a raw embedding, or image
/// bytes. The spikes don't produce the first two at all, and camera frames are
/// summarised to numbers before anything reaches here.
final class SpikeLog: @unchecked Sendable {
    private let handle: FileHandle?
    private let url: URL?
    private let queue = DispatchQueue(label: "dev.facekey.spikes.log")
    private let formatter: DateFormatter

    /// - Parameter spike: short tag used in the log filename, e.g. "camera" or "model".
    init(spike: String) {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.formatter = fmt

        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/FaceKeySpikes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(spike)-\(day.string(from: Date())).log")
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        self.url = file
        self.handle = try? FileHandle(forWritingTo: file)
        try? self.handle?.seekToEnd()
    }

    func log(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)"
        queue.sync {
            print(line)
            if let data = (line + "\n").data(using: .utf8) {
                self.handle?.write(data)
            }
        }
    }

    /// Absolute path of the log file, printed once at startup so the owner can find it.
    var path: String { url?.path ?? "(no file)" }

    deinit { try? handle?.close() }
}
