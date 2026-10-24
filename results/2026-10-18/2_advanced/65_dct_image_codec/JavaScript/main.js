'use strict';

const io = require('./image_io');
const color = require('./color');
const dct = require('./dct');
const entropy = require('./entropy');
const { Writer, Reader, DecodeError } = require('./bitstream');

const COMPONENT_NAMES = ['Y', 'Cb', 'Cr'];
const TABLE_NAMES = ['dc_luma', 'ac_luma', 'dc_chroma', 'ac_chroma'];
const TABLE_KEYS = [[0, 0], [1, 0], [0, 1], [1, 1]];
const word = value => [Math.floor(value / 256), value % 256];
const tableKey = (tableClass, id) => 16 * tableClass + id;

function geometry(width, height, components, restart) {
  const hMax = Math.max(...components.map(component => component.h));
  const vMax = Math.max(...components.map(component => component.v));
  const mx = Math.ceil(width / (8 * hMax)), my = Math.ceil(height / (8 * vMax));
  const blocks = [];
  for (let mcu = 0; mcu < mx * my; mcu++) components.forEach((component, k) => {
    for (let v = 0; v < component.v; v++) for (let h = 0; h < component.h; h++) {
      blocks.push({ number: blocks.length, mcu, component: k,
        bx: component.h * (mcu % mx) + h, by: component.v * Math.floor(mcu / mx) + v,
        z: Array(64).fill(0) });
    }
  });
  const perMCU = blocks.length / (mx * my), intervalSize = restart || mx * my, intervals = [];
  for (let first = 0; first < mx * my; first += intervalSize) {
    const count = Math.min(intervalSize, mx * my - first);
    intervals.push({ number: intervals.length, first, count, start: first * perMCU, end: (first + count) * perMCU });
  }
  return { width, height, components, restart, hMax, vMax, mx, my, blocks, intervals };
}

function standardComponents(h, v) {
  return [0, 1, 2].map(k => ({ id: k + 1, h: k === 0 ? h : 1, v: k === 0 ? v : 1,
    quant: k === 0 ? 0 : 1, dc: k === 0 ? 0 : 1, ac: k === 0 ? 0 : 1 }));
}

function encode(image, quality, sampling, mode, restart, tables) {
  const h = sampling === '444' ? 1 : 2, v = sampling === '420' ? 2 : 1;
  const layout = geometry(image.width, image.height, standardComponents(h, v), restart);
  const quant = new Map(dct.tables(tables.base, quality).map((table, id) => [id, table]));
  const planes = color.components(image, layout);
  const blocks = layout.blocks.map(block => {
    const pixels = [];
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) pixels.push(planes[block.component][8 * block.by + y][8 * block.bx + x]);
    return { ...block, z: dct.quantize(dct.forward(pixels, tables.C), quant.get(layout.components[block.component].quant)) };
  });
  return { ...assemble(layout, quant, blocks, mode, tables.huffman), planes };
}

function buildSymbols(layout, inputBlocks) {
  const frequencies = TABLE_KEYS.map(() => Array(256).fill(0));
  const blocks = inputBlocks.map(block => ({ ...block, symbols: [], bits: 0 }));
  function add(block, table, symbol, value = 0, length = 0) {
    block.symbols.push({ table, symbol, length, extra: entropy.extra(value, length) });
    frequencies[table][symbol]++;
  }
  for (const interval of layout.intervals) {
    const predictors = [0, 0, 0];
    for (let index = interval.start; index < interval.end; index++) {
      const block = blocks[index], k = block.component, base = k === 0 ? 0 : 2;
      block.diff = block.z[0] - predictors[k]; predictors[k] = block.z[0];
      const category = entropy.category(block.diff);
      add(block, base, category, block.diff, category);
      let run = 0;
      for (let i = 1; i < 64; i++) {
        if (block.z[i] === 0) { run++; continue; }
        while (run >= 16) { add(block, base + 1, 240); run -= 16; }
        const length = entropy.category(block.z[i]);
        add(block, base + 1, 16 * run + length, block.z[i], length); run = 0;
      }
      if (run > 0) add(block, base + 1, 0);
    }
  }
  return { blocks, frequencies };
}

