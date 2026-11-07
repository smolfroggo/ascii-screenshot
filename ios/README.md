# ascii-screenshot on iOS

Swift port of the macOS pipeline (`ocr.scpt` + `detect_lines.js` + `ascii.js`) plus an iOS app that
captures the screen once per second, OCRs it with Apple Vision on-device, and appends each frame to a JSONL log.
No jailbreak needed; the user starts capture from the system picker.

```
ios/
  AsciiScreenshotKit/   Swift package: TextRecognizer (Vision), LineDetector, AsciiRenderer, AsciiScreenshot
  ScreenOCR/            iOS app (XcodeGen project.yml) + ReplayKit broadcast upload extension
```

## How capture works

| Path | iOS | Runs while in other apps | Notes |
| --- | --- | --- | --- |
| ScreenCaptureKit: `SCContentSharingPicker` → `SCStream` | 27+ | system decides | New in iOS 27. Pick **Entire Screen**. |
| ReplayKit broadcast extension (`RPBroadcastSampleHandler`) | 12+ | yes | Deprecated in iOS 27 but still works. Long-press the record button → ScreenOCR. ~50 MB memory cap, so frames are downscaled to 1600 px. |

iOS doesn't have `SCStreamConfiguration.minimumFrameInterval`, so `FrameSampler` keeps the newest
pixel buffer and processes it from a 1 s timer, including frames where the screen didn't change. If a frame is
still processing when the next tick fires, the tick is counted as dropped.

Each processed frame becomes one line in `captures/YYYY-MM-DD.jsonl` in the App Group container
(`group.com.smolfroggo.screenocr`), with the same `ocr` / `lines` annotation shape as the Node CLI, plus
`ascii`, `width`, `height`, `ocrMs`, `linesMs`. The app's share button exports today's log.

## Build

Requires Xcode 27 for the ScreenCaptureKit path. Older SDKs still build; they only get the broadcast path.

```sh
brew install xcodegen
cd ios/ScreenOCR && xcodegen generate && open ScreenOCR.xcodeproj
```

Set your team on both targets (the app group must be enabled for your team), then run on an iOS 27 device. The
iOS Simulator SDK doesn't include ScreenCaptureKit and the simulator can't broadcast, so live capture only works
on a device. In the simulator you can still OCR a still image with "OCR a screenshot…" or
`-processImage /path/to.png` as a launch argument.

The Run scheme uses Release: the line detector is far slower in unoptimized Debug builds.

## Swift package / CLI

```sh
cd ios/AsciiScreenshotKit
swift test                                   # parity tests against Node-generated fixtures
swift run -c release asciiscreenshot shot.png --width 160 --height 60 --timing
swift run -c release asciiscreenshot shot.png --ocr-json o.json --lines-json l.json   # render precomputed JSON
```

On the fixtures in `Tests/AsciiScreenshotKitTests/Fixtures`, OCR, line JSON, and rendered ASCII are identical
to the Node CLI output.
