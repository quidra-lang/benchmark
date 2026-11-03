import { readFileSync, writeFileSync } from 'node:fs';
import {
  floorDiv,
  round,
  Layer,
  composite,
  type Point,
  type Rectangle,
  type Color,
  type RGB,
  type Segment,
  type FillRule,
  type Block,
  type LayerBlock,
  type Node,
  type Command,
} from './canvas.ts';
import { bresenham, expandPoint, circlePoints, ellipsePoints, bezier } from './primitives.ts';
import { contains, intersection, isEmpty, clipSegment, clipPolygon } from './clipping.ts';
import { fillPolygon, fillShape, floodFill } from './fill.ts';
import { writeImages } from './ppm_writer.ts';

interface Pen {
  width: number;
  colorName: string;
  color: Color;
  on: number;
  off: number;
}
interface Brush {
  colorNames: string[];
  colors: Color[];
  rule: FillRule;
  axis: 'x' | 'y' | null;
}
interface Font {
  width: number;
  height: number;
  glyphs: Map<string, Point[]>;
}
interface Probe {
  kind: string;
  coordinates: number[];
}
interface Input {
  colors: Map<string, Color>;
  pens: Map<string, Pen>;
  brushes: Map<string, Brush>;
  font: Font;
  layers: LayerBlock[];
  symbols: Map<string, Block>;
  width: number;
  height: number;
  backgroundName: string;
  background: Color;
  probes: Probe[];
}
type Matrix = [number, number, number, number, number, number];
interface StatePair {
  matrix: Matrix;
  clip: Rectangle;
}
interface State extends StatePair {
  stack: StatePair[];
}
interface PathCommand {
  keyword: string;
  values: number[];
}
interface Subpath {
  points: Point[];
  closed: boolean;
}
interface KeywordCount {
  executed: number;
  errors: number;
  pixels: number;
}
const penCommands = new Set(['LINE', 'RECT', 'CIRCLE', 'ELLIPSE', 'POLYLINE', 'POLYGON', 'PATH']);
const brushCommands = new Set([
  'FILLRECT',
  'FILLCIRCLE',
  'FILLELLIPSE',
  'FILLPOLYGON',
  'FILLPATH',
  'FLOOD',
  'TEXT',
]);
const stateCommands = new Set([
  'TRANSLATE',
  'SCALE',
  'ROTATE',
  'SAVE',
  'RESTORE',
  'CLIP',
  'NOCLIP',
  'USE',
]);
const errorNames = [
  'unknown_command',
  'bad_arguments',
  'unknown_style',
  'unknown_symbol',
  'unknown_glyph',
  'bad_value',
  'stack_empty',
] as const;
type ErrorName = (typeof errorNames)[number];
type Check = { error: ErrorName } | { path: PathCommand[] | null };
const compareText = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
const isInteger = (word: string) => /^-?[0-9]+$/.test(word);
const readLines = (name: string) => readFileSync(`input/${name}`, 'ascii').split('\n').slice(0, -1);
const writeLines = (name: string, lines: string[]) =>
  writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
const ruleOf = (word: string): FillRule => (word === 'evenodd' ? 'evenodd' : 'nonzero');