function assemble(layout, quant, inputBlocks, mode, standard) {
  const { blocks, frequencies } = buildSymbols(layout, inputBlocks);
  const huffman = TABLE_KEYS.map(([tableClass, id], i) => mode === 'standard'
    ? entropy.assign(standard[i]) : entropy.optimized(frequencies[i], tableClass, id));
  const header = [255, 216];
  function segment(marker, contents) { header.push(255, marker, ...word(contents.length + 2), ...contents); }
  segment(219, [0, ...dct.zigzag.map(i => quant.get(0)[i]), 1, ...dct.zigzag.map(i => quant.get(1)[i])]);
  segment(192, [8, ...word(layout.height), ...word(layout.width), 3,
    ...layout.components.flatMap(component => [component.id, 16 * component.h + component.v, component.quant])]);
  segment(196, huffman.flatMap(table => [tableKey(table.tableClass, table.id), ...table.bits, ...table.values]));
  if (layout.restart > 0) segment(221, word(layout.restart));
  header.push(255, 218, 0, 12, 3, 1, 0, 2, 17, 3, 17, 0, 63, 0);
  const writer = new Writer(), intervals = [];
  for (const interval of layout.intervals) {
    if (interval.number > 0) writer.marker(208 + (interval.number - 1) % 8);
    const start = writer.bytes.length;
    for (let index = interval.start; index < interval.end; index++) {
      const block = blocks[index];
      for (const symbol of block.symbols) {
        const code = huffman[symbol.table].codes.get(symbol.symbol);
        writer.write(code.code, code.length); writer.write(symbol.extra, symbol.length);
        block.bits += code.length + symbol.length;
      }
    }
    writer.pad();
    intervals.push({ ...interval, position: header.length + start, length: writer.bytes.length - start });
  }
  return { layout, quant, blocks, frequencies, huffman, intervals,
    headerBytes: header.length, scanBytes: writer.bytes.length, padding: writer.padding, stuffed: writer.stuffed,
    bytes: header.concat(writer.bytes, [255, 217]) };
}

function parseHeader(bytes) {
  const quant = new Map(), huffman = new Map(), segments = [{ position: 0, name: 'SOI', length: 0 }];
  let width = 0, height = 0, components = [], restart = 0, position = 2;
  const names = new Map([[192, 'SOF0'], [196, 'DHT'], [219, 'DQT'], [221, 'DRI'], [218, 'SOS'], [254, 'COM']]);
  while (true) {
    const marker = bytes[position + 1], length = bytes[position + 2] * 256 + bytes[position + 3];
    const contents = bytes.slice(position + 4, position + length + 2);
    segments.push({ position, name: names.get(marker) || `APP${marker - 224}`, length });
    position += length + 2;
    if (marker === 219) {
      for (let offset = 0; offset < contents.length; offset += 65) {
        const table = Array(64).fill(0);
        for (let i = 0; i < 64; i++) table[dct.zigzag[i]] = contents[offset + 1 + i];
        quant.set(contents[offset], table);
      }
    } else if (marker === 196) {
      let offset = 0;
      while (offset < contents.length) {
        const key = contents[offset++], bits = contents.slice(offset, offset + 16);
        offset += 16;
        let count = 0;
        for (const number of bits) count += number;
        const values = contents.slice(offset, offset + count); offset += count;
        huffman.set(key, entropy.assign({ tableClass: Math.floor(key / 16), id: key % 16, bits, values }));
      }
    } else if (marker === 192) {
      height = contents[1] * 256 + contents[2]; width = contents[3] * 256 + contents[4];
      components = [0, 1, 2].map(k => ({ id: contents[6 + 3 * k], h: Math.floor(contents[7 + 3 * k] / 16),
        v: contents[7 + 3 * k] % 16, quant: contents[8 + 3 * k] }));
    } else if (marker === 221) restart = contents[0] * 256 + contents[1];
    else if (marker === 218) {
      components.forEach((component, k) => {
        component.dc = Math.floor(contents[2 + 2 * k] / 16); component.ac = contents[2 + 2 * k] % 16;
      });
      break;
    }
  }
  segments.push({ position: bytes.length - 2, name: 'EOI', length: 0 });
  return { layout: geometry(width, height, components, restart), quant, huffman, segments,
    scanStart: position, scanBytes: bytes.length - 2 - position };
}

