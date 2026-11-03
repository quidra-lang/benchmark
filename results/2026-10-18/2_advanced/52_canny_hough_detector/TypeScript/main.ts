import { mkdirSync, writeFileSync } from 'node:fs';
import { readImage, readParams, readTrig, writeImage } from './pgm_io.ts';
import type { Point, Image, Parameters, Trig } from './pgm_io.ts';
import { smooth, gradient } from './filters.ts';
import { directions, suppress, hysteresis, components, neighbors } from './canny.ts';
import { circleVotes, circlePeaks, lineVotes, linePeaks, rho } from './hough.ts';
import type { CirclePeak, LinePeak } from './hough.ts';
import { detect } from './corners.ts';
import type { Corner } from './corners.ts';

interface Pixel extends Point {
  index: number;
}
interface Segment {
  number: number;
  line: number;
  theta: number;
  start: Point;
  end: Point;
  length: number;
  pixels: number[];
}
interface Line extends LinePeak {
  number: number;
  segments: Segment[];
}
interface Measurement {
  number: number;
  pixelCount: number;
  mean: number;
  contrast: number;
  enclosing: Shape | null;
  explained: Uint8Array;
}
interface Circle extends CirclePeak, Measurement {
  type: 'circle';
  gap: number;
  arcs: number;
}
type Kind =
  | 'equilateral_triangle'
  | 'right_triangle'
  | 'triangle'
  | 'square'
  | 'rectangle'
  | 'parallelogram'
  | 'trapezoid'
  | 'quadrilateral';
