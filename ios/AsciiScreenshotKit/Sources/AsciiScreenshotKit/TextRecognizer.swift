import CoreGraphics
import Foundation
import Vision

/// Apple Vision OCR, matching ocr.scpt (VNRecognizeTextRequest, en-US, default accurate level).
public enum TextRecognizer {
    public static func recognize(
        _ image: CGImage,
        level: VNRequestTextRecognitionLevel = .accurate
    ) throws -> [Annotation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        request.recognitionLevel = level
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).map { observation in
            let box = observation.boundingBox
            return Annotation(
                text: observation.topCandidates(1).first?.string ?? "",
                x: Double(box.origin.x), y: Double(box.origin.y),
                width: Double(box.size.width), height: Double(box.size.height)
            )
        }
    }
}
