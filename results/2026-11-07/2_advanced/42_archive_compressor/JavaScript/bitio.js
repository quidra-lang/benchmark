'use strict';

class DecodingError extends Error {
  constructor(kind) {
    super(kind);
    this.kind = kind;
  }
}

function bits(value) {
  let width = 0;
  while (value > 0) {
    width++;
    value = Math.floor(value / 2);
  }
  return width;
}

class BitWriter {
  constructor() {
    this.bytes = [];
    this.current = 0;
    this.used = 0;
    this.length = 0;
  }

  write(value, width) {
    for (let shift = width - 1; shift >= 0; shift--) {
      this.current = this.current * 2 + Math.floor(value / 2 ** shift) % 2;
      this.used++;
      this.length++;
      if (this.used === 8) {
        this.bytes.push(this.current);
        this.current = 0;
        this.used = 0;
      }
    }
  }

  finish() {
    if (this.used > 0) {
      this.bytes.push(this.current * 2 ** (8 - this.used));
      this.current = 0;
      this.used = 0;
    }
    return Buffer.from(this.bytes);
  }
}

class BitReader {
  constructor(data, zeroFill = false) {
    this.data = data;
    this.position = 0;
    this.zeroFill = zeroFill;
  }

  read(width) {
    if (!this.zeroFill && this.position + width > this.data.length * 8) throw new DecodingError('end_of_data');
    let value = 0;
    for (let index = 0; index < width; index++) {
      const byte = this.position < this.data.length * 8 ? this.data[Math.floor(this.position / 8)] : 0;
      value = value * 2 + Math.floor(byte / 2 ** (7 - this.position % 8)) % 2;
      this.position++;
    }
    return value;
  }
}

module.exports = { DecodingError, bits, BitWriter, BitReader };
