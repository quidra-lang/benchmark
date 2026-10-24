'use strict';

const fs = require('node:fs');
const { floorDiv, round, Layer, composite } = require('./canvas');
const { bresenham, expandPoint, circlePoints, ellipsePoints, bezier } = require('./primitives');
const { contains, intersection, isEmpty, clipSegment, clipPolygon } = require('./clipping');
const { fillPolygon, fillShape, floodFill } = require('./fill');
const { writeImages } = require('./ppm_writer');

const penCommands = new Set(['LINE', 'RECT', 'CIRCLE', 'ELLIPSE', 'POLYLINE', 'POLYGON', 'PATH']);
const brushCommands = new Set(['FILLRECT', 'FILLCIRCLE', 'FILLELLIPSE', 'FILLPOLYGON', 'FILLPATH', 'FLOOD', 'TEXT']);
const stateCommands = new Set(['TRANSLATE', 'SCALE', 'ROTATE', 'SAVE', 'RESTORE', 'CLIP', 'NOCLIP', 'USE']);
const errorNames = ['unknown_command', 'bad_arguments', 'unknown_style', 'unknown_symbol', 'unknown_glyph', 'bad_value', 'stack_empty'];
const compareText = (left, right) => left < right ? -1 : left > right ? 1 : 0;
const isInteger = word => /^-?[0-9]+$/.test(word);
const readLines = name => fs.readFileSync(`input/${name}`, 'ascii').split('\n').slice(0, -1);
const writeLines = (name, lines) => fs.writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');

function readInput() {
  const colors = new Map(), pens = new Map(), brushes = new Map();
  for (const line of readLines('styles.txt')) {
    if (line === '' || line.startsWith('#')) continue;
    const [kind, name, ...values] = line.split(' ');
    if (kind === 'color') colors.set(name, values.map(Number));
    else if (kind === 'pen') pens.set(name, { width: Number(values[0]), colorName: values[1],
      color: colors.get(values[1]), on: Number(values[2]), off: Number(values[3]) });
    else if (kind === 'brush') brushes.set(name, { colorNames: [values[0]],
      colors: [colors.get(values[0])], rule: values[1], axis: null });
    else brushes.set(name, { colorNames: values.slice(0, 2), colors: values.slice(0, 2).map(value => colors.get(value)),
      axis: values[2], rule: values[3] });
  }
  const fontLines = readLines('font.txt'), [, glyphWidth, glyphHeight] = fontLines[0].split(' ');
  const font = { width: Number(glyphWidth), height: Number(glyphHeight), glyphs: new Map() };
  for (let index = 1; index < fontLines.length; index += font.height + 1) {
    const character = fontLines[index].split(' ')[1], dots = [];
    for (let y = 0; y < font.height; y++) for (let x = 0; x < font.width; x++) {
      if (fontLines[index + y + 1][x] === '#') dots.push([x, y]);
    }
    font.glyphs.set(character, dots);
  }
  const layers = [], symbols = new Map(), containers = [];
  let width, height, backgroundName, block;
  const scene = readLines('scene.txt');
  for (let index = 0; index < scene.length; index++) {
    const text = scene[index].replace(/^ +/, '');
    if (text === '' || text.startsWith('#')) continue;
    const [keyword, ...args] = text.split(/ +/), line = index + 1;
    if (keyword === 'CANVAS') [width, height, backgroundName] = [Number(args[0]), Number(args[1]), args[2]];
    else if (keyword === 'LAYER' || keyword === 'SYMBOL') {
      block = { name: args[0], body: [], end: null };
      if (keyword === 'LAYER') {
        Object.assign(block, { opacity: Number(args[1]), mode: args[2] });
        layers.push(block);
      } else symbols.set(block.name, block);
      containers.push(block.body);
    } else if (keyword === 'END') { block.end = line; containers.pop(); }
    else if (keyword === 'REPEAT') {
      const repeat = { kind: 'repeat', count: Number(args[0]), dx: Number(args[1]), dy: Number(args[2]), body: [] };
      containers.at(-1).push(repeat);
      containers.push(repeat.body);
    } else if (keyword === 'ENDREPEAT') containers.pop();
    else containers.at(-1).push({ kind: 'command', keyword, args, line });
  }
  const probes = readLines('probes.txt').slice(1).map(line => {
    const [kind, ...values] = line.split(' ');
    return { kind, coordinates: values.map(Number) };
  });
  return { colors, pens, brushes, font, layers, symbols, width, height, backgroundName,
    background: colors.get(backgroundName), probes };
}

