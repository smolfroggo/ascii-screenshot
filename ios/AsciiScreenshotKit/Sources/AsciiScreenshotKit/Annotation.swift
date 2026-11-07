import Foundation

/// OCR fragment or detected line, in normalized 0-1 coordinates.
/// OCR boxes use Vision's bottom-left origin; lines use a top-left origin (same as the JS tool).
public struct Annotation: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public struct Size: Codable, Equatable, Sendable {
        public var width: Double
        public var height: Double
        public init(width: Double, height: Double) { self.width = width; self.height = height }
    }

    public var text: String
    public var origin: Point
    public var size: Size

    public init(text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        self.origin = Point(x: x, y: y)
        self.size = Size(width: width, height: height)
    }
}

/// JavaScript `Math.round` / `Math.floor(x + 0.5)`.
@inline(__always) func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }
@inline(__always) func jsFloor(_ x: Double) -> Int { Int(x.rounded(.down)) }