function readSymbol(reader, table) {
  let code = 0;
  for (let length = 1; length <= 16; length++) {
    code = code * 2 + reader.bit();
    if (table.decode[length].has(code)) return table.decode[length].get(code);
  }
  throw new DecodeError('code');
}

function readBlock(reader, component, k, predictors, huffman) {
  const z = Array(64).fill(0);
  const n = readSymbol(reader, huffman.get(tableKey(0, component.dc)));
  predictors[k] += entropy.restore(reader.read(n), n); z[0] = predictors[k];
  let index = 1;
  while (index <= 63) {
    const symbol = readSymbol(reader, huffman.get(tableKey(1, component.ac)));
    if (symbol === 0) break;
    const run = Math.floor(symbol / 16), length = symbol % 16;
    index += run;
    if (index > 63) throw new DecodeError('index');
    if (length > 0) z[index] = entropy.restore(reader.read(length), length);
    index++;
  }
  return z;
}

function render(layout, blocks, quant, C, keep = 64) {
  const componentPlanes = layout.components.map(component =>
    Array.from({ length: 8 * component.v * layout.my }, () => Array(8 * component.h * layout.mx).fill(128)));
  for (const block of blocks) {
    const table = quant.get(layout.components[block.component].quant);
    const pixels = dct.inverse(dct.dequantize(block.z, table, block.component === 0 ? keep : 64), C);
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) componentPlanes[block.component][8 * block.by + y][8 * block.bx + x] = pixels[8 * y + x];
  }
  return { componentPlanes, ...color.upsample(componentPlanes, layout) };
}

function decode(bytes, C) {
  const parsed = parseHeader(bytes), { layout, quant, huffman } = parsed;
  const reader = new Reader(bytes, parsed.scanStart), blocks = layout.blocks;
  const intervals = layout.intervals.map(interval => ({ ...interval, state: 'lost' }));
  let j = 0;
  while (j < intervals.length) {
    const interval = intervals[j], predictors = [0, 0, 0], decoded = [];
    let currentMCU = interval.first;
    try {
      for (let index = interval.start; index < interval.end; index++) {
        const block = blocks[index]; currentMCU = block.mcu;
        decoded.push(readBlock(reader, layout.components[block.component], block.component, predictors, huffman));
      }
      reader.clear();
      const expected = j < intervals.length - 1 ? 208 + j % 8 : 217;
      if (bytes[reader.position] !== 255 || bytes[reader.position + 1] !== expected) throw new DecodeError('sync');
      for (let i = 0; i < decoded.length; i++) blocks[interval.start + i].z = decoded[i];
      interval.state = 'ok'; reader.position += 2; j++;
    } catch (error) {
      if (!(error instanceof DecodeError)) throw error;
      const offset = reader.position;
      reader.clear();
      const resync = reader.resync(), marker = bytes[resync + 1];
      Object.assign(interval, { state: 'damaged', kind: error.kind, mcu: currentMCU, offset, resync });
      if (marker === 217) break;
      const number = marker - 208, next = j + 1 + ((number - j) % 8 + 8) % 8;
      reader.position = resync + 2; j = next;
    }
  }
  return { ...parsed, blocks, intervals, ...render(layout, blocks, quant, C) };
}

function psnr(first, second) {
  let error = 0;
  for (let i = 0; i < first.length; i++) {
    const difference = first[i] - second[i]; error += difference * difference;
  }
  return error === 0 ? 'inf' : (10 * Math.log10(65025 * first.length / error)).toFixed(2);
}

function fraction(numerator, denominator) {
  let a = numerator, b = denominator;
  while (b !== 0) { const remainder = a % b; a = b; b = remainder; }
  return `${numerator / a}/${denominator / a}`;
}

function imageMetrics(original, originalPlanes, decoded) {
  const channels = originalPlanes.map((plane, k) => psnr(plane.flat(), decoded.planes[k].flat()));
  const first = original.pixels.flat(2), second = decoded.image.pixels.flat(2);
  let maximum = 0;
  for (let i = 0; i < first.length; i++) maximum = Math.max(maximum, Math.abs(first[i] - second[i]));
  return { channels, rgb: psnr(first, second), maximum };
}