function copyState(state) {
  return { matrix: [...state.matrix], clip: [...state.clip],
    stack: state.stack.map(pair => ({ matrix: [...pair.matrix], clip: [...pair.clip] })) };
}

function transform(matrix, [x, y]) {
  const [a, b, c, d, e, f] = matrix;
  return [a * x + b * y + e, c * x + d * y + f];
}

function deviceRectangle(matrix, values) {
  const [x0, y0] = transform(matrix, values.slice(0, 2)), [x1, y1] = transform(matrix, values.slice(2, 4));
  return [Math.min(x0, x1), Math.min(y0, y1), Math.max(x0, x1), Math.max(y0, y1)];
}

function translate(state, dx, dy) {
  const [a, b, c, d, e, f] = state.matrix;
  state.matrix = [a, b, c, d, e + a * dx + b * dy, f + c * dx + d * dy];
}

function parsePath(words) {
  const sizes = { M: 2, L: 2, H: 1, V: 1, Q: 4, C: 6, Z: 0 }, commands = [];
  let index = 0, needMove = true;
  while (index < words.length) {
    const keyword = words[index++], upper = keyword.toUpperCase();
    if (keyword.length !== 1 || !Object.hasOwn(sizes, upper) || (needMove && upper !== 'M')) return null;
    const count = sizes[upper], args = words.slice(index, index + count);
    if (args.length !== count || !args.every(isInteger)) return null;
    commands.push({ keyword, values: args.map(Number) });
    index += count;
    needMove = upper === 'Z';
  }
  return commands.length === 0 ? null : commands;
}

function checkCommand(command, drawing) {
  const { keyword, args, line } = command;
  if (!penCommands.has(keyword) && !brushCommands.has(keyword) && !stateCommands.has(keyword) && keyword !== 'ERASE') {
    return { error: 'unknown_command' };
  }
  const forms = {
    LINE: [5, 1, 5], RECT: [5, 1, 5], FILLRECT: [5, 1, 5], CIRCLE: [4, 1, 4], FILLCIRCLE: [4, 1, 4],
    ELLIPSE: [5, 1, 5], FILLELLIPSE: [5, 1, 5], FLOOD: [3, 1, 3], TEXT: [5, 1, 3],
    ERASE: [4, 0, 4], TRANSLATE: [2, 0, 2], SCALE: [2, 0, 2], ROTATE: [1, 0, 1],
    SAVE: [0, 0, 0], RESTORE: [0, 0, 0], NOCLIP: [0, 0, 0], CLIP: [4, 0, 4], USE: [3, 1, 3]
  };
  let path = null, valid;
  if (Object.hasOwn(forms, keyword)) {
    const [count, first, end] = forms[keyword];
    valid = args.length === count && args.slice(first, end).every(isInteger);
  } else if (keyword === 'PATH' || keyword === 'FILLPATH') {
    path = parsePath(args.slice(2));
    valid = args.length >= 2 && isInteger(args[1]) && path !== null;
  } else valid = args.length >= 2 && args.slice(1).every(isInteger) && args.length === 2 + 2 * Number(args[1]);
  if (!valid) return { error: 'bad_arguments' };
  if ((penCommands.has(keyword) && !drawing.pens.has(args[0])) || (brushCommands.has(keyword) && !drawing.brushes.has(args[0]))) {
    return { error: 'unknown_style' };
  }
  if (keyword === 'USE' && (!drawing.symbols.has(args[0]) || drawing.symbols.get(args[0]).end > line)) return { error: 'unknown_symbol' };
  if (keyword === 'TEXT' && [...args[4]].some(character => character !== '_' && !drawing.font.glyphs.has(character))) {
    return { error: 'unknown_glyph' };
  }
  let badValue = false;
  if (keyword === 'CIRCLE' || keyword === 'FILLCIRCLE') badValue = Number(args[3]) < 1;
  else if (keyword === 'ELLIPSE' || keyword === 'FILLELLIPSE') badValue = Number(args[3]) < 1 || Number(args[4]) < 1;
  else if (keyword === 'POLYLINE') badValue = Number(args[1]) < 2;
  else if (keyword === 'POLYGON' || keyword === 'FILLPOLYGON') badValue = Number(args[1]) < 3;
  else if (keyword === 'PATH' || keyword === 'FILLPATH') badValue = Number(args[1]) < 1 || Number(args[1]) > 32;
  else if (keyword === 'TEXT') badValue = !['left', 'center', 'right'].includes(args[3]);
  else if (keyword === 'SCALE') badValue = Number(args[0]) === 0 || Number(args[1]) === 0;
  else if (keyword === 'FLOOD') badValue = !contains(drawing.state.clip, transform(drawing.state.matrix, args.slice(1).map(Number)));
  else if (keyword === 'CLIP') badValue = isEmpty(intersection(drawing.state.clip, deviceRectangle(drawing.state.matrix, args.map(Number))));
  if (badValue) return { error: 'bad_value' };
  if (keyword === 'RESTORE' && drawing.state.stack.length === 0) return { error: 'stack_empty' };
  return { path };
}

