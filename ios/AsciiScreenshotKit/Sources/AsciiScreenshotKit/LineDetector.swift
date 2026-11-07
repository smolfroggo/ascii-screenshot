import Foundation

/// Swift port of detect_lines.js; keep constants and logic in sync.
public enum LineDetector {
    static let edgeThreshold = 4
    static let strongEdgeThreshold = 10
    static let minLineFrac = 0.025
    static let edgeTolFrac = 0.004
    static let flatTol = 0.0
    static let flatPixFrac = 0.9
    static let flatChunk = 4
    static let flatMinFrac = 0.5

    struct Edge { var first: Int; var last: Int; var start: Int; var end: Int }

    public static func detect(_ image: RGBAImage) -> [Annotation] {
        let w = image.width, h = image.height
        let tol = max(2, jsRound(Double(h) * edgeTolFrac))

        return image.withPixels { px in
            func diff(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) -> Int {
                let i = (y1 * w + x1) * 4, j = (y2 * w + x2) * 4
                return max(abs(Int(px[i]) - Int(px[j])), abs(Int(px[i + 1]) - Int(px[j + 1])), abs(Int(px[i + 2]) - Int(px[j + 2])))
            }

            // Horizontal edges: row r sits between pixel rows r and r + 1.
            let horizontal = mergeRuns(
                runs(rows: h - 1, cols: w, minLen: jsRound(Double(w) * minLineFrac)) { r, c in diff(c, r + 1, c, r) >= edgeThreshold },
                tol: tol
            ).filter { hasFlatSide(rows: h, edge: $0, offset: tol) { r, i, c in Int(px[(r * w + i) * 4 + c]) } }

            // Vertical edges: row r sits between pixel columns r and r + 1.
            let vertical = mergeRuns(
                runs(rows: w - 1, cols: h, minLen: jsRound(Double(h) * minLineFrac)) { r, c in diff(r + 1, c, r, c) >= edgeThreshold },
                tol: tol
            ).filter { hasFlatSide(rows: w, edge: $0, offset: tol) { r, i, c in Int(px[(i * w + r) * 4 + c]) } }

            let W = Double(w), H = Double(h)
            return vertical.map { e in
                Annotation(text: "|", x: Double(e.first + e.last) / 2 / W, y: Double(e.start) / H, width: 0, height: Double(e.end - e.start) / H)
            } + horizontal.map { e in
                Annotation(text: "_", x: Double(e.start) / W, y: Double(e.first + e.last) / 2 / H, width: Double(e.end - e.start) / W, height: 0)
            } + [
                Annotation(text: "|", x: 0, y: 0, width: 0, height: 1),
                Annotation(text: "|", x: 1, y: 0, width: 0, height: 1),
                Annotation(text: "_", x: 0, y: 0, width: 1, height: 0),
                Annotation(text: "_", x: 0, y: 1, width: 1, height: 0),
            ]
        }
    }

    /// (row, start, end) for each run of isEdge(row, col) along each row with length >= minLen.
    static func runs(rows: Int, cols: Int, minLen: Int, isEdge: (Int, Int) -> Bool) -> [(Int, Int, Int)] {
        var out: [(Int, Int, Int)] = []
        guard rows > 0 else { return out }
        for r in 0..<rows {
            var start = -1
            for c in 0...cols {
                if c < cols && isEdge(r, c) {
                    if start < 0 { start = c }
                } else if start >= 0 {
                    if c - start >= minLen { out.append((r, start, c)) }
                    start = -1
                }
            }
        }
        return out
    }

    /// Merge runs within tol rows of each other whose spans overlap or nearly touch.
    static func mergeRuns(_ runList: [(Int, Int, Int)], tol: Int) -> [Edge] {
        let sorted = runList.sorted { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }
        var edges: [Edge] = []
        for (row, a, b) in sorted {
            var target: Int?
            var i = edges.count - 1
            while i >= 0 {
                let e = edges[i]
                if row - e.first > tol { break }
                if a <= e.end + tol && b >= e.start - tol {
                    target = i
                    break
                }
                i -= 1
            }
            if let t = target {
                edges[t].last = row
                edges[t].start = min(edges[t].start, a)
                edges[t].end = max(edges[t].end, b)
            } else {
                edges.append(Edge(first: row, last: row, start: a, end: b))
            }
        }
        return edges
    }

    /// True if, along most of the edge, the strip just before or after it is a solid colour.
    static func hasFlatSide(rows: Int, edge: Edge, offset: Int, get: (Int, Int, Int) -> Int) -> Bool {
        let (p0, p1, a, b) = (edge.first, edge.last, edge.start, edge.end)
        let before = p0 - offset + 1, after = p1 + offset
        if before >= 0 && after < rows {
            var contrast = 0
            for i in a..<b {
                var across = 0, strong = 0
                for c in 0..<3 {
                    across = max(across, abs(get(before, i, c) - get(after, i, c)))
                    for r in p0...p1 {
                        strong = max(strong, abs(get(r + 1, i, c) - get(r, i, c)))
                    }
                }
                if across >= edgeThreshold || strong >= strongEdgeThreshold { contrast += 1 }
            }
            // Reject faint narrow stripes whose two surrounding regions are the same.
            if Double(contrast) / Double(b - a) < flatMinFrac { return false }
        }

        let n = b - a
        let nChunks = max(1, n / (offset * flatChunk))
        var flat = Array(repeating: false, count: nChunks)
        var vals: [Int] = []
        for r in [p0 - offset + 1, p1 + offset] where r >= 0 && r < rows {
            for k in 0..<nChunks {
                let lo = a + k * n / nChunks, hi = a + (k + 1) * n / nChunks
                guard hi > lo else { continue }
                var near = Array(repeating: true, count: hi - lo)
                for c in 0..<3 {
                    vals.removeAll(keepingCapacity: true)
                    for i in lo..<hi { vals.append(get(r, i, c)) }
                    let sorted = vals.sorted()
                    let m = sorted.count
                    let median = m % 2 == 1 ? Double(sorted[(m - 1) / 2]) : Double(sorted[m / 2 - 1] + sorted[m / 2]) / 2
                    for (i, v) in vals.enumerated() where abs(Double(v) - median) > flatTol { near[i] = false }
                }
                if Double(near.lazy.filter { $0 }.count) / Double(hi - lo) >= flatPixFrac { flat[k] = true }
            }
        }
        return Double(flat.lazy.filter { $0 }.count) / Double(nChunks) >= flatMinFrac
    }
}