function readInput(): Input {
  const colors = new Map<string, Color>();
  const pens = new Map<string, Pen>();
  const brushes = new Map<string, Brush>();
  for (const line of readLines('styles.txt')) {
    if (line === '' || line.startsWith('#')) continue;
    const [kind, name, ...v] = line.split(' ');
    if (kind === 'color') {
      colors.set(name, [Number(v[0]), Number(v[1]), Number(v[2]), Number(v[3])]);
    } else if (kind === 'pen') {
      pens.set(name, {
        width: Number(v[0]),
        colorName: v[1],
        color: colors.get(v[1])!,
        on: Number(v[2]),
        off: Number(v[3]),
      });
    } else if (kind === 'brush') {
      brushes.set(name, {
        colorNames: [v[0]],
        colors: [colors.get(v[0])!],
        rule: ruleOf(v[1]),
        axis: null,
      });
    } else {
      brushes.set(name, {
        colorNames: v.slice(0, 2),
        colors: v.slice(0, 2).map((n) => colors.get(n)!),
        axis: v[2] === 'x' ? 'x' : 'y',
        rule: ruleOf(v[3]),
      });
    }
  }
  const fontLines = readLines('font.txt');
  const header = fontLines[0].split(' ');
  const font: Font = { width: Number(header[1]), height: Number(header[2]), glyphs: new Map() };
  for (let i = 1; i < fontLines.length; i += font.height + 1) {
    const dots: Point[] = [];
    for (let y = 0; y < font.height; y++) {
      for (let x = 0; x < font.width; x++) if (fontLines[i + y + 1][x] === '#') dots.push([x, y]);
    }
    font.glyphs.set(fontLines[i].split(' ')[1], dots);
  }
  const layers: LayerBlock[] = [];
  const symbols = new Map<string, Block>();
  const containers: Node[][] = [];
  let width = 0;
  let height = 0;
  let backgroundName = '';
  let block: Block | undefined;
  const scene = readLines('scene.txt');
  for (let i = 0; i < scene.length; i++) {
    const text = scene[i].replace(/^ +/, '');
    if (text === '' || text.startsWith('#')) continue;
    const [keyword, ...args] = text.split(/ +/);
    const line = i + 1;
    if (keyword === 'CANVAS') {
      width = Number(args[0]);
      height = Number(args[1]);
      backgroundName = args[2];
    } else if (keyword === 'LAYER' || keyword === 'SYMBOL') {
      if (keyword === 'LAYER') {
        const layer: LayerBlock = {
          name: args[0],
          body: [],
          end: 0,
          opacity: Number(args[1]),
          mode: args[2] === 'multiply' ? 'multiply' : args[2] === 'screen' ? 'screen' : 'normal',
        };
        layers.push(layer);
        block = layer;
      } else {
        block = { name: args[0], body: [], end: 0 };
        symbols.set(block.name, block);
      }
      containers.push(block.body);
    } else if (keyword === 'END') {
      block!.end = line;
      containers.pop();
    } else if (keyword === 'REPEAT') {
      const repeat: Node = {
        kind: 'repeat',
        count: Number(args[0]),
        dx: Number(args[1]),
        dy: Number(args[2]),
        body: [],
      };
      containers[containers.length - 1].push(repeat);
      containers.push(repeat.body);
    } else if (keyword === 'ENDREPEAT') containers.pop();
    else containers[containers.length - 1].push({ kind: 'command', keyword, args, line });
  }
  const probes = readLines('probes.txt')
    .slice(1)
    .map((line) => {
      const [kind, ...v] = line.split(' ');
      return { kind, coordinates: v.map(Number) };
    });
  return {
    colors,
    pens,
    brushes,
    font,
    layers,
    symbols,
    width,
    height,
    backgroundName,
    background: colors.get(backgroundName)!,
    probes,
  };
}
function copyPair(pair: StatePair): StatePair {
  return { matrix: [...pair.matrix], clip: [...pair.clip] };
}
function copyState(state: State): State {
  return { ...copyPair(state), stack: state.stack.map(copyPair) };
}
function transform([a, b, c, d, e, f]: Matrix, [x, y]: Point): Point {
  return [a * x + b * y + e, c * x + d * y + f];
}
function deviceRectangle(matrix: Matrix, v: number[]): Rectangle {
  const [x0, y0] = transform(matrix, [v[0], v[1]]);
  const [x1, y1] = transform(matrix, [v[2], v[3]]);
  return [Math.min(x0, x1), Math.min(y0, y1), Math.max(x0, x1), Math.max(y0, y1)];
}
function translate(state: State, dx: number, dy: number): void {
  const [a, b, c, d, e, f] = state.matrix;
  state.matrix = [a, b, c, d, e + a * dx + b * dy, f + c * dx + d * dy];
}
function parsePath(words: string[]): PathCommand[] | null {
  const sizes: Record<string, number> = { M: 2, L: 2, H: 1, V: 1, Q: 4, C: 6, Z: 0 };
  const commands: PathCommand[] = [];
  let i = 0;
  let needMove = true;
  while (i < words.length) {
    const keyword = words[i++];
    const upper = keyword.toUpperCase();
    if (keyword.length !== 1 || !Object.hasOwn(sizes, upper) || (needMove && upper !== 'M')) {
      return null;
    }
    const count = sizes[upper];
    const args = words.slice(i, i + count);
    if (args.length !== count || !args.every(isInteger)) return null;
    commands.push({ keyword, values: args.map(Number) });
    i += count;
    needMove = upper === 'Z';
  }
  return commands.length ? commands : null;
}
function checkCommand({ keyword, args, line }: Command, d: Drawing): Check {
  if (
    !penCommands.has(keyword) &&
    !brushCommands.has(keyword) &&
    !stateCommands.has(keyword) &&
    keyword !== 'ERASE'
  ) {
    return { error: 'unknown_command' };
  }
  const forms: Record<string, [number, number, number]> = {
    LINE: [5, 1, 5],
    RECT: [5, 1, 5],
    FILLRECT: [5, 1, 5],
    CIRCLE: [4, 1, 4],
    FILLCIRCLE: [4, 1, 4],
    ELLIPSE: [5, 1, 5],
    FILLELLIPSE: [5, 1, 5],
    FLOOD: [3, 1, 3],
    TEXT: [5, 1, 3],
    ERASE: [4, 0, 4],
    TRANSLATE: [2, 0, 2],
    SCALE: [2, 0, 2],
    ROTATE: [1, 0, 1],
    SAVE: [0, 0, 0],
    RESTORE: [0, 0, 0],
    NOCLIP: [0, 0, 0],
    CLIP: [4, 0, 4],
    USE: [3, 1, 3],
  };
  let path: PathCommand[] | null = null;
  let valid: boolean;
  if (Object.hasOwn(forms, keyword)) {
    const [count, first, end] = forms[keyword];
    valid = args.length === count && args.slice(first, end).every(isInteger);
  } else if (keyword === 'PATH' || keyword === 'FILLPATH') {
    path = parsePath(args.slice(2));
    valid = args.length >= 2 && isInteger(args[1]) && path !== null;
  } else {
    valid =
      args.length >= 2 && args.slice(1).every(isInteger) && args.length === 2 + 2 * Number(args[1]);
  }
  if (!valid) return { error: 'bad_arguments' };
  const { pens, brushes, symbols, font } = d.data;
  if (
    (penCommands.has(keyword) && !pens.has(args[0])) ||
    (brushCommands.has(keyword) && !brushes.has(args[0]))
  ) {
    return { error: 'unknown_style' };
  }
  if (keyword === 'USE' && (!symbols.has(args[0]) || symbols.get(args[0])!.end > line)) {
    return { error: 'unknown_symbol' };
  }
  if (keyword === 'TEXT' && [...args[4]].some((c) => c !== '_' && !font.glyphs.has(c))) {
    return { error: 'unknown_glyph' };
  }
  let badValue = false;
  if (keyword === 'CIRCLE' || keyword === 'FILLCIRCLE') badValue = Number(args[3]) < 1;
  else if (keyword === 'ELLIPSE' || keyword === 'FILLELLIPSE') {
    badValue = Number(args[3]) < 1 || Number(args[4]) < 1;
  } else if (keyword === 'POLYLINE') badValue = Number(args[1]) < 2;
  else if (keyword === 'POLYGON' || keyword === 'FILLPOLYGON') badValue = Number(args[1]) < 3;
  else if (keyword === 'PATH' || keyword === 'FILLPATH') {
    badValue = Number(args[1]) < 1 || Number(args[1]) > 32;
  } else if (keyword === 'TEXT') badValue = !['left', 'center', 'right'].includes(args[3]);
  else if (keyword === 'SCALE') badValue = Number(args[0]) === 0 || Number(args[1]) === 0;
  else if (keyword === 'FLOOD') {
    badValue = !contains(
      d.state.clip,
      transform(d.state.matrix, [Number(args[1]), Number(args[2])]),
    );
  } else if (keyword === 'CLIP') {
    badValue = isEmpty(
      intersection(d.state.clip, deviceRectangle(d.state.matrix, args.map(Number))),
    );
  }
  if (badValue) return { error: 'bad_value' };
  if (keyword === 'RESTORE' && d.state.stack.length === 0) return { error: 'stack_empty' };
  return { path };
}
function buildSubpaths(commands: PathCommand[], segments: number, matrix: Matrix): Subpath[] {
  const subpaths: Subpath[] = [];
  let current: Point = [0, 0];
  let start: Point = [0, 0];
  for (const { keyword, values } of commands) {
    const upper = keyword.toUpperCase();
    const relative = keyword !== upper;
    if (upper === 'Z') {
      subpaths[subpaths.length - 1].closed = true;
      current = start;
      continue;
    }
    const points: Point[] = [];
    if (upper === 'H') points.push([values[0] + (relative ? current[0] : 0), current[1]]);
    else if (upper === 'V') points.push([current[0], values[0] + (relative ? current[1] : 0)]);
    else {
      for (let i = 0; i < values.length; i += 2) {
        points.push([
          values[i] + (relative ? current[0] : 0),
          values[i + 1] + (relative ? current[1] : 0),
        ]);
      }
    }
    current = points[points.length - 1];
    const device = points.map((p) => transform(matrix, p));
    if (upper === 'M') {
      start = current;
      subpaths.push({ points: device, closed: false });
    } else {
      const last = subpaths[subpaths.length - 1];
      if (upper === 'Q' || upper === 'C') {
        last.points.push(
          ...bezier([last.points[last.points.length - 1], ...device], segments).slice(1),
        );
      } else last.points.push(device[0]);
    }
  }
  return subpaths;
}
function segmentsOf(points: Point[], closed: boolean): Segment[] {
  const segments: Segment[] = [];
  for (let i = 1; i < points.length; i++) segments.push([points[i - 1], points[i]]);
  if (closed) segments.push([points[points.length - 1], points[0]]);
  return segments;
}
function boxOf(pixels: Iterable<number>, width: number): Rectangle | null {
  let box: Rectangle | null = null;
  for (const i of pixels) {
    const x = i % width;
    const y = floorDiv(i, width);
    box =
      box === null
        ? [x, y, x, y]
        : [Math.min(box[0], x), Math.min(box[1], y), Math.max(box[2], x), Math.max(box[3], y)];
  }
  return box;
}
const boxText = (box: Rectangle | null) => (box === null ? 'none' : box.join(' '));