function buildSubpaths(commands, segments, matrix) {
  const subpaths = [];
  let current = [0, 0], start = [0, 0];
  for (const { keyword, values } of commands) {
    const upper = keyword.toUpperCase(), relative = keyword !== upper;
    if (upper === 'Z') { subpaths.at(-1).closed = true; current = start; continue; }
    const points = [];
    if (upper === 'H') points.push([values[0] + (relative ? current[0] : 0), current[1]]);
    else if (upper === 'V') points.push([current[0], values[0] + (relative ? current[1] : 0)]);
    else for (let index = 0; index < values.length; index += 2) {
      points.push([values[index] + (relative ? current[0] : 0), values[index + 1] + (relative ? current[1] : 0)]);
    }
    current = points.at(-1);
    const device = points.map(point => transform(matrix, point));
    if (upper === 'M') { start = current; subpaths.push({ points: device, closed: false }); }
    else if (upper === 'Q' || upper === 'C') {
      const subpath = subpaths.at(-1);
      subpath.points.push(...bezier([subpath.points.at(-1), ...device], segments).slice(1));
    } else subpaths.at(-1).points.push(device[0]);
  }
  return subpaths;
}

function segmentsOf(points, closed) {
  const segments = [];
  for (let index = 1; index < points.length; index++) segments.push([points[index - 1], points[index]]);
  if (closed) segments.push([points.at(-1), points[0]]);
  return segments;
}

function boxOf(pixels, width) {
  if (pixels.size === 0 || pixels.length === 0) return null;
  const first = pixels.values().next().value;
  let x0 = first % width, y0 = floorDiv(first, width), x1 = x0, y1 = y0;
  for (const index of pixels) {
    const x = index % width, y = floorDiv(index, width);
    x0 = Math.min(x0, x); y0 = Math.min(y0, y);
    x1 = Math.max(x1, x); y1 = Math.max(y1, y);
  }
  return [x0, y0, x1, y1];
}

const boxText = box => box === null ? 'none' : box.join(' ');

class Drawing {
  constructor(data) {
    Object.assign(this, data);
    this.layers = data.layers.map((block, index) => new Layer(block, data.width, data.height, index + 1));
    this.full = [0, 0, this.width - 1, this.height - 1];
    this.log = [];
    this.counts = { commands: 0, drawing: 0, state: 0, errors: 0, painted: 0, erased: 0 };
    this.errorCounts = new Map(errorNames.map(name => [name, 0]));
    this.keywords = new Map();
    this.uses = new Map([...this.symbols.keys()].map(name => [name, 0]));
    this.used = { color: new Set([this.backgroundName]), pen: new Set(), brush: new Set(), symbol: new Set() };
  }

  execute() {
    for (const layer of this.layers) {
      this.layer = layer;
      this.state = { matrix: [1, 0, 0, 1, 0, 0], clip: [...this.full], stack: [] };
      this.executeBlock(layer.body);
    }
  }

  executeBlock(body) {
    for (const node of body) {
      if (node.kind === 'command') this.executeCommand(node);
      else {
        const saved = copyState(this.state);
        for (let iteration = 0; iteration < node.count; iteration++) {
          this.state = copyState(saved);
          translate(this.state, iteration * node.dx, iteration * node.dy);
          this.executeBlock(node.body);
        }
        this.state = copyState(saved);
      }
    }
  }

