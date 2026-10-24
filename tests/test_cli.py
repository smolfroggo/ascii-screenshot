import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import cv2
import numpy as np

from index import ResidentAppleVision

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == "darwin", "Apple Vision is macOS-only")
class ContinuousCLITests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.image = Path(directory.name) / "same frame.png"
        self.write_text("Hello Vision")

    def write_text(self, text, path=None):
        pixels = np.full((160, 320, 3), 255, dtype=np.uint8)
        cv2.putText(pixels, text, (20, 80), cv2.FONT_HERSHEY_SIMPLEX,
                    1, (0, 0, 0), 2)
        cv2.imwrite(str(path or self.image), pixels)

    def test_identical_images_are_processed_twice_in_both_clis(self):
        for command in (["node", "index.js"], [sys.executable, "index.py"]):
            with self.subTest(command=command):
                output = subprocess.run(
                    [*command, "--stream", "--fast", "--width", "40", "--height", "10"],
                    input=f"{self.image}\n{self.image}\n", cwd=ROOT,
                    capture_output=True, text=True, timeout=90, check=True,
                )
                results = [json.loads(line) for line in output.stdout.splitlines()]
                self.assertEqual(len(results), 2)
                self.assertEqual(results[0], results[1])
                self.assertEqual(results[0]["image"], str(self.image))
                self.assertIn("Vision", results[0]["ascii"])

    def test_workers_refresh_between_completed_frames_without_losing_results(self):
        backend = ResidentAppleVision(fast=True, max_frames=2)
        try:
            results = [backend.run(str(self.image)) for _ in range(6)]
            self.assertEqual(backend._frames, 2)
            self.assertTrue(all(result == results[0] for result in results))
            self.assertIn("Vision", " ".join(item["text"] for item in results[0]))
        finally:
            backend.close()
        script = """
const { createVisionOCR } = require('./vision_ocr');
(async () => {
  const ocr = await createVisionOCR(true, 2);
  try {
    console.log(JSON.stringify(await Promise.all(Array.from({length: 6}, () => ocr.run(process.argv[1])))));
  } finally { await ocr.close(); }
})().catch(err => { console.error(err); process.exit(1); });
"""
        result = subprocess.run(["node", "-e", script, str(self.image)], cwd=ROOT,
                                capture_output=True, text=True, timeout=90, check=True)
        results = json.loads(result.stdout)
        self.assertEqual(len(results), 6)
        self.assertTrue(all(result == results[0] for result in results))
        self.assertIn("Vision", " ".join(item["text"] for item in results[0]))

    def test_reused_requests_read_new_pixels_at_the_same_image_path(self):
        backend = ResidentAppleVision(fast=True)
        try:
            first = backend.run(str(self.image))
            self.write_text("Second Frame")
            second = backend.run(str(self.image))
            self.assertIn("Vision", " ".join(item["text"] for item in first))
            self.assertIn("Frame", " ".join(item["text"] for item in second))
        finally:
            backend.close()
        self.write_text("Hello Vision")
        second_image = self.image.with_name("second.png")
        self.write_text("Second Frame", second_image)
        target = self.image.with_name("changing.png")
        script = """
const fs = require('fs');
const { createVisionOCR } = require('./vision_ocr');
(async () => {
  const ocr = await createVisionOCR(true);
  try {
    const output = [];
    for (const image of process.argv.slice(1, 3)) {
      fs.copyFileSync(image, process.argv[3]);
      output.push(await ocr.run(process.argv[3]));
    }
    console.log(JSON.stringify(output));
  } finally { await ocr.close(); }
})().catch(err => { console.error(err); process.exit(1); });
"""
        result = subprocess.run(["node", "-e", script, str(self.image), str(second_image), str(target)],
                                cwd=ROOT, capture_output=True, text=True, timeout=90, check=True)
        first, second = json.loads(result.stdout)
        self.assertIn("Vision", " ".join(item["text"] for item in first))
        self.assertIn("Frame", " ".join(item["text"] for item in second))

    def test_missing_image_fails_instead_of_returning_empty_ocr(self):
        for command in (["node", "index.js"], [sys.executable, "index.py"]):
            with self.subTest(command=command):
                result = subprocess.run([*command, os.path.join(tempfile.gettempdir(),
                                         "not-an-image-ascii-screenshot.png")], cwd=ROOT,
                                        capture_output=True, text=True, timeout=30)
                self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
