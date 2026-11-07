import AsciiScreenshotKit
import ReplayKit

/// ReplayKit broadcast upload extension: keeps running while the user is in other apps.
/// Frames are downscaled to keep the extension under its ~50 MB memory limit.
final class SampleHandler: RPBroadcastSampleHandler {
    private let sampler = FrameSampler(source: "broadcast", maxDimension: 1600)

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        sampler.start()
    }

    override func broadcastFinished() {
        sampler.stop()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        sampler.submit(pixelBuffer)
    }
}
