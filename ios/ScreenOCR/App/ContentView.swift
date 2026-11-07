import AsciiScreenshotKit
import Combine
import PhotosUI
import ReplayKit
import SwiftUI

struct ContentView: View {
    @State private var model = CaptureModel()
    @State private var photo: PhotosPickerItem?
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                Section("Live screen (1 frame/sec)") {
                    if model.captureSupported {
                        Button(model.isCapturing ? "Stop capture" : "Start capture (ScreenCaptureKit)") {
                            model.isCapturing ? model.stopCapture() : model.startCapture()
                        }
                    } else {
                        Text(model.unsupportedReason).font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("ReplayKit broadcast")
                        Spacer()
                        BroadcastButton().frame(width: 44, height: 44)
                    }
                    LabeledContent("Processed", value: "\(model.stats.processed)")
                    LabeledContent("Dropped ticks", value: "\(model.stats.dropped)")
                    LabeledContent("Last frame", value: String(format: "%.0f ms", model.stats.lastMs))
                    if let error = model.stats.lastError { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                Section("Still image") {
                    PhotosPicker("OCR a screenshot…", selection: $photo, matching: .images)
                    Stepper("Columns: \(model.columns)", value: $model.columns, in: 40...200, step: 10)
                }
                Section("Status") {
                    Text(model.status).font(.footnote).accessibilityIdentifier("status")
                    ShareLink("Share today's log", item: CaptureLog.fileURL())
                }
                if let frame = model.stats.lastFrame ?? model.broadcastRecord?.frame ?? model.stillFrame {
                    Section("Latest ASCII (\(frame.width)x\(frame.height), \(frame.ocr.count) text boxes)") {
                        ScrollView([.horizontal, .vertical]) {
                            Text(frame.ascii)
                                .font(.system(size: 7, design: .monospaced))
                                .fixedSize()
                                .textSelection(.enabled)
                                .accessibilityIdentifier("ascii")
                        }
                        .frame(minHeight: 420)
                    }
                }
            }
            .navigationTitle("ScreenOCR")
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await model.process(image: image)
                }
            }
        }
        .onReceive(refresh) { _ in model.refreshBroadcast() }
        .task { await processLaunchArgument() }
    }

    /// `-processImage <path>` runs the pipeline on a file at launch (used for simulator checks).
    private func processLaunchArgument() async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-processImage"), i + 1 < args.count,
              let image = UIImage(contentsOfFile: args[i + 1]) else { return }
        await model.process(image: image)
    }
}

/// System broadcast picker targeting the bundled upload extension (deprecated in iOS 27 but still the
/// background-capable path on iOS 12–26).
struct BroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        view.preferredExtension = "com.smolfroggo.screenocr.broadcast"
        view.showsMicrophoneButton = false
        return view
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
