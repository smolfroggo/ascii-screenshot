import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

/// 8-bit RGBA pixels, row-major with no padding (same layout as Jimp's bitmap).
public struct RGBAImage: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public private(set) var data: [UInt8]

    public init(width: Int, height: Int, data: [UInt8]) {
        precondition(data.count == width * height * 4)
        self.width = width
        self.height = height
        self.data = data
    }

    /// Decodes without colour conversion when the image is already RGB, so pixel values match Jimp.
    public init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        let space = cgImage.colorSpace?.model == .rgb ? cgImage.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.init(width: w, height: h, data: data)
    }

    public init?(contentsOf url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        self.init(cgImage: image)
    }

    /// Copies a BGRA pixel buffer; other formats (e.g. YUV video frames) go through Core Image.
    public init?(pixelBuffer: CVPixelBuffer, context: CIContext) {
        let w = CVPixelBufferGetWidth(pixelBuffer), h = CVPixelBufferGetHeight(pixelBuffer)
        if CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
            let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            var data = [UInt8](repeating: 0, count: w * h * 4)
            for y in 0..<h {
                let row = base + y * stride
                for x in 0..<w {
                    let s = x * 4, d = (y * w + x) * 4
                    data[d] = row[s + 2]
                    data[d + 1] = row[s + 1]
                    data[d + 2] = row[s]
                    data[d + 3] = row[s + 3]
                }
            }
            self.init(width: w, height: h, data: data)
        } else {
            var data = [UInt8](repeating: 0, count: w * h * 4)
            data.withUnsafeMutableBytes { buf in
                context.render(
                    CIImage(cvPixelBuffer: pixelBuffer), toBitmap: buf.baseAddress!, rowBytes: w * 4,
                    bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
                )
            }
            self.init(width: w, height: h, data: data)
        }
    }

    /// Area-averaged downscale so the longest side is at most `maxDimension`.
    public func downscaled(maxDimension: Int) -> RGBAImage {
        let longest = max(width, height)
        guard longest > maxDimension, let image = cgImage() else { return self }
        let scale = Double(maxDimension) / Double(longest)
        let w = max(1, Int((Double(width) * scale).rounded())), h = max(1, Int((Double(height) * scale).rounded()))
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return RGBAImage(width: w, height: h, data: data)
    }

    public func cgImage() -> CGImage? {
        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    func withPixels<T>(_ body: (UnsafeBufferPointer<UInt8>) -> T) -> T {
        data.withUnsafeBufferPointer(body)
    }
}
