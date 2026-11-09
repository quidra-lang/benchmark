'use strict';

function append(target, source) {
  for (const byte of source) target.push(byte);
  return target;
}

function bits(value) {
  let width = 0;
  while (value > 0) {
    width++;
    value = Math.floor(value / 2);
  }
  return width;
}

function uleb(value) {
  const result = [];
  while (value >= 128) {
    result.push(value % 128 + 128);
    value = Math.floor(value / 128);
  }
  result.push(value);
  return result;
}

function zigzag(value) {
  return uleb(value >= 0 ? 2 * value : -2 * value - 1);
}

function uint32(value) {
  return [value % 256, Math.floor(value / 256) % 256,
    Math.floor(value / 65536) % 256, Math.floor(value / 16777216)];
}

function signed32(value) {
  return uint32(value < 0 ? value + 4294967296 : value);
}

class Reader {
  constructor(bytes, position = 0) {
    this.bytes = bytes;
    this.position = position;
  }

  byte() {
    return this.bytes[this.position++];
  }

  take(count) {
    const result = this.bytes.slice(this.position, this.position + count);
    this.position += count;
    return result;
  }

  text(count) {
    return Buffer.from(this.take(count)).toString('ascii');
  }

  uleb() {
    let result = 0;
    let scale = 1;
    for (;;) {
      const byte = this.byte();
      result += byte % 128 * scale;
      if (byte < 128) return result;
      scale *= 128;
    }
  }

  zigzag() {
    const value = this.uleb();
    return value % 2 === 0 ? value / 2 : -(value + 1) / 2;
  }

  uint32() {
    return this.byte() + this.byte() * 256 + this.byte() * 65536 + this.byte() * 16777216;
  }

  signed32() {
    const value = this.uint32();
    return value >= 2147483648 ? value - 4294967296 : value;
  }
}

function pack(values, width) {
  const result = Array(values.length * width / 8).fill(0);
  for (let index = 0; index < values.length; index++) {
    let value = values[index];
    for (let bit = 0; bit < width; bit++) {
      const serial = index * width + bit;
      result[Math.floor(serial / 8)] += value % 2 * 2 ** (serial % 8);
      value = Math.floor(value / 2);
    }
  }
  return result;
}

function unpack(reader, count, width) {
  const bytes = reader.take(count * width / 8);
  const result = Array(count).fill(0);
  for (let index = 0; index < count; index++) {
    for (let bit = 0; bit < width; bit++) {
      const serial = index * width + bit;
      const value = Math.floor(bytes[Math.floor(serial / 8)] / 2 ** (serial % 8)) % 2;
      result[index] += value * 2 ** bit;
    }
  }
  return result;
}

function hybridEncode(values, width) {
  const result = [];
  const runLength = start => {
    let end = start + 1;
    while (end < values.length && values[end] === values[start]) end++;
    return end - start;
  };
  let index = 0;
  while (index < values.length) {
    const length = runLength(index);
    if (length >= 8) {
      append(result, uleb(2 * length));
      let value = values[index];
      for (let byte = 0; byte < Math.ceil(width / 8); byte++) {
        result.push(value % 256);
        value = Math.floor(value / 256);
      }
      index += length;
    } else {
      let end = index;
      let groups = 0;
      do {
        end += 8;
        groups++;
      } while (end < values.length && groups < 63 && runLength(end) < 8);
      append(result, uleb(2 * groups + 1));
      const packed = values.slice(index, end);
      while (packed.length < 8 * groups) packed.push(0);
      append(result, pack(packed, width));
      index = end;
    }
  }
  return result;
}

function hybridDecode(reader, count, width) {
  const result = [];
  while (result.length < count) {
    const header = reader.uleb();
    if (header % 2 === 0) {
      let value = 0;
      let scale = 1;
      for (let byte = 0; byte < Math.ceil(width / 8); byte++) {
        value += reader.byte() * scale;
        scale *= 256;
      }
      for (let index = 0; index < header / 2; index++) result.push(value);
    } else append(result, unpack(reader, 8 * ((header - 1) / 2), width));
  }
  return result.slice(0, count);
}

function adler32(bytes) {
  let a = 1;
  let b = 0;
  for (const byte of bytes) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return b * 65536 + a;
}

module.exports = {Reader, append, bits, uleb, zigzag, uint32, signed32, pack, unpack,
  hybridEncode, hybridDecode, adler32};
