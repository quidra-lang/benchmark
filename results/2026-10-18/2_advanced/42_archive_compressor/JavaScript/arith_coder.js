'use strict';

const { DecodingError, BitWriter, BitReader } = require('./bitio');

const TOP = 65535;
const HALF = 32768;
const QUARTER = 16384;
const THREE = 49152;

class Model {
  constructor() {
    this.contexts = new Map();
    this.rescales = 0;
  }

  table(context) {
    if (!this.contexts.has(context)) this.contexts.set(context, { frequencies: Array(257).fill(1), total: 257 });
    return this.contexts.get(context);
  }

  update(table, symbol) {
    table.frequencies[symbol] += 32;
    table.total += 32;
    if (table.total >= 8192) {
      table.total = 0;
      for (let index = 0; index < 257; index++) {
        table.frequencies[index] = Math.floor((table.frequencies[index] + 1) / 2);
        table.total += table.frequencies[index];
      }
      this.rescales++;
    }
  }
}

function encode(data) {
  const model = new Model();
  const writer = new BitWriter();
  let low = 0;
  let high = TOP;
  let follow = 0;
  let context = 10;
  function emit(bit) {
    writer.write(bit, 1);
    for (let index = 0; index < follow; index++) writer.write(1 - bit, 1);
    follow = 0;
  }
  for (let index = 0; index <= data.length; index++) {
    const symbol = index === data.length ? 256 : data[index];
    const table = model.table(context);
    let cumulative = 0;
    for (let earlier = 0; earlier < symbol; earlier++) cumulative += table.frequencies[earlier];
    const range = high - low + 1;
    high = low + Math.floor(range * (cumulative + table.frequencies[symbol]) / table.total) - 1;
    low += Math.floor(range * cumulative / table.total);
    while (true) {
      if (high < HALF) emit(0);
      else if (low >= HALF) {
        emit(1);
        low -= HALF;
        high -= HALF;
      } else if (low >= QUARTER && high < THREE) {
        follow++;
        low -= QUARTER;
        high -= QUARTER;
      } else break;
      low *= 2;
      high = high * 2 + 1;
    }
    if (symbol !== 256) {
      model.update(table, symbol);
      context = symbol;
    }
  }
  follow++;
  emit(low < QUARTER ? 0 : 1);
  const statistics = { bits: writer.length, contexts: model.contexts.size, rescales: model.rescales };
  return { payload: writer.finish(), statistics };
}

function decode(payload, originalLength, output) {
  const model = new Model();
  const reader = new BitReader(payload, true);
  let low = 0;
  let high = TOP;
  let value = reader.read(16);
  let context = 10;
  while (true) {
    const table = model.table(context);
    const range = high - low + 1;
    const quotient = Math.floor(((value - low + 1) * table.total - 1) / range);
    let symbol = 0;
    let cumulative = 0;
    while (cumulative + table.frequencies[symbol] <= quotient) cumulative += table.frequencies[symbol++];
    high = low + Math.floor(range * (cumulative + table.frequencies[symbol]) / table.total) - 1;
    low += Math.floor(range * cumulative / table.total);
    while (true) {
      if (high < HALF) {
        // The interval is already in the lower half.
      } else if (low >= HALF) {
        low -= HALF;
        high -= HALF;
        value -= HALF;
      } else if (low >= QUARTER && high < THREE) {
        low -= QUARTER;
        high -= QUARTER;
        value -= QUARTER;
      } else break;
      low *= 2;
      high = high * 2 + 1;
      value = value * 2 + reader.read(1);
    }
    if (symbol === 256) {
      if (output.length < originalLength) throw new DecodingError('early_end');
      return;
    }
    if (output.length === originalLength) throw new DecodingError('overrun');
    output.push(symbol);
    model.update(table, symbol);
    context = symbol;
  }
}

module.exports = { encode, decode };
