'use strict';

const fs = require('node:fs');
const { ALPHANUMERIC, append, fromCodewords, toCodewords, BitReader, binary } = require('./bitstream');
const reedSolomon = require('./reed_solomon');
const matrix = require('./matrix');
const masking = require('./masking');
const render = require('./render');

const MODES = ['NUMERIC', 'ALPHANUMERIC', 'BYTE'], LEVELS = ['L', 'M', 'Q', 'H'];
const INDICATORS = { NUMERIC: 1, ALPHANUMERIC: 2, BYTE: 4 };
const readLines = path => fs.readFileSync(path, 'ascii').split('\n').slice(0, -1);
const copy = grid => grid.map(row => row.slice());
const hexadecimal = values => values.map(value => value.toString(16).padStart(2, '0')).join('');
const writeLines = (path, lines) => fs.writeFileSync(path, lines.length ? lines.join('\n') + '\n' : '', 'ascii');

function placementOrder(lengths, degree) {
  const order = [], maximum = Math.max(...lengths);
  for (let i = 0; i < maximum; i++) {
    for (let block = 0; block < lengths.length; block++) if (i < lengths[block]) order.push([block, i]);
  }
  for (let i = 0; i < degree; i++) {
    for (let block = 0; block < lengths.length; block++) order.push([block, lengths[block] + i]);
  }
  return order;
}

function readInputs() {
  const requests = readLines('input/requests.txt').map(line => {
    const separator = line.indexOf(':'), [id, level, mode, version, mask] = line.slice(0, separator).split(' ');
    return { id, level, mode, version, mask, text: line.slice(separator + 1) };
  });
  const [quiet, scale] = readLines('input/params.txt').map(line => Number(line.split(' ')[1]));
  const tables = Array.from({ length: 11 }, () => ({ blocks: {}, centers: [] }));
  for (const line of readLines('input/tables.txt')) {
    const fields = line.split(' '), version = Number(fields[1]);
    if (fields[0] === 'align') tables[version].centers = fields.slice(2).map(Number);
    else {
      const [e, b1, k1, b2, k2] = fields.slice(3).map(Number);
      const lengths = Array(b1).fill(k1).concat(Array(b2).fill(k2)), data = b1 * k1 + b2 * k2;
      tables[version].blocks[fields[2]] = { e, lengths, data, total: data + e * lengths.length,
        placement: placementOrder(lengths, e) };
    }
  }
  for (let version = 1; version <= 10; version++) tables[version].layout = matrix.create(version, tables[version].centers);
  const damage = new Map();
  for (const line of readLines('input/damage.txt')) {
    const [id, kind, ...args] = line.split(' ');
    if (!damage.has(id)) damage.set(id, []);
    damage.get(id).push({ kind, args });
  }
  const scanLines = readLines('input/scans.txt'), scans = [];
  for (let i = 0; i < scanLines.length;) {
    const name = scanLines[i++].split(' ')[1], size = scanLines[i].length;
    const grid = scanLines.slice(i, i + size).map(line => Array.from(line, character => character === '#' ? 1 : 0));
    scans.push({ name, grid }); i += size;
  }
  return { requests, quiet, scale, tables, damage, scans };
}

function encodable(character, mode) {
  if (mode === 'NUMERIC') return character >= '0' && character <= '9';
  if (mode === 'ALPHANUMERIC') return ALPHANUMERIC.includes(character);
  return true;
}

function countWidth(mode, version) {
  if (version <= 9) return { NUMERIC: 10, ALPHANUMERIC: 9, BYTE: 8 }[mode];
  return { NUMERIC: 12, ALPHANUMERIC: 11, BYTE: 16 }[mode];
}

function dataWidth(mode, count) {
  if (mode === 'NUMERIC') return 10 * Math.floor(count / 3) + [0, 4, 7][count % 3];
  if (mode === 'ALPHANUMERIC') return 11 * Math.floor(count / 2) + 6 * (count % 2);
  return 8 * count;
}

