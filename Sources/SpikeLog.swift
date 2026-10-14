import Foundation

/// Timestamped log that is mirrored to `Documents/spike-log.txt` and flushed on every line,
/// so it survives the app being killed in the background.
@MainActor
final class SpikeLog: ObservableObject {
    static let shared = SpikeLog()

    @Published private(set) var lines: [String] = []
    let fileURL: URL

    private var handle: FileHandle?
    private let formatter: DateFormatter

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = docs.appendingPathComponent("spike-log.txt")
        self.formatter = DateFormatter()
        self.formatter.dateFormat = "HH:mm:ss.SSS"

        if !FileManager.default.fileExists(atPath: self.fileURL.path) {
            FileManager.default.createFile(atPath: self.fileURL.path, contents: nil)
        }
        self.handle = try? FileHandle(forWritingTo: self.fileURL)
        _ = try? self.handle?.seekToEnd()
        self.write("---- launch \(Date()) ----")
    }

    func log(_ category: String, _ message: String) {
        let line = "\(self.formatter.string(from: Date())) [\(category)] \(message)"
        self.lines.append(line)
        if self.lines.count > 400 {
            self.lines.removeFirst(self.lines.count - 400)
        }
        self.write(line)
    }

    func clear() {
        self.lines.removeAll()
        try? self.handle?.truncate(atOffset: 0)
        _ = try? self.handle?.seek(toOffset: 0)
    }

    private func write(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        try? self.handle?.write(contentsOf: data)
        try? self.handle?.synchronize()
    }
}

/// UserDefaults-backed flags. The `@AppStorage` toggles in the UI use the same keys.
enum SpikeSettings {
    static var desktopUserAgent: Bool { bool("desktopUA", default: true) }
    static var spoofVisibility: Bool { bool("spoofVisibility", default: false) }
    static var autoConfirm: Bool { bool("autoConfirm", default: true) }
    static var resumeOnBackground: Bool { bool("resumeOnBackground", default: false) }
    /// Silent Web Audio output inside the page, to keep the WebContent process alive while paused.
    static var keepAlive: Bool { bool("keepAlive", default: false) }
    /// Native play/pause lock-screen commands that drive the page through evaluateJavaScript.
    static var nativeTransport: Bool { bool("nativeTransport", default: false) }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}