  executeCommand(command) {
    const { keyword, args, line } = command, checked = checkCommand(command, this);
    const sequence = ++this.counts.commands, prefix = `cmd ${sequence} line ${line} ${keyword}`;
    this.layer.commands++;
    if (!this.keywords.has(keyword)) this.keywords.set(keyword, { executed: 0, errors: 0, pixels: 0 });
    const keywordCount = this.keywords.get(keyword);
    keywordCount.executed++;
    if (checked.error) {
      this.log.push(`${prefix} error ${checked.error}`);
      this.counts.errors++; this.layer.errors++; keywordCount.errors++;
      this.errorCounts.set(checked.error, this.errorCounts.get(checked.error) + 1);
      return;
    }
    if (stateCommands.has(keyword)) {
      this.counts.state++;
      this.log.push(`${prefix} ok`);
      this.executeState(keyword, args);
      return;
    }
    const pixels = this.coverage(keyword, args, checked.path), box = boxOf(pixels, this.width);
    this.counts.drawing++;
    keywordCount.pixels += pixels.size;
    if (keyword === 'ERASE') {
      for (const index of pixels) this.layer.erase(index);
      this.counts.erased += pixels.size;
    } else {
      this.counts.painted += pixels.size;
      if (penCommands.has(keyword)) {
        const pen = this.pens.get(args[0]);
        this.used.pen.add(args[0]); this.used.color.add(pen.colorName);
        for (const index of pixels) this.layer.paint(index, pen.color, line);
      } else {
        const brush = this.brushes.get(args[0]);
        this.used.brush.add(args[0]);
        for (const name of brush.colorNames) this.used.color.add(name);
        for (const index of pixels) this.layer.paint(index, this.brushColor(brush, index, box), line);
      }
    }
    this.log.push(`${prefix} pixels ${pixels.size} box ${boxText(box)}`);
  }

  executeState(keyword, args) {
    const state = this.state;
    if (keyword === 'TRANSLATE') translate(state, ...args.map(Number));
    else if (keyword === 'SCALE') {
      const [sx, sy] = args.map(Number), [a, b, c, d, e, f] = state.matrix;
      state.matrix = [a * sx, b * sy, c * sx, d * sy, e, f];
    } else if (keyword === 'ROTATE') {
      const turns = ((Number(args[0]) % 4) + 4) % 4;
      for (let turn = 0; turn < turns; turn++) {
        const [a, b, c, d, e, f] = state.matrix;
        state.matrix = [b, -a, d, -c, e, f];
      }
    } else if (keyword === 'SAVE') state.stack.push({ matrix: [...state.matrix], clip: [...state.clip] });
    else if (keyword === 'RESTORE') Object.assign(state, state.stack.pop());
    else if (keyword === 'CLIP') state.clip = intersection(state.clip, deviceRectangle(state.matrix, args.map(Number)));
    else if (keyword === 'NOCLIP') state.clip = [...this.full];
    else {
      const saved = copyState(state), name = args[0];
      this.uses.set(name, this.uses.get(name) + 1);
      this.used.symbol.add(name);
      translate(state, Number(args[1]), Number(args[2]));
      this.executeBlock(this.symbols.get(name).body);
      this.state = copyState(saved);
    }
  }

  rectanglePixels(rectangle, paintedOnly = false) {
    const clipped = intersection(rectangle, this.state.clip), pixels = new Set();
    for (let y = clipped[1]; y <= clipped[3]; y++) for (let x = clipped[0]; x <= clipped[2]; x++) {
      const index = y * this.width + x;
      if (!paintedOnly || this.layer.pixels[index] !== null) pixels.add(index);
    }
    return pixels;
  }

  penPoints(points, pen, pixels) {
    for (const point of points) for (const expanded of expandPoint(point, pen.width)) {
      if (contains(this.state.clip, expanded)) pixels.add(expanded[1] * this.width + expanded[0]);
    }
  }

  penSegments(segments, pen) {
    const pixels = new Set();
    let position = 0;
    for (const [start, end] of segments) {
      const clipped = clipSegment(start, end, this.state.clip);
      if (clipped === null) continue;
      for (const point of bresenham(...clipped)) {
        if (pen.off === 0 || position % (pen.on + pen.off) < pen.on) this.penPoints([point], pen, pixels);
        position++;
      }
    }
    return pixels;
  }

  textPixels(args) {
    const [, xText, yText, alignment, text] = args, x = Number(xText), y = Number(yText);
    const extent = text.length * (this.font.width + 1) - 1;
    const left = alignment === 'left' ? x : alignment === 'center' ? x - floorDiv(extent, 2) : x - extent + 1;
    const pixels = new Set();
    for (let index = 0; index < text.length; index++) {
      if (text[index] === '_') continue;
      const origin = left + index * (this.font.width + 1);
      for (const [column, row] of this.font.glyphs.get(text[index])) {
        const rectangle = deviceRectangle(this.state.matrix, [origin + column, y + row, origin + column + 1, y + row + 1]);
        rectangle[2]--; rectangle[3]--;
        for (const pixel of this.rectanglePixels(rectangle)) pixels.add(pixel);
      }
    }
    return pixels;
  }

