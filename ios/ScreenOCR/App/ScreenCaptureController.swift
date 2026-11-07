#if canImport(ScreenCaptureKit)
import CoreMedia
import ScreenCaptureKit

/// iOS 27 system-wide capture: Control Center's content picker -> SCStream -> FrameSampler (1 fps).
@available(iOS 27.0, *)
final class ScreenCaptureController: NSObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let sampler: FrameSampler
    var onState: (@Sendable (String) -> Void)?
    private var stream: SCStream?
    private let frameQueue = DispatchQueue(label: "screenocr.frames")

    init(sampler: FrameSampler) {
        self.sampler = sampler
        super.init()
    }

    var isAvailable: Bool { SCContentSharingPicker.shared.isAvailable }

    func start() {
        let picker = SCContentSharingPicker.shared
        picker.add(self)
        picker.isActive = true
        picker.present(using: .display)
    }

    func stop() {
        let s = stream
        stream = nil
        sampler.stop()
        Task { try? await s?.stopCapture() }
        SCContentSharingPicker.shared.isActive = false
        onState?("stopped")
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        onState?("picker cancelled")
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        onState?("picker failed: \(error.localizedDescription)")
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
        } catch {
            onState?("addStreamOutput failed: \(error.localizedDescription)")
            return
        }
        self.stream = s
        Task {
            do {
                try await s.startCapture()
                sampler.start()
                onState?("capturing \(config.width)x\(config.height)")
            } catch {
                onState?("startCapture failed: \(error.localizedDescription)")
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        if let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
           let raw = info[.status] as? Int, let status = SCFrameStatus(rawValue: raw),
           status != .complete && status != .started {
            return
        }
        sampler.submit(pixelBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        sampler.stop()
        onState?("stream stopped: \(error.localizedDescription)")
    }
}
#endif
