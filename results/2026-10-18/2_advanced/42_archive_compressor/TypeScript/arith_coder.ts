import { DecodingError, BitWriter, BitReader } from './bitio.ts';
const TOP = 65535;
const HALF = 32768;
const QUARTER = 16384;
const THREE = 49152;
interface Table {
  frequencies: number[];
  total: number;
}
class ContextModel {
  contexts = new Map<number, Table>();
  rescales = 0;
  table(context: number) {
    let table = this.contexts.get(context);
    if (!table) {
      table = { frequencies: Array(257).fill(1), total: 257 };
      this.contexts.set(context, table);
    }
    return table;
  }
  update(table: Table, symbol: number) {
    table.frequencies[symbol] += 32;
    table.total += 32;
    if (table.total >= 8192) {
      table.total = 0;
      for (let i = 0; i < 257; i++) {
        table.frequencies[i] = Math.floor((table.frequencies[i] + 1) / 2);
        table.total += table.frequencies[i];
      }
      this.rescales++;
    }
  }
}
export function encode(data: Uint8Array) {
  const model = new ContextModel();
  const writer = new BitWriter();
  let low = 0;
  let high = TOP;
  let follow = 0;
  let context = 10;
  const emit = (bit: number) => {
    writer.write(bit, 1);
    for (let i = 0; i < follow; i++) writer.write(1 - bit, 1);
    follow = 0;
  };
  for (let i = 0; i <= data.length; i++) {
    const symbol = i === data.length ? 256 : data[i];
    const table = model.table(context);
    let cumulative = 0;
    for (let s = 0; s < symbol; s++) cumulative += table.frequencies[s];
    const range = high - low + 1;
    high = low + Math.floor((range * (cumulative + table.frequencies[symbol])) / table.total) - 1;
    low += Math.floor((range * cumulative) / table.total);
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
  const statistics = {
    bits: writer.length,
    contexts: model.contexts.size,
    rescales: model.rescales,
  };
  return { payload: writer.finish(), statistics };
}
export function decode(payload: Uint8Array, originalLength: number, output: number[]) {
  const model = new ContextModel();
  const reader = new BitReader(payload, true);
  let low = 0;
  let high = TOP;
  let value = reader.read(16);
  let context = 10;
  while (true) {
    const table = model.table(context);
    const range = high - low + 1;
    const q = Math.floor(((value - low + 1) * table.total - 1) / range);
    let symbol = 0;
    let cumulative = 0;
    while (cumulative + table.frequencies[symbol] <= q) cumulative += table.frequencies[symbol++];
    high = low + Math.floor((range * (cumulative + table.frequencies[symbol])) / table.total) - 1;
    low += Math.floor((range * cumulative) / table.total);
    while (true) {
      if (high < HALF) {
        /* No subtraction in the lower half. */
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
