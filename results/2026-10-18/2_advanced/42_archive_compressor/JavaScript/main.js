'use strict';

const fs = require('node:fs');
const { DecodingError, bits, BitWriter, BitReader } = require('./bitio');
const lzw = require('./lzw');
const lz77 = require('./lz77');
const huffman = require('./huffman');
const arithmetic = require('./arith_coder');

const METHODS = ['STORE', 'LZW', 'LZ77', 'LZH', 'ARITH'];
const STATUSES = ['ok', 'repaired', 'checksum', 'error', 'unsupported', 'truncated', 'bad_header'];

function readLines(filename) {
  const text = fs.readFileSync(filename, 'ascii');
  return text === '' ? [] : text.slice(0, -1).split('\n');
}

function ratio(compressed, original) {
  return original === 0 ? '-' : String(Math.floor(1000 * compressed / original));
}

function hex32(value) {
  return value.toString(16).padStart(8, '0');
}

function methodName(method) {
  return method < METHODS.length ? METHODS[method] : `#${method}`;
}

function fixedLengths(symbols) {
  const width = bits(symbols - 1);
  const shorter = 2 ** width - symbols;
  return Array.from({ length: symbols }, (_, symbol) => symbol < shorter ? width - 1 : width);
}

function codebook(lengths) {
  const codes = huffman.canonical(lengths);
  const byLength = Array.from({ length: 16 }, () => new Map());
  let maximum = 0;
  let used = 0;
  for (let symbol = 0; symbol < lengths.length; symbol++) {
    if (lengths[symbol] === 0) continue;
    byLength[lengths[symbol]].set(codes[symbol], symbol);
    maximum = Math.max(maximum, lengths[symbol]);
    used++;
  }
  return { lengths, codes, byLength, maximum, used };
}

function writeTable(writer, lengths) {
  let symbol = 0;
  while (symbol < lengths.length) {
    if (lengths[symbol] > 0) writer.write(lengths[symbol++], 4);
    else {
      let run = 1;
      while (run < 256 && symbol + run < lengths.length && lengths[symbol + run] === 0) run++;
      writer.write(0, 4);
      writer.write(run - 1, 8);
      symbol += run;
    }
  }
}

function readTable(reader, symbols) {
  const lengths = [];
  while (lengths.length < symbols) {
    const length = reader.read(4);
    if (length > 0) lengths.push(length);
    else {
      const run = reader.read(8) + 1;
      if (lengths.length + run > symbols) throw new DecodingError('bad_table');
      for (let index = 0; index < run; index++) lengths.push(0);
    }
  }
  let used = 0;
  let singleLength = 0;
  let kraft = 0;
  for (const length of lengths) {
    if (length > 0) {
      used++;
      singleLength = length;
      kraft += 2 ** (15 - length);
    }
  }
  if ((used === 1 && singleLength !== 1) || (used >= 2 && kraft !== 32768)) throw new DecodingError('bad_table');
  return codebook(lengths);
}

function readSymbol(reader, table) {
  if (table.used === 0) throw new DecodingError('bad_code');
  let value = 0;
  for (let width = 1; width <= table.maximum; width++) {
    value = value * 2 + reader.read(1);
    const symbol = table.byLength[width].get(value);
    if (symbol !== undefined) return symbol;
  }
  throw new DecodingError('bad_code');
}

function writeLzhTokens(writer, tokens, literalTable, distanceTable) {
  for (const token of tokens) {
    const symbol = token.literal ?? 256 + token.length - 3;
    writer.write(literalTable.codes[symbol], literalTable.lengths[symbol]);
    if (token.literal !== undefined) continue;
    const offset = token.distance - 1;
    const slot = bits(offset);
    writer.write(distanceTable.codes[slot], distanceTable.lengths[slot]);
    if (slot >= 2) writer.write(offset - 2 ** (slot - 1), slot - 1);
  }
}