function splitSegments(text, mode, version) {
  if (mode !== 'MIXED') {
    return { segments: [{ mode, text }], bits: 4 + countWidth(mode, version) + dataWidth(mode, text.length) };
  }
  const invalid = MODES.map(candidate => {
    const prefix = [0];
    for (const character of text) prefix.push(prefix[prefix.length - 1] + (encodable(character, candidate) ? 0 : 1));
    return prefix;
  });
  const costs = [0], choices = [null];
  for (let i = 1; i <= text.length; i++) {
    let best = null, choice = null;
    for (let j = 0; j < i; j++) for (let m = 0; m < MODES.length; m++) {
      if (invalid[m][i] !== invalid[m][j]) continue;
      const candidate = MODES[m], cost = costs[j] + 4 + countWidth(candidate, version) + dataWidth(candidate, i - j);
      if (best === null || cost < best) { best = cost; choice = { start: j, mode: candidate }; }
    }
    costs.push(best); choices.push(choice);
  }
  const segments = [];
  for (let i = text.length; i > 0;) {
    const choice = choices[i];
    segments.push({ mode: choice.mode, text: text.slice(choice.start, i) }); i = choice.start;
  }
  return { segments: segments.reverse(), bits: costs[text.length] };
}

function resolveRequest(request, tables) {
  if (!LEVELS.some(level => request.level === level || request.level === level + '+')) return { error: 'level ' + request.level };
  if (![...MODES, 'AUTO', 'MIXED'].includes(request.mode)) return { error: 'mode ' + request.mode };
  if (!/^(AUTO|[1-9]|10)$/.test(request.version)) return { error: 'version ' + request.version };
  if (!/^(AUTO|[0-7])$/.test(request.mask)) return { error: 'mask ' + request.mask };
  if (request.text.length === 0) return { error: 'text' };
  if (request.mode === 'NUMERIC' || request.mode === 'ALPHANUMERIC') {
    for (let i = 0; i < request.text.length; i++) {
      if (!encodable(request.text[i], request.mode)) return { error: 'charset position ' + i };
    }
  }
  const mode = request.mode === 'AUTO' ? MODES.find(candidate => Array.from(request.text).every(character => encodable(character, candidate))) : request.mode;
  const cache = new Map();
  const split = (candidate, version) => {
    const key = candidate + '/' + (version === 10 ? 10 : 1);
    if (!cache.has(key)) cache.set(key, splitSegments(request.text, candidate, version));
    return cache.get(key);
  };
  const candidates = request.version === 'AUTO' ? Array.from({ length: 10 }, (_, i) => i + 1) : [Number(request.version)];
  const base = request.level[0];
  let version = null;
  for (const candidate of candidates) {
    if (split(mode, candidate).bits <= 8 * tables[candidate].blocks[base].data) { version = candidate; break; }
  }
  if (version === null) {
    const last = candidates[candidates.length - 1];
    return { error: `capacity bits ${split(mode, last).bits} capacity ${8 * tables[last].blocks[base].data}` };
  }
  const selected = split(mode, version);
  let level = base;
  if (request.level.endsWith('+')) {
    for (const candidate of LEVELS.slice(LEVELS.indexOf(base))) {
      if (selected.bits <= 8 * tables[version].blocks[candidate].data) level = candidate;
    }
  }
  return { request, mode, version, level, split, ...selected, table: tables[version].blocks[level], layout: tables[version].layout };
}

function groups(text, mode) {
  const size = mode === 'NUMERIC' ? 3 : mode === 'ALPHANUMERIC' ? 2 : 1, result = [];
  for (let i = 0; i < text.length; i += size) {
    const characters = text.slice(i, i + size);
    let value;
    if (mode === 'NUMERIC') value = Number(characters);
    else if (mode === 'ALPHANUMERIC') {
      value = ALPHANUMERIC.indexOf(characters[0]);
      if (characters.length === 2) value = 45 * value + ALPHANUMERIC.indexOf(characters[1]);
    } else value = characters.charCodeAt(0);
    result.push({ characters, value, width: dataWidth(mode, characters.length) });
  }
  return result;
}

function pad(bits, capacity) {
  const padded = bits.slice(), terminator = Math.min(4, capacity - bits.length);
  for (let i = 0; i < terminator; i++) padded.push(0);
  let zeroFill = 0, padBytes = 0;
  while (padded.length % 8 !== 0) { padded.push(0); zeroFill++; }
  while (padded.length < capacity) { append(padded, padBytes % 2 === 0 ? 0xec : 0x11, 8); padBytes++; }
  return { bits: padded, terminator, zeroFill, padBytes };
}