  coverage(keyword, args, path) {
    const matrix = this.state.matrix, clip = this.state.clip, pen = this.pens.get(args[0]), brush = this.brushes.get(args[0]);
    if (keyword === 'ERASE') return this.rectanglePixels(deviceRectangle(matrix, args.map(Number)), true);
    if (keyword === 'FILLRECT') return this.rectanglePixels(deviceRectangle(matrix, args.slice(1).map(Number)));
    if (keyword === 'FLOOD') return floodFill(this.layer, transform(matrix, args.slice(1).map(Number)), clip, this.width);
    if (keyword === 'TEXT') return this.textPixels(args);
    if (keyword === 'LINE') return this.penSegments([[transform(matrix, args.slice(1, 3).map(Number)),
      transform(matrix, args.slice(3, 5).map(Number))]], pen);
    if (keyword === 'RECT') {
      const [x0, y0, x1, y1] = deviceRectangle(matrix, args.slice(1).map(Number));
      return this.penSegments(segmentsOf([[x0, y0], [x1, y0], [x1, y1], [x0, y1]], true), pen);
    }
    if (['CIRCLE', 'FILLCIRCLE', 'ELLIPSE', 'FILLELLIPSE'].includes(keyword)) {
      const circle = keyword === 'CIRCLE' || keyword === 'FILLCIRCLE';
      const center = transform(matrix, args.slice(1, 3).map(Number)), rx = Number(args[3]), ry = circle ? rx : Number(args[4]);
      const [a, b, c, d] = matrix, horizontal = Math.abs(a) * rx + Math.abs(b) * ry, vertical = Math.abs(c) * rx + Math.abs(d) * ry;
      const points = circle && horizontal === vertical ? circlePoints(horizontal) : ellipsePoints(horizontal, vertical);
      if (keyword.startsWith('FILL')) return fillShape(points, center, clip, this.width);
      const pixels = new Set();
      this.penPoints(points.map(([x, y]) => [center[0] + x, center[1] + y]), pen, pixels);
      return pixels;
    }
    let subpaths;
    if (keyword === 'PATH' || keyword === 'FILLPATH') subpaths = buildSubpaths(path, Number(args[1]), matrix);
    else {
      const points = [];
      for (let index = 2; index < args.length; index += 2) points.push(transform(matrix, [Number(args[index]), Number(args[index + 1])]));
      subpaths = [{ points, closed: keyword !== 'POLYLINE' }];
    }
    if (keyword === 'FILLPATH' || keyword === 'FILLPOLYGON') {
      return fillPolygon(subpaths.map(subpath => clipPolygon(subpath.points, clip)), brush.rule, clip, this.width);
    }
    return this.penSegments(subpaths.flatMap(subpath => segmentsOf(subpath.points, subpath.closed)), pen);
  }

  brushColor(brush, index, box) {
    if (brush.axis === null) return brush.colors[0];
    const axis = brush.axis === 'x' ? 0 : 1, coordinate = axis === 0 ? index % this.width : floorDiv(index, this.width);
    const length = box[axis + 2] - box[axis], distance = coordinate - box[axis];
    return brush.colors[0].map((value, channel) => length === 0 ? value
      : value + round((brush.colors[1][channel] - value) * distance, length));
  }
}

function colorCounts(colors) {
  const groups = new Map();
  for (const color of colors) {
    const key = color.join(',');
    if (!groups.has(key)) groups.set(key, { color, count: 0 });
    groups.get(key).count++;
  }
  return [...groups.values()].sort((left, right) => {
    if (left.count !== right.count) return right.count - left.count;
    for (let index = 0; index < left.color.length; index++) {
      if (left.color[index] !== right.color[index]) return left.color[index] - right.color[index];
    }
    return 0;
  });
}

