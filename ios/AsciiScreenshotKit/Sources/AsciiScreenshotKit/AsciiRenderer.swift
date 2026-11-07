import Foundation

/// Swift port of ascii.js. Keep behaviour identical so output matches the Node CLI.
public enum AsciiRenderer {
    public struct Result: Sendable {
        public var originalText: String
        public var linesText: String
        public var finalText: String
    }

    public static let cursor: Unicode.Scalar = "\u{1F446}"
    private static let space: UInt16 = 0x20
    private static let separators: Set<String> = [".", ",", "\"", "'", ":", ";", "!", "?", "{", "}", "\u{2019}", "\u{201D}"]

    public static func ascii(
        ocr: [Annotation], lines: [Annotation],
        normX: Double? = nil, normY: Double? = nil,
        width: Int = 160, height: Int = 60
    ) -> Result {
        let original = formatText(ocr, width: width, height: height)

        var canvas = Array(original.components(separatedBy: "\n").dropFirst().dropLast())
            .map { Array($0.unicodeScalars) }

        if let normX, let normY, let first = canvas.first {
            let x = min(first.count - 1, jsRound(normX * Double(first.count)))
            let y = min(canvas.count - 1, jsRound(normY * Double(canvas.count)))
            if y >= 0 && y < canvas.count && x >= 0 && x < canvas[y].count {
                canvas[y][x] = cursor
            }
        }

        let border = String(repeating: "_", count: width)
        let page = canvas.map { String(String.UnicodeScalarView($0)) }.joined(separator: "\n")
        let bordered = border + "\n" + page + "\n" + border

        return addLines(
            bordered,
            lines.filter { !isTextEdge($0, ocr) },
            width: width, height: height
        )
    }

    static func formatText(_ ocr: [Annotation], width: Int, height: Int) -> String {
        var clusters: [Int: [Annotation]] = [:]
        for i in 0..<height { clusters[i] = [] }
        for a in ocr {
            clusters[jsFloor((1 - a.origin.y) * Double(height)), default: []].append(a)
        }

        var canvas = Array(repeating: Array(repeating: space, count: width), count: height)
        // JS enumerates the sorted clusters by position, not by key.
        for (i, key) in clusters.keys.sorted().enumerated() {
            guard i < height else { break }
            let line = clusters[key]!.enumerated()
                .sorted { $0.element.origin.x != $1.element.origin.x ? $0.element.origin.x < $1.element.origin.x : $0.offset < $1.offset }
                .map(\.element)

            var lastX = 0
            for annotation in groupWordsInSentence(line) {
                let text = Array(annotation.text.utf16)
                let startX = max(jsFloor(annotation.origin.x * Double(width)), lastX)
                for (j, unit) in text.enumerated() where startX + j < width {
                    canvas[i][startX + j] = unit
                }
                lastX = startX + text.count + 1
            }
        }

        let border = String(repeating: "_", count: width)
        let page = canvas.map { String(decoding: $0, as: UTF16.self) }.joined(separator: "\n")
        return border + "\n" + page + "\n" + border
    }

    static func groupWordsInSentence(_ line: [Annotation]) -> [Annotation] {
        var grouped: [Annotation] = []
        var current: [Annotation] = []
        for annotation in line {
            guard let previous = current.last else {
                current.append(annotation)
                continue
            }
            let characterWidth = (previous.size.width / Double(previous.text.utf16.count)) * 2
            let nextStartX = previous.origin.x + previous.size.width
            if annotation.origin.x <= nextStartX + characterWidth {
                current.append(annotation)
            } else {
                grouped.append(createGroupedAnnotation(current))
                current = [annotation]
            }
        }
        if !current.isEmpty { grouped.append(createGroupedAnnotation(current)) }
        return grouped
    }

    static func createGroupedAnnotation(_ group: [Annotation]) -> Annotation {
        var text = ""
        for (index, word) in group.enumerated() {
            if separators.contains(word.text) {
                text += word.text
            } else {
                text += (index > 0 ? " " : "") + word.text
            }
        }
        let width = group.reduce(0.0) { $0 + $1.size.width }
        return Annotation(text: text, x: group[0].origin.x, y: group[0].origin.y, width: width, height: group[0].size.height)
    }

    static func addLines(_ asciiLines: String, _ lineData: [Annotation], width: Int, height: Int) -> Result {
        var canvas = Array(repeating: Array(repeating: Character(" "), count: width), count: height)

        for line in lineData {
            if line.text == "|" {
                let x = min(jsFloor(line.origin.x * Double(width)), width - 1)
                let startY = max(jsFloor(line.origin.y * Double(height)), 0)
                let endY = min(jsFloor((line.origin.y + line.size.height) * Double(height)), height - 1)
                guard x >= 0, startY <= endY else { continue }
                for y in startY...endY {
                    canvas[y][x] = (canvas[y][x] == "_" || canvas[y][x] == "+") ? "+" : "|"
                }
            } else if line.text == "_" {
                let y = min(jsFloor(line.origin.y * Double(height)), height - 1)
                let startX = max(jsFloor(line.origin.x * Double(width)), 0)
                let endX = min(startX + jsFloor(line.size.width * Double(width)), width - 1)
                guard y >= 0, startX <= endX else { continue }
                for x in startX...endX {
                    canvas[y][x] = (canvas[y][x] == "|" || canvas[y][x] == "+") ? "+" : "_"
                }
            }
        }

        let linesText = canvas.map { String($0) }.joined(separator: "\n")

        let rows = Array(asciiLines.components(separatedBy: "\n").dropFirst().dropLast())
        let finalText = rows.enumerated().map { rowIndex, row -> String in
            var out = ""
            for (colIndex, scalar) in row.unicodeScalars.enumerated() {
                let line: Character = rowIndex < canvas.count && colIndex < width ? canvas[rowIndex][colIndex] : " "
                if scalar == cursor {
                    out.unicodeScalars.append(scalar)
                } else if scalar == " " || line == "|" || line == "+" {
                    out.append(line)
                } else if line == "_" {
                    out.unicodeScalars.append(scalar)
                    out.unicodeScalars.append("\u{0332}")
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
            return out
        }.joined(separator: "\n")

        return Result(originalText: asciiLines, linesText: linesText, finalText: finalText)
    }

    /// Glyph stems/underlines can look like boundaries, but lie inside OCR text boxes.
    static func isTextEdge(_ line: Annotation, _ ocr: [Annotation]) -> Bool {
        let vertical = line.text == "|"
        let pos = vertical ? line.origin.x : line.origin.y
        let start = vertical ? line.origin.y : line.origin.x
        let length = vertical ? line.size.height : line.size.width
        if length == 1 && (pos == 0 || pos == 1) { return false }
        return ocr.contains { box in
            let top = 1 - box.origin.y - box.size.height
            let lo = vertical ? top : box.origin.x
            let hi = lo + (vertical ? box.size.height : box.size.width)
            let side = vertical ? box.origin.x : top
            let sideEnd = side + (vertical ? box.size.width : box.size.height)
            let overlap = max(0, min(start + length, hi) - max(start, lo))
            return pos >= side && pos <= sideEnd && length > 0 && overlap >= 0.8 * length
        }
    }
}