function encodeLzh(tokens, parameters) {
  const literalCount = 256 + 2 ** parameters.lengthBits;
  const distanceCount = parameters.offsetBits + 1;
  const literalFrequency = Array(literalCount).fill(0);
  const distanceFrequency = Array(distanceCount).fill(0);
  for (const token of tokens) {
    literalFrequency[token.literal ?? 256 + token.length - 3]++;
    if (token.literal === undefined) distanceFrequency[bits(token.distance - 1)]++;
  }
  const literalLengths = huffman.limitedLengths(literalFrequency, parameters.maxCodeLength);
  const distanceLengths = huffman.limitedLengths(distanceFrequency, parameters.maxCodeLength);
  const literalTable = codebook(literalLengths.lengths);
  const distanceTable = codebook(distanceLengths.lengths);
  const dynamic = new BitWriter();
  dynamic.write(1, 1);
  writeTable(dynamic, literalTable.lengths);
  writeTable(dynamic, distanceTable.lengths);
  const tableBits = dynamic.length - 1;
  writeLzhTokens(dynamic, tokens, literalTable, distanceTable);
  const codeBits = dynamic.length - 1 - tableBits;
  const fixed = new BitWriter();
  fixed.write(0, 1);
  writeLzhTokens(fixed, tokens, codebook(fixedLengths(literalCount)), codebook(fixedLengths(distanceCount)));
  const fixedBits = fixed.length - 1;
  const useFixed = fixedBits <= tableBits + codeBits;
  const statistics = {
    mode: useFixed ? 'fixed' : 'dynamic', fixedBits, tableBits, codeBits,
    halvings: literalLengths.halvings + distanceLengths.halvings,
    literalUsed: literalTable.used, literalMaximum: literalTable.maximum,
    distanceUsed: distanceTable.used, distanceMaximum: distanceTable.maximum,
    slots: distanceFrequency
  };
  return { payload: (useFixed ? fixed : dynamic).finish(), statistics };
}

function encodeLz77(tokens, parameters) {
  const writer = new BitWriter();
  for (const token of tokens) {
    if (token.literal !== undefined) {
      writer.write(0, 1);
      writer.write(token.literal, 8);
    } else {
      writer.write(1, 1);
      writer.write(token.distance - 1, parameters.offsetBits);
      writer.write(token.length - 3, parameters.lengthBits);
    }
  }
  return writer.finish();
}

function decodeLz77(payload, originalLength, parameters, output) {
  const reader = new BitReader(payload);
  while (output.length < originalLength) {
    if (reader.read(1) === 0) output.push(reader.read(8));
    else {
      const distance = reader.read(parameters.offsetBits) + 1;
      const length = reader.read(parameters.lengthBits) + 3;
      lz77.copyMatch(output, distance, length, originalLength);
    }
  }
}

function decodeLzh(payload, originalLength, parameters, output) {
  const reader = new BitReader(payload);
  const dynamic = reader.read(1) === 1;
  const literalCount = 256 + 2 ** parameters.lengthBits;
  const distanceCount = parameters.offsetBits + 1;
  const literalTable = dynamic ? readTable(reader, literalCount) : codebook(fixedLengths(literalCount));
  const distanceTable = dynamic ? readTable(reader, distanceCount) : codebook(fixedLengths(distanceCount));
  while (output.length < originalLength) {
    const symbol = readSymbol(reader, literalTable);
    if (symbol < 256) output.push(symbol);
    else {
      const slot = readSymbol(reader, distanceTable);
      const offset = slot >= 2 ? 2 ** (slot - 1) + reader.read(slot - 1) : slot;
      lz77.copyMatch(output, offset + 1, symbol - 253, originalLength);
    }
  }
}

function decodePayload(method, payload, originalLength, parameters) {
  const output = [];
  try {
    if (method === 0) {
      for (let index = 0; index < originalLength; index++) {
        if (index === payload.length) throw new DecodingError('end_of_data');
        output.push(payload[index]);
      }
    } else if (method === 1) lzw.decode(payload, originalLength, output);
    else if (method === 2) decodeLz77(payload, originalLength, parameters, output);
    else if (method === 3) decodeLzh(payload, originalLength, parameters, output);
    else arithmetic.decode(payload, originalLength, output);
  } catch (error) {
    if (!(error instanceof DecodingError)) throw error;
    return { error: error.kind, position: output.length };
  }
  return { data: Buffer.from(output) };
}

function adler32(data) {
  let low = 1;
  let high = 0;
  for (const byte of data) {
    low = (low + byte) % 65521;
    high = (high + low) % 65521;
  }
  return high * 65536 + low;
}

function modularPower(base, exponent) {
  let result = 1;
  while (exponent > 0) {
    if (exponent % 2 === 1) result = result * base % 65521;
    base = base * base % 65521;
    exponent = Math.floor(exponent / 2);
  }
  return result;
}