function encodeRequest(resolved) {
  const { request, version, level, segments, table, layout } = resolved, capacity = 8 * table.data;
  const bits = [], bitLines = [`request ${request.id} version ${version} bits ${resolved.bits} capacity ${capacity}`];
  for (const segment of segments) {
    const width = countWidth(segment.mode, version), indicator = INDICATORS[segment.mode];
    append(bits, indicator, 4); append(bits, segment.text.length, width);
    bitLines.push(`segment ${segment.mode} indicator ${binary(indicator, 4)} count ${segment.text.length} ${binary(segment.text.length, width)}`);
    for (const group of groups(segment.text, segment.mode)) {
      append(bits, group.value, group.width);
      bitLines.push(`group ${group.value} ${binary(group.value, group.width)} "${group.characters}"`);
    }
  }
  const padded = pad(bits, capacity), data = toCodewords(padded.bits);
  bitLines.push(`terminator ${padded.terminator} zero_fill ${padded.zeroFill} pad_bytes ${padded.padBytes}`);
  const blocks = [];
  let offset = 0;
  for (const length of table.lengths) {
    const blockData = data.slice(offset, offset + length), ec = reedSolomon.encode(blockData, table.e);
    blocks.push({ data: blockData, ec, words: blockData.concat(ec) }); offset += length;
  }
  const interleaved = table.placement.map(([block, position]) => blocks[block].words[position]);
  const placedBits = fromCodewords(interleaved), unmasked = copy(layout.grid);
  layout.order.forEach(([x, y], i) => { unmasked[y][x] = i < placedBits.length ? placedBits[i] : 0; });
  const symbols = [], penalties = [];
  for (let mask = 0; mask < 8; mask++) {
    const grid = masking.apply(unmasked, layout.areas, mask), information = matrix.formatInformation(level, mask);
    for (const positions of layout.locations.format) matrix.writeValue(grid, positions, information);
    symbols.push(grid); penalties.push(masking.penalties(grid));
  }
  let mask = request.mask === 'AUTO' ? 0 : Number(request.mask);
  if (request.mask === 'AUTO') for (let candidate = 1; candidate < 8; candidate++) {
    if (penalties[candidate].total < penalties[mask].total) mask = candidate;
  }
  return { ...resolved, blocks, interleaved, bitLines, penalties, mask, grid: symbols[mask], dark: penalties[mask].dark };
}

function generationReports(encoded, tables, output) {
  const { request, version, level, mode, segments, bits, split, table, layout, mask, penalties, blocks, interleaved } = encoded;
  const alternatives = MODES.map(candidate => Array.from(request.text).every(character => encodable(character, candidate)) ?
    4 + countWidth(candidate, version) + dataWidth(candidate, request.text.length) : '-');
  const fits = LEVELS.map(candidate => {
    for (let v = 1; v <= 10; v++) if (split(mode, v).bits <= 8 * tables[v].blocks[candidate].data) return v;
    return '-';
  });
  output.codes.push(`symbol version ${version} level ${level} mask ${mask} size ${layout.size}`,
    `segments ${segments.length} ${segments.map(segment => segment.mode + ':' + segment.text.length).join(' ')}`,
    `bits data ${bits} capacity ${8 * table.data} alternatives NUMERIC ${alternatives[0]} ALPHANUMERIC ${alternatives[1]} BYTE ${alternatives[2]} MIXED ${split('MIXED', version).bits}`,
    `fits L ${fits[0]} M ${fits[1]} Q ${fits[2]} H ${fits[3]}`,
    `modules function ${layout.functionCount} data ${layout.order.length} remainder ${layout.order.length - 8 * table.total} dark ${encoded.dark}`,
    `format ${binary(matrix.formatInformation(level, mask), 15)} version ${version >= 7 ? binary(matrix.versionInformation(version), 18) : 'none'}`);
  penalties.forEach((penalty, m) => output.codes.push(`penalty ${m} n1 ${penalty.n1} n2 ${penalty.n2} n3 ${penalty.n3} n4 ${penalty.n4} total ${penalty.total}`));
  output.codes.push(...render.symbolLines(encoded.grid));
  output.codewords.push(`request ${request.id} version ${version} level ${level} blocks ${blocks.length} data ${table.data} ec_per_block ${table.e} total ${table.total}`);
  blocks.forEach((block, b) => output.codewords.push(`block ${b} data ${hexadecimal(block.data)}`, `block ${b} ec ${hexadecimal(block.ec)}`));
  output.codewords.push('interleaved ' + hexadecimal(interleaved));
  output.bitstream.push(...encoded.bitLines);
}

