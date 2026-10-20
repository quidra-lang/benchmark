import {
  readImage,
  readParameters,
  readTables,
  readHex,
  writeLines,
  writeImage,
  writeHex,
  type Image,
  type Plane,
} from './image_io.ts';
import {
  convert,
  componentPlanes,
  geometry,
  upsample,
  imageFromPlanes,
  rgb,
  clamp,
} from './color.ts';
import { zigzag, quantization, transform, inverse, quantize, dequantize } from './dct.ts';
import { category, extra, signed, optimized, assign, type HuffmanTable } from './entropy.ts';
import { BitWriter, BitReader, ScanError, resync } from './bitstream.ts';

interface Component {
  id: number;
  h: number;
  v: number;
  tq: number;
  td: number;
  ta: number;
}
interface Frame {
  width: number;
  height: number;
  components: Component[];
  restart: number;
}
interface Token {
  table: number;
  symbol: number;
  value: number;
  size: number;
}
interface Block {
  mcu: number;
  component: number;
  bx: number;
  by: number;
  z: number[];
  diff: number;
  bits: number;
  tokens: Token[];
}
interface Interval {
  first: number;
  count: number;
}
interface Segment {
  position: number;
  name: string;
  length: number;
}
const image = readImage();
const p = readParameters();
const tables = readTables();
const componentNames = ['Y', 'Cb', 'Cr'];
const tableNames = ['dc_luma', 'ac_luma', 'dc_chroma', 'ac_chroma'];
function frameFor(image: Image, sampling: number, restart: number): Frame {
  return {
    width: image.width,
    height: image.height,
    restart,
    components: [
      { id: 1, h: sampling === 444 ? 1 : 2, v: sampling === 420 ? 2 : 1, tq: 0, td: 0, ta: 0 },
      { id: 2, h: 1, v: 1, tq: 1, td: 1, ta: 1 },
      { id: 3, h: 1, v: 1, tq: 1, td: 1, ta: 1 },
    ],
  };
}
function intervals(frame: Frame): Interval[] {
  const g = geometry(frame.width, frame.height, frame.components);
  const count = g.mx * g.my;
  const step = frame.restart || count;
  return Array.from({ length: Math.ceil(count / step) }, (_, j) => ({
    first: j * step,
    count: Math.min(step, count - j * step),
  }));
}
function blocksFor(frame: Frame): Block[] {
  const g = geometry(frame.width, frame.height, frame.components);
  const blocks: Block[] = [];
  for (let mcu = 0; mcu < g.mx * g.my; mcu++) {
    frame.components.forEach((c, component) => {
      for (let v = 0; v < c.v; v++) {
        for (let h = 0; h < c.h; h++) {
          blocks.push({
            mcu,
            component,
            bx: c.h * (mcu % g.mx) + h,
            by: c.v * Math.floor(mcu / g.mx) + v,
            z: Array<number>(64).fill(0),
            diff: 0,
            bits: 0,
            tokens: [],
          });
        }
      }
    });
  }
  return blocks;
}
function blockValues(plane: Plane, block: Block): number[] {
  return Array.from(
    { length: 64 },
    (_, i) =>
      plane.pixels[(8 * block.by + Math.floor(i / 8)) * plane.width + 8 * block.bx + (i % 8)],
  );
}
function symbolsFor(frame: Frame, blocks: Block[]): number[][] {
  const frequencies = Array.from({ length: 4 }, () => Array<number>(256).fill(0));
  const predictors = [0, 0, 0];
  let previousInterval = -1;
  for (const block of blocks) {
    const interval = frame.restart ? Math.floor(block.mcu / frame.restart) : 0;
    if (interval !== previousInterval) {
      predictors.fill(0);
      previousInterval = interval;
    }
    const table = block.component === 0 ? 0 : 2;
    const difference = block.z[0] - predictors[block.component];
    predictors[block.component] = block.z[0];
    block.diff = difference;
    block.tokens = [];
    const emit = (table: number, symbol: number, value: number, size: number) => {
      block.tokens.push({ table, symbol, value, size });
      frequencies[table][symbol]++;
    };
    emit(
      table,
      category(difference),
      extra(difference, category(difference)),
      category(difference),
    );
    let run = 0;
    for (let i = 1; i < 64; i++) {
      if (block.z[i] === 0) run++;
      else {
        while (run >= 16) {
          emit(table + 1, 240, 0, 0);
          run -= 16;
        }
        const size = category(block.z[i]);
        emit(table + 1, 16 * run + size, extra(block.z[i], size), size);
        run = 0;
      }
    }
    if (run > 0) emit(table + 1, 0, 0, 0);
  }
  return frequencies;
}
function pack(frame: Frame, blocks: Block[], quant: number[][], mode: string) {
  const frequencies = symbolsFor(frame, blocks);
  const huffman =
    mode === 'standard'
      ? tables.huffman
      : frequencies.map((freq, i) => optimized(freq, i % 2, Math.floor(i / 2)));
  const codes = huffman.map(assign);
  const bytes = [255, 216];
  const word = (n: number) => [Math.floor(n / 256), n % 256];
  const segment = (marker: number, body: number[]) =>
    bytes.push(255, marker, ...word(body.length + 2), ...body);
  segment(219, [0, ...zigzag.map((i) => quant[0][i]), 1, ...zigzag.map((i) => quant[1][i])]);
  segment(192, [
    8,
    ...word(frame.height),
    ...word(frame.width),
    3,
    ...frame.components.flatMap((c) => [c.id, 16 * c.h + c.v, c.tq]),
  ]);
  segment(
    196,
    huffman.flatMap((t) => [16 * t.class + t.id, ...t.counts, ...t.values]),
  );
  if (frame.restart) segment(221, word(frame.restart));
  segment(218, [3, ...frame.components.flatMap((c) => [c.id, 16 * c.td + c.ta]), 0, 63, 0]);
  const headerBytes = bytes.length;
  const writer = new BitWriter();
  const intervalInfo: (Interval & { position: number; length: number })[] = [];
  intervals(frame).forEach((interval, j) => {
    if (j > 0) writer.marker(208 + ((j - 1) % 8));
    const position = headerBytes + writer.bytes.length;
    for (const block of blocks) {
      if (block.mcu >= interval.first && block.mcu < interval.first + interval.count) {
        block.bits = 0;
        for (const token of block.tokens) {
          const code = codes[token.table].encode.get(token.symbol);
          if (!code) throw new Error('Missing Huffman symbol');
          writer.write(code.value, code.length);
          writer.write(token.value, token.size);
          block.bits += code.length + token.size;
        }
      }
    }
    writer.pad();
    intervalInfo.push({
      ...interval,
      position,
      length: headerBytes + writer.bytes.length - position,
    });
  });
  bytes.push(...writer.bytes, 255, 217);
  return {
    bytes,
    frame,
    blocks,
    quant,
    huffman,
    frequencies,
    headerBytes,
    scanBytes: writer.bytes.length,
    padding: writer.paddingBits,
    stuffed: writer.stuffedBytes,
    intervals: intervalInfo,
  };
}
function encode(source: Image, quality: number, sampling = p.sampling, mode = p.huffman) {
  const frame = frameFor(source, sampling, p.restart);
  const planes = componentPlanes(source, frame.components);
  const quant = quantization(tables.quant, quality);
  const blocks = blocksFor(frame);
  for (const block of blocks) {
    block.z = quantize(
      transform(blockValues(planes[block.component], block), tables.dct),
      quant[frame.components[block.component].tq],
    );
  }
  return { ...pack(frame, blocks, quant, mode), planes };
}
function render(frame: Frame, blocks: Block[], quant: Map<number, number[]>, keep = 64): Plane[] {
  const g = geometry(frame.width, frame.height, frame.components);
  const planes = frame.components.map((c) => ({
    width: 8 * c.h * g.mx,
    height: 8 * c.v * g.my,
    pixels: Array<number>(64 * c.h * c.v * g.mx * g.my).fill(128),
  }));
  for (const block of blocks) {
    const q = quant.get(frame.components[block.component].tq);
    if (!q) throw new Error('Missing quantization table');
    const pixels = inverse(dequantize(block.z, q, block.component === 0 ? keep : 64), tables.dct);
    const plane = planes[block.component];
    pixels.forEach(
      (value, i) =>
        (plane.pixels[(8 * block.by + Math.floor(i / 8)) * plane.width + 8 * block.bx + (i % 8)] =
          value),
    );
  }
  return planes;
}
function decode(bytes: number[]) {
  const segments: Segment[] = [{ position: 0, name: 'SOI', length: 0 }];
  const quant = new Map<number, number[]>();
  const huffman = new Map<number, HuffmanTable>();
  let position = 2;
  let width = 0;
  let height = 0;
  let restart = 0;
  let components: Component[] = [];
  while (true) {
    const marker = bytes[position + 1];
    const length = 256 * bytes[position + 2] + bytes[position + 3];
    const body = bytes.slice(position + 4, position + length + 2);
    const name =
      marker === 192
        ? 'SOF0'
        : marker === 196
          ? 'DHT'
          : marker === 219
            ? 'DQT'
            : marker === 221
              ? 'DRI'
              : marker === 218
                ? 'SOS'
                : marker === 254
                  ? 'COM'
                  : 'APP' + (marker - 224);
    segments.push({ position, name, length });
    position += length + 2;
    if (marker === 219) {
      for (let i = 0; i < body.length; i += 65) {
        const q = Array<number>(64);
        zigzag.forEach((index, k) => (q[index] = body[i + 1 + k]));
        quant.set(body[i], q);
      }
    } else if (marker === 196) {
      for (let i = 0; i < body.length;) {
        const type = body[i++];
        const counts = body.slice(i, i + 16);
        i += 16;
        const count = counts.reduce((a, b) => a + b, 0);
        const values = body.slice(i, i + count);
        i += count;
        huffman.set(type, { class: Math.floor(type / 16), id: type % 16, counts, values });
      }
    } else if (marker === 192) {
      height = 256 * body[1] + body[2];
      width = 256 * body[3] + body[4];
      components = Array.from({ length: body[5] }, (_, i) => ({
        id: body[6 + 3 * i],
        h: Math.floor(body[7 + 3 * i] / 16),
        v: body[7 + 3 * i] % 16,
        tq: body[8 + 3 * i],
        td: 0,
        ta: 0,
      }));
    } else if (marker === 221) restart = 256 * body[0] + body[1];
    else if (marker === 218) {
      components.forEach((c, i) => {
        c.td = Math.floor(body[2 + 2 * i] / 16);
        c.ta = body[2 + 2 * i] % 16;
      });
      break;
    }
  }
  segments.push({ position: bytes.length - 2, name: 'EOI', length: 0 });
  const scanStart = position;
  const frame = { width, height, restart, components };
  const blocks = blocksFor(frame);
  const spans = intervals(frame);
  const states = spans.map(() => 'lost');
  const reader = new BitReader(bytes, position);
  const codes = new Map(
    [...huffman].map(([key, table]): [number, ReturnType<typeof assign>] => [key, assign(table)]),
  );
  function symbol(tableClass: number, id: number): number {
    const table = codes.get(16 * tableClass + id);
    if (!table) throw new Error('Missing Huffman table');
    let code = 0;
    for (let length = 1; length <= 16; length++) {
      code = 2 * code + reader.read(1);
      const value = table.decode.get(`${length}:${code}`);
      if (value !== undefined) return value;
    }
    throw new ScanError('code');
  }
  let j = 0;
  while (j < spans.length) {
    const span = spans[j];
    const predictors = [0, 0, 0];
    const pending: { block: Block; z: number[] }[] = [];
    let currentMcu = span.first;
    try {
      for (const block of blocks) {
        if (block.mcu >= span.first && block.mcu < span.first + span.count) {
          currentMcu = block.mcu;
          const c = components[block.component];
          const z = Array<number>(64).fill(0);
          const n = symbol(0, c.td);
          const difference = signed(reader.read(n), n);
          predictors[block.component] += difference;
          z[0] = predictors[block.component];
          let i = 1;
          while (i <= 63) {
            const a = symbol(1, c.ta);
            if (a === 0) break;
            const run = Math.floor(a / 16);
            const size = a % 16;
            i += run;
            if (i > 63) throw new ScanError('index');
            if (size > 0) z[i] = signed(reader.read(size), size);
            i++;
          }
          pending.push({ block, z });
        }
      }
      reader.clear();
      const expected = j + 1 < spans.length ? 208 + (j % 8) : 217;
      currentMcu = span.first + span.count - 1;
      if (bytes[reader.position] !== 255 || bytes[reader.position + 1] !== expected) {
        throw new ScanError('sync');
      }
      for (const item of pending) item.block.z = item.z;
      states[j] = 'ok';
      reader.position += 2;
      j++;
    } catch (error) {
      if (!(error instanceof ScanError)) throw error;
      const offset = reader.position;
      const q = resync(bytes, offset);
      reader.clear();
      states[j] = `damaged ${error.kind} mcu ${currentMcu} offset ${offset} resync ${q}`;
      if (bytes[q + 1] === 217) break;
      const marker = bytes[q + 1] - 208;
      j = j + 1 + ((((marker - j) % 8) + 8) % 8);
      reader.position = q + 2;
    }
  }
  const planes = render(frame, blocks, quant);
  const full = upsample(planes, width, height, components);
  return {
    frame,
    blocks,
    quant,
    huffman,
    segments,
    spans,
    states,
    planes,
    full,
    image: imageFromPlanes(full),
    scanBytes: bytes.length - 2 - scanStart,
  };
}
function psnr(a: number[], b: number[]): string {
  let error = 0;
  for (let i = 0; i < a.length; i++) error += (a[i] - b[i]) ** 2;
  return error === 0 ? 'inf' : (10 * Math.log10((65025 * a.length) / error)).toFixed(2);
}
function fraction(a: number, b: number): string {
  let x = a;
  let y = b;
  while (y) [x, y] = [y, x % y];
  return `${a / x}/${b / x}`;
}
const original = convert(image);
const cache = new Map<string, ReturnType<typeof encode>>();
function encoded(quality: number, sampling = p.sampling, mode = p.huffman) {
  const key = `${quality}:${sampling}:${mode}`;
  let result = cache.get(key);
  if (!result) {
    result = encode(image, quality, sampling, mode);
    cache.set(key, result);
  }
  return result;
}
function qualityMetrics(decoded: ReturnType<typeof decode>) {
  return [
    ...original.map((plane, c) => psnr(plane.pixels, decoded.full[c].pixels)),
    psnr(image.pixels, decoded.image.pixels),
  ];
}
const rate = [
  'quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error',
];
for (const quality of p.qualities) {
  const standard = encoded(quality, p.sampling, 'standard');
  const optimized = encoded(quality, p.sampling, 'optimized');
  const selected = p.huffman === 'standard' ? standard : optimized;
  const decoded = decode(selected.bytes);
  rate.push(
    [
      quality,
      standard.bytes.length,
      optimized.bytes.length,
      fraction(8 * selected.bytes.length, image.width * image.height),
      ...qualityMetrics(decoded),
      Math.max(...image.pixels.map((v, i) => Math.abs(v - decoded.image.pixels[i]))),
    ].join(','),
  );
}
const reference = encoded(p.qualities[0]);
const restored = decode(reference.bytes);
const g = geometry(image.width, image.height, reference.frame.components);
const names = reference.frame.components;
const errors = reference.blocks.map((block) => {
  const a = blockValues(reference.planes[block.component], block);
  const b = blockValues(restored.planes[block.component], block);
  return a.reduce((sum, value, i) => sum + (value - b[i]) ** 2, 0);
});
const blockLines = [
  `blocks ${reference.blocks.length}`,
  ...reference.blocks.map((block, i) => {
    let last = 0;
    block.z.forEach((v, index) => {
      if (v !== 0) last = index;
    });
    return `block ${i} ${componentNames[block.component]} ${block.bx} ${block.by} dc ${block.z[0]} diff ${block.diff} nonzero ${block.z.slice(1).filter((v) => v !== 0).length} last ${last} bits ${block.bits} sse ${errors[i]}`;
  }),
];
const tw = Math.ceil(image.width / 8);
const th = Math.ceil(image.height / 8);
const thumbnail: Image = { width: tw, height: th, pixels: [] };
for (let y = 0; y < th; y++) {
  for (let x = 0; x < tw; x++) {
    const values = names.map((c, component) => {
      const bx = Math.floor((x * c.h) / g.hmax);
      const by = Math.floor((y * c.v) / g.vmax);
      const block = restored.blocks.find(
        (b) => b.component === component && b.bx === bx && b.by === by,
      );
      const q = restored.quant.get(c.tq);
      if (!block || !q) throw new Error('Missing thumbnail block');
      return clamp(Math.floor((block.z[0] * q[0] + 4) / 8) + 128);
    });
    thumbnail.pixels.push(...rgb(values[0], values[1], values[2]));
  }
}
const huffmanLines: string[] = [];
reference.huffman.forEach((table, i) => {
  const codes = assign(table).encode;
  const frequency = reference.frequencies[i];
  const coded = frequency.reduce((a, b) => a + b, 0);
  let bits = 0;
  for (const symbol of table.values) {
    const code = codes.get(symbol);
    if (code) bits += frequency[symbol] * code.length;
  }
  huffmanLines.push(
    `table ${tableNames[i]} class ${table.class} id ${table.id} symbols ${table.values.length} coded ${coded} bits ${bits}`,
    'counts ' + table.counts.join(' '),
  );
  for (const symbol of table.values) {
    const code = codes.get(symbol);
    if (!code) throw new Error('Missing assigned code');
    huffmanLines.push(
      `symbol ${symbol.toString(16).padStart(2, '0')} length ${code.length} code ${code.value.toString(2).padStart(code.length, '0')} count ${frequency[symbol]}`,
    );
  }
});
const report = [
  `image ${image.width} ${image.height}`,
  `sampling ${p.sampling} mcu ${8 * g.hmax} ${8 * g.vmax} grid ${g.mx} ${g.my}`,
  `padded ${g.pw} ${g.ph}`,
  'blocks ' +
    names.map((_, c) => reference.blocks.filter((b) => b.component === c).length).join(' '),
  `restart_interval ${p.restart} markers ${reference.intervals.length - 1}`,
  `huffman ${p.huffman}`,
  `quality ${p.qualities[0]}`,
  ...reference.quant.map((q, i) => `quant ${i} ` + zigzag.map((index) => q[index]).join(' ')),
  'symbols ' + reference.frequencies.map((freq) => freq.reduce((a, b) => a + b, 0)).join(' '),
  `eob ${reference.frequencies[1][0] + reference.frequencies[3][0]} zrl ${reference.frequencies[1][240] + reference.frequencies[3][240]}`,
  `zero_ac_blocks ${reference.blocks.filter((b) => b.z.slice(1).every((v) => v === 0)).length}`,
  'nonzero ' +
    Array.from({ length: 64 }, (_, i) => reference.blocks.filter((b) => b.z[i] !== 0).length).join(
      ' ',
    ),
];
names.forEach((_, c) => {
  const blocks = reference.blocks.filter((b) => b.component === c);
  report.push(
    `component ${componentNames[c]} bits ${blocks.reduce((sum, b) => sum + b.bits, 0)} nonzero ${blocks.reduce((sum, b) => sum + b.z.filter((v) => v !== 0).length, 0)} sse ${reference.blocks.reduce((sum, b, i) => sum + (b.component === c ? errors[i] : 0), 0)}`,
  );
});
report.push(
  `padding_bits ${reference.padding}`,
  `stuffed_bytes ${reference.stuffed}`,
  `header_bytes ${reference.headerBytes}`,
  `scan_bytes ${reference.scanBytes}`,
  `total_bytes ${reference.bytes.length}`,
  ...reference.intervals.map(
    (span, j) => `interval ${j} ${span.first} ${span.count} ${span.position} ${span.length}`,
  ),
);
const histogram = Array<number>(8).fill(0);
image.pixels.forEach((v, i) => {
  const error = Math.abs(v - restored.image.pixels[i]);
  let bin = 0;
  while (bin < 7 && error >= 2 ** bin) bin++;
  histogram[bin]++;
});
report.push('error_histogram ' + histogram.join(' '));
for (const keep of p.truncate) {
  const planes = render(restored.frame, restored.blocks, restored.quant, keep);
  const full = upsample(planes, image.width, image.height, names);
  report.push(`truncate ${keep} ${psnr(original[0].pixels, full[0].pixels)}`);
}
for (const sampling of [444, 422, 420]) {
  const coding = encoded(p.qualities[0], sampling);
  const decoded = decode(coding.bytes);
  const metrics = qualityMetrics(decoded);
  report.push(
    `sampling_compare ${sampling} ${coding.bytes.length} ${metrics[1]} ${metrics[2]} ${metrics[3]}`,
  );
}
let generationImage = image;
for (let generation = 1; generation <= p.generations; generation++) {
  const coding = encode(generationImage, p.qualities[0]);
  const decoded = decode(coding.bytes);
  let changed = 0;
  for (let i = 0; i < image.width * image.height; i++) {
    if (
      [0, 1, 2].some((c) => generationImage.pixels[3 * i + c] !== decoded.image.pixels[3 * i + c])
    ) {
      changed++;
    }
  }
  report.push(
    `generation ${generation} ${coding.bytes.length} ${psnr(image.pixels, decoded.image.pixels)} ${changed}`,
  );
  generationImage = decoded.image;
}
let lo = 1;
let hi = 100;
while (lo < hi) {
  const mid = Math.floor((lo + hi + 1) / 2);
  const bytes = encoded(mid).bytes.length;
  report.push(`rate_control_step ${mid} ${bytes}`);
  if (bytes <= p.target) lo = mid;
  else hi = mid - 1;
}
const controlled = encoded(lo);
const controlledImage = decode(controlled.bytes).image;
report.push(
  `rate_control ${lo} ${controlled.bytes.length} ${controlled.bytes.length <= p.target ? 'yes' : 'no'} ${psnr(image.pixels, controlledImage.pixels)}`,
);
const stream = decode(readHex());
report.push(
  ...stream.segments.map(
    (segment) => `stream_segment ${segment.position} ${segment.name} ${segment.length}`,
  ),
  `stream_image ${stream.frame.width} ${stream.frame.height}`,
  ...stream.frame.components.map(
    (c) => `stream_component ${c.id} ${c.h} ${c.v} ${c.tq} ${c.td} ${c.ta}`,
  ),
);
for (const [id, q] of [...stream.quant].sort((a, b) => a[0] - b[0])) {
  report.push(`stream_quant ${id} ` + zigzag.map((i) => q[i]).join(' '));
}
for (const [, table] of [...stream.huffman].sort((a, b) => a[0] - b[0])) {
  let longest = 0;
  table.counts.forEach((count, i) => {
    if (count) longest = i + 1;
  });
  report.push(
    `stream_huffman ${table.class} ${table.id} symbols ${table.values.length} longest ${longest}`,
  );
}
report.push(
  `stream_restart ${stream.frame.restart} intervals ${stream.spans.length} ok ${stream.states.filter((s) => s === 'ok').length} damaged ${stream.states.filter((s) => s.startsWith('damaged')).length} lost ${stream.states.filter((s) => s === 'lost').length}`,
  ...stream.spans.map(
    (span, j) => `stream_interval ${j} ${span.first} ${span.count} ${stream.states[j]}`,
  ),
  `stream_scan_bytes ${stream.scanBytes}`,
);
const repairFrame: Frame = {
  ...stream.frame,
  components: stream.frame.components.map((c, i) => ({
    ...c,
    id: i + 1,
    tq: i === 0 ? 0 : 1,
    td: i === 0 ? 0 : 1,
    ta: i === 0 ? 0 : 1,
  })),
};
const repairLuma = stream.quant.get(stream.frame.components[0].tq);
const repairChroma = stream.quant.get(stream.frame.components[1].tq);
if (!repairLuma || !repairChroma) throw new Error('Missing repair quantization table');
const repair = pack(repairFrame, stream.blocks, [repairLuma, repairChroma], 'optimized');
const repairedImage = decode(repair.bytes).image;
const identical = stream.image.pixels.every((v, i) => v === repairedImage.pixels[i]);
report.push(
  `repair ${repair.bytes.length} ${repair.headerBytes} ${repair.scanBytes} identical ${identical ? 'yes' : 'no'}`,
);
writeLines('rate_distortion.csv', rate);
writeImage('decoded.ppm', restored.image);
writeHex('bitstream.hex', reference.bytes);
writeImage('thumbnail.ppm', thumbnail);
writeLines('huffman_tables.txt', huffmanLines);
writeLines('blocks.txt', blockLines);
writeImage('stream_decoded.ppm', stream.image);
writeHex('repaired.hex', repair.bytes);
writeLines('report.txt', report);
