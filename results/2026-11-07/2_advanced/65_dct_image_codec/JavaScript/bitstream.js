'use strict';

class DecodeError extends Error {
  constructor(kind) { super(kind); this.kind = kind; }
}

class Writer {
  constructor() { this.bytes = []; this.buffer = 0; this.count = 0; this.padding = 0; this.stuffed = 0; }

  write(value, length) {
    for (let i = length - 1; i >= 0; i--) {
      this.buffer = this.buffer * 2 + Math.floor(value / 2 ** i) % 2;
      this.count++;
      if (this.count === 8) {
        this.bytes.push(this.buffer);
        if (this.buffer === 255) { this.bytes.push(0); this.stuffed++; }
        this.buffer = 0; this.count = 0;
      }
    }
  }

  pad() { while (this.count !== 0) { this.write(1, 1); this.padding++; } }
  marker(value) { this.bytes.push(255, value); }
}

class Reader {
  constructor(bytes, position) { this.bytes = bytes; this.position = position; this.clear(); }
  clear() { this.buffer = 0; this.remaining = 0; }

  bit() {
    if (this.remaining === 0) {
      const value = this.bytes[this.position];
      if (value === 255) {
        if (this.bytes[this.position + 1] !== 0) throw new DecodeError('marker');
        this.position += 2;
      } else this.position++;
      this.buffer = value; this.remaining = 8;
    }
    this.remaining--;
    return Math.floor(this.buffer / 2 ** this.remaining) % 2;
  }

  read(length) {
    let value = 0;
    for (let i = 0; i < length; i++) value = value * 2 + this.bit();
    return value;
  }

  resync() {
    for (let q = this.position; q + 1 < this.bytes.length; q++) {
      const marker = this.bytes[q + 1];
      if (this.bytes[q] === 255 && ((marker >= 208 && marker <= 215) || marker === 217)) return q;
    }
    return -1;
  }
}

module.exports = { DecodeError, Writer, Reader };