function readImage(text) {
  const lines = text.split('\n'), [width, height] = lines[1].split(' ').map(Number);
  const pixels = lines.slice(2, 2 + height);
  let left = width, right = -1, top = height;
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    if (pixels[y][x] === '1') { left = Math.min(left, x); right = Math.max(right, x); top = Math.min(top, y); }
  }
  let run = 0;
  while (left + run < width && pixels[top][left + run] === '1') run++;
  const scale = Math.floor(run / 7), size = Math.floor((right - left + 1) / scale);
  const grid = Array.from({ length: size }, (_, y) =>
    Array.from({ length: size }, (_, x) => pixels[top + scale * y][left + scale * x] === '1' ? 1 : 0));
  let wellFormed = true;
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const expected = x >= left && x < left + scale * size && y >= top && y < top + scale * size ?
      grid[Math.floor((y - top) / scale)][Math.floor((x - left) / scale)] : 0;
    if (Number(pixels[y][x]) !== expected) wellFormed = false;
  }
  return { width, height, quiet: Math.floor(left / scale), scale, size, grid, wellFormed };
}

function rotate(grid) {
  const size = grid.length;
  return Array.from({ length: size }, (_, y) => Array.from({ length: size }, (_, x) => grid[size - 1 - x][y]));
}

function transpose(grid) {
  return grid.map((row, y) => row.map((value, x) => grid[x][y]));
}

function hamming(first, second) {
  let value = first ^ second, distance = 0;
  while (value !== 0) { distance += value & 1; value >>>= 1; }
  return distance;
}

const FORMAT_VALUES = LEVELS.flatMap(level => Array.from({ length: 8 }, (_, mask) =>
  ({ level, mask, value: matrix.formatInformation(level, mask) })));
const VERSION_VALUES = Array.from({ length: 34 }, (_, i) =>
  ({ version: i + 7, value: matrix.versionInformation(i + 7) }));

function nearest(value, candidates) {
  let best = null;
  for (const candidate of candidates) {
    const distance = hamming(value, candidate.value);
    if (best === null || distance < best.distance) best = { ...candidate, distance };
  }
  return best;
}

function parseData(bits, version) {
  const reader = new BitReader(bits), lines = [], characters = [];
  let end = 0;
  while (reader.remaining >= 4) {
    const indicator = reader.read(4);
    if (indicator === 0) break;
    const mode = { 1: 'NUMERIC', 2: 'ALPHANUMERIC', 4: 'BYTE' }[indicator];
    if (mode === undefined) {
      lines.push('parse failed indicator ' + binary(indicator, 4));
      return { success: false, lines };
    }
    const width = countWidth(mode, version);
    if (reader.remaining < width) {
      lines.push('parse failed length ' + mode); return { success: false, lines };
    }
    const count = reader.read(width);
    if (reader.remaining < dataWidth(mode, count)) {
      lines.push('parse failed length ' + mode); return { success: false, lines };
    }
    let remaining = count, segment = '';
    while (remaining > 0) {
      const size = Math.min(remaining, mode === 'NUMERIC' ? 3 : mode === 'ALPHANUMERIC' ? 2 : 1);
      const value = reader.read(dataWidth(mode, size));
      let valid = true, group = '';
      if (mode === 'NUMERIC') {
        valid = value < 10 ** size;
        if (valid) group = String(value).padStart(size, '0');
      } else if (mode === 'ALPHANUMERIC') {
        valid = value < (size === 2 ? 2025 : 45);
        if (valid) group = size === 2 ? ALPHANUMERIC[Math.floor(value / 45)] + ALPHANUMERIC[value % 45] : ALPHANUMERIC[value];
      } else {
        valid = value >= 32 && value <= 126;
        if (valid) group = String.fromCharCode(value);
      }
      if (!valid) { lines.push('parse failed value ' + mode); return { success: false, lines }; }
      segment += group; remaining -= size;
    }
    characters.push(segment); end = reader.position;
    lines.push(`segment ${mode} ${count}`);
  }
  const expected = pad(bits.slice(0, end), bits.length).bits, text = characters.join('');
  const paddingOK = expected.every((value, i) => value === bits[i]);
  lines.push('padding ' + (paddingOK ? 'ok' : 'bad'), `text "${text}"`);
  return { success: true, text, lines };
}

