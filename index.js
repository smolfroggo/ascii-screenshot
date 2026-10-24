#!/usr/bin/env node
const { spawn } = require('child_process');
const fs = require('fs/promises');
const os = require('os');
const readline = require('readline');
const { detectLines } = require('./detect_lines');
const { ascii } = require('./ascii');
const pathLib = require('path');
const { createVisionOCR } = require('./vision_ocr');

let onBrokenPipe = () => process.exit(0);
process.stdout.on('error', err => {
  if (err.code === 'EPIPE') return onBrokenPipe();
  throw err;
});

async function asciiScreenshot(imagePath, ocr, normX, normY, canvasWidth, canvasHeight) {
  const [screenshotJSON, linesJSON] = await Promise.all([
    ocr.run(pathLib.resolve(imagePath)), detectLines(imagePath),
  ]);

  const { finalText } = ascii(screenshotJSON, linesJSON, normX, normY, canvasWidth, canvasHeight);
  return finalText;
}

function parseFlags(argv) {
  const flags = {};
  const positional = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const val = ["fast", "stream"].includes(key) ? true :
        argv[i + 1] && !argv[i + 1].startsWith("-") ? argv[++i] : true;
      flags[key] = /^\d+(\.\d+)?$/.test(val) ? Number(val) : val;
    } else if (arg.startsWith("-")) {
      // short flags like -h
      arg.slice(1).split("").forEach(c => flags[c] = true);
    } else {
      positional.push(arg);
    }
  }
  return { flags, positional };
}

const { flags, positional } = parseFlags(process.argv.slice(2));

if (flags.h || flags.help) {
  console.log(`
Usage: ascii-screenshot <image> [options]

Options:
  --px <float>         Normalized X coordinate (0–1) for pointer
  --py <float>         Normalized Y coordinate (0–1) for pointer
  --width <int>        Canvas width (default: 160)
  --height <int>       Canvas height (default: 60)
  --fast               Lower-CPU Vision mode (less accurate on small text)
  --stream             Read one image path per line from stdin; emit JSON lines
  --capture-every <s>  Capture and process the full screen every s seconds
  -h, --help           Show this help message
`);
  process.exit(0);
}

const imagePath = positional[0];
const px = flags.px ?? null;
const py = flags.py ?? null;
const canvasWidth = flags.width || 160;
const canvasHeight = flags.height || 60;

if ((!imagePath && !flags.stream && !flags['capture-every']) ||
    Number(Boolean(flags.stream)) + Number(Boolean(flags['capture-every'])) + Number(Boolean(imagePath)) !== 1 ||
    (flags['capture-every'] && (!(flags['capture-every'] > 0) || typeof flags['capture-every'] !== 'number'))) {
  console.error('Provide exactly one of <image>, --stream, or --capture-every <positive seconds>');
  process.exit(1);
}

async function main() {
  const ocr = await createVisionOCR(Boolean(flags.fast));
  try {
    if (imagePath) {
      console.log(await asciiScreenshot(imagePath, ocr, px, py, canvasWidth, canvasHeight));
    } else if (flags.stream) {
      for await (const image of readline.createInterface({ input: process.stdin })) {
        if (!image) continue;
        const output = await asciiScreenshot(image, ocr, px, py, canvasWidth, canvasHeight);
        console.log(JSON.stringify({ image, ascii: output }));
      }
    } else {
      const directory = await fs.mkdtemp(pathLib.join(os.tmpdir(), 'ascii-screenshot-'));
      const image = pathLib.join(directory, 'screen.png');
      let deadline = performance.now();
      let stopping = false;
      const stop = () => { stopping = true; };
      onBrokenPipe = stop;
      process.once('SIGINT', stop);
      process.once('SIGTERM', stop);
      try {
        while (!stopping) {
          const remaining = deadline - performance.now();
          if (remaining > 0) await new Promise(resolve => setTimeout(resolve, remaining));
          if (stopping) break;
          const capturedAt = new Date().toISOString();
          await new Promise((resolve, reject) => {
            const capture = spawn('screencapture', ['-x', image]);
            capture.on('error', reject);
            capture.on('close', code => code === 0 ? resolve() : reject(new Error(`screencapture exited ${code}`)));
          });
          const output = await asciiScreenshot(image, ocr, px, py, canvasWidth, canvasHeight);
          console.log(JSON.stringify({ capturedAt, ascii: output }));
          deadline = Math.max(deadline + flags['capture-every'] * 1000, performance.now());
        }
      } finally {
        process.removeListener('SIGINT', stop);
        process.removeListener('SIGTERM', stop);
        await fs.rm(directory, { recursive: true, force: true });
      }
    }
  } finally {
    await ocr.close();
  }
}

main().catch(err => {
  console.error("Error:", err.message);
  process.exit(1);
});
