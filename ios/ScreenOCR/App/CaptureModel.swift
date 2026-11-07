import AsciiScreenshotKit
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CaptureModel {
    var status = "idle"
    var stats = FrameSampler.Stats()
    var stillFrame: AsciiScreenshot.Frame?
    var broadcastRecord: CaptureLog.Record?
    var isCapturing = false
    var columns = 80

    private let sampler = FrameSampler(source: "screencapturekit")
    private var controller: AnyObject?

    var captureSupported: Bool {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) { return true }
        #endif
        return false
    }

    var unsupportedReason: String {
        #if targetEnvironment(simulator)
        "ScreenCaptureKit isn't in the iOS Simulator SDK; run on an iOS 27 device."
        #else
        "System-wide capture needs iOS 27 (ScreenCaptureKit). On older iOS use the broadcast button."
        #endif
    }

    init() {
        sampler.onUpdate = { [weak self] stats in
            Task { @MainActor in self?.stats = stats }
        }
    }

    func startCapture() {
        sampler.pipeline = AsciiScreenshot(columns: columns, rows: nil)
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            let c = (controller as? ScreenCaptureController) ?? ScreenCaptureController(sampler: sampler)
            c.onState = { [weak self] state in
                Task { @MainActor in
                    self?.status = state
                    self?.isCapturing = state.hasPrefix("capturing")
                }
            }
            controller = c
            status = "choose Entire Screen in the picker"
            c.start()
            return
        }
        #endif
        status = unsupportedReason
    }

    func stopCapture() {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *), let c = controller as? ScreenCaptureController { c.stop() }
        #endif
        isCapturing = false
    }

    func process(image: UIImage) async {
        guard let cg = image.cgImage, let rgba = RGBAImage(cgImage: cg) else {
            status = "could not decode image"
            return
        }
        status = "processing image…"
        let pipeline = AsciiScreenshot(columns: columns, rows: nil)
        do {
            let frame = try await Task.detached(priority: .userInitiated) { try pipeline.process(rgba) }.value
            try CaptureLog().append(.init(time: Date(), source: "image", frame: frame))
            stillFrame = frame
            status = String(format: "image: OCR %.0f ms, lines %.0f ms", frame.ocrMs, frame.linesMs)
        } catch {
            status = "failed: \(error)"
        }
    }

    func refreshBroadcast() {
        broadcastRecord = CaptureLog.lastRecord().flatMap { $0.source == "broadcast" ? $0 : nil }
    }
}