function blockStatistics(reference, decoded) {
  const nonzero = Array(64).fill(0), components = [0, 1, 2].map(() => ({ bits: 0, nonzero: 0, error: 0 }));
  const lines = [`blocks ${reference.blocks.length}`];
  let zeroAC = 0;
  for (const block of reference.blocks) {
    let ac = 0, last = 0, error = 0;
    for (let i = 0; i < 64; i++) if (block.z[i] !== 0) {
      nonzero[i]++; components[block.component].nonzero++; last = i;
      if (i > 0) ac++;
    }
    if (ac === 0) zeroAC++;
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
      const row = 8 * block.by + y, column = 8 * block.bx + x;
      const difference = reference.planes[block.component][row][column] - decoded.componentPlanes[block.component][row][column];
      error += difference * difference;
    }
    components[block.component].bits += block.bits; components[block.component].error += error;
    lines.push(`block ${block.number} ${COMPONENT_NAMES[block.component]} ${block.bx} ${block.by} dc ${block.z[0]} diff ${block.diff} nonzero ${ac} last ${last} bits ${block.bits} sse ${error}`);
  }
  return { lines, nonzero, components, zeroAC };
}

function huffmanLines(reference) {
  const lines = [];
  reference.huffman.forEach((table, i) => {
    let coded = 0, bits = 0;
    for (const symbol of table.values) {
      coded += reference.frequencies[i][symbol]; bits += reference.frequencies[i][symbol] * table.codes.get(symbol).length;
    }
    lines.push(`table ${TABLE_NAMES[i]} class ${table.tableClass} id ${table.id} symbols ${table.values.length} coded ${coded} bits ${bits}`,
      `counts ${table.bits.join(' ')}`);
    for (const symbol of table.values) {
      const code = table.codes.get(symbol);
      lines.push(`symbol ${symbol.toString(16).padStart(2, '0')} length ${code.length} code ${code.code.toString(2).padStart(code.length, '0')} count ${reference.frequencies[i][symbol]}`);
    }
  });
  return lines;
}

function thumbnail(decoded) {
  const { layout } = decoded, width = Math.ceil(layout.width / 8), height = Math.ceil(layout.height / 8);
  const byPosition = new Map(decoded.blocks.map(block => [`${block.component},${block.bx},${block.by}`, block]));
  const pixels = Array.from({ length: height }, (_, y) => Array.from({ length: width }, (_, x) => {
    const values = layout.components.map((component, k) => {
      const bx = Math.floor(x * component.h / layout.hMax), by = Math.floor(y * component.v / layout.vMax);
      const block = byPosition.get(`${k},${bx},${by}`), weight = decoded.quant.get(component.quant)[0];
      return color.clamp(Math.floor((block.z[0] * weight + 4) / 8) + 128);
    });
    return color.toRGB(values);
  }));
  return { width, height, pixels };
}

function referenceReport(reference, stats, original, decoded, params) {
  const { layout, quant } = reference;
  const counts = reference.frequencies.map(frequencies => frequencies.reduce((sum, count) => sum + count, 0));
  const eob = reference.frequencies[1][0] + reference.frequencies[3][0];
  const zrl = reference.frequencies[1][240] + reference.frequencies[3][240];
  const lines = [`image ${layout.width} ${layout.height}`,
    `sampling ${params.sampling} mcu ${8 * layout.hMax} ${8 * layout.vMax} grid ${layout.mx} ${layout.my}`,
    `padded ${8 * layout.hMax * layout.mx} ${8 * layout.vMax * layout.my}`,
    `blocks ${layout.components.map(component => component.h * component.v * layout.mx * layout.my).join(' ')}`,
    `restart_interval ${layout.restart} markers ${layout.intervals.length - 1}`,
    `huffman ${params.huffman}`, `quality ${params.qualities[0]}`,
    `quant 0 ${dct.zigzag.map(i => quant.get(0)[i]).join(' ')}`,
    `quant 1 ${dct.zigzag.map(i => quant.get(1)[i]).join(' ')}`,
    `symbols ${counts.join(' ')}`, `eob ${eob} zrl ${zrl}`, `zero_ac_blocks ${stats.zeroAC}`,
    `nonzero ${stats.nonzero.join(' ')}`];
  stats.components.forEach((component, k) => lines.push(`component ${COMPONENT_NAMES[k]} bits ${component.bits} nonzero ${component.nonzero} sse ${component.error}`));
  lines.push(`padding_bits ${reference.padding}`, `stuffed_bytes ${reference.stuffed}`,
    `header_bytes ${reference.headerBytes}`, `scan_bytes ${reference.scanBytes}`, `total_bytes ${reference.bytes.length}`);
  for (const interval of reference.intervals) lines.push(`interval ${interval.number} ${interval.first} ${interval.count} ${interval.position} ${interval.length}`);
  const histogram = Array(8).fill(0), upper = [0, 1, 3, 7, 15, 31, 63, 255];
  const first = original.pixels.flat(2), second = decoded.image.pixels.flat(2);
  for (let i = 0; i < first.length; i++) {
    const error = Math.abs(first[i] - second[i]);
    let bin = 0;
    while (error > upper[bin]) bin++;
    histogram[bin]++;
  }
  lines.push(`error_histogram ${histogram.join(' ')}`);
  return lines;
}