function attempt(grid, tables) {
  const version = (grid.length - 17) / 4, locations = matrix.positions(grid.length), lines = [], blocks = [];
  const fail = () => ({ success: false, lines, blocks });
  const format = locations.format.map(positions => matrix.readValue(grid, positions));
  const formats = format.map(value => nearest(value, FORMAT_VALUES));
  const chosen = formats[1].distance < formats[0].distance ? formats[1] : formats[0];
  const formatPrefix = `format ${binary(format[0], 15)} ${binary(format[1], 15)} distance ${formats[0].distance} ${formats[1].distance}`;
  if (chosen.distance > 3) { lines.push(formatPrefix + ' unreadable'); return fail(); }
  lines.push(formatPrefix + ` level ${chosen.level} mask ${chosen.mask}`);
  if (version >= 7) {
    const information = locations.version.map(positions => matrix.readValue(grid, positions));
    const versions = information.map(value => nearest(value, VERSION_VALUES));
    const decoded = versions[1].distance < versions[0].distance ? versions[1] : versions[0];
    const prefix = `version ${binary(information[0], 18)} ${binary(information[1], 18)} distance ${versions[0].distance} ${versions[1].distance}`;
    if (decoded.distance > 3) { lines.push(prefix + ' unreadable'); return fail(); }
    lines.push(prefix + ' decoded ' + decoded.version);
    if (decoded.version !== version) return fail();
  }
  const layout = tables[version].layout, table = tables[version].blocks[chosen.level];
  const unmasked = masking.apply(grid, layout.areas, chosen.mask);
  const bits = layout.order.slice(0, 8 * table.total).map(([x, y]) => unmasked[y][x]);
  const codewords = toCodewords(bits), received = table.lengths.map(length => Array(length + table.e).fill(0));
  table.placement.forEach(([block, position], i) => { received[block][position] = codewords[i]; });
  for (let block = 0; block < received.length; block++) {
    const result = reedSolomon.correct(received[block], table.e);
    blocks.push(result);
    let suffix = result.status;
    if (result.status === 'corrected') suffix += ' ' + result.positions.join(' ');
    lines.push(`block ${block} syndromes ${hexadecimal(result.syndromes)} ${suffix}`);
  }
  if (blocks.some(block => block.status === 'failed')) return fail();
  const data = [];
  blocks.forEach((block, b) => data.push(...block.codewords.slice(0, table.lengths[b])));
  const parsed = parseData(fromCodewords(data), version);
  lines.push(...parsed.lines);
  return { success: parsed.success, text: parsed.text, lines, blocks };
}

function decode(grid, tables) {
  const size = grid.length, corners = [[size - 7, size - 7], [size - 7, 0], [0, 0], [0, size - 7]];
  const scores = corners.map(([x0, y0]) => {
    let score = 0;
    for (let y = 0; y < 7; y++) for (let x = 0; x < 7; x++) {
      const expected = Math.max(Math.abs(x - 3), Math.abs(y - 3)) === 2 ? 0 : 1;
      if (grid[y0 + y][x0 + x] === expected) score++;
    }
    return score;
  });
  let rotations = 0;
  for (let k = 1; k < 4; k++) if (scores[k] < scores[rotations]) rotations = k;
  let oriented = grid;
  for (let k = 0; k < rotations; k++) oriented = rotate(oriented);
  let adopted = attempt(oriented, tables), mirrored = false;
  if (!adopted.success) {
    const retry = attempt(transpose(oriented), tables);
    if (retry.success) { adopted = retry; mirrored = true; }
  }
  return { ...adopted, lines: [`orientation rotations ${rotations} mirrored ${mirrored ? 'yes' : 'no'}`, ...adopted.lines] };
}