function layerLines(drawing, alphas) {
  const lines = [`layers ${drawing.layers.length}`], blocked = Array(drawing.width * drawing.height).fill(false);
  const visible = drawing.layers.map(() => 0);
  for (let layer = drawing.layers.length - 1; layer >= 0; layer--) for (let index = 0; index < blocked.length; index++) {
    if (alphas[layer][index] > 0 && !blocked[index]) visible[layer]++;
    if (alphas[layer][index] === 255) blocked[index] = true;
  }
  for (const layer of drawing.layers) {
    const indices = [], colors = [];
    for (let index = 0; index < layer.pixels.length; index++) if (layer.pixels[index] !== null) {
      indices.push(index); colors.push(layer.pixels[index].color);
    }
    const ranked = colorCounts(colors);
    lines.push(`layer ${layer.number} ${layer.name} opacity ${layer.opacity} mode ${layer.mode} commands ${layer.commands}`
      + ` errors ${layer.errors} pixels ${indices.length} box ${boxText(boxOf(indices, drawing.width))}`
      + ` visible ${visible[layer.number - 1]} colors ${ranked.length}`);
    for (const item of ranked.slice(0, 5)) lines.push(`color ${item.color.join(' ')} pixels ${item.count}`);
  }
  return lines;
}

function summaryLines(drawing, image) {
  const counts = drawing.counts, colors = colorCounts(image);
  const lines = [`canvas ${drawing.width} ${drawing.height}`, `background ${drawing.background.slice(0, 3).join(' ')}`,
    `layers ${drawing.layers.length}`, `symbols ${drawing.symbols.size}`, `commands ${counts.commands}`,
    `drawing ${counts.drawing}`, `state ${counts.state}`, `errors ${counts.errors}`];
  for (const name of errorNames) lines.push(`error ${name} ${drawing.errorCounts.get(name)}`);
  lines.push(`painted ${counts.painted}`, `erased ${counts.erased}`, `colors ${colors.length}`);
  for (let index = 0; index < Math.min(8, colors.length); index++) {
    lines.push(`top ${index + 1} ${colors[index].color.join(' ')} pixels ${colors[index].count}`);
  }
  for (const name of [...drawing.symbols.keys()].sort(compareText)) lines.push(`symbol ${name} uses ${drawing.uses.get(name)}`);
  for (const keyword of [...drawing.keywords.keys()].sort(compareText)) {
    const value = drawing.keywords.get(keyword);
    lines.push(`keyword ${keyword} executed ${value.executed} errors ${value.errors} pixels ${value.pixels}`);
  }
  const unused = [];
  for (const [kind, items] of [['color', drawing.colors], ['pen', drawing.pens], ['brush', drawing.brushes], ['symbol', drawing.symbols]]) {
    for (const name of [...items.keys()].sort(compareText)) if (!drawing.used[kind].has(name)) unused.push(`unused ${kind} ${name}`);
  }
  lines.push(`unused ${unused.length}`, ...unused);
  return lines;
}

function probeLines(drawing, image, alphas) {
  return drawing.probes.map((probe, index) => {
    const prefix = `${probe.kind} ${index + 1} ${probe.coordinates.join(' ')}`;
    if (probe.kind === 'point') {
      const [x, y] = probe.coordinates, pixel = y * drawing.width + x, stack = [];
      for (let layer = 0; layer < drawing.layers.length; layer++) if (alphas[layer][pixel] > 0) {
        stack.push(`${layer + 1}:${drawing.layers[layer].pixels[pixel].line}`);
      }
      return `${prefix} rgb ${image[pixel].join(' ')} layers ${stack.length} stack ${stack.length === 0 ? 'none' : stack.join(' ')}`;
    }
    const [x0, y0, x1, y1] = probe.coordinates, count = (x1 - x0 + 1) * (y1 - y0 + 1);
    const total = [0, 0, 0], colors = new Set(), cover = drawing.layers.map(() => 0);
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
      const pixel = y * drawing.width + x, color = image[pixel];
      for (let channel = 0; channel < 3; channel++) total[channel] += color[channel];
      colors.add(color.join(','));
      for (let layer = 0; layer < drawing.layers.length; layer++) if (alphas[layer][pixel] > 0) cover[layer]++;
    }
    return `${prefix} pixels ${count} mean ${total.map(value => floorDiv(value, count)).join(' ')} colors ${colors.size} cover ${cover.join(' ')}`;
  });
}

function main() {
  const drawing = new Drawing(readInput());
  drawing.execute();
  const image = composite(drawing.layers, drawing.background, drawing.width * drawing.height);
  const alphas = drawing.layers.map(layer => layer.pixels.map((_, index) => layer.alpha(index)));
  writeImages(image, drawing.width, drawing.height);
  writeLines('commands.txt', drawing.log);
  writeLines('layers.txt', layerLines(drawing, alphas));
  writeLines('summary.txt', summaryLines(drawing, image));
  writeLines('probes.txt', probeLines(drawing, image, alphas));
}

main();