function repairByte(data, stored, computed) {
  const deltaA = ((stored % 65536 - computed % 65536) % 65521 + 65521) % 65521;
  const deltaB = ((Math.floor(stored / 65536) - Math.floor(computed / 65536)) % 65521 + 65521) % 65521;
  let delta;
  if (deltaA >= 1 && deltaA <= 255) delta = deltaA;
  else if (deltaA >= 65266 && deltaA <= 65520) delta = deltaA - 65521;
  else return null;
  const inverse = modularPower(deltaA, 65519);
  const distance = deltaB * inverse % 65521;
  if (distance < 1 || distance > data.length) return null;
  const position = data.length - distance;
  const before = data[position];
  const after = before + delta;
  if (after < 0 || after > 255) return null;
  const repaired = Buffer.from(data);
  repaired[position] = after;
  if (adler32(repaired) !== stored) return null;
  return { data: repaired, position, before, after };
}

function buildArchive(entries, parameters) {
  const header = Buffer.alloc(8);
  header.write('TXAR', 0, 'ascii');
  header[4] = parameters.offsetBits;
  header[5] = parameters.lengthBits;
  header.writeUInt16BE(entries.length, 6);
  const parts = [header];
  for (const entry of entries) {
    const name = Buffer.from(entry.name, 'ascii');
    const entryHeader = Buffer.alloc(15 + name.length);
    entryHeader[0] = name.length;
    name.copy(entryHeader, 1);
    entryHeader[1 + name.length] = entry.method;
    entryHeader.writeUInt32BE(entry.data.length, 2 + name.length);
    entryHeader.writeUInt32BE(entry.payload.length, 6 + name.length);
    entryHeader.writeUInt32BE(adler32(entry.data), 10 + name.length);
    let check = 0;
    for (let index = 0; index < entryHeader.length - 1; index++) check += entryHeader[index];
    entryHeader[entryHeader.length - 1] = check % 256;
    parts.push(entryHeader, entry.payload);
  }
  return Buffer.concat(parts);
}

function parseArchive(data) {
  const archive = { length: data.length, entries: [], stopped: false, trailing: 0, error: null };
  if (data.length < 8 || !data.subarray(0, 4).equals(Buffer.from('TXAR', 'ascii'))) {
    archive.error = 'bad_magic';
    return archive;
  }
  archive.offsetBits = data[4];
  archive.lengthBits = data[5];
  if (archive.offsetBits < 6 || archive.offsetBits > 12 || archive.lengthBits < 2 || archive.lengthBits > 5) {
    archive.error = 'bad_params';
    return archive;
  }
  archive.expected = data.readUInt16BE(6);
  let position = 8;
  for (let number = 1; number <= archive.expected; number++) {
    const entry = { number, offset: position, validHeader: false };
    archive.entries.push(entry);
    if (position >= data.length || position + 15 + data[position] > data.length) {
      entry.status = 'truncated';
      archive.stopped = true;
      break;
    }
    const nameLength = data[position];
    entry.name = data.subarray(position + 1, position + 1 + nameLength).toString('latin1');
    entry.method = data[position + 1 + nameLength];
    entry.original = data.readUInt32BE(position + 2 + nameLength);
    entry.compressed = data.readUInt32BE(position + 6 + nameLength);
    entry.adler = data.readUInt32BE(position + 10 + nameLength);
    entry.start = position + 15 + nameLength;
    const next = entry.start + entry.compressed;
    let check = 0;
    for (let index = position; index < entry.start - 1; index++) check += data[index];
    const validName = nameLength >= 1 && nameLength <= 32 && !/[^a-z0-9._-]/.test(entry.name);
    if (check % 256 !== data[entry.start - 1] || !validName) {
      entry.status = 'bad_header';
      position = next;
      if (position > data.length) {
        archive.stopped = true;
        break;
      }
      continue;
    }
    entry.validHeader = true;
    if (next > data.length) {
      entry.status = 'truncated';
      archive.stopped = true;
      break;
    }
    if (entry.method >= METHODS.length) entry.status = 'unsupported';
    else {
      const decoded = decodePayload(entry.method, data.subarray(entry.start, next), entry.original, archive);
      if (decoded.error) {
        entry.status = 'error';
        entry.error = decoded.error;
        entry.errorPosition = decoded.position;
      } else {
        entry.data = decoded.data;
        entry.computed = adler32(entry.data);
        if (entry.computed === entry.adler) entry.status = 'ok';
        else {
          entry.repair = repairByte(entry.data, entry.adler, entry.computed);
          entry.status = entry.repair ? 'repaired' : 'checksum';
          if (entry.repair) entry.data = entry.repair.data;
        }
      }
    }
    position = next;
  }
  if (!archive.stopped) archive.trailing = data.length - position;
  return archive;
}

