import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { DecodingError, bits, BitWriter, BitReader, type ErrorKind } from './bitio.ts';
import * as lzw from './lzw.ts';
import { tokenize, copyMatch, type Token } from './lz77.ts';
import { limitedLengths, canonical } from './huffman.ts';
import * as arithmetic from './arith_coder.ts';
const METHODS = ['STORE', 'LZW', 'LZ77', 'LZH', 'ARITH'];
const STATUSES = [
  'ok',
  'repaired',
  'checksum',
  'error',
  'unsupported',
  'truncated',
  'bad_header',
] as const;
interface CodingParameters {
  offsetBits: number;
  lengthBits: number;
}
interface Parameters extends CodingParameters {
  maxCodeLength: number;
}
interface Source {
  name: string;
  data: Buffer;
}
interface Packed extends Source {
  method: number;
  payload: Buffer;
}
interface Repair {
  data: Buffer;
  position: number;
  before: number;
  after: number;
}
interface Header {
  number: number;
  offset: number;
  validHeader: true;
  name: string;
  method: number;
  original: number;
  compressed: number;
  adler: number;
  start: number;
}
type Entry =
  | { number: number; offset: number; validHeader: false; status: 'bad_header' | 'truncated' }
  | (Header &
      (
        | { status: 'ok'; data: Buffer }
        | { status: 'repaired'; data: Buffer; repair: Repair }
        | { status: 'checksum'; computed: number }
        | { status: 'error'; error: ErrorKind; errorPosition: number }
        | { status: 'unsupported' | 'truncated' }
      ));
type IntactEntry = Header &
  ({ status: 'ok'; data: Buffer } | { status: 'repaired'; data: Buffer; repair: Repair });
type Archive =
  | { length: number; error: 'bad_magic' | 'bad_params'; entries: Entry[] }
  | {
      length: number;
      error: null;
      parameters: CodingParameters;
      expected: number;
      entries: Entry[];
      stopped: boolean;
      trailing: number;
    };
