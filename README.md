# ASCII Screenshot

A simple tool to generate an ASCII-like version of images, optimized for screenshots. It also includes basic line detection to enhance the ASCII output.

## Features
- Converts images to ASCII-like art.
- Optimized for screenshots.
- Detects straight UI boundaries: rules, table cells, filled panels and cards.
- Works best with images sized around **1600x1000 pixels**.

## Installation
Install the package via npm:

```bash
npm install -g ascii-screenshot
```

## Usage
Run the tool from the command line, specifying the path to your image:

```bash
ascii-screenshot path/to/img
```

On macOS, the Node CLI calls Vision through a small Swift worker. It compiles
once on first use using Xcode Command Line Tools (`swiftc`) and caches the
binary in `~/Library/Caches/ascii-screenshot`. Subsequent screenshots in a
running process reuse the same worker. Accurate OCR is the default; `--fast`
uses less CPU but misses more small text.

Continuous modes refresh the native OCR worker after 512 completed frames to
bound the native RSS growth observed on this VM. Every image is still processed;
refreshes happen between frames, not instead of processing them. Python uses
an isolated PyObjC worker in continuous modes, and in-process PyObjC for a single
image. Startup cost is amortized over each 512-frame batch.

To process **every full-screen capture**, including unchanged screens, in a
single process (Ctrl-C to stop):

```bash
ascii-screenshot --capture-every 1 --fast
```

`--capture-every 1` attempts one capture per second. If processing takes longer
than a second, it captures the next frame immediately after finishing the
previous one; it never discards a captured frame. Each result is one JSON line
with `capturedAt` and `ascii`. Grant your terminal Screen Recording permission
in macOS settings if prompted. To supply screenshots yourself instead, use
`--stream`: send one image path per line on stdin and receive JSON lines with
`image` and `ascii`. Each path is processed even when repeated.

## Requirements
- **Node CLI**: macOS with Xcode Command Line Tools (`xcode-select --install`).
- Ensure your image resolution is close to **1600x1000** for best results.