function tokenStatistics(tokens) {
  const statistics = { tokens: tokens.length, literals: 0, matches: 0, matched: 0, longest: 0, farthest: 0 };
  for (const token of tokens) {
    if (token.literal !== undefined) statistics.literals++;
    else {
      statistics.matches++;
      statistics.matched += token.length;
      statistics.longest = Math.max(statistics.longest, token.length);
      statistics.farthest = Math.max(statistics.farthest, token.distance);
    }
  }
  return statistics;
}

function compress(data, parameters) {
  const tokens = lz77.tokenize(data, parameters.offsetBits, parameters.lengthBits);
  const dictionary = lzw.encode(data);
  const sliding = encodeLz77(tokens, parameters);
  const hybrid = encodeLzh(tokens, parameters);
  const arithmeticResult = arithmetic.encode(data);
  const payloads = [data, dictionary.payload, sliding, hybrid.payload, arithmeticResult.payload];
  let method = 0;
  for (let index = 1; index < METHODS.length; index++) if (payloads[index].length < payloads[method].length) method = index;
  return { payloads, method, payload: payloads[method], lzw: dictionary.statistics, lz77: tokenStatistics(tokens),
    lzh: hybrid.statistics, arith: arithmeticResult.statistics };
}

function verifiedEntries(archive, sources) {
  let verified = 0;
  for (const entry of archive.entries) {
    if (entry.status === 'ok' && entry.data.equals(sources[entry.number - 1].data)) verified++;
  }
  return verified;
}

function creationReports(files, parameters, archiveData, verification) {
  const sizes = [`params offset_bits ${parameters.offsetBits} length_bits ${parameters.lengthBits} window ${2 ** parameters.offsetBits} lookahead ${2 ** parameters.lengthBits + 2} max_code_length ${parameters.maxCodeLength}`];
  const analysis = [];
  const totals = Array(5).fill(0);
  const chosen = Array(5).fill(0);
  let original = 0;
  let best = 0;
  for (const file of files) {
    const encoded = file.encoded;
    const values = encoded.payloads.map(payload => payload.length);
    const methods = METHODS.map((name, method) => `${name} ${values[method]} ${ratio(values[method], file.data.length)}`).join(' ');
    sizes.push(`file ${file.name} original ${file.data.length} ${methods} best ${METHODS[encoded.method]}`);
    original += file.data.length;
    best += encoded.payload.length;
    chosen[encoded.method]++;
    for (let method = 0; method < 5; method++) totals[method] += values[method];
    const dictionary = encoded.lzw;
    analysis.push(`lzw ${file.name} codes ${dictionary.codes} clears ${dictionary.clears} widths ${dictionary.widths.join(' ')} longest ${dictionary.longest}`);
    const tokens = encoded.lz77;
    analysis.push(`lz77 ${file.name} tokens ${tokens.tokens} literals ${tokens.literals} matches ${tokens.matches} matched ${tokens.matched} longest ${tokens.longest} farthest ${tokens.farthest}`);
    const hybrid = encoded.lzh;
    analysis.push(`lzh ${file.name} mode ${hybrid.mode} fixed_bits ${hybrid.fixedBits} table_bits ${hybrid.tableBits} code_bits ${hybrid.codeBits} halvings ${hybrid.halvings} litlen_used ${hybrid.literalUsed} litlen_max ${hybrid.literalMaximum} offset_used ${hybrid.distanceUsed} offset_max ${hybrid.distanceMaximum}`);
    analysis.push(`slots ${file.name} ${hybrid.slots.join(' ')}`);
    analysis.push(`arith ${file.name} bits ${encoded.arith.bits} contexts ${encoded.arith.contexts} rescales ${encoded.arith.rescales}`);
  }
  sizes.push(`total original ${original} ${METHODS.map((name, method) => `${name} ${totals[method]} ${ratio(totals[method], original)}`).join(' ')} best ${best} ${ratio(best, original)}`);
  sizes.push(`chosen ${METHODS.map((name, method) => `${name} ${chosen[method]}`).join(' ')}`);
  sizes.push(`archive bytes ${archiveData.length} entries ${files.length} ratio ${ratio(archiveData.length, original)}`);
  sizes.push(`verify entries ${verification.entries.length} ok ${verifiedEntries(verification, files)}`);
  return { sizes, analysis };
}

