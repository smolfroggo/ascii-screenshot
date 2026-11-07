import XCTest
@testable import AsciiScreenshotKit

/// Fixtures were produced by the Node CLI (ocr.scpt + detect_lines.js + ascii.js).
final class ParityTests: XCTestCase {
    let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    let names = ["sim", "apple"]

    func load(_ file: String) throws -> [Annotation] {
        try JSONDecoder().decode([Annotation].self, from: Data(contentsOf: dir.appendingPathComponent(file)))
    }

    func image(_ name: String) throws -> RGBAImage {
        try XCTUnwrap(RGBAImage(contentsOf: dir.appendingPathComponent("\(name).png")))
    }

    func testRendererMatchesJS() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".txt") }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let stem = file.dropLast(".txt".count)
            let name = String(stem.prefix { $0 != "." })
            let dims = stem.dropFirst(name.count + 1).split(separator: "x").map { Double($0)! }
            let expected = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            let result = AsciiRenderer.ascii(
                ocr: try load("\(name).ocr.json"), lines: try load("\(name).lines.json"),
                normX: dims.count > 2 ? dims[2] : nil, normY: dims.count > 3 ? dims[3] : nil,
                width: Int(dims[0]), height: Int(dims[1])
            )
            XCTAssertEqual(result.finalText, expected, file)
        }
    }

    func testLineDetectorMatchesJS() throws {
        for name in names {
            XCTAssertEqual(LineDetector.detect(try image(name)), try load("\(name).lines.json"), name)
        }
    }

    func testOCRMatchesAppleVisionScript() throws {
        for name in names {
            let ocr = try TextRecognizer.recognize(try XCTUnwrap(try image(name).cgImage()))
            let expected = try load("\(name).ocr.json")
            #if os(macOS)
            XCTAssertEqual(ocr, expected, name)
            #else
            // iOS (esp. the Simulator's CPU-only Vision) returns slightly different boxes and ordering.
            let found = expected.filter { e in
                ocr.contains { $0.text == e.text && abs($0.origin.x - e.origin.x) < 0.02 && abs($0.origin.y - e.origin.y) < 0.02 }
            }
            XCTAssertLessThanOrEqual(expected.count - found.count, max(1, expected.count / 7), name)
            #endif
        }
    }

    func testAutoRowsFollowAspectRatio() {
        XCTAssertEqual(AsciiScreenshot(columns: 80, rows: nil).gridRows(forWidth: 1206, height: 2622), 87)
        XCTAssertEqual(AsciiScreenshot(columns: 160, rows: nil).gridRows(forWidth: 1600, height: 1000), 50)
    }
}