interface Salvaged extends Packed {
  source: IntactEntry;
}
const readLines = (name: string) => {
  const text = readFileSync(name, 'ascii');
  return text === '' ? [] : text.slice(0, -1).split('\n');
};
const ratio = (z: number, o: number) => (o ? String(Math.floor((1000 * z) / o)) : '-');
const hex32 = (n: number) => n.toString(16).padStart(8, '0');
const methodName = (n: number) => METHODS[n] ?? `#${n}`;
function fixedLengths(count: number) {
  const k = bits(count - 1);
  const u = 2 ** k - count;
  return Array.from({ length: count }, (_, s) => (s < u ? k - 1 : k));
}
function codebook(lengths: number[]) {
  const codes = canonical(lengths);
  const byLength = Array.from({ length: 16 }, () => new Map<number, number>());
  let maximum = 0;
  let used = 0;
  for (let s = 0; s < lengths.length; s++) {
    if (lengths[s]) {
      byLength[lengths[s]].set(codes[s], s);
      maximum = Math.max(maximum, lengths[s]);
      used++;
    }
  }
  return { lengths, codes, byLength, maximum, used };
}
type Codebook = ReturnType<typeof codebook>;
function writeTable(writer: BitWriter, lengths: number[]) {
  let s = 0;
  while (s < lengths.length) {
    if (lengths[s]) writer.write(lengths[s++], 4);
    else {
      let run = 1;
      while (run < 256 && s + run < lengths.length && !lengths[s + run]) run++;
      writer.write(0, 4);
      writer.write(run - 1, 8);
      s += run;
    }
  }
}
function readTable(reader: BitReader, count: number) {
  const lengths: number[] = [];
  while (lengths.length < count) {
    const v = reader.read(4);
    if (v) lengths.push(v);
    else {
      const run = reader.read(8) + 1;
      if (lengths.length + run > count) throw new DecodingError('bad_table');
      for (let i = 0; i < run; i++) lengths.push(0);
    }
  }
  let used = 0;
  let single = 0;
  let kraft = 0;
  for (const length of lengths) {
    if (length) {
      used++;
      single = length;
      kraft += 2 ** (15 - length);
    }
  }
  if ((used === 1 && single !== 1) || (used >= 2 && kraft !== 32768)) {
    throw new DecodingError('bad_table');
  }
  return codebook(lengths);
}
function readSymbol(reader: BitReader, table: Codebook) {
  if (!table.used) throw new DecodingError('bad_code');
  let value = 0;
  for (let w = 1; w <= table.maximum; w++) {
    value = value * 2 + reader.read(1);
    const symbol = table.byLength[w].get(value);
    if (symbol !== undefined) return symbol;
  }
  throw new DecodingError('bad_code');
}
function writeLzhTokens(writer: BitWriter, tokens: Token[], literal: Codebook, distance: Codebook) {
  for (const t of tokens) {
    const s = 'literal' in t ? t.literal : 256 + t.length - 3;
    writer.write(literal.codes[s], literal.lengths[s]);
    if ('literal' in t) continue;
    const u = t.distance - 1;
    const g = bits(u);
    writer.write(distance.codes[g], distance.lengths[g]);
    if (g >= 2) writer.write(u - 2 ** (g - 1), g - 1);
  }
}
function encodeLzh(tokens: Token[], p: Parameters) {
  const a = 256 + 2 ** p.lengthBits;
  const b = p.offsetBits + 1;
  const lf: number[] = Array(a).fill(0);
  const df: number[] = Array(b).fill(0);
  for (const t of tokens) {
    if ('literal' in t) lf[t.literal]++;
    else {
      lf[256 + t.length - 3]++;
      df[bits(t.distance - 1)]++;
    }
  }
  const ll = limitedLengths(lf, p.maxCodeLength);
  const dl = limitedLengths(df, p.maxCodeLength);
  const literal = codebook(ll.lengths);
  const distance = codebook(dl.lengths);
  const dynamic = new BitWriter();
  const fixed = new BitWriter();
  dynamic.write(1, 1);
  writeTable(dynamic, literal.lengths);
  writeTable(dynamic, distance.lengths);
  const tableBits = dynamic.length - 1;
  writeLzhTokens(dynamic, tokens, literal, distance);
  const codeBits = dynamic.length - 1 - tableBits;
  fixed.write(0, 1);
  writeLzhTokens(fixed, tokens, codebook(fixedLengths(a)), codebook(fixedLengths(b)));
  const fixedBits = fixed.length - 1;
  const useFixed = fixedBits <= tableBits + codeBits;
  return {
    payload: (useFixed ? fixed : dynamic).finish(),
    statistics: {
      mode: useFixed ? 'fixed' : 'dynamic',
      fixedBits,
      tableBits,
      codeBits,
      halvings: ll.halvings + dl.halvings,
      literalUsed: literal.used,
      literalMaximum: literal.maximum,
      distanceUsed: distance.used,
      distanceMaximum: distance.maximum,
      slots: df,
    },
  };
}
function encodeLz77(tokens: Token[], p: CodingParameters) {
  const writer = new BitWriter();
  for (const t of tokens) {
    if ('literal' in t) {
      writer.write(0, 1);
      writer.write(t.literal, 8);
    } else {
      writer.write(1, 1);
      writer.write(t.distance - 1, p.offsetBits);
      writer.write(t.length - 3, p.lengthBits);
    }
  }
  return writer.finish();
}
function decodeLz77(payload: Buffer, n: number, p: CodingParameters, output: number[]) {
  const reader = new BitReader(payload);
  while (output.length < n) {
    if (!reader.read(1)) output.push(reader.read(8));
    else {
      const d = reader.read(p.offsetBits) + 1;
      const length = reader.read(p.lengthBits) + 3;
      copyMatch(output, d, length, n);
    }
  }
}
function decodeLzh(payload: Buffer, n: number, p: CodingParameters, output: number[]) {
  const reader = new BitReader(payload);
  const dynamic = reader.read(1) === 1;
  const a = 256 + 2 ** p.lengthBits;
  const b = p.offsetBits + 1;
  const literal = dynamic ? readTable(reader, a) : codebook(fixedLengths(a));
  const distance = dynamic ? readTable(reader, b) : codebook(fixedLengths(b));
  while (output.length < n) {
    const t = readSymbol(reader, literal);
    if (t < 256) output.push(t);
    else {
      const g = readSymbol(reader, distance);
      const u = g >= 2 ? 2 ** (g - 1) + reader.read(g - 1) : g;
      copyMatch(output, u + 1, t - 253, n);
    }
  }
}
function decodePayload(
  method: number,
  payload: Buffer,
  n: number,
  p: CodingParameters,
): { data: Buffer } | { error: ErrorKind; position: number } {
  const output: number[] = [];
  try {
    if (method === 0) {
      for (let i = 0; i < n; i++) {
        if (i === payload.length) throw new DecodingError('end_of_data');
        output.push(payload[i]);
      }
    } else if (method === 1) lzw.decode(payload, n, output);
    else if (method === 2) decodeLz77(payload, n, p, output);
    else if (method === 3) decodeLzh(payload, n, p, output);
    else arithmetic.decode(payload, n, output);
  } catch (error) {
    if (!(error instanceof DecodingError)) throw error;
    return { error: error.kind, position: output.length };
  }
  return { data: Buffer.from(output) };
}
function adler32(data: Uint8Array) {
  let low = 1;
  let high = 0;
  for (const byte of data) {
    low = (low + byte) % 65521;
    high = (high + low) % 65521;
  }
  return high * 65536 + low;
}
function modularPower(base: number, exponent: number) {
  let result = 1;
  while (exponent > 0) {
    if (exponent % 2) result = (result * base) % 65521;
    base = (base * base) % 65521;
    exponent = Math.floor(exponent / 2);
  }
  return result;
}
function repairByte(data: Buffer, stored: number, computed: number): Repair | null {
  const deltaA = ((((stored % 65536) - (computed % 65536)) % 65521) + 65521) % 65521;
  const deltaB =
    (((Math.floor(stored / 65536) - Math.floor(computed / 65536)) % 65521) + 65521) % 65521;
  let delta: number;
  if (deltaA >= 1 && deltaA <= 255) delta = deltaA;
  else if (deltaA >= 65266 && deltaA <= 65520) delta = deltaA - 65521;
  else return null;
  const inverse = modularPower(deltaA, 65519);
  const distance = (deltaB * inverse) % 65521;
  if (distance < 1 || distance > data.length) return null;
  const position = data.length - distance;
  const before = data[position];
  const after = before + delta;
  if (after < 0 || after > 255) return null;
  const repaired = Buffer.from(data);
  repaired[position] = after;
  return adler32(repaired) === stored ? { data: repaired, position, before, after } : null;
}
function buildArchive(entries: Packed[], p: CodingParameters) {
  const header = Buffer.alloc(8);
  header.write('TXAR', 0, 'ascii');
  header[4] = p.offsetBits;
  header[5] = p.lengthBits;
  header.writeUInt16BE(entries.length, 6);
  const parts: Buffer[] = [header];
  for (const e of entries) {
    const name = Buffer.from(e.name, 'ascii');
    const h = Buffer.alloc(15 + name.length);
    h[0] = name.length;
    name.copy(h, 1);
    h[1 + name.length] = e.method;
    h.writeUInt32BE(e.data.length, 2 + name.length);
    h.writeUInt32BE(e.payload.length, 6 + name.length);
    h.writeUInt32BE(adler32(e.data), 10 + name.length);
    let check = 0;
    for (let i = 0; i < h.length - 1; i++) check += h[i];
    h[h.length - 1] = check % 256;
    parts.push(h, e.payload);
  }
  return Buffer.concat(parts);
}
function parseArchive(data: Buffer): Archive {
  const length = data.length;
  const entries: Entry[] = [];
  if (length < 8 || !data.subarray(0, 4).equals(Buffer.from('TXAR', 'ascii'))) {
    return { length, entries, error: 'bad_magic' };
  }
  const parameters = { offsetBits: data[4], lengthBits: data[5] };
  if (
    parameters.offsetBits < 6 ||
    parameters.offsetBits > 12 ||
    parameters.lengthBits < 2 ||
    parameters.lengthBits > 5
  ) {
    return { length, entries, error: 'bad_params' };
  }
  const expected = data.readUInt16BE(6);
  let pos = 8;
  let stopped = false;
  for (let number = 1; number <= expected; number++) {
    const offset = pos;
    if (pos >= length || pos + 15 + data[pos] > length) {
      entries.push({ number, offset, validHeader: false, status: 'truncated' });
      stopped = true;
      break;
    }
    const m = data[pos];
    const name = data.subarray(pos + 1, pos + 1 + m).toString('latin1');
    const method = data[pos + 1 + m];
    const original = data.readUInt32BE(pos + 2 + m);
    const compressed = data.readUInt32BE(pos + 6 + m);
    const adler = data.readUInt32BE(pos + 10 + m);
    const start = pos + 15 + m;
    const next = start + compressed;
    let check = 0;
    for (let i = pos; i < start - 1; i++) check += data[i];
    if (check % 256 !== data[start - 1] || m < 1 || m > 32 || /[^a-z0-9._-]/.test(name)) {
      entries.push({ number, offset, validHeader: false, status: 'bad_header' });
      pos = next;
      if (pos > length) {
        stopped = true;
        break;
      }
      continue;
    }
    const h: Header = {
      number,
      offset,
      validHeader: true,
      name,
      method,
      original,
      compressed,
      adler,
      start,
    };
    if (next > length) {
      entries.push({ ...h, status: 'truncated' });
      stopped = true;
      break;
    }
    if (method >= 5) entries.push({ ...h, status: 'unsupported' });
    else {
      const decoded = decodePayload(method, data.subarray(start, next), original, parameters);
      if ('error' in decoded) {
        entries.push({
          ...h,
          status: 'error',
          error: decoded.error,
          errorPosition: decoded.position,
        });
      } else {
        const computed = adler32(decoded.data);
        if (computed === adler) entries.push({ ...h, status: 'ok', data: decoded.data });
        else {
          const repair = repairByte(decoded.data, adler, computed);
          entries.push(
            repair
              ? { ...h, status: 'repaired', data: repair.data, repair }
              : { ...h, status: 'checksum', computed },
          );
        }
      }
    }
    pos = next;
  }
  return {
    length,
    error: null,
    parameters,
    expected,
    entries,
    stopped,
    trailing: stopped ? 0 : length - pos,
  };
}
function tokenStatistics(tokens: Token[]) {
  const s = { tokens: tokens.length, literals: 0, matches: 0, matched: 0, longest: 0, farthest: 0 };
  for (const t of tokens) {
    if ('literal' in t) s.literals++;
    else {
      s.matches++;
      s.matched += t.length;
      s.longest = Math.max(s.longest, t.length);
      s.farthest = Math.max(s.farthest, t.distance);
    }
  }
  return s;
}
function compress(data: Buffer, p: Parameters) {
  const tokens = tokenize(data, p.offsetBits, p.lengthBits);
  const dictionary = lzw.encode(data);
  const sliding = encodeLz77(tokens, p);
  const hybrid = encodeLzh(tokens, p);
  const arith = arithmetic.encode(data);
  const payloads = [data, dictionary.payload, sliding, hybrid.payload, arith.payload];
  let method = 0;
  for (let i = 1; i < 5; i++) if (payloads[i].length < payloads[method].length) method = i;
  return {
    payloads,
    method,
    payload: payloads[method],
    lzw: dictionary.statistics,
    lz77: tokenStatistics(tokens),
    lzh: hybrid.statistics,
    arith: arith.statistics,
  };
}
interface Created extends Source {
  encoded: ReturnType<typeof compress>;
}
function verifiedEntries(archive: Archive, sources: Source[]) {
  let count = 0;
  for (const e of archive.entries) {
    if (e.status === 'ok' && e.data.equals(sources[e.number - 1].data)) count++;
  }
  return count;
}
function creationReports(files: Created[], p: Parameters, data: Buffer, verification: Archive) {
  const sizes = [
    `params offset_bits ${p.offsetBits} length_bits ${p.lengthBits} window ${2 ** p.offsetBits} lookahead ${2 ** p.lengthBits + 2} max_code_length ${p.maxCodeLength}`,
  ];
  const analysis: string[] = [];
  const totals = [0, 0, 0, 0, 0];
  const chosen = [0, 0, 0, 0, 0];
  let original = 0;
  let best = 0;
  for (const file of files) {
    const e = file.encoded;
    const values = e.payloads.map((p) => p.length);
    sizes.push(
      `file ${file.name} original ${file.data.length} ${METHODS.map((name, i) => `${name} ${values[i]} ${ratio(values[i], file.data.length)}`).join(' ')} best ${METHODS[e.method]}`,
    );
    original += file.data.length;
    best += e.payload.length;
    chosen[e.method]++;
    for (let i = 0; i < 5; i++) totals[i] += values[i];
    const l = e.lzw;
    const t = e.lz77;
    const h = e.lzh;
    analysis.push(
      `lzw ${file.name} codes ${l.codes} clears ${l.clears} widths ${l.widths.join(' ')} longest ${l.longest}`,
      `lz77 ${file.name} tokens ${t.tokens} literals ${t.literals} matches ${t.matches} matched ${t.matched} longest ${t.longest} farthest ${t.farthest}`,
      `lzh ${file.name} mode ${h.mode} fixed_bits ${h.fixedBits} table_bits ${h.tableBits} code_bits ${h.codeBits} halvings ${h.halvings} litlen_used ${h.literalUsed} litlen_max ${h.literalMaximum} offset_used ${h.distanceUsed} offset_max ${h.distanceMaximum}`,
      `slots ${file.name} ${h.slots.join(' ')}`,
      `arith ${file.name} bits ${e.arith.bits} contexts ${e.arith.contexts} rescales ${e.arith.rescales}`,
    );
  }
  sizes.push(
    `total original ${original} ${METHODS.map((name, i) => `${name} ${totals[i]} ${ratio(totals[i], original)}`).join(' ')} best ${best} ${ratio(best, original)}`,
    `chosen ${METHODS.map((name, i) => `${name} ${chosen[i]}`).join(' ')}`,
    `archive bytes ${data.length} entries ${files.length} ratio ${ratio(data.length, original)}`,
    `verify entries ${verification.entries.length} ok ${verifiedEntries(verification, files)}`,
  );
  return { sizes, analysis };
}
function listingLines(a: Archive) {
  if (a.error !== null) return [`archive bytes ${a.length} error ${a.error}`];
  const lines = [
    `archive bytes ${a.length} offset_bits ${a.parameters.offsetBits} length_bits ${a.parameters.lengthBits} entries ${a.expected}`,
  ];
  const totals = METHODS.map(() => ({ entries: 0, original: 0, compressed: 0 }));
  let listed = 0;
  for (const e of a.entries) {
    const prefix = `entry ${e.number} offset ${e.offset}`;
    if (!e.validHeader) {
      lines.push(prefix + (e.status === 'bad_header' ? ' bad_header' : ' truncated header'));
      continue;
    }
    listed++;
    lines.push(
      `${prefix} method ${methodName(e.method)} original ${e.original} compressed ${e.compressed} ratio ${ratio(e.compressed, e.original)} adler ${hex32(e.adler)} name ${e.name}`,
    );
    if (e.method < 5) {
      const t = totals[e.method];
      t.entries++;
      t.original += e.original;
      t.compressed += e.compressed;
    }
  }
  for (let i = 0; i < 5; i++) {
    const t = totals[i];
    lines.push(
      `method ${METHODS[i]} entries ${t.entries} original ${t.original} compressed ${t.compressed} ratio ${ratio(t.compressed, t.original)}`,
    );
  }
  lines.push(
    `end listed ${listed} of ${a.expected} stop ${a.stopped ? 'truncated' : 'complete'} trailing ${a.trailing}`,
  );
  return lines;
}
function testLines(a: Archive, salvaged: Salvaged[], data: Buffer, verification: Archive) {
  const lines: string[] = [];
  if (a.error !== null) lines.push(`archive error ${a.error}`);
  else {
    const counts = new Map<(typeof STATUSES)[number], number>(STATUSES.map((s) => [s, 0]));
    for (const e of a.entries) {
      counts.set(e.status, counts.get(e.status)! + 1);
      const prefix = `entry ${e.number} offset ${e.offset}`;
      if (!e.validHeader) {
        lines.push(
          prefix + (e.status === 'bad_header' ? ' status bad_header' : ' status truncated header'),
        );
        continue;
      }
      let details = '';
      if (e.status === 'repaired') {
        details = ` byte ${e.repair.position} from ${e.repair.before} to ${e.repair.after}`;
      } else if (e.status === 'checksum') {
        details = ` stored ${hex32(e.adler)} computed ${hex32(e.computed)}`;
      } else if (e.status === 'error') details = ` ${e.error} at ${e.errorPosition}`;
      else if (e.status === 'truncated') {
        details = ` payload have ${a.length - e.start} need ${e.compressed}`;
      }
      lines.push(
        `${prefix} name ${e.name} method ${methodName(e.method)} status ${e.status}${details}`,
      );
    }
    lines.push(
      `summary entries ${a.expected} checked ${a.entries.length} ${STATUSES.map((s) => `${s} ${counts.get(s)}`).join(' ')} missing ${a.expected - a.entries.length} trailing ${a.trailing}`,
    );
  }
  let original = 0;
  for (const e of salvaged) {
    original += e.data.length;
    lines.push(
      `salvage ${e.name} method ${METHODS[e.method]} compressed ${e.payload.length} was ${methodName(e.source.method)} ${e.source.compressed}`,
    );
  }
  lines.push(
    `salvaged entries ${salvaged.length} bytes ${data.length} original ${original} verified ${verifiedEntries(verification, salvaged)}`,
  );
  return lines;
}
const textLines = (data: Buffer) =>
  data.length ? data.toString('ascii').slice(0, -1).split('\n') : [];
