#!/usr/bin/env python3
"""CLI wrapper for the Python ascii-screenshot port."""

import argparse
from concurrent.futures import ProcessPoolExecutor
from datetime import datetime, timezone
import json
import math
import multiprocessing
import os
import signal
import subprocess
import sys
import tempfile
import time

from ascii_screenshot import (
    AppleVisionBackend, RapidOCRBackend, ascii, detect_lines,
)

_worker_backend = None


def _recognize_apple(image, fast):
    global _worker_backend
    if _worker_backend is None:
        _worker_backend = AppleVisionBackend(fast=fast)
    return _worker_backend.run(image)


class ResidentAppleVision:
    """Keep Vision warm while bounding native memory growth between frames."""

    def __init__(self, fast=False, max_frames=512):
        if not isinstance(max_frames, int) or max_frames < 1:
            raise ValueError("max_frames must be a positive integer")
        self.fast = fast
        self.max_frames = max_frames
        self._pool = None
        self._frames = 0

    def run(self, image):
        if self._frames >= self.max_frames:
            self.close()
        if self._pool is None:
            self._pool = ProcessPoolExecutor(max_workers=1, mp_context=multiprocessing.get_context("spawn"))
        result = self._pool.submit(_recognize_apple, image, self.fast).result()
        self._frames += 1
        return result

    def close(self):
        if self._pool is not None:
            self._pool.shutdown(wait=True)
            self._pool = None
        self._frames = 0


def render(image, backend, args):
    import cv2

    ocr_data = backend.run(image)
    if ocr_data is None:
        raise RuntimeError("OCR failed")
    img = cv2.imread(image)
    if img is None:
        raise RuntimeError("Cannot read image")
    height, width = img.shape[:2]
    canvas_height = args.height
    if canvas_height is None:
        canvas_height = min(100, max(1, math.floor(args.width * height / width * 0.5)))
    line_data = detect_lines(image, width, height)
    return ascii(ocr_data, line_data, args.px, args.py, args.width, canvas_height)["finalText"]


def main():
    parser = argparse.ArgumentParser(description="ascii-screenshot (Python port)")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("image", nargs="?", help="Path to image file")
    source.add_argument("--stream", action="store_true", help="Read image paths from stdin; output JSON lines")
    source.add_argument("--capture-every", type=float, metavar="SECONDS",
                        help="Capture and process the entire screen every SECONDS")
    parser.add_argument("--px", type=float, default=None, help="Normalized X coordinate (0-1) for pointer")
    parser.add_argument("--py", type=float, default=None, help="Normalized Y coordinate (0-1) for pointer")
    parser.add_argument("--width", type=int, default=160, help="Canvas width (default: 160)")
    parser.add_argument("--height", type=int, default=None, help="Canvas height (default: auto)")
    parser.add_argument("--ocr", choices=["rapidocr", "apple"],
                        default="apple" if sys.platform == "darwin" else "rapidocr",
                        help="OCR backend (default: apple on macOS, rapidocr elsewhere)")
    parser.add_argument("--fast", action="store_true", help="Lower-CPU Vision mode (less accurate on small text)")
    args = parser.parse_args()
    if args.fast and args.ocr != "apple":
        parser.error("--fast requires --ocr apple")
    if args.capture_every is not None and (not math.isfinite(args.capture_every) or
                                           args.capture_every <= 0 or sys.platform != "darwin"):
        parser.error("--capture-every requires macOS and a positive interval")
    if args.width <= 0 or (args.height is not None and args.height <= 0):
        parser.error("canvas dimensions must be positive")

    if args.ocr == "apple":
        backend = AppleVisionBackend(fast=args.fast) if args.image else ResidentAppleVision(fast=args.fast)
    else:
        backend = RapidOCRBackend()
    try:
        if args.image:
            print(render(args.image, backend, args))
        elif args.stream:
            for image in sys.stdin:
                image = image.rstrip("\r\n")
                if image:
                    print(json.dumps({"image": image, "ascii": render(image, backend, args)}), flush=True)
        else:
            signal.signal(signal.SIGTERM, signal.default_int_handler)
            with tempfile.TemporaryDirectory(prefix="ascii-screenshot-") as directory:
                image = os.path.join(directory, "screen.png")
                deadline = time.monotonic()
                while True:
                    time.sleep(max(0, deadline - time.monotonic()))
                    captured_at = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
                    subprocess.run(["screencapture", "-x", image], check=True)
                    output = render(image, backend, args)
                    print(json.dumps({"capturedAt": captured_at, "ascii": output}), flush=True)
                    deadline = max(deadline + args.capture_every, time.monotonic())
    except BrokenPipeError:
        sys.stdout = open(os.devnull, "w")
        return
    except KeyboardInterrupt:
        return
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Error: {error}\n")
    finally:
        if isinstance(backend, ResidentAppleVision):
            backend.close()


if __name__ == "__main__":
    main()
