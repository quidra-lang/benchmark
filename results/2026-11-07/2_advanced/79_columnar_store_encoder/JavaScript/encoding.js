'use strict';

const bitstream = require('./bitstream');
const {append, uleb, zigzag, bits, pack, unpack, Reader} = bitstream;
const methods = ['PLAIN', 'DICTIONARY', 'RLE', 'DELTA_BINARY_PACKED', 'DELTA_LENGTH_BYTE_ARRAY'];
const types = ['INT', 'STRING', 'BOOL', 'DATE'];
const candidates = {INT: [0, 1, 3], STRING: [0, 1, 4], BOOL: [0, 2], DATE: [0, 1, 3]};

function deltaEncode(values) {
  const result = [];
  for (const value of [128, 4, values.length]) append(result, uleb(value));
  append(result, zigzag(values.length ? values[0] : 0));
  for (let start = 1; start < values.length; start += 128) {
    const deltas = [];
    for (let index = start; index < Math.min(start + 128, values.length); index++) {
      deltas.push(values[index] - values[index - 1]);
    }
    const minimum = Math.min(...deltas);
    append(result, zigzag(minimum));
    const miniblocks = [];
    const widths = [];
    for (let block = 0; block < 4; block++) {
      const adjusted = deltas.slice(32 * block, 32 * block + 32).map(value => value - minimum);
      widths.push(adjusted.length ? bits(Math.max(...adjusted)) : 0);
      miniblocks.push(adjusted);
    }
    append(result, widths);
    for (let block = 0; block < 4; block++) {
      const adjusted = miniblocks[block];
      if (adjusted.length === 0) continue;
      while (adjusted.length < 32) adjusted.push(0);
      append(result, pack(adjusted, widths[block]));
    }
  }
  return result;
}

function deltaDecode(reader) {
  reader.uleb();
  reader.uleb();
  const count = reader.uleb();
  const first = reader.zigzag();
  const result = count ? [first] : [];
  while (result.length < count) {
    const minimum = reader.zigzag();
    const widths = reader.take(4);
    for (let block = 0; block < 4 && result.length < count; block++) {
      const remaining = Math.min(32, count - result.length);
      const adjusted = unpack(reader, 32, widths[block]);
      for (let index = 0; index < remaining; index++) {
        result.push(result.at(-1) + (minimum + adjusted[index]));
      }
    }
  }
  return result;
}

function encodeValues(type, method, values, dictionary = [], ranks = null) {
  const result = [];
  if (method === 0) {
    if (type === 'BOOL') {
      const numbers = values.map(value => value ? 1 : 0);
      while (numbers.length % 8) numbers.push(0);
      return pack(numbers, 1);
    }
    for (const value of values) {
      if (type === 'STRING') {
        append(result, bitstream.uint32(value.length));
        append(result, Buffer.from(value, 'ascii'));
      } else append(result, bitstream.signed32(value));
    }
  } else if (method === 1) {
    const width = bits(dictionary.length - 1);
    if (ranks === null) ranks = new Map(dictionary.map((value, index) => [value, index]));
    result.push(width);
    append(result, bitstream.hybridEncode(values.map(value => ranks.get(value)), width));
  } else if (method === 2) {
    const encoded = bitstream.hybridEncode(values.map(value => value ? 1 : 0), 1);
    append(result, bitstream.uint32(encoded.length));
    append(result, encoded);
  } else if (method === 3) return deltaEncode(values);
  else {
    append(result, deltaEncode(values.map(value => value.length)));
    for (const value of values) append(result, Buffer.from(value, 'ascii'));
  }
  return result;
}

function decodeValues(type, method, reader, count, dictionary = []) {
  if (method === 1) {
    const width = reader.byte();
    return bitstream.hybridDecode(reader, count, width).map(index => dictionary[index]);
  }
  if (method === 2) {
    const encoded = new Reader(reader.take(reader.uint32()));
    return bitstream.hybridDecode(encoded, count, 1).map(value => value === 1);
  }
  if (method === 3) return deltaDecode(reader);
  if (method === 4) return deltaDecode(reader).map(length => reader.text(length));
  if (type === 'BOOL') return unpack(reader, Math.ceil(count / 8) * 8, 1).slice(0, count).map(value => value === 1);
  const result = [];
  for (let index = 0; index < count; index++) {
    result.push(type === 'STRING' ? reader.text(reader.uint32()) : reader.signed32());
  }
  return result;
}

function statisticValue(type, value) {
  if (type === 'STRING') return append(uleb(value.length), Buffer.from(value, 'ascii'));
  if (type === 'BOOL') return [value ? 1 : 0];
  return zigzag(value);
}

function readStatisticValue(reader, type) {
  if (type === 'STRING') return reader.text(reader.uleb());
  if (type === 'BOOL') return reader.byte() === 1;
  return reader.zigzag();
}

function statisticsBytes(type, statistics) {
  if (statistics === null) return [0];
  const result = [1];
  append(result, statisticValue(type, statistics.minimum));
  append(result, statisticValue(type, statistics.maximum));
  return result;
}

function readStatistics(reader, type) {
  if (reader.byte() === 0) return null;
  return {minimum: readStatisticValue(reader, type), maximum: readStatisticValue(reader, type)};
}

module.exports = {methods, types, candidates, deltaEncode, deltaDecode, encodeValues, decodeValues,
  statisticsBytes, readStatistics};