function damageSymbol(encoded, operations) {
  let grid = copy(encoded.grid);
  for (const { kind, args } of operations) {
    if (kind === 'flip') {
      const [x, y] = args.map(Number); grid[y][x] ^= 1;
    } else if (kind === 'fill') {
      const [x, y, width, height] = args.slice(0, 4).map(Number), color = args[4] === 'dark' ? 1 : 0;
      for (let dy = 0; dy < height; dy++) for (let dx = 0; dx < width; dx++) grid[y + dy][x + dx] = color;
    }
  }
  const { layout, table } = encoded;
  const indices = Array.from({ length: layout.size }, () => Array(layout.size).fill(-1));
  layout.order.forEach(([x, y], i) => { indices[y][x] = i; });
  const counts = { changed: 0, function: 0, format: 0, version: 0, data: 0, remainder: 0 };
  const errors = table.lengths.map(() => new Set());
  for (let y = 0; y < layout.size; y++) for (let x = 0; x < layout.size; x++) {
    if (grid[y][x] === encoded.grid[y][x]) continue;
    counts.changed++;
    const area = layout.areas[y][x];
    if (area !== 'data') counts[area]++;
    else if (indices[y][x] >= 8 * table.total) counts.remainder++;
    else {
      counts.data++;
      const [block, position] = table.placement[Math.floor(indices[y][x] / 8)];
      errors[block].add(position);
    }
  }
  for (const { kind } of operations) {
    if (kind === 'rotate') grid = rotate(grid);
    else if (kind === 'mirror') grid = transpose(grid);
  }
  return { grid, counts, errors: errors.map(positions => positions.size) };
}

function tolerance(encoded, tables, color) {
  const size = encoded.layout.size;
  for (let side = 1; side <= size; side++) {
    const start = Math.floor((size - side) / 2), grid = copy(encoded.grid);
    for (let y = start; y < start + side; y++) for (let x = start; x < start + side; x++) grid[y][x] = color;
    const result = decode(grid, tables);
    if (!result.success || result.text !== encoded.request.text) return side - 1;
  }
  return size;
}

function capacityReport(tables) {
  const lines = [];
  for (let version = 1; version <= 10; version++) {
    const { layout, centers, blocks } = tables[version], total = blocks.L.total;
    lines.push(`version ${version} size ${layout.size} data_modules ${layout.order.length} codewords ${total} remainder ${layout.order.length - 8 * total} alignment ${centers.length ? centers.join(' ') : 'none'}`);
    for (const level of LEVELS) {
      const table = blocks[level], capacity = 8 * table.data;
      const maxima = MODES.map(mode => {
        let count = 0;
        while (4 + countWidth(mode, version) + dataWidth(mode, count + 1) <= capacity) count++;
        return count;
      });
      lines.push(`level ${level} blocks ${table.lengths.length} data ${table.data} ec_per_block ${table.e} numeric ${maxima[0]} alphanumeric ${maxima[1]} byte ${maxima[2]}`);
    }
  }
  return lines;
}

function newSummary() {
  return { encoded: 0, errorCount: 0, errors: { level: 0, mode: 0, version: 0, mask: 0, text: 0, charset: 0, capacity: 0 },
    modes: { NUMERIC: 0, ALPHANUMERIC: 0, BYTE: 0, MIXED: 0 }, levels: { L: 0, M: 0, Q: 0, H: 0 }, boosted: 0,
    versions: Array(10).fill(0), masks: Array(8).fill(0), segments: 0, dataCodewords: 0, ecCodewords: 0, modules: 0, dark: 0,
    checks: { total: 0, ok: 0, mismatch: 0, failed: 0 }, blocks: { ok: 0, corrected: 0, failed: 0, codewords: 0 },
    scans: { decoded: 0, failed: 0 } };
}

function countEncoding(encoded, summary) {
  summary.encoded++; summary.modes[encoded.mode]++; summary.levels[encoded.level]++;
  if (encoded.level !== encoded.request.level[0]) summary.boosted++;
  summary.versions[encoded.version - 1]++; summary.masks[encoded.mask]++;
  summary.segments += encoded.segments.length; summary.dataCodewords += encoded.table.data;
  summary.ecCodewords += encoded.table.e * encoded.table.lengths.length;
  summary.modules += encoded.layout.size * encoded.layout.size; summary.dark += encoded.dark;
}

function countCheck(decoded, expected, summary) {
  const result = !decoded.success ? 'failed' : decoded.text === expected ? 'ok' : 'mismatch';
  summary.checks.total++; summary.checks[result]++;
  for (const block of decoded.blocks) {
    summary.blocks[block.status]++;
    if (block.status === 'corrected') summary.blocks.codewords += block.positions.length;
  }
  return result;
}

