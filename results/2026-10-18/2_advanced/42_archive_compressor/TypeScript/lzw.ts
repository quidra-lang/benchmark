import { DecodingError, bits, BitWriter, BitReader } from './bitio.ts';
export function encode(data: Uint8Array) {
  const writer = new BitWriter();
  const statistics = { codes: 0, clears: 0, widths: [0, 0, 0, 0], longest: 0 };
  let dictionary = new Map<string, number>();
  let next = 258;
  let sinceClear = 0;
  const initialize = () => {
    dictionary = new Map();
    for (let k = 0; k < 256; k++) dictionary.set(String.fromCharCode(k), k);
    next = 258;
  };
  const emit = (code: number, length = 0) => {
    const width = Math.min(12, bits(258 + sinceClear));
    writer.write(code, width);
    statistics.codes++;
    statistics.widths[width - 9]++;
    statistics.longest = Math.max(statistics.longest, length);
    if (code === 256) {
      statistics.clears++;
      sinceClear = 0;
    } else sinceClear++;
  };
  initialize();
  emit(256);
  let word = '';
  for (const byte of data) {
    const character = String.fromCharCode(byte);
    const extended = word + character;
    if (dictionary.has(extended)) word = extended;
    else {
      emit(dictionary.get(word)!, word.length);
      dictionary.set(extended, next++);
      if (next === 4096) {
        emit(256);
        initialize();
      }
      word = character;
    }
  }
  if (word !== '') emit(dictionary.get(word)!, word.length);
  emit(257);
  return { payload: writer.finish(), statistics };
}
export function decode(payload: Uint8Array, originalLength: number, output: number[]) {
  const reader = new BitReader(payload);
  let dictionary: number[][] = [];
  let next = 258;
  let previous: number[] | null = null;
  let sinceClear = 0;
  const initialize = () => {
    dictionary = Array.from({ length: 256 }, (_, k) => [k]);
    next = 258;
    previous = null;
  };
  initialize();
  while (true) {
    const count = sinceClear;
    const code = reader.read(Math.min(12, bits(258 + count)));
    if (code === 256) {
      initialize();
      sinceClear = 0;
      continue;
    }
    sinceClear++;
    if (code === 257) {
      if (output.length < originalLength) throw new DecodingError('early_end');
      return;
    }
    if (count === 3838) throw new DecodingError('bad_code');
    let sequence: number[];
    if (previous === null) {
      if (code >= 256) throw new DecodingError('bad_code');
      sequence = dictionary[code];
    } else if (code < next) sequence = dictionary[code];
    else if (code === next) sequence = previous.concat(previous[0]);
    else throw new DecodingError('bad_code');
    if (output.length + sequence.length > originalLength) throw new DecodingError('overrun');
    for (const byte of sequence) output.push(byte);
    if (previous !== null) dictionary[next++] = previous.concat(sequence[0]);
    previous = sequence;
  }
}