function extractionLines(intact: IntactEntry[]) {
  const result: string[] = [];
  for (const e of intact) {
    const lines = textLines(e.data);
    let words = 0;
    let longest = 0;
    for (const line of lines) {
      words += line.split(' ').filter(Boolean).length;
      longest = Math.max(longest, line.length);
    }
    result.push(
      `file ${e.name} bytes ${e.data.length} lines ${lines.length} words ${words} longest ${longest}`,
      ...lines,
    );
  }
  return result;
}
function lineEdits(oldLines: string[], newLines: string[]) {
  const a = oldLines.length;
  const b = newLines.length;
  const deletion: Uint8Array[] = [];
  let later = new Uint32Array(b + 1);
  for (let i = a - 1; i >= 0; i--) {
    const current = new Uint32Array(b + 1);
    deletion[i] = new Uint8Array(Math.ceil(b / 8));
    for (let j = b - 1; j >= 0; j--) {
      if (oldLines[i] === newLines[j]) current[j] = later[j + 1] + 1;
      else if (later[j] >= current[j + 1]) {
        current[j] = later[j];
        deletion[i][Math.floor(j / 8)] |= 2 ** (j % 8);
      } else current[j] = current[j + 1];
    }
    later = current;
  }
  let i = 0;
  let j = 0;
  let removed = 0;
  let added = 0;
  const edits: string[] = [];
  while (i < a || j < b) {
    if (i < a && j < b && oldLines[i] === newLines[j]) {
      i++;
      j++;
    } else if (j === b || (i < a && (deletion[i][Math.floor(j / 8)] & (2 ** (j % 8))) !== 0)) {
      edits.push(`-${i + 1}:${oldLines[i++]}`);
      removed++;
    } else {
      edits.push(`+${j + 1}:${newLines[j++]}`);
      added++;
    }
  }
  return { edits, removed, added };
}
function comparisonLines(intact: IntactEntry[], files: Source[]) {
  const manifest = new Map(files.map((f) => [f.name, f]));
  const present = new Set<string>();
  const lines: string[] = [];
  for (const e of intact) {
    present.add(e.name);
    const file = manifest.get(e.name);
    if (!file) {
      lines.push(`archive_only ${e.name}`);
      continue;
    }
    const oldLines = textLines(e.data);
    const newLines = textLines(file.data);
    let first = 0;
    while (
      first < oldLines.length &&
      first < newLines.length &&
      oldLines[first] === newLines[first]
    ) {
      first++;
    }
    if (first === oldLines.length && first === newLines.length) {
      lines.push(`same ${e.name} lines ${oldLines.length}`);
    } else {
      const c = lineEdits(oldLines, newLines);
      lines.push(
        `differs ${e.name} first_line ${first + 1} archive_lines ${oldLines.length} manifest_lines ${newLines.length} removed ${c.removed} added ${c.added}`,
        ...c.edits,
      );
    }
  }
  for (const f of files) if (!present.has(f.name)) lines.push(`new ${f.name}`);
  return lines;
}
function hexLines(data: Buffer) {
  const lines: string[] = [];
  for (let i = 0; i < data.length; i += 32) lines.push(data.subarray(i, i + 32).toString('hex'));
  return lines;
}
function writeLines(name: string, lines: string[]) {
  writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
function main() {
  const manifest = readLines('input/manifest.txt');
  const p: Parameters = {
    offsetBits: Number(manifest[0].split(' ')[1]),
    lengthBits: Number(manifest[1].split(' ')[1]),
    maxCodeLength: Number(manifest[2].split(' ')[1]),
  };
  const files: Created[] = manifest.slice(3).map((line) => {
    const name = line.slice(5);
    const data = readFileSync('input/files/' + name);
    return { name, data, encoded: compress(data, p) };
  });
  const created = files.map((f) => ({
    name: f.name,
    data: f.data,
    method: f.encoded.method,
    payload: f.encoded.payload,
  }));
  const data = buildArchive(created, p);
  const verification = parseArchive(data);
  const reports = creationReports(files, p, data, verification);
  const archive = parseArchive(Buffer.from(readLines('input/archive.hex').join(''), 'hex'));
  const intact = archive.entries.filter(
    (e): e is IntactEntry => e.status === 'ok' || e.status === 'repaired',
  );
  const salvageParameters: Parameters =
    archive.error !== null ? p : { ...archive.parameters, maxCodeLength: p.maxCodeLength };
  const salvaged: Salvaged[] = intact.map((e) => {
    const encoded = compress(e.data, salvageParameters);
    return {
      name: e.name,
      data: e.data,
      method: encoded.method,
      payload: encoded.payload,
      source: e,
    };
  });
  const salvageData = buildArchive(salvaged, salvageParameters);
  const salvageVerification = parseArchive(salvageData);
  mkdirSync('output', { recursive: true });
  writeLines('sizes.txt', reports.sizes);
  writeLines('analysis.txt', reports.analysis);
  writeLines('archive.hex', hexLines(data));
  writeLines('listing.txt', listingLines(archive));
  writeLines('test_report.txt', testLines(archive, salvaged, salvageData, salvageVerification));
  writeLines('extracted.txt', extractionLines(intact));
  writeLines('compare.txt', comparisonLines(intact, files));
  writeLines('salvaged.hex', hexLines(salvageData));
}
main();