## Python port (cross-platform)
`index.py` mirrors the CLI: direct PyObjC Vision by default on macOS,
RapidOCR by default elsewhere. Requires Python 3.9+.

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python index.py path/to/img [--width 160] [--height 60] [--px 0.5 --py 0.5] [--ocr rapidocr|apple]
```

Python also accepts `--fast`, `--stream`, and `--capture-every 1` on macOS.
Accurate Vision at 1 Hz is CPU-intensive; fast mode is an explicit quality
tradeoff. CPU time alone does not establish physical Mac battery usage.

`./compare.sh path/to/img` runs the JS, Python + RapidOCR and Python + Apple Vision pipelines side by side (uses `python3` on `PATH`).

## Boundary detection

The JS and Python detectors find long horizontal/vertical colour transitions,
including boundaries between filled regions with no explicit border stroke.
Nearby edges are merged, and locally solid colours distinguish UI regions from
photo texture. The detector retains the four image borders.

This is a pixel heuristic, not semantic segmentation: rounded corners are
approximated by straight segments, and gradual shadows or translucent panels
can be missed. Large glyph stems, underlines and icons can still produce false
segments. Lossless screenshots work best; JPEG compression affects flat-colour
filtering.

Rendering suppresses segments contained in OCR text boxes (usually glyph stems
or underlines). Junctions keep a plain `|`, with the horizontal underline stopping
at that cell: neither `+` nor a combining underline on `|` reliably aligns with
the low horizontal rule in native fonts. This is a text approximation, not a
perfectly joined box. Vertical boundaries take precedence over colliding
characters on the coarse ASCII grid;
horizontal rules underline text. Use a wider canvas for dense tables to reduce
text collisions. The renderer's `originalText` field retains text before the
boundary overlay.

Run the generated-image regressions (including JS/Python output parity):

```bash
.venv/bin/python -m unittest discover -s tests -v
```

## Shell script to convert latest screenshot
```
tt () {
	local screenshots_dir=~/Desktop
	local sorted_files=$(ls -t $screenshots_dir)
	local selected_file=$(echo "$sorted_files" | sed "${1}q;d")
	if [ -n "$selected_file" ]
	then
		ascii-screenshot "$screenshots_dir/$selected_file" "${@:2}"
	else
		echo "No such file found at position $1." >&2
	fi
}
```

## Acknowledgments
Inspired by the work on the [Tarsier](https://github.com/tarsier-project) and [Textra](https://github.com/textra) GitHub projects.

---

## Example
```
________________________________________________________________________________________________________________________________________________________________
|                                                                                                                                                              |
| < > Code     Issues                      Actions                                                                                                             |
|                         Pull requests            # Projects  D Wiki       Security I Insights      Settings                                                  |
________________________________________________________________________________________________________________________________________________________________
|                                                                                             _______                                                          |
|                                                                                                                                                              |
|                                                                                                                                            Star              |
|         ascil-screenshot Public                                                            _&̲_P̲i̲n̲__  • Unwatch        2 Fork O                               |
|                                                                                                                                                              |
|      __________________________________________________________________________________________________________________________________________________      |
|                                                                                                                                                              |
|                                                            __________________________                                                                        |
|                                                                                                                                                              |
|       & master       § 1 Branch • O Tags                    • Go to file                Add file    <> Code ~      About                                     |
|      _____________________________________________________________________________________________                                                           |
|      __________________________________________________________________________________________________________ |                                            |
|      |                                                                                                          |                                            |
|      |                                                                                                          | No description, website, or topics         |
|      |                                                                                             D 18 Commits |                                            |
|      |    tetratorus Update README.md                                            aa77d0e • 3 weeks ago          | provided.                                  |
|      ____________________________________________________________________________________________________________                                            |
|      |                                                                                                          |                                            |
|      |                                                                                                          |     Readme                                 |
|      |    public                                 added back lines                                   3 weeks ago |                                            |
|      ____________________________________________________________________________________________________________                                            |
|      |                                                                                                          | * Activity                                 |
|      |                                                                                                          |                                            |
|      |    •gitignore                             cleanup                                            3 weeks ago |                                            |
|      ____________________________________________________________________________________________________________  # 0 stars                                 |
|      |                                                                                                          |                                            |
|      |    README.md                              Update README.md                                   3 weeks ago |     1 watching                             |
|      ____________________________________________________________________________________________________________                                            |
|      |                                                                                                          |                                            |
|      |                                                                                                          |    O forks                                 |
|      |    ascii.js                               update to 60 for height to respect 1600x1200 divisibility 3 weeks ago                                       |
|      ____________________________________________________________________________________________________________                                            |
|      |                                                                                                          |                                            |
|      |                                                                                                          |                                            |
|      |    detect_lines.js                        turn into a single cli                             3 weeks ago |  Releases                                  |
|      ____________________________________________________________________________________________________________                                            |
|      |                                                                                                          |                                            |
|      |                                                                                                          |                                            |
|      |   index.js                                working tt                                         3 weeks ago | No releases published                      |
|      ____________________________________________________________________________________________________________  Create a new release                      |
|      |                                                                                                          |                                            |
|      |    lines.json                             turn into a single cli                             3 weeks ago |                                            |
|      ____________________________________________________________________________________________________________                                            |
|      |                                                                                                          |                                            |
|      |                                                                                                          |  Packages                                  |
|      |    ocr.swift                              turn into a single cli                             3 weeks ago |                                            |
|      ____________________________________________________________________________________________________________                                            |
|      |                                                                                                          |                                            |
|      |                                                                                                          | No packages published                      |
|      |    opencv.js                              working                                            3 weeks ago |  Publish your first package                |
|      ____________________________________________________________________________________________________________                                            |
|      |                                                                                                          |                                            |
|      |                                                                                                          |                                            |
|      |    package-lock.json                      added back lines                                   3 weeks ago |                                            |
____________________________________________________________________________________________________________________L̲a̲n̲g̲u̲a̲g̲e̲s̲___________________________________
```

**Note**: This project is experimental and may not work optimally for all image sizes or types. Feedback and contributions are welcome!