function compareSampling(original, originalPlanes, params, tables) {
  const lines = [];
  for (const sampling of ['444', '422', '420']) {
    const encoded = encode(original, params.qualities[0], sampling, params.huffman, params.restart_interval, tables);
    const decoded = decode(encoded.bytes, tables.C), metrics = imageMetrics(original, originalPlanes, decoded);
    lines.push(`sampling_compare ${sampling} ${encoded.bytes.length} ${metrics.channels[1]} ${metrics.channels[2]} ${metrics.rgb}`);
  }
  return lines;
}

function repeatedCompression(original, params, tables) {
  let previous = original;
  const lines = [], originalValues = original.pixels.flat(2);
  for (let generation = 1; generation <= params.generations; generation++) {
    const encoded = encode(previous, params.qualities[0], params.sampling, params.huffman, params.restart_interval, tables);
    const next = decode(encoded.bytes, tables.C).image;
    let changed = 0;
    for (let y = 0; y < original.height; y++) for (let x = 0; x < original.width; x++) {
      if (previous.pixels[y][x].some((value, k) => value !== next.pixels[y][x][k])) changed++;
    }
    lines.push(`generation ${generation} ${encoded.bytes.length} ${psnr(originalValues, next.pixels.flat(2))} ${changed}`);
    previous = next;
  }
  return lines;
}

function qualitySearch(original, params, tables) {
  const lines = [];
  let lo = 1, hi = 100;
  while (lo < hi) {
    const mid = Math.floor((lo + hi + 1) / 2);
    const encoded = encode(original, mid, params.sampling, params.huffman, params.restart_interval, tables);
    lines.push(`rate_control_step ${mid} ${encoded.bytes.length}`);
    if (encoded.bytes.length <= params.target_bytes) lo = mid; else hi = mid - 1;
  }
  const encoded = encode(original, lo, params.sampling, params.huffman, params.restart_interval, tables);
  const decoded = decode(encoded.bytes, tables.C);
  lines.push(`rate_control ${lo} ${encoded.bytes.length} ${encoded.bytes.length <= params.target_bytes ? 'yes' : 'no'} ${psnr(original.pixels.flat(2), decoded.image.pixels.flat(2))}`);
  return lines;
}

function repairStream(decoded, tables) {
  const originalLayout = decoded.layout, first = originalLayout.components[0];
  const layout = geometry(originalLayout.width, originalLayout.height,
    standardComponents(first.h, first.v), originalLayout.restart);
  const quant = new Map([[0, decoded.quant.get(first.quant)], [1, decoded.quant.get(originalLayout.components[1].quant)]]);
  const blocks = layout.blocks.map((block, i) => ({ ...block, z: decoded.blocks[i].z }));
  const encoded = assemble(layout, quant, blocks, 'optimized', tables.huffman);
  const repaired = decode(encoded.bytes, tables.C), values = decoded.image.pixels.flat(2);
  const identical = repaired.image.pixels.flat(2).every((value, i) => value === values[i]);
  return { ...encoded, identical };
}