function listingLines(archive) {
  if (archive.error) return [`archive bytes ${archive.length} error ${archive.error}`];
  const lines = [`archive bytes ${archive.length} offset_bits ${archive.offsetBits} length_bits ${archive.lengthBits} entries ${archive.expected}`];
  const totals = Array.from({ length: 5 }, () => ({ entries: 0, original: 0, compressed: 0 }));
  let listed = 0;
  for (const entry of archive.entries) {
    const prefix = `entry ${entry.number} offset ${entry.offset}`;
    if (!entry.validHeader) {
      lines.push(prefix + (entry.status === 'bad_header' ? ' bad_header' : ' truncated header'));
      continue;
    }
    listed++;
    lines.push(`${prefix} method ${methodName(entry.method)} original ${entry.original} compressed ${entry.compressed} ratio ${ratio(entry.compressed, entry.original)} adler ${hex32(entry.adler)} name ${entry.name}`);
    if (entry.method < 5) {
      const total = totals[entry.method];
      total.entries++;
      total.original += entry.original;
      total.compressed += entry.compressed;
    }
  }
  for (let method = 0; method < 5; method++) {
    const total = totals[method];
    lines.push(`method ${METHODS[method]} entries ${total.entries} original ${total.original} compressed ${total.compressed} ratio ${ratio(total.compressed, total.original)}`);
  }
  lines.push(`end listed ${listed} of ${archive.expected} stop ${archive.stopped ? 'truncated' : 'complete'} trailing ${archive.trailing}`);
  return lines;
}

function testLines(archive, salvaged, salvageData, salvageVerification) {
  const lines = [];
  if (archive.error) lines.push(`archive error ${archive.error}`);
  else {
    const counts = Object.fromEntries(STATUSES.map(status => [status, 0]));
    for (const entry of archive.entries) {
      counts[entry.status]++;
      const prefix = `entry ${entry.number} offset ${entry.offset}`;
      if (!entry.validHeader) {
        lines.push(prefix + (entry.status === 'bad_header' ? ' status bad_header' : ' status truncated header'));
        continue;
      }
      let details = '';
      if (entry.status === 'repaired') details = ` byte ${entry.repair.position} from ${entry.repair.before} to ${entry.repair.after}`;
      else if (entry.status === 'checksum') details = ` stored ${hex32(entry.adler)} computed ${hex32(entry.computed)}`;
      else if (entry.status === 'error') details = ` ${entry.error} at ${entry.errorPosition}`;
      else if (entry.status === 'truncated') details = ` payload have ${archive.length - entry.start} need ${entry.compressed}`;
      lines.push(`${prefix} name ${entry.name} method ${methodName(entry.method)} status ${entry.status}${details}`);
    }
    const statuses = STATUSES.map(status => `${status} ${counts[status]}`).join(' ');
    lines.push(`summary entries ${archive.expected} checked ${archive.entries.length} ${statuses} missing ${archive.expected - archive.entries.length} trailing ${archive.trailing}`);
  }
  let original = 0;
  for (const entry of salvaged) {
    original += entry.data.length;
    lines.push(`salvage ${entry.name} method ${METHODS[entry.method]} compressed ${entry.payload.length} was ${methodName(entry.source.method)} ${entry.source.compressed}`);
  }
  lines.push(`salvaged entries ${salvaged.length} bytes ${salvageData.length} original ${original} verified ${verifiedEntries(salvageVerification, salvaged)}`);
  return lines;
}

function textLines(data) {
  return data.length === 0 ? [] : data.toString('ascii').slice(0, -1).split('\n');
}

function extractionLines(intact) {
  const result = [];
  for (const entry of intact) {
    const lines = textLines(entry.data);
    let words = 0;
    let longest = 0;
    for (const line of lines) {
      words += line.split(' ').filter(Boolean).length;
      longest = Math.max(longest, line.length);
    }
    result.push(`file ${entry.name} bytes ${entry.data.length} lines ${lines.length} words ${words} longest ${longest}`);
    for (const line of lines) result.push(line);
  }
  return result;
}

