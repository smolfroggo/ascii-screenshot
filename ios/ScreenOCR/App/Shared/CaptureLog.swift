import AsciiScreenshotKit
import CoreImage
import CoreVideo
import Foundation

/// Appends one JSON line per processed frame to captures/YYYY-MM-DD.jsonl in the shared App Group
/// container (falls back to the process's Documents directory when the group is unavailable).
final class CaptureLog: @unchecked Sendable {
    static let appGroup = "group.com.smolfroggo.screenocr"

    struct Record: Codable {
        var time: Date
        var source: String
        var frame: AsciiScreenshot.Frame
    }

    static var directory: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(for date: Date = Date()) -> URL {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return directory.appendingPathComponent("\(f.string(from: date)).jsonl")
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    func append(_ record: Record) throws {
        var line = try encoder.encode(record)
        line.append(0x0A)
        let url = Self.fileURL(for: record.time)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    static func lastRecord() -> Record? {
        guard let data = try? Data(contentsOf: fileURL()),
              let last = data.split(separator: 0x0A).last else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(Record.self, from: last)
    }
}

/// Holds the newest screen frame and processes it once per second on a serial queue,
/// whether or not the screen changed. Ticks that arrive while a frame is still processing are counted as dropped.
final class FrameSampler: @unchecked Sendable {
    struct Stats: Sendable {
        var processed = 0
        var dropped = 0
        var lastMs = 0.0
        var lastFrame: AsciiScreenshot.Frame?
        var lastError: String?
    }

    let source: String
    var pipeline: AsciiScreenshot
    var maxDimension: Int?
    var onUpdate: (@Sendable (Stats) -> Void)?

    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var busy = false
    private var stats = Stats()
    private let queue = DispatchQueue(label: "screenocr.process", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let log = CaptureLog()

    init(source: String, pipeline: AsciiScreenshot = AsciiScreenshot(columns: 80, rows: nil), maxDimension: Int? = nil) {
        self.source = source
        self.pipeline = pipeline
        self.maxDimension = maxDimension
    }

    func submit(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        latest = pixelBuffer
        lock.unlock()
    }

    func start(interval: TimeInterval = 1) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        lock.lock()
        latest = nil
        lock.unlock()
    }

    private func tick() {
        lock.lock()
        guard let buffer = latest else { lock.unlock(); return }
        if busy {
            stats.dropped += 1
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()

        queue.async { [self] in
            let start = Date()
            var error: String?
            var frame: AsciiScreenshot.Frame?
            autoreleasepool {
                do {
                    guard var image = RGBAImage(pixelBuffer: buffer, context: ciContext) else { throw CocoaError(.coderInvalidValue) }
                    if let maxDimension { image = image.downscaled(maxDimension: maxDimension) }
                    let f = try pipeline.process(image)
                    try log.append(.init(time: start, source: source, frame: f))
                    frame = f
                } catch let e {
                    error = "\(e)"
                }
            }
            lock.lock()
            busy = false
            if let frame { stats.processed += 1; stats.lastFrame = frame }
            stats.lastError = error
            stats.lastMs = Date().timeIntervalSince(start) * 1000
            let snapshot = stats
            lock.unlock()
            onUpdate?(snapshot)
        }
    }
}
