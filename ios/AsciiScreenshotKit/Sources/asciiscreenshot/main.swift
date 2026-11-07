import AsciiScreenshotKit
import Foundation

// Usage: asciiscreenshot <image> [--width N] [--height N] [--px F --py F]
//        [--ocr-json in.json] [--lines-json in.json] [--dump-ocr out.json] [--dump-lines out.json] [--timing]
var args = Array(CommandLine.arguments.dropFirst())
var flags: [String: String] = [:]
var positional: [String] = []
while !args.isEmpty {
    let a = args.removeFirst()
    if a.hasPrefix("--") {
        if let next = args.first, !next.hasPrefix("--") { flags[String(a.dropFirst(2))] = args.removeFirst() } else { flags[String(a.dropFirst(2))] = "" }
    } else {
        positional.append(a)
    }
}
guard let path = positional.first else {
    FileHandle.standardError.write("usage: asciiscreenshot <image> [--width N] [--height N]\n".data(using: .utf8)!)
    exit(1)
}

func load(_ p: String) throws -> [Annotation] {
    try JSONDecoder().decode([Annotation].self, from: Data(contentsOf: URL(fileURLWithPath: p)))
}
func dump(_ v: [Annotation], _ p: String) throws {
    try JSONEncoder().encode(v).write(to: URL(fileURLWithPath: p))
}

let width = Int(flags["width"] ?? "") ?? 160
let height = Int(flags["height"] ?? "") ?? 60
let px = flags["px"].flatMap(Double.init), py = flags["py"].flatMap(Double.init)

do {
    guard let image = RGBAImage(contentsOf: URL(fileURLWithPath: path)) else { throw CocoaError(.fileReadCorruptFile) }
    let t0 = Date()
    let ocr = try flags["ocr-json"].map(load) ?? TextRecognizer.recognize(image.cgImage()!)
    let t1 = Date()
    let lines = try flags["lines-json"].map(load) ?? LineDetector.detect(image)
    let t2 = Date()
    if let p = flags["dump-ocr"] { try dump(ocr, p) }
    if let p = flags["dump-lines"] { try dump(lines, p) }
    print(AsciiRenderer.ascii(ocr: ocr, lines: lines, normX: px, normY: py, width: width, height: height).finalText)
    if flags["timing"] != nil {
        FileHandle.standardError.write(String(format: "ocr %.0f ms, lines %.0f ms\n", t1.timeIntervalSince(t0) * 1000, t2.timeIntervalSince(t1) * 1000).data(using: .utf8)!)
    }
} catch {
    FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