function lineEdits(oldLines, newLines) {
  const oldCount = oldLines.length;
  const newCount = newLines.length;
  const deletion = Array(oldCount);
  let later = new Uint32Array(newCount + 1);
  // Keep LCS lengths in two rows and retain only the deletion/addition decisions.
  for (let old = oldCount - 1; old >= 0; old--) {
    const current = new Uint32Array(newCount + 1);
    deletion[old] = new Uint8Array(Math.ceil(newCount / 8));
    for (let next = newCount - 1; next >= 0; next--) {
      if (oldLines[old] === newLines[next]) current[next] = later[next + 1] + 1;
      else if (later[next] >= current[next + 1]) {
        current[next] = later[next];
        deletion[old][Math.floor(next / 8)] |= 2 ** (next % 8);
      } else current[next] = current[next + 1];
    }
    later = current;
  }
  let old = 0;
  let next = 0;
  let removed = 0;
  let added = 0;
  const edits = [];
  while (old < oldCount || next < newCount) {
    if (old < oldCount && next < newCount && oldLines[old] === newLines[next]) {
      old++;
      next++;
    } else if (next === newCount || (old < oldCount && (deletion[old][Math.floor(next / 8)] & 2 ** (next % 8)) !== 0)) {
      edits.push(`-${old + 1}:${oldLines[old]}`);
      old++;
      removed++;
    } else {
      edits.push(`+${next + 1}:${newLines[next]}`);
      next++;
      added++;
    }
  }
  return { edits, removed, added };
}

function comparisonLines(intact, files) {
  const manifest = new Map(files.map(file => [file.name, file]));
  const present = new Set();
  const lines = [];
  for (const entry of intact) {
    present.add(entry.name);
    const file = manifest.get(entry.name);
    if (!file) {
      lines.push(`archive_only ${entry.name}`);
      continue;
    }
    const oldLines = textLines(entry.data);
    const newLines = textLines(file.data);
    let first = 0;
    while (first < oldLines.length && first < newLines.length && oldLines[first] === newLines[first]) first++;
    if (first === oldLines.length && first === newLines.length) lines.push(`same ${entry.name} lines ${oldLines.length}`);
    else {
      const changes = lineEdits(oldLines, newLines);
      lines.push(`differs ${entry.name} first_line ${first + 1} archive_lines ${oldLines.length} manifest_lines ${newLines.length} removed ${changes.removed} added ${changes.added}`);
      for (const edit of changes.edits) lines.push(edit);
    }
  }
  for (const file of files) if (!present.has(file.name)) lines.push(`new ${file.name}`);
  return lines;
}

function hexLines(data) {
  const lines = [];
  for (let offset = 0; offset < data.length; offset += 32) lines.push(data.subarray(offset, offset + 32).toString('hex'));
  return lines;
}

function writeLines(filename, lines) {
  fs.writeFileSync(`output/${filename}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

function main() {
  const manifest = readLines('input/manifest.txt');
  const parameters = { offsetBits: Number(manifest[0].split(' ')[1]), lengthBits: Number(manifest[1].split(' ')[1]),
    maxCodeLength: Number(manifest[2].split(' ')[1]) };
  const files = manifest.slice(3).map(line => {
    const name = line.slice(5);
    const data = fs.readFileSync(`input/files/${name}`);
    return { name, data, encoded: compress(data, parameters) };
  });
  const createdEntries = files.map(file => ({ name: file.name, data: file.data, method: file.encoded.method, payload: file.encoded.payload }));
  const archiveData = buildArchive(createdEntries, parameters);
  const verification = parseArchive(archiveData);
  const reports = creationReports(files, parameters, archiveData, verification);
  const supplied = Buffer.from(readLines('input/archive.hex').join(''), 'hex');
  const archive = parseArchive(supplied);
  const intact = archive.entries.filter(entry => entry.status === 'ok' || entry.status === 'repaired');
  const salvageParameters = archive.error ? parameters : { offsetBits: archive.offsetBits, lengthBits: archive.lengthBits, maxCodeLength: parameters.maxCodeLength };
  const salvaged = intact.map(entry => {
    const encoded = compress(entry.data, salvageParameters);
    return { name: entry.name, data: entry.data, method: encoded.method, payload: encoded.payload, source: entry };
  });
  const salvageData = buildArchive(salvaged, salvageParameters);
  const salvageVerification = parseArchive(salvageData);
  fs.mkdirSync('output', { recursive: true });
  writeLines('sizes.txt', reports.sizes);
  writeLines('analysis.txt', reports.analysis);
  writeLines('archive.hex', hexLines(archiveData));
  writeLines('listing.txt', listingLines(archive));
  writeLines('test_report.txt', testLines(archive, salvaged, salvageData, salvageVerification));
  writeLines('extracted.txt', extractionLines(intact));
  writeLines('compare.txt', comparisonLines(intact, files));
  writeLines('salvaged.hex', hexLines(salvageData));
}

if (require.main === module) main();