function selfCheck(encoded, input, summary, lines) {
  const path = 'output/qr_' + encoded.request.id + '.pbm';
  fs.writeFileSync(path, render.pbm(encoded.grid, input.quiet, input.scale), 'ascii');
  const image = readImage(fs.readFileSync(path, 'ascii')), clean = decode(image.grid, input.tables);
  lines.push('request ' + encoded.request.id,
    `image ${image.width} ${image.height} quiet ${image.quiet} scale ${image.scale} size ${image.size} ${image.wellFormed ? 'ok' : 'bad'}`,
    'check clean', ...clean.lines, 'result ' + countCheck(clean, encoded.request.text, summary));
  if (input.damage.has(encoded.request.id)) {
    const operations = input.damage.get(encoded.request.id), damaged = damageSymbol(encoded, operations);
    const result = decode(damaged.grid, input.tables), counts = damaged.counts;
    lines.push(`check damaged operations ${operations.length}`,
      `damage changed ${counts.changed} function ${counts.function} format ${counts.format} version ${counts.version} data ${counts.data} remainder ${counts.remainder}`,
      `errors ${damaged.errors.join(' ')} limit ${Math.floor(encoded.table.e / 2)}`,
      ...result.lines, 'result ' + countCheck(result, encoded.request.text, summary));
  }
  const light = tolerance(encoded, input.tables, 0), dark = tolerance(encoded, input.tables, 1);
  lines.push(`tolerance light ${light} dark ${dark}`);
}

function summaryReport(input, summary) {
  const errorKinds = ['level', 'mode', 'version', 'mask', 'text', 'charset', 'capacity'];
  const { checks, blocks, scans } = summary;
  return [`requests ${input.requests.length} encoded ${summary.encoded} errors ${summary.errorCount}`,
    'error_kinds ' + errorKinds.map(kind => kind + ' ' + summary.errors[kind]).join(' '),
    'modes ' + [...MODES, 'MIXED'].map(mode => mode + ' ' + summary.modes[mode]).join(' '),
    'levels ' + LEVELS.map(level => level + ' ' + summary.levels[level]).join(' ') + ' boosted ' + summary.boosted,
    'versions ' + summary.versions.join(' '), 'masks ' + summary.masks.join(' '),
    `segments ${summary.segments} data_codewords ${summary.dataCodewords} ec_codewords ${summary.ecCodewords}`,
    `modules ${summary.modules} dark ${summary.dark}`,
    `checks ${checks.total} ok ${checks.ok} mismatch ${checks.mismatch} failed ${checks.failed}`,
    `blocks ok ${blocks.ok} corrected ${blocks.corrected} failed ${blocks.failed} codewords ${blocks.codewords}`,
    `scans ${input.scans.length} decoded ${scans.decoded} failed ${scans.failed}`];
}

function main() {
  const input = readInputs(), summary = newSummary();
  const output = { codes: [], codewords: [], bitstream: [], selfcheck: [], scans: [], capacity: [], summary: [] };
  fs.mkdirSync('output', { recursive: true });
  for (const request of input.requests) {
    output.codes.push('request ' + request.id);
    const resolved = resolveRequest(request, input.tables);
    if (resolved.error) {
      output.codes.push('error ' + resolved.error);
      summary.errorCount++; summary.errors[resolved.error.split(' ')[0]]++;
      continue;
    }
    const encoded = encodeRequest(resolved);
    generationReports(encoded, input.tables, output);
    countEncoding(encoded, summary);
    selfCheck(encoded, input, summary, output.selfcheck);
  }
  for (const scan of input.scans) {
    const decoded = decode(scan.grid, input.tables), result = decoded.success ? 'decoded' : 'failed';
    output.scans.push(`scan ${scan.name} size ${scan.grid.length}`, ...decoded.lines, 'result ' + result);
    summary.scans[result]++;
  }
  output.capacity = capacityReport(input.tables);
  output.summary = summaryReport(input, summary);
  for (const name of ['codes', 'codewords', 'bitstream', 'selfcheck', 'scans', 'capacity', 'summary']) {
    writeLines('output/' + name + '.txt', output[name]);
  }
}

main();