class Drawing {
  readonly layers: Layer[];
  readonly full: Rectangle;
  readonly log: string[] = [];
  readonly counts = { commands: 0, drawing: 0, state: 0, errors: 0, painted: 0, erased: 0 };
  readonly errorCounts = new Map<ErrorName, number>(errorNames.map((n) => [n, 0]));
  readonly keywords = new Map<string, KeywordCount>();
  readonly uses = new Map<string, number>();
  readonly used: Record<'color' | 'pen' | 'brush' | 'symbol', Set<string>>;
  layer!: Layer;
  state!: State;
  constructor(readonly data: Input) {
    this.layers = data.layers.map((b, i) => new Layer(b, data.width, data.height, i + 1));
    this.full = [0, 0, data.width - 1, data.height - 1];
    for (const name of data.symbols.keys()) this.uses.set(name, 0);
    this.used = {
      color: new Set([data.backgroundName]),
      pen: new Set(),
      brush: new Set(),
      symbol: new Set(),
    };
  }
  execute(): void {
    for (const layer of this.layers) {
      this.layer = layer;
      this.state = { matrix: [1, 0, 0, 1, 0, 0], clip: [...this.full], stack: [] };
      this.executeBlock(layer.block.body);
    }
  }
  executeBlock(body: Node[]): void {
    for (const node of body) {
      if (node.kind === 'command') this.executeCommand(node);
      else {
        const saved = copyState(this.state);
        for (let k = 0; k < node.count; k++) {
          this.state = copyState(saved);
          translate(this.state, k * node.dx, k * node.dy);
          this.executeBlock(node.body);
        }
        this.state = copyState(saved);
      }
    }
  }
  executeCommand(command: Command): void {
    const { keyword, args, line } = command;
    const checked = checkCommand(command, this);
    const prefix = `cmd ${++this.counts.commands} line ${line} ${keyword}`;
    this.layer.commands++;
    const count = this.keywords.get(keyword) ?? { executed: 0, errors: 0, pixels: 0 };
    this.keywords.set(keyword, count);
    count.executed++;
    if ('error' in checked) {
      this.log.push(`${prefix} error ${checked.error}`);
      this.counts.errors++;
      this.layer.errors++;
      count.errors++;
      this.errorCounts.set(checked.error, this.errorCounts.get(checked.error)! + 1);
      return;
    }
    if (stateCommands.has(keyword)) {
      this.counts.state++;
      this.log.push(`${prefix} ok`);
      this.executeState(keyword, args);
      return;
    }
    const pixels = this.coverage(keyword, args, checked.path);
    const box = boxOf(pixels, this.data.width);
    this.counts.drawing++;
    count.pixels += pixels.size;
    if (keyword === 'ERASE') {
      for (const i of pixels) this.layer.erase(i);
      this.counts.erased += pixels.size;
    } else {
      this.counts.painted += pixels.size;
      if (penCommands.has(keyword)) {
        const pen = this.data.pens.get(args[0])!;
        this.used.pen.add(args[0]);
        this.used.color.add(pen.colorName);
        for (const i of pixels) this.layer.paint(i, pen.color, line);
      } else {
        const brush = this.data.brushes.get(args[0])!;
        this.used.brush.add(args[0]);
        for (const name of brush.colorNames) this.used.color.add(name);
        for (const i of pixels) this.layer.paint(i, this.brushColor(brush, i, box!), line);
      }
    }
    this.log.push(`${prefix} pixels ${pixels.size} box ${boxText(box)}`);
  }
  executeState(keyword: string, args: string[]): void {
    const state = this.state;
    if (keyword === 'TRANSLATE') translate(state, Number(args[0]), Number(args[1]));
    else if (keyword === 'SCALE') {
      const [sx, sy] = args.map(Number);
      const [a, b, c, d, e, f] = state.matrix;
      state.matrix = [a * sx, b * sy, c * sx, d * sy, e, f];
    } else if (keyword === 'ROTATE') {
      for (let k = 0; k < ((Number(args[0]) % 4) + 4) % 4; k++) {
        const [a, b, c, d, e, f] = state.matrix;
        state.matrix = [b, -a, d, -c, e, f];
      }
    } else if (keyword === 'SAVE') state.stack.push(copyPair(state));
    else if (keyword === 'RESTORE') {
      const pair = state.stack.pop()!;
      state.matrix = pair.matrix;
      state.clip = pair.clip;
    } else if (keyword === 'CLIP') {
      state.clip = intersection(state.clip, deviceRectangle(state.matrix, args.map(Number)));
    } else if (keyword === 'NOCLIP') state.clip = [...this.full];
    else {
      const saved = copyState(state);
      const name = args[0];
      this.uses.set(name, this.uses.get(name)! + 1);
      this.used.symbol.add(name);
      translate(state, Number(args[1]), Number(args[2]));
      this.executeBlock(this.data.symbols.get(name)!.body);
      this.state = copyState(saved);
    }
  }
  rectanglePixels(rectangle: Rectangle, paintedOnly = false): Set<number> {
    const r = intersection(rectangle, this.state.clip);
    const pixels = new Set<number>();
    for (let y = r[1]; y <= r[3]; y++) {
      for (let x = r[0]; x <= r[2]; x++) {
        const i = y * this.data.width + x;
        if (!paintedOnly || this.layer.pixels[i] !== null) pixels.add(i);
      }
    }
    return pixels;
  }
  penPoints(points: Iterable<Point>, pen: Pen, pixels: Set<number>): void {
    for (const p of points) {
      for (const q of expandPoint(p, pen.width)) {
        if (contains(this.state.clip, q)) pixels.add(q[1] * this.data.width + q[0]);
      }
    }
  }
  penSegments(segments: Segment[], pen: Pen): Set<number> {
    const pixels = new Set<number>();
    let position = 0;
    for (const [a, b] of segments) {
      const clipped = clipSegment(a, b, this.state.clip);
      if (clipped === null) continue;
      for (const p of bresenham(clipped[0], clipped[1])) {
        if (pen.off === 0 || position % (pen.on + pen.off) < pen.on) {
          this.penPoints([p], pen, pixels);
        }
        position++;
      }
    }
    return pixels;
  }
  textPixels(args: string[]): Set<number> {
    const [, xt, yt, alignment, text] = args;
    const x = Number(xt);
    const y = Number(yt);
    const font = this.data.font;
    const extent = text.length * (font.width + 1) - 1;
    const left =
      alignment === 'left' ? x : alignment === 'center' ? x - floorDiv(extent, 2) : x - extent + 1;
    const pixels = new Set<number>();
    for (let i = 0; i < text.length; i++) {
      if (text[i] === '_') continue;
      const origin = left + i * (font.width + 1);
      for (const [column, row] of font.glyphs.get(text[i])!) {
        const r = deviceRectangle(this.state.matrix, [
          origin + column,
          y + row,
          origin + column + 1,
          y + row + 1,
        ]);
        r[2]--;
        r[3]--;
        for (const p of this.rectanglePixels(r)) pixels.add(p);
      }
    }
    return pixels;
  }
  coverage(keyword: string, args: string[], path: PathCommand[] | null): Set<number> {
    const matrix = this.state.matrix;
    const clip = this.state.clip;
    const pen = this.data.pens.get(args[0])!;
    const brush = this.data.brushes.get(args[0])!;
    const point = (i: number) => transform(matrix, [Number(args[i]), Number(args[i + 1])]);
    if (keyword === 'ERASE') {
      return this.rectanglePixels(deviceRectangle(matrix, args.map(Number)), true);
    }
    if (keyword === 'FILLRECT') {
      return this.rectanglePixels(deviceRectangle(matrix, args.slice(1).map(Number)));
    }
    if (keyword === 'FLOOD') return floodFill(this.layer, point(1), clip, this.data.width);
    if (keyword === 'TEXT') return this.textPixels(args);
    if (keyword === 'LINE') return this.penSegments([[point(1), point(3)]], pen);
    if (keyword === 'RECT') {
      const [x0, y0, x1, y1] = deviceRectangle(matrix, args.slice(1).map(Number));
      return this.penSegments(
        segmentsOf(
          [
            [x0, y0],
            [x1, y0],
            [x1, y1],
            [x0, y1],
          ],
          true,
        ),
        pen,
      );
    }
    if (['CIRCLE', 'FILLCIRCLE', 'ELLIPSE', 'FILLELLIPSE'].includes(keyword)) {
      const circle = keyword === 'CIRCLE' || keyword === 'FILLCIRCLE';
      const center = point(1);
      const rx = Number(args[3]);
      const ry = circle ? rx : Number(args[4]);
      const [a, b, c, d] = matrix;
      const horizontal = Math.abs(a) * rx + Math.abs(b) * ry;
      const vertical = Math.abs(c) * rx + Math.abs(d) * ry;
      const points =
        circle && horizontal === vertical
          ? circlePoints(horizontal)
          : ellipsePoints(horizontal, vertical);
      if (keyword.startsWith('FILL')) return fillShape(points, center, clip, this.data.width);
      const pixels = new Set<number>();
      this.penPoints(
        points.map(([x, y]): Point => [center[0] + x, center[1] + y]),
        pen,
        pixels,
      );
      return pixels;
    }
    let subpaths: Subpath[];
    if (keyword === 'PATH' || keyword === 'FILLPATH') {
      subpaths = buildSubpaths(path!, Number(args[1]), matrix);
    } else {
      const points: Point[] = [];
      for (let i = 2; i < args.length; i += 2) points.push(point(i));
      subpaths = [{ points, closed: keyword !== 'POLYLINE' }];
    }
    if (keyword === 'FILLPATH' || keyword === 'FILLPOLYGON') {
      return fillPolygon(
        subpaths.map((s) => clipPolygon(s.points, clip)),
        brush.rule,
        clip,
        this.data.width,
      );
    }
    return this.penSegments(
      subpaths.flatMap((s) => segmentsOf(s.points, s.closed)),
      pen,
    );
  }
  brushColor(brush: Brush, i: number, box: Rectangle): Color {
    if (brush.axis === null) return brush.colors[0];
    const axis = brush.axis === 'x' ? 0 : 1;
    const coordinate = axis === 0 ? i % this.data.width : floorDiv(i, this.data.width);
    const length = box[axis + 2] - box[axis];
    const distance = coordinate - box[axis];
    const component = (c: number) =>
      brush.colors[0][c] +
      (length === 0 ? 0 : round((brush.colors[1][c] - brush.colors[0][c]) * distance, length));
    return [component(0), component(1), component(2), component(3)];
  }
}

