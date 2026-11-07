import CoreGraphics
import Foundation
import Vision

/// Full pipeline: OCR + boundary detection + ASCII rendering for one frame.
public struct AsciiScreenshot: Sendable {
    public struct Frame: Codable, Sendable {
        public var width: Int
        public var height: Int
        public var ocr: [Annotation]
        public var lines: [Annotation]
        public var ascii: String
        public var ocrMs: Double
        public var linesMs: Double
    }

    public var columns: Int
    /// Rows; nil picks rows from the image aspect ratio assuming 1:2 character cells.
    public var rows: Int?
    public var recognitionLevel: VNRequestTextRecognitionLevel

    public init(columns: Int = 160, rows: Int? = 60, recognitionLevel: VNRequestTextRecognitionLevel = .accurate) {
        self.columns = columns
        self.rows = rows
        self.recognitionLevel = recognitionLevel
    }

    public func gridRows(forWidth width: Int, height: Int) -> Int {
        rows ?? max(1, Int((Double(columns) * Double(height) / Double(width) / 2).rounded()))
    }

    public func process(_ image: RGBAImage, normX: Double? = nil, normY: Double? = nil) throws -> Frame {
        guard let cg = image.cgImage() else { throw CocoaError(.coderInvalidValue) }
        let t0 = Date()
        let ocr = try TextRecognizer.recognize(cg, level: recognitionLevel)
        let t1 = Date()
        let lines = LineDetector.detect(image)
        let t2 = Date()
        let rows = gridRows(forWidth: image.width, height: image.height)
        let text = AsciiRenderer.ascii(ocr: ocr, lines: lines, normX: normX, normY: normY, width: columns, height: rows).finalText
        return Frame(
            width: image.width, height: image.height, ocr: ocr, lines: lines, ascii: text,
            ocrMs: t1.timeIntervalSince(t0) * 1000, linesMs: t2.timeIntervalSince(t1) * 1000
        )
    }
}
