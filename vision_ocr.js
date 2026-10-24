const { createHash } = require('crypto');
const { spawn } = require('child_process');
const fs = require('fs/promises');
const os = require('os');
const path = require('path');
const readline = require('readline');

async function binaryPath() {
  if (process.platform !== 'darwin') throw new Error('Apple Vision requires macOS');
  const source = await fs.readFile(path.join(__dirname, 'ocr.swift'));
  const hash = createHash('sha256').update(source).update(process.arch).digest('hex').slice(0, 16);
  const directory = path.join(os.homedir(), 'Library', 'Caches', 'ascii-screenshot');
  const binary = path.join(directory, `ocr-${hash}`);
  try {
    await fs.access(binary);
    return binary;
  } catch (_) {
    await fs.mkdir(directory, { recursive: true });
  }
  const temporary = `${binary}-${process.pid}`;
  await new Promise((resolve, reject) => {
    const compiler = spawn('swiftc', ['-O', path.join(__dirname, 'ocr.swift'), '-o', temporary]);
    compiler.stdout.resume();
    let stderr = '';
    compiler.stderr.on('data', data => { stderr += data; });
    compiler.on('error', reject);
    compiler.on('close', code => code === 0 ? resolve() : reject(new Error(`swiftc failed: ${stderr.trim()}`)));
  });
  await fs.rename(temporary, binary);
  return binary;
}

function createWorker(binary, fast) {
  const child = spawn(binary, fast ? ['--fast'] : []);
  const pending = [];
  let error = '';
  let failure;
  function fail(err) {
    failure = err;
    while (pending.length) pending.shift().reject(err);
  }
  child.stderr.on('data', data => { error = (error + data).slice(-4096); });
  child.on('error', fail);
  child.stdin.on('error', fail);
  const closed = new Promise(resolve => child.on('close', code => {
    fail(new Error(`Vision exited (${code}): ${error.trim()}`));
    resolve();
  }));
  const lines = readline.createInterface({ input: child.stdout });
  lines.on('line', line => {
    const item = pending.shift();
    if (!item) return;
    try {
      const result = JSON.parse(line);
      if (!Array.isArray(result)) throw new Error(result.error || 'Invalid Vision response');
      item.resolve(result);
    } catch (err) {
      item.reject(err);
    }
  });
  return {
    run(imagePath) {
      if (failure) return Promise.reject(failure);
      if (imagePath.includes('\n') || imagePath.includes('\r')) {
        return Promise.reject(new Error('Image path cannot contain a newline'));
      }
      return new Promise((resolve, reject) => {
        pending.push({ resolve, reject });
        child.stdin.write(imagePath + '\n', err => {
          if (err) fail(err);
        });
      });
    },
    close() { child.stdin.end(); return closed; },
  };
}

async function createVisionOCR(fast = false, maxFrames = 512) {
  if (!Number.isInteger(maxFrames) || maxFrames < 1) throw new Error('maxFrames must be a positive integer');
  const binary = await binaryPath();
  let worker = createWorker(binary, fast);
  let frames = 0;
  let queued = Promise.resolve();
  let closing = false;
  return {
    run(imagePath) {
      if (closing) return Promise.reject(new Error('Vision worker is closed'));
      const result = queued.then(async () => {
        if (frames >= maxFrames) {
          await worker.close();
          worker = createWorker(binary, fast);
          frames = 0;
        }
        frames++;
        return worker.run(imagePath);
      });
      queued = result.catch(() => {});
      return result;
    },
    close() { closing = true; return queued.then(() => worker.close()); },
  };
}

module.exports = { createVisionOCR };