interface Polygon extends Measurement {
  type: 'polygon';
  segments: Segment[];
  vertices: Point[];
  angles: number[];
  length2: number[];
  support: number[];
  sigma: number;
  area: string;
  kind: Kind;
  vertexCorners: (Corner | null)[];
}
type Shape = Circle | Polygon;
interface MatchedCorner extends Corner {
  match: string;
  matchKind: 'none' | 'polygon' | 'segment';
}
interface Junction {
  point: Point;
  end: number;
}
const cross = (a: Point, b: Point) => a.x * b.y - a.y * b.x;
const subtract = (a: Point, b: Point): Point => ({ x: a.x - b.x, y: a.y - b.y });
const distance = (a: Point, b: Point) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
const angle = (a: number, b: number) => Math.min(Math.abs(a - b), 180 - Math.abs(a - b));
const insideImage = (p: Point, w: number, h: number) => p.x >= 0 && p.x < w && p.y >= 0 && p.y < h;
const shapeReference = (shape: Shape | null) => (shape ? `${shape.type} ${shape.number}` : 'none');
function count(values: Iterable<number>) {
  let total = 0;
  for (const value of values) total += value;
  return total;
}
function rounded(n: number, d: number) {
  if (d < 0) {
    n = -n;
    d = -d;
  }
  return Math.floor((2 * n + d) / (2 * d));
}
function measurement(size: number): Measurement {
  return {
    number: 0,
    pixelCount: 0,
    mean: 0,
    contrast: 0,
    enclosing: null,
    explained: new Uint8Array(size),
  };
}
function bresenham(start: Point, end: Point) {
  const dx = Math.abs(end.x - start.x);
  const dy = -Math.abs(end.y - start.y);
  const sx = start.x < end.x ? 1 : -1;
  const sy = start.y < end.y ? 1 : -1;
  let x = start.x;
  let y = start.y;
  let error = dx + dy;
  const points: Point[] = [];
  while (true) {
    points.push({ x, y });
    if (x === end.x && y === end.y) return points;
    const twice = 2 * error;
    if (twice >= dy) {
      error += dy;
      x += sx;
    }
    if (twice <= dx) {
      error += dx;
      y += sy;
    }
  }
}
function circleGaps(circle: CirclePeak, edges: Uint8Array, w: number, h: number) {
  const half = (p: Point) => (p.y > 0 || (p.y === 0 && p.x > 0) ? 0 : 1);
  const offsets = circle.offsets.slice().sort((a, b) => half(a) - half(b) || -cross(a, b));
  const hits = offsets.map((o) => {
    const q = { x: circle.x + o.x, y: circle.y + o.y };
    return insideImage(q, w, h) && edges[q.y * w + q.x] ? 1 : 0;
  });
  const total = count(hits);
  const n = hits.length;
  if (!total) return { gap: n, arcs: 0 };
  if (total === n) return { gap: 0, arcs: 1 };
  let arcs = 0;
  let gap = 0;
  let run = 0;
  for (let i = 0; i < n; i++) if (hits[i] && !hits[(i + n - 1) % n]) arcs++;
  const first = hits.indexOf(1);
  for (let i = 1; i <= n; i++) {
    if (hits[(first + i) % n]) run = 0;
    else {
      run++;
      gap = Math.max(gap, run);
    }
  }
  return { gap, arcs };
}
function selectCircles(
  peaks: CirclePeak[],
  edges: Uint8Array,
  w: number,
  h: number,
  maximum: number,
): Circle[] {
  peaks.sort(
    (a, b) =>
      b.votes * a.points - a.votes * b.points || a.radius - b.radius || a.y - b.y || a.x - b.x,
  );
  return peaks.slice(0, maximum).map((peak, i) => ({
    ...measurement(edges.length),
    ...peak,
    type: 'circle',
    number: i + 1,
    ...circleGaps(peak, edges, w, h),
  }));
}
function removeCircles(edges: Uint8Array, circles: Circle[], w: number) {
  const removed = new Uint8Array(edges.length);
  const pixels: Pixel[] = [];
  for (let i = 0; i < edges.length; i++) {
    if (edges[i]) {
      const q = { x: i % w, y: Math.floor(i / w), index: i };
      for (const c of circles) {
        const dx = q.x - c.x;
        const dy = q.y - c.y;
        const squared = dx * dx + dy * dy;
        if ((c.radius - 1) ** 2 <= squared && squared <= (c.radius + 1) ** 2) {
          c.explained[i] = removed[i] = 1;
        }
      }
      if (!removed[i]) pixels.push(q);
    }
  }
  return { removed, pixels };
}
function extractSegments(
  peaks: LinePeak[],
  pixels: Pixel[],
  trig: Trig,
  p: Parameters,
  size: number,
) {
  const used = new Uint8Array(size);
  const lines: Line[] = [];
  const segments: Segment[] = [];
  peaks.sort((a, b) => b.votes - a.votes || a.theta - b.theta || a.rho - b.rho);
  for (const peak of peaks) {
    if (lines.length === p.hough_max_lines) break;
    const selected = pixels
      .filter(
        (q) =>
          !used[q.index] &&
          Math.abs(rho(q, peak.theta, trig, p.hough_rho_step) - peak.rho) <= p.segment_tolerance,
      )
      .map((q) => ({ ...q, u: q.y * trig.cos[peak.theta] - q.x * trig.sin[peak.theta] }));
    selected.sort((a, b) => a.u - b.u || a.x - b.x || a.y - b.y);
    const groups: (typeof selected)[] = [];
    for (const q of selected) {
      const last = groups[groups.length - 1];
      if (!last || q.u - last[last.length - 1].u > p.segment_max_gap * 16384) groups.push([q]);
      else last.push(q);
    }
    const accepted = groups.filter(
      (g) => distance(g[0], g[g.length - 1]) + 1 >= p.segment_min_length,
    );
    if (!accepted.length) continue;
    const line: Line = { ...peak, number: lines.length + 1, segments: [] };
    lines.push(line);
    for (const g of accepted) {
      const start = g[0];
      const end = g[g.length - 1];
      const segment = {
        number: segments.length + 1,
        line: line.number,
        theta: peak.theta,
        start,
        end,
        length: distance(start, end) + 1,
        pixels: g.map((q) => q.index),
      };
      segments.push(segment);
      line.segments.push(segment);
      for (const q of g) used[q.index] = 1;
    }
  }
  return { lines, segments, used };
}
function findJunctions(segments: Segment[], p: Parameters) {
  const adjacency = segments.map(() => new Map<number, Junction>());
  let total = 0;
  for (let a = 0; a < segments.length; a++) {
    for (let b = a + 1; b < segments.length; b++) {
      const first = segments[a];
      const second = segments[b];
      if (angle(first.theta, second.theta) < p.junction_min_angle) continue;
      const da = subtract(first.end, first.start);
      const db = subtract(second.end, second.start);
      const den = cross(da, db);
      if (!den) continue;
      const lambda = cross(subtract(second.start, first.start), db);
      const point = {
        x: rounded(first.start.x * den + lambda * da.x, den),
        y: rounded(first.start.y * den + lambda * da.y, den),
      };
      const ea = distance(first.start, point) <= distance(first.end, point) ? 0 : 1;
      const eb = distance(second.start, point) <= distance(second.end, point) ? 0 : 1;
      if (
        distance(ea ? first.end : first.start, point) > p.junction_distance ||
        distance(eb ? second.end : second.start, point) > p.junction_distance
      ) {
        continue;
      }
      adjacency[a].set(b, { point, end: ea });
      adjacency[b].set(a, { point, end: eb });
      total++;
    }
  }
  return { adjacency, total };
}
function findPolygons(segments: Segment[], adjacency: Map<number, Junction>[], size: number) {
  const polygons: Polygon[] = [];
  for (const k of [3, 4]) {
    for (let first = 0; first < segments.length; first++) {
      const search = (path: number[]) => {
        const last = path[path.length - 1];
        if (path.length === k) {
          if (path[1] >= last || !adjacency[last].has(first)) return;
          if (
            adjacency[last].get(path[k - 2])!.end === adjacency[last].get(first)!.end ||
            adjacency[first].get(last)!.end === adjacency[first].get(path[1])!.end
          ) {
            return;
          }
          const vertices = path.map((s, i) => adjacency[s].get(path[(i + k - 1) % k])!.point);
          const turns = vertices.map((v, i) =>
            cross(
              subtract(vertices[(i + 1) % k], v),
              subtract(vertices[(i + 2) % k], vertices[(i + 1) % k]),
            ),
          );
          if (!turns.every((z) => z > 0) && !turns.every((z) => z < 0)) return;
          polygons.push({
            ...measurement(size),
            type: 'polygon',
            segments: path.map((s) => segments[s]),
            vertices,
            angles: [],
            length2: [],
            support: [],
            sigma: 0,
            area: '',
            kind: 'triangle',
            vertexCorners: [],
          });
          return;
        }
        for (const next of [...adjacency[last].keys()].sort((a, b) => a - b)) {
          if (next <= first || path.includes(next)) continue;
          if (
            path.length > 1 &&
            adjacency[last].get(path[path.length - 2])!.end === adjacency[last].get(next)!.end
          ) {
            continue;
          }
          search([...path, next]);
        }
      };
      search([first]);
    }
  }
  polygons.sort((a, b) => {
    if (a.segments.length !== b.segments.length) return a.segments.length - b.segments.length;
    for (let i = 0; i < a.segments.length; i++) {
      const d = a.segments[i].number - b.segments[i].number;
      if (d) return d;
    }
    return 0;
  });
  polygons.forEach((polygon, i) => (polygon.number = i + 1));
  return polygons;
}
function polygonAttributes(
  polygon: Polygon,
  edges: Uint8Array,
  w: number,
  h: number,
  p: Parameters,
) {
  const { vertices: v, segments: s } = polygon;
  const k = v.length;
  for (let i = 0; i < k; i++) {
    const previous = (i + k - 1) % k;
    const next = (i + 1) % k;
    const a = subtract(v[previous], v[i]);
    const b = subtract(v[next], v[i]);
    const phi = angle(s[previous].theta, s[i].theta);
    polygon.angles.push(a.x * b.x + a.y * b.y < 0 ? 180 - phi : phi);
    polygon.length2.push(b.x * b.x + b.y * b.y);
    polygon.sigma += cross(v[i], v[next]);
    const points = bresenham(v[i], v[next]);
    let supported = 0;
    for (const q of points) {
      let hit = false;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const point = { x: q.x + dx, y: q.y + dy };
          if (insideImage(point, w, h)) {
            const index = point.y * w + point.x;
            polygon.explained[index] = 1;
            if (edges[index]) hit = true;
          }
        }
      }
      if (hit) supported++;
    }
    polygon.support.push(Math.floor((100 * supported) / points.length));
  }
  const area = Math.abs(polygon.sigma);
  polygon.area = `${Math.floor(area / 2)}.${area % 2 ? 5 : 0}`;
  if (k === 3) {
    polygon.kind = polygon.angles.every((a) => Math.abs(a - 60) <= p.angle_tolerance)
      ? 'equilateral_triangle'
      : polygon.angles.some((a) => Math.abs(a - 90) <= p.angle_tolerance)
        ? 'right_triangle'
        : 'triangle';
  } else {
    const pa = angle(s[0].theta, s[2].theta) <= p.angle_tolerance;
    const pb = angle(s[1].theta, s[3].theta) <= p.angle_tolerance;
    if (!pa && !pb) polygon.kind = 'quadrilateral';
    else if (!pa || !pb) polygon.kind = 'trapezoid';
    else if (polygon.angles.some((a) => Math.abs(a - 90) > p.angle_tolerance)) {
      polygon.kind = 'parallelogram';
    } else {
      const max = Math.max(...polygon.length2);
      const min = Math.min(...polygon.length2);
      polygon.kind = 100 * (max - min) <= p.square_tolerance * max ? 'square' : 'rectangle';
    }
  }
}
function representatives(shape: Shape): Point[] {
  return shape.type === 'polygon'
    ? shape.vertices
    : [
        { x: shape.x + shape.radius, y: shape.y },
        { x: shape.x, y: shape.y + shape.radius },
        { x: shape.x - shape.radius, y: shape.y },
        { x: shape.x, y: shape.y - shape.radius },
      ];
}
function contains(shape: Shape, q: Point) {
  if (shape.type === 'circle') {
    return (q.x - shape.x) ** 2 + (q.y - shape.y) ** 2 <= shape.radius ** 2;
  }
  return shape.vertices.every((v, i) => {
    const z = cross(subtract(shape.vertices[(i + 1) % shape.vertices.length], v), subtract(q, v));
    return z === 0 || z > 0 === shape.sigma > 0;
  });
}
function measureShapes(shapes: Shape[], image: Image, margin: number) {
  for (const shape of shapes) {
    const reps = representatives(shape);
    const minX = Math.max(0, Math.min(...reps.map((q) => q.x)) - margin);
    const maxX = Math.min(image.width - 1, Math.max(...reps.map((q) => q.x)) + margin);
    const minY = Math.max(0, Math.min(...reps.map((q) => q.y)) - margin);
    const maxY = Math.min(image.height - 1, Math.max(...reps.map((q) => q.y)) + margin);
    let inner = 0;
    let outer = 0;
    let innerSum = 0;
    let outerSum = 0;
    for (let y = minY; y <= maxY; y++) {
      for (let x = minX; x <= maxX; x++) {
        const value = image.pixels[y * image.width + x];
        if (contains(shape, { x, y })) {
          inner++;
          innerSum += value;
        } else {
          outer++;
          outerSum += value;
        }
      }
    }
    shape.pixelCount = inner;
    shape.mean = inner ? Math.floor(innerSum / inner) : 0;
    shape.contrast = shape.mean - (outer ? Math.floor(outerSum / outer) : 0);
  }
  for (const shape of shapes) {
    for (const candidate of shapes) {
      if (
        candidate !== shape &&
        candidate.pixelCount > shape.pixelCount &&
        (!shape.enclosing || candidate.pixelCount < shape.enclosing.pixelCount) &&
        representatives(shape).every((q) => contains(candidate, q))
      ) {
        shape.enclosing = candidate;
      }
    }
  }
}
function matchCorners(
  corners: Corner[],
  polygons: Polygon[],
  segments: Segment[],
  maximum: number,
): MatchedCorner[] {
  const matched = corners.map((corner): MatchedCorner => {
    let best = maximum + 1;
    let match = 'none';
    let matchKind: MatchedCorner['matchKind'] = 'none';
    for (const polygon of polygons) {
      polygon.vertices.forEach((v, i) => {
        const d = distance(corner, v);
        if (d < best) {
          best = d;
          match = `polygon ${polygon.number} vertex ${i + 1}`;
          matchKind = 'polygon';
        }
      });
    }
    if (matchKind === 'none') {
      for (const segment of segments) {
        for (const end of ['start', 'end'] as const) {
          const d = distance(corner, segment[end]);
          if (d < best) {
            best = d;
            match = `segment ${segment.number} ${end}`;
            matchKind = 'segment';
          }
        }
      }
    }
    return { ...corner, match, matchKind };
  });
  for (const polygon of polygons) {
    polygon.vertexCorners = polygon.vertices.map((v) => {
      let best = maximum + 1;
      let chosen: Corner | null = null;
      for (const corner of corners) {
        const d = distance(v, corner);
        if (d < best) {
          best = d;
          chosen = corner;
        }
      }
      return chosen;
    });
  }
  return matched;
}
function componentRows(
  groups: number[][],
  edges: Uint8Array,
  magnitude: number[],
  dir: number[],
  shapes: Shape[],
  w: number,
  h: number,
) {
  return groups.map((group, i) => {
    const xs = group.map((n) => n % w);
    const ys = group.map((n) => Math.floor(n / w));
    const bins = [0, 45, 90, 135].map((d) => group.filter((n) => dir[n] === d).length);
    const main = [0, 45, 90, 135][bins.indexOf(Math.max(...bins))];
    let best = 0;
    let match: Shape | null = null;
    for (const shape of shapes) {
      const n = count(group.map((index) => shape.explained[index]));
      if (n > best) {
        best = n;
        match = shape;
      }
    }
    const ends = group.filter(
      (n) => neighbors(n, w, h).filter((j) => edges[j]).length === 1,
    ).length;
    return `component ${i + 1} pixels ${group.length} box ${Math.min(...xs)} ${Math.min(...ys)} ${Math.max(...xs)} ${Math.max(...ys)} ends ${ends} strength ${Math.floor(count(group.map((n) => magnitude[n])) / group.length)} direction ${main} shape ${shapeReference(match)} explained ${best}`;
  });
}
function voteImage(votes: Map<number, number>[], trig: Trig, w: number, h: number, step: number) {
  let lo = 0;
  let hi = 0;
  let maximum = 0;
  for (let t = 0; t < 180; t++) {
    for (const q of [
      { x: 0, y: 0 },
      { x: w - 1, y: 0 },
      { x: 0, y: h - 1 },
      { x: w - 1, y: h - 1 },
    ]) {
      const r = rho(q, t, trig, step);
      lo = Math.min(lo, r);
      hi = Math.max(hi, r);
    }
    for (const n of votes[t].values()) maximum = Math.max(maximum, n);
  }
  const pixels: number[] = [];
  for (let r = lo; r <= hi; r++) {
    for (let t = 0; t < 180; t++) {
      pixels.push(maximum ? Math.floor((255 * (votes[t].get(r) ?? 0)) / maximum) : 0);
    }
  }
  return { pixels, height: hi - lo + 1, maximum };
}
function main() {
  const image = readImage('input/image.pgm');
  const trig = readTrig('input/trig.txt');
  const p = readParams('input/params.txt');
  const { width: w, height: h } = image;
  const { gx, gy, magnitude } = gradient(smooth(image, p), w, h);
  const dir = directions(gx, gy);
  const nms = suppress(magnitude, dir, w, h);
  const { edges, strong, weak } = hysteresis(nms, w, h, p.canny_low, p.canny_high);
  const groups = components(edges, w, h);
  const circleDetection = circlePeaks(
    circleVotes(edges, w, h, p.circle_min_radius, p.circle_max_radius),
    w,
    h,
    p.circle_min_percent,
  );
  const circles = selectCircles(circleDetection.peaks, edges, w, h, p.circle_max_count);
  const { removed, pixels } = removeCircles(edges, circles, w);
  const votes = lineVotes(pixels, trig, p.hough_rho_step);
  const peaks = linePeaks(votes, p.hough_threshold);
  const vote = voteImage(votes, trig, w, h, p.hough_rho_step);
  const { lines, segments, used } = extractSegments(peaks, pixels, trig, p, edges.length);
  const junctions = findJunctions(segments, p);
  const polygons = findPolygons(segments, junctions.adjacency, edges.length);
  for (const polygon of polygons) polygonAttributes(polygon, edges, w, h, p);
  const shapes: Shape[] = [...polygons, ...circles];
  measureShapes(shapes, image, p.contrast_margin);
  const cornerDetection = detect(
    gx,
    gy,
    w,
    h,
    p.harris_window,
    p.harris_threshold,
    p.harris_max_count,
  );
  const corners = matchCorners(
    cornerDetection.corners,
    polygons,
    segments,
    p.corner_match_distance,
  );
  mkdirSync('output', { recursive: true });
  const write = (file: string, rows: string[]) =>
    writeFileSync(`output/${file}.txt`, rows.join('\n') + '\n', 'ascii');
  writeImage(
    'output/edges.pgm',
    w,
    h,
    edges.map((e) => e * 255),
  );
  writeImage('output/hough.pgm', 180, vote.height, vote.pixels);
  const overlay = image.pixels.map((value) => Math.floor(value / p.overlay_divisor));
  const mark = (q: Point) => {
    if (insideImage(q, w, h)) overlay[q.y * w + q.x] = 255;
  };
  for (const segment of segments) for (const q of bresenham(segment.start, segment.end)) mark(q);
  for (const circle of circles) {
    for (const q of circle.offsets) mark({ x: circle.x + q.x, y: circle.y + q.y });
  }
  for (const corner of corners) {
    for (let e = -2; e <= 2; e++) {
      mark({ x: corner.x + e, y: corner.y });
      mark({ x: corner.x, y: corner.y + e });
    }
  }
  writeImage('output/overlay.pgm', w, h, overlay);
  const lineRows = [`lines ${lines.length}`];
  for (const line of lines) {
    lineRows.push(
      `line ${line.number} theta ${line.theta} rho ${line.rho} votes ${line.votes} segments ${line.segments.length}`,
    );
    for (const s of line.segments) {
      lineRows.push(
        `segment ${s.number} start ${s.start.x} ${s.start.y} end ${s.end.x} ${s.end.y} length ${s.length} pixels ${s.pixels.length}`,
      );
    }
  }
  write('lines', lineRows);
  write('circles', [
    `circles ${circles.length}`,
    ...circles.map(
      (c) =>
        `circle ${c.number} center ${c.x} ${c.y} radius ${c.radius} votes ${c.votes} points ${c.points} gap ${c.gap} arcs ${c.arcs} pixels ${c.pixelCount} mean ${c.mean} contrast ${c.contrast} inside ${shapeReference(c.enclosing)}`,
    ),
  ]);
  const polygonRows = [`polygons ${polygons.length}`];
  for (const q of polygons) {
    polygonRows.push(
      `polygon ${q.number} ${q.kind} segments ${q.segments.map((s) => s.number).join(' ')} area ${q.area} pixels ${q.pixelCount} mean ${q.mean} contrast ${q.contrast} inside ${shapeReference(q.enclosing)}`,
    );
    q.vertices.forEach((v, i) =>
      polygonRows.push(
        `vertex ${i + 1} ${v.x} ${v.y} angle ${q.angles[i]} corner ${q.vertexCorners[i]?.number ?? 'none'}`,
      ),
    );
    q.segments.forEach((s, i) =>
      polygonRows.push(
        `side ${i + 1} segment ${s.number} length2 ${q.length2[i]} support ${q.support[i]}`,
      ),
    );
  }
  write('polygons', polygonRows);
  write('corners', [
    `corners ${corners.length}`,
    ...corners.map(
      (c) => `corner ${c.number} ${c.x} ${c.y} response ${c.response} match ${c.match}`,
    ),
  ]);
  write('components', [
    `components ${groups.length}`,
    ...componentRows(groups, edges, magnitude, dir, shapes, w, h),
  ]);
  const weakKept = count(weak.map((v, i) => (v && edges[i] ? 1 : 0)));
  const report = [`image ${w} ${h}`];
  const metrics: [string, number][] = [
    ['gradient_nonzero', magnitude.filter((n) => n > 0).length],
    ['gradient_max', Math.max(...magnitude)],
    ['nms_kept', nms.filter((n) => n > 0).length],
    ['strong', count(strong)],
    ['weak', count(weak)],
    ['edges', count(edges)],
    ['weak_kept', weakKept],
    ['weak_dropped', count(weak) - weakKept],
    ['edge_components', groups.length],
    ...[0, 45, 90, 135].map((d): [string, number] => [
      `direction_${d}`,
      count(edges.map((e, i) => (e && dir[i] === d ? 1 : 0))),
    ]),
    ['circle_candidates', circleDetection.candidates],
    ['circle_peaks', circleDetection.peaks.length],
    ['circles', circles.length],
    ['circle_edge_pixels', count(removed)],
    ['line_edge_pixels', pixels.length],
    ['hough_max_votes', vote.maximum],
    ['hough_peaks', peaks.length],
    ['lines', lines.length],
    ['segments', segments.length],
    ['claimed_pixels', count(used)],
    ['junctions', junctions.total],
    ['polygons', polygons.length],
    ...[
      'equilateral_triangle',
      'right_triangle',
      'triangle',
      'square',
      'rectangle',
      'parallelogram',
      'trapezoid',
      'quadrilateral',
    ].map((kind): [string, number] => [kind, polygons.filter((q) => q.kind === kind).length]),
    ['corner_candidates', cornerDetection.candidates.length],
    ['corners', corners.length],
    ['corners_on_vertices', corners.filter((c) => c.matchKind === 'polygon').length],
    ['corners_on_segments', corners.filter((c) => c.matchKind === 'segment').length],
    ['corners_unmatched', corners.filter((c) => c.matchKind === 'none').length],
    [
      'vertices_with_corner',
      count(polygons.map((q) => q.vertexCorners.filter((c) => c !== null).length)),
    ],
  ];
  report.push(...metrics.map(([name, value]) => `${name} ${value}`));
  write('report', report);
}
main();