function streamReport(decoded, repair) {
  const lines = [];
  for (const segment of decoded.segments) lines.push(`stream_segment ${segment.position} ${segment.name} ${segment.length}`);
  lines.push(`stream_image ${decoded.layout.width} ${decoded.layout.height}`);
  for (const component of decoded.layout.components) lines.push(`stream_component ${component.id} ${component.h} ${component.v} ${component.quant} ${component.dc} ${component.ac}`);
  for (const id of [...decoded.quant.keys()].sort((a, b) => a - b)) lines.push(`stream_quant ${id} ${dct.zigzag.map(i => decoded.quant.get(id)[i]).join(' ')}`);
  for (const key of [...decoded.huffman.keys()].sort((a, b) => a - b)) {
    const table = decoded.huffman.get(key);
    let longest = 16;
    while (longest > 0 && table.bits[longest - 1] === 0) longest--;
    lines.push(`stream_huffman ${table.tableClass} ${table.id} symbols ${table.values.length} longest ${longest}`);
  }
  const count = state => decoded.intervals.filter(interval => interval.state === state).length;
  lines.push(`stream_restart ${decoded.layout.restart} intervals ${decoded.intervals.length} ok ${count('ok')} damaged ${count('damaged')} lost ${count('lost')}`);
  for (const interval of decoded.intervals) {
    const state = interval.state === 'damaged'
      ? `damaged ${interval.kind} mcu ${interval.mcu} offset ${interval.offset} resync ${interval.resync}` : interval.state;
    lines.push(`stream_interval ${interval.number} ${interval.first} ${interval.count} ${state}`);
  }
  lines.push(`stream_scan_bytes ${decoded.scanBytes}`,
    `repair ${repair.bytes.length} ${repair.headerBytes} ${repair.scanBytes} identical ${repair.identical ? 'yes' : 'no'}`);
  return lines;
}

function main() {
  const image = io.readPPM('input/image.ppm'), params = io.readParams('input/params.txt');
  const tables = io.readTables('input/tables.txt'), originalPlanes = color.planes(image);
  const rates = ['quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error'];
  let reference = null, referenceDecoded = null;
  for (const quality of params.qualities) {
    const standard = encode(image, quality, params.sampling, 'standard', params.restart_interval, tables);
    const optimized = encode(image, quality, params.sampling, 'optimized', params.restart_interval, tables);
    const encoded = params.huffman === 'standard' ? standard : optimized;
    const decoded = decode(encoded.bytes, tables.C), metrics = imageMetrics(image, originalPlanes, decoded);
    rates.push([quality, standard.bytes.length, optimized.bytes.length,
      fraction(8 * encoded.bytes.length, image.width * image.height), ...metrics.channels, metrics.rgb, metrics.maximum].join(','));
    if (reference === null) { reference = encoded; referenceDecoded = decoded; }
  }
  const stats = blockStatistics(reference, referenceDecoded);
  const report = referenceReport(reference, stats, image, referenceDecoded, params);
  for (const keep of params.truncate) {
    const truncated = render(referenceDecoded.layout, referenceDecoded.blocks, referenceDecoded.quant, tables.C, keep);
    report.push(`truncate ${keep} ${psnr(originalPlanes[0].flat(), truncated.planes[0].flat())}`);
  }
  for (const line of compareSampling(image, originalPlanes, params, tables)) report.push(line);
  for (const line of repeatedCompression(image, params, tables)) report.push(line);
  for (const line of qualitySearch(image, params, tables)) report.push(line);
  const stream = decode(io.readHex('input/stream.hex'), tables.C), repair = repairStream(stream, tables);
  for (const line of streamReport(stream, repair)) report.push(line);
  io.writeLines('output/rate_distortion.csv', rates);
  io.writePPM('output/decoded.ppm', referenceDecoded.image);
  io.writeHex('output/bitstream.hex', reference.bytes);
  io.writePPM('output/thumbnail.ppm', thumbnail(referenceDecoded));
  io.writeLines('output/huffman_tables.txt', huffmanLines(reference));
  io.writeLines('output/blocks.txt', stats.lines);
  io.writePPM('output/stream_decoded.ppm', stream.image);
  io.writeHex('output/repaired.hex', repair.bytes);
  io.writeLines('output/report.txt', report);
}

main();