function colorCounts<C extends RGB | Color>(colors: C[]): { color: C; count: number }[] {
  const groups = new Map<string, { color: C; count: number }>();
  for (const color of colors) {
    const key = color.join(',');
    const item = groups.get(key) ?? { color, count: 0 };
    item.count++;
    groups.set(key, item);
  }
  return [...groups.values()].sort((a, b) => {
    if (a.count !== b.count) return b.count - a.count;
    for (let i = 0; i < a.color.length; i++) {
      if (a.color[i] !== b.color[i]) return a.color[i] - b.color[i];
    }
    return 0;
  });
}
function layerLines(d: Drawing, alphas: number[][]): string[] {
  const lines = [`layers ${d.layers.length}`];
  const blocked = Array<boolean>(d.data.width * d.data.height).fill(false);
  const visible = d.layers.map(() => 0);
  for (let l = d.layers.length - 1; l >= 0; l--) {
    for (let i = 0; i < blocked.length; i++) {
      if (alphas[l][i] > 0 && !blocked[i]) visible[l]++;
      if (alphas[l][i] === 255) blocked[i] = true;
    }
  }
  for (const layer of d.layers) {
    const indices: number[] = [];
    const colors: Color[] = [];
    const b = layer.block;
    for (let i = 0; i < layer.pixels.length; i++) {
      const p = layer.pixels[i];
      if (p !== null) {
        indices.push(i);
        colors.push(p.color);
      }
    }
    const ranked = colorCounts(colors);
    lines.push(
      `layer ${layer.number} ${b.name} opacity ${b.opacity} mode ${b.mode} commands ${layer.commands} errors ${layer.errors} pixels ${indices.length} box ${boxText(boxOf(indices, d.data.width))} visible ${visible[layer.number - 1]} colors ${ranked.length}`,
    );
    for (const item of ranked.slice(0, 5)) {
      lines.push(`color ${item.color.join(' ')} pixels ${item.count}`);
    }
  }
  return lines;
}
function summaryLines(d: Drawing, image: RGB[]): string[] {
  const c = d.counts;
  const colors = colorCounts(image);
  const data = d.data;
  const lines = [
    `canvas ${data.width} ${data.height}`,
    `background ${data.background.slice(0, 3).join(' ')}`,
    `layers ${d.layers.length}`,
    `symbols ${data.symbols.size}`,
    `commands ${c.commands}`,
    `drawing ${c.drawing}`,
    `state ${c.state}`,
    `errors ${c.errors}`,
  ];
  for (const name of errorNames) lines.push(`error ${name} ${d.errorCounts.get(name)}`);
  lines.push(`painted ${c.painted}`, `erased ${c.erased}`, `colors ${colors.length}`);
  colors
    .slice(0, 8)
    .forEach((item, i) => lines.push(`top ${i + 1} ${item.color.join(' ')} pixels ${item.count}`));
  for (const name of [...data.symbols.keys()].sort(compareText)) {
    lines.push(`symbol ${name} uses ${d.uses.get(name)}`);
  }
  for (const name of [...d.keywords.keys()].sort(compareText)) {
    const item = d.keywords.get(name)!;
    lines.push(
      `keyword ${name} executed ${item.executed} errors ${item.errors} pixels ${item.pixels}`,
    );
  }
  const unused: string[] = [];
  const kinds: ['color' | 'pen' | 'brush' | 'symbol', Iterable<string>][] = [
    ['color', data.colors.keys()],
    ['pen', data.pens.keys()],
    ['brush', data.brushes.keys()],
    ['symbol', data.symbols.keys()],
  ];
  for (const [kind, names] of kinds) {
    for (const name of [...names].sort(compareText)) {
      if (!d.used[kind].has(name)) unused.push(`unused ${kind} ${name}`);
    }
  }
  lines.push(`unused ${unused.length}`, ...unused);
  return lines;
}
function probeLines(d: Drawing, image: RGB[], alphas: number[][]): string[] {
  return d.data.probes.map((probe, index) => {
    const prefix = `${probe.kind} ${index + 1} ${probe.coordinates.join(' ')}`;
    const width = d.data.width;
    if (probe.kind === 'point') {
      const [x, y] = probe.coordinates;
      const i = y * width + x;
      const stack: string[] = [];
      for (let l = 0; l < d.layers.length; l++) {
        if (alphas[l][i] > 0) stack.push(`${l + 1}:${d.layers[l].pixels[i]!.line}`);
      }
      return `${prefix} rgb ${image[i].join(' ')} layers ${stack.length} stack ${stack.length ? stack.join(' ') : 'none'}`;
    }
    const [x0, y0, x1, y1] = probe.coordinates;
    const count = (x1 - x0 + 1) * (y1 - y0 + 1);
    const total = [0, 0, 0];
    const colors = new Set<string>();
    const cover = d.layers.map(() => 0);
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const i = y * width + x;
        for (let c = 0; c < 3; c++) total[c] += image[i][c];
        colors.add(image[i].join(','));
        for (let l = 0; l < d.layers.length; l++) if (alphas[l][i] > 0) cover[l]++;
      }
    }
    return `${prefix} pixels ${count} mean ${total.map((v) => floorDiv(v, count)).join(' ')} colors ${colors.size} cover ${cover.join(' ')}`;
  });
}
function main(): void {
  const drawing = new Drawing(readInput());
  drawing.execute();
  const { width, height, background } = drawing.data;
  const image = composite(drawing.layers, background, width * height);
  const alphas = drawing.layers.map((l) => l.pixels.map((_, i) => l.alpha(i)));
  writeImages(image, width, height);
  writeLines('commands.txt', drawing.log);
  writeLines('layers.txt', layerLines(drawing, alphas));
  writeLines('summary.txt', summaryLines(drawing, image));
  writeLines('probes.txt', probeLines(drawing, image, alphas));
}
main();
