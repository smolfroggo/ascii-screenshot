import Foundation
import Vision

let fast = CommandLine.arguments.contains("--fast")
setvbuf(stdout, nil, _IOLBF, 0)
let request = VNRecognizeTextRequest()
request.recognitionLevel = fast ? .fast : .accurate
request.recognitionLanguages = ["en-US"]

func recognize(_ path: String) -> Any {
    let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path), options: [:])
    do {
        try handler.perform([request])
    } catch {
        return ["error": error.localizedDescription]
    }
    return (request.results ?? []).compactMap { observation -> [String: Any]? in
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        let box = observation.boundingBox
        return ["text": text,
                "origin": ["x": box.origin.x, "y": box.origin.y],
                "size": ["width": box.size.width, "height": box.size.height]]
    }
}

while let path = readLine() {
    autoreleasepool {
        let result = recognize(path)
        if let data = try? JSONSerialization.data(withJSONObject: result),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        } else {
            print("{\"error\":\"Cannot encode OCR result\"}")
        }
    }
}
