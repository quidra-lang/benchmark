import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { Fraction, point, cross, equal, pointOrder, pointKey, pointText, segmentText } from './rational.ts';
import { onSegment, touch, overlap, lineIntersection } from './intersections.ts';
import * as rings from './rings.ts';
import { GreinerHormann } from './greiner_hormann.ts';
import { render } from './render.ts';
import type { Point } from './rational.ts';
import type {
  Ring, Region, Polygon, PolygonRegistry, ResultTarget, RecordLine,
  Operation, Prepared, PolygonValues, RingRecord,
} from './types.ts';

const KINDS = ['UNION', 'INTERSECTION', 'DIFFERENCE', 'XOR', 'CLIP', 'AREA', 'MOVE', 'ROTATE', 'MIRROR', 'SNAP', 'LOCATE', 'RENDER'];
const BINARY = new Set(KINDS.slice(0, 5)), DEFINITIONS = new Set(['MOVE', 'ROTATE', 'MIRROR', 'SNAP']);
const WORD_COUNTS = [3, 3, 3, 3, 3, 2, 5, 6, 5, 3, 4, 8];
const integerWord = (word: string): boolean => /^-?[0-9]{1,9}$/.test(word);
const nameWord = (word: string): boolean => /^[a-z0-9_]{1,16}$/.test(word);
const integerIn = (word: string, low: number, high: number): boolean => integerWord(word) && Number(word) >= low && Number(word) <= high;
const fixed = (value: number, digits = 3): string => value.toFixed(digits);
const LIMIT = new Fraction(1000);
const outOfRange = (p: Point): boolean => p.x.sign() < 0 || p.y.sign() < 0 || p.x.compare(LIMIT) > 0 || p.y.compare(LIMIT) > 0;
const polygonResult = (polygon: Polygon): Region[] => [{ outer: polygon.rings[0], holes: polygon.rings.slice(1) }];

function readRecords(path: string): RecordLine[] {
  return readFileSync(path, 'ascii').split('\n').slice(0, -1)
    .map((text, index) => ({ text, line: index + 1 })).filter(record => record.text !== '' && !record.text.startsWith('#'));
}

function parseRings(content: RecordLine[], endLine: number): {reason?: string; rings?: Ring[]} {
  const result: Ring[] = [];
  let index = 0;
  while (index < content.length) {
    const header = content[index++], words = header.text.split(' '), count = Number(words[1]);
    if (words.length !== 2 || !['OUTER', 'HOLE'].includes(words[0]) || !/^[0-9]{1,9}$/.test(words[1]) || count < 1
      || (words[0] === 'OUTER' ? result.length !== 0 : result.length === 0)) return { reason: `format line ${header.line}` };
    const ring: Ring = [];
    for (let vertex = 0; vertex < count; vertex++) {
      if (index === content.length) return { reason: `format line ${endLine}` };
      const record = content[index++], coordinates = record.text.split(' ');
      if (coordinates.length !== 2 || !coordinates.every(integerWord)) return { reason: `format line ${record.line}` };
      ring.push(point(Number(coordinates[0]), Number(coordinates[1])));
    }
    result.push(ring);
  }
  return result.length === 0 ? { reason: `format line ${endLine}` } : { rings: result };
}

function checkPolygon(sequence: Ring[]): string | null {
  for (let k = 0; k < sequence.length; k++) {
    const ring = sequence[k], size = ring.length, number = k + 1;
    if (size < 3) return `too_few_vertices ring ${number}`;
    for (const p of ring) if (outOfRange(p)) return `out_of_range ring ${number} ${pointText(p)}`;
    const seen = new Set<string>();
    for (const p of ring) {
      const key = pointKey(p);
      if (seen.has(key)) return `duplicate_vertex ring ${number} ${pointText(p)}`;
      seen.add(key);
    }
    for (let i = 0; i < size; i++) {
      if (cross(ring[(i + size - 1) % size], ring[i], ring[(i + 1) % size]).sign() === 0) {
        return `collinear ring ${number} ${pointText(ring[i])}`;
      }
    }
    for (let i = 0; i < size; i++) for (let j = i + 2; j < size; j++) {
      if (i === 0 && j === size - 1) continue;
      const a = ring[i], b = ring[(i + 1) % size], c = ring[j], d = ring[(j + 1) % size];
      if (touch(a, b, c, d)) return `self_intersection ring ${number} ${segmentText(a, b)} ${segmentText(c, d)}`;
    }
  }
  for (let i = 0; i < sequence.length; i++) for (let j = i + 1; j < sequence.length; j++) {
    const first = sequence[i], second = sequence[j];
    for (let e = 0; e < first.length; e++) for (let f = 0; f < second.length; f++) {
      const a = first[e], b = first[(e + 1) % first.length], c = second[f], d = second[(f + 1) % second.length];
      if (touch(a, b, c, d)) return `rings_touch rings ${i + 1} ${j + 1} ${segmentText(a, b)} ${segmentText(c, d)}`;
    }
  }
  for (let k = 1; k < sequence.length; k++) {
    if (!rings.inside(sequence[k][0], sequence[0])) return `hole_outside ring ${k + 1} ${pointText(sequence[k][0])}`;
  }
  for (let i = 1; i < sequence.length; i++) for (let j = i + 1; j < sequence.length; j++) {
    if (rings.inside(sequence[j][0], sequence[i])) return `hole_in_hole rings ${i + 1} ${j + 1} ${pointText(sequence[j][0])}`;
    if (rings.inside(sequence[i][0], sequence[j])) return `hole_in_hole rings ${i + 1} ${j + 1} ${pointText(sequence[i][0])}`;
  }
  return null;
}

function makePolygon(name: string, input: Ring[]): Polygon {
  const normalized = input.map((ring, index) => {
    const rotated = rings.rotate(ring);
    return rings.counterclockwise(rotated) === (index === 0) ? rotated : rings.reverse(rotated);
  });
  return { name, input, rings: [normalized[0], ...normalized.slice(1).sort((a, b) => pointOrder(a[0], b[0]))] };
}

function readPolygons(): PolygonRegistry {
  const records = readRecords('input/polygons.txt');
  const used = new Set<string>(), valid = new Map<string, Polygon>(), rejected: string[] = [];
  let index = 0, blocks = 0;
  while (index < records.length) {
    const start = records[index++], name = start.text.split(' ')[1], content: RecordLine[] = [];
    while (records[index].text !== 'END') content.push(records[index++]);
    const end = records[index++];
    blocks++;
    if (used.has(name)) { rejected.push(`polygon ${name} duplicate_name line ${start.line}`); continue; }
    used.add(name);
    const parsed = parseRings(content, end.line);
    const reason = parsed.reason || checkPolygon(parsed.rings!);
    if (reason !== null && reason !== undefined) rejected.push(`polygon ${name} ${reason}`);
    else valid.set(name, makePolygon(name, parsed.rings!));
  }
  return { used, valid, rejected, blocks, validBlocks: valid.size };
}

function generalPosition(a: Polygon, b: Polygon): string | null {
  const verticesA = a.rings.flat(), verticesB = b.rings.flat(), keysB = new Set(verticesB.map(pointKey));
  for (const p of verticesA) if (keysB.has(pointKey(p))) return `shared_vertex ${pointText(p)}`;
  const edges = (polygon: Polygon): [Point, Point][] =>
    polygon.rings.flatMap(ring => ring.map((p, i): [Point, Point] => [p, ring[(i + 1) % ring.length]]));
  const edgesA = edges(a), edgesB = edges(b);
  for (const [p, q] of edgesA) for (const [r, s] of edgesB) {
    if (overlap(p, q, r, s)) return `overlapping_edges ${segmentText(p, q)} ${segmentText(r, s)}`;
  }
  for (const p of verticesA) for (const [r, s] of edgesB) {
    if (onSegment(p, r, s)) return `vertex_on_edge ${a.name} ${pointText(p)} ${b.name} ${segmentText(r, s)}`;
  }
  for (const p of verticesB) for (const [r, s] of edgesA) {
    if (onSegment(p, r, s)) return `vertex_on_edge ${b.name} ${pointText(p)} ${a.name} ${segmentText(r, s)}`;
  }
  return null;
}

function validArguments(kind: string, words: string[]): boolean {
  if (words.length !== WORD_COUNTS[KINDS.indexOf(kind)]) return false;
  if (kind === 'LOCATE') return integerIn(words[2], 0, 1000) && integerIn(words[3], 0, 1000);
  if (kind === 'MOVE') return integerIn(words[2], -1000, 1000) && integerIn(words[3], -1000, 1000) && nameWord(words[4]);
  if (kind === 'ROTATE') return integerIn(words[2], 0, 1000) && integerIn(words[3], 0, 1000) && integerIn(words[4], 1, 3) && nameWord(words[5]);
  if (kind === 'MIRROR') return ['x', 'y'].includes(words[2]) && integerIn(words[3], 0, 1000) && nameWord(words[4]);
  if (kind === 'SNAP') return nameWord(words[2]);
  if (kind === 'RENDER') {
    if (!words.slice(2).every(integerWord)) return false;
    const [x0, y0, width, height, columns, rows] = words.slice(2).map(Number);
    return x0 >= 0 && y0 >= 0 && width >= 1 && width <= 100 && height >= 1 && height <= 100
      && columns >= 1 && columns <= 100 && rows >= 1 && rows <= 60 && x0 + width * columns <= 1000 && y0 + height * rows <= 1000;
  }
  return true;
}

function resolvePolygon(name: string, polygons: PolygonRegistry): {reason?: string; polygon?: Polygon} {
  if (!polygons.used.has(name)) return { reason: `unknown_polygon ${name}` };
  if (!polygons.valid.has(name)) return { reason: `invalid_polygon ${name}` };
  return { polygon: polygons.valid.get(name) };
}

function resolveTarget(name: string, polygons: PolygonRegistry, results: Map<number, ResultTarget>):
  {reason?: string; target?: ResultTarget} {
  if (name.startsWith('@')) {
    const suffix = name.slice(1);
    return /^[0-9]{1,9}$/.test(suffix) && results.has(Number(suffix)) ? { target: results.get(Number(suffix)) } : { reason: `bad_target ${name}` };
  }
  const resolved = resolvePolygon(name, polygons);
  return resolved.reason ? resolved : { target: { result: polygonResult(resolved.polygon!), operands: null } };
}

function transformedInput(kind: string, words: string[], source: Polygon): Ring[] {
  return source.input.map(ring => ring.map(p => {
    let x = p.x.n, y = p.y.n;
    if (kind === 'MOVE') { x += BigInt(words[2]); y += BigInt(words[3]); }
    else if (kind === 'MIRROR') {
      const constant = BigInt(words[3]);
      if (words[2] === 'x') x = 2n * constant - x;
      else y = 2n * constant - y;
    } else {
      const cx = BigInt(words[2]), cy = BigInt(words[3]);
      for (let i = 0; i < Number(words[4]); i++) [x, y] = [cx - (y - cy), cy + (x - cx)];
    }
    return point(x, y);
  }));
}

function checkOperation(operation: Operation, polygons: PolygonRegistry, results: Map<number, ResultTarget>): Prepared {
  const { kind, words } = operation;
  const prepared: Prepared = {};
  if (!KINDS.includes(kind)) return { reason: `unknown_operation ${kind}` };
  if (!validArguments(kind, words)) return { reason: 'bad_arguments' };
  if (['SNAP', 'LOCATE', 'RENDER'].includes(kind)) {
    const resolved = resolveTarget(words[1], polygons, results);
    if (resolved.reason) return resolved;
    prepared.target = resolved.target;
  } else {
    const first = resolvePolygon(words[1], polygons);
    if (first.reason) return first;
    prepared.a = first.polygon;
    if (BINARY.has(kind)) {
      const second = resolvePolygon(words[2], polygons);
      if (second.reason) return second;
      prepared.b = second.polygon;
    }
  }
  if (DEFINITIONS.has(kind)) {
    prepared.name = words[words.length - 1];
    if (polygons.used.has(prepared.name!)) return { reason: `duplicate_name ${prepared.name}` };
  }
  if (kind === 'SNAP' && prepared.target!.result.length !== 1) return { reason: `not_single ${words[1]}` };
  if (kind === 'CLIP') {
    const window = prepared.b!.rings[0];
    if (prepared.b!.rings.length !== 1 || window.some((p, i) => cross(window[(i + window.length - 1) % window.length], p, window[(i + 1) % window.length]).sign() <= 0)) {
      return { reason: `not_convex ${words[2]}` };
    }
  }
  if (BINARY.has(kind)) {
    const reason = generalPosition(prepared.a!, prepared.b!);
    if (reason !== null) return { reason };
  }
  if (DEFINITIONS.has(kind)) {
    if (kind === 'SNAP') {
      const polygon = prepared.target!.result[0];
      prepared.input = [polygon.outer, ...polygon.holes].map(ring => ring.map(p => point(p.x.round(), p.y.round())));
      const reason = checkPolygon(prepared.input);
      if (reason !== null) return { reason: `invalid_result ${reason}` };
    } else {
      prepared.input = transformedInput(kind, words, prepared.a!);
      if (prepared.input.some(ring => ring.some(outOfRange))) return { reason: `out_of_range ${prepared.name}` };
    }
  }
  return prepared;
}

function totalArea(result: Region[]): number {
  let total = 0.0;
  for (const ring of rings.flatten(result)) total += rings.area(ring);
  return total;
}

function binaryResult(kind: string, a: Polygon, b: Polygon): ResultTarget {
  const graph = new GreinerHormann(a.rings, b.rings);
  const intersection = rings.assemble(graph.traverse(false, false)), union = rings.assemble(graph.traverse(true, true));
  let result: Region[];
  if (kind === 'UNION') result = union;
  else if (kind === 'INTERSECTION' || kind === 'CLIP') result = intersection;
  else {
    result = rings.assemble(graph.traverse(true, false));
    if (kind === 'XOR') {
      const reverse = new GreinerHormann(b.rings, a.rings);
      result = result.concat(rings.assemble(reverse.traverse(true, false))).sort((p, q) => pointOrder(p.outer[0], q.outer[0]));
    }
  }
  let relation = 'overlap';
  if (graph.crossings.length === 0) {
    if (graph.nA === a.rings.length && graph.nB === 0) relation = 'within';
    else if (graph.nB === b.rings.length && graph.nA === 0) relation = 'contains';
    else if (graph.nA === 0 && graph.nB === 0) relation = 'disjoint';
  }
  return { result, operands: [a, b], graph, relation, iou: totalArea(intersection) / totalArea(union) };
}

function resultValues(result: Region[], a: Polygon, b: Polygon | null): PolygonValues {
  const verticesA = new Set(a.rings.flat().map(pointKey)), verticesB = new Set(b ? b.rings.flat().map(pointKey) : []);
  const values: PolygonValues = { polygons: result.length, rings: [], holes: 0, vertices: 0, area: 0.0, perimeter: 0.0,
    low: null, high: null, centroid: null, origins: { a: 0, b: 0, crossing: 0 } };
  let sx = 0.0, sy = 0.0;
  result.forEach((polygon, index) => [polygon.outer, ...polygon.holes].forEach((ring, hole) => {
    const area = rings.area(ring);
    values.rings.push({ ring, polygon: index + 1, hole, area });
    if (hole !== 0) values.holes++;
    values.vertices += ring.length; values.area += area; values.perimeter += rings.perimeter(ring);
    ring.forEach((p, i) => {
      const key = pointKey(p); values.origins[verticesA.has(key) ? 'a' : verticesB.has(key) ? 'b' : 'crossing']++;
      if (values.low === null) { values.low = point(p.x, p.y); values.high = point(p.x, p.y); }
      else {
        if (p.x.compare(values.low.x) < 0) values.low.x = p.x;
        if (p.y.compare(values.low.y) < 0) values.low.y = p.y;
        if (p.x.compare(values.high!.x) > 0) values.high.x = p.x;
        if (p.y.compare(values.high!.y) > 0) values.high.y = p.y;
      }
      const next = ring[(i + 1) % ring.length], x1 = p.x.value(), y1 = p.y.value(), x2 = next.x.value(), y2 = next.y.value();
      const c = x1 * y2 - x2 * y1;
      sx += (x1 + x2) * c; sy += (y1 + y2) * c;
    });
  }));
  if (values.rings.length !== 0) values.centroid = [sx / (6 * values.area), sy / (6 * values.area)];
  return values;
}

function twiceIntegerArea(ring: Ring): bigint {
  let value = 0n;
  ring.forEach((p, i) => { const q = ring[(i + 1) % ring.length]; value += p.x.n * q.y.n - q.x.n * p.y.n; });
  return value;
}

function polygonProperties(polygon: Polygon, area: number): string[] {
  const orientations = polygon.input.map(ring => twiceIntegerArea(ring) > 0n ? 'ccw' : 'cw');
  let reflex = 0;
  for (const ring of polygon.rings) ring.forEach((p, i) => {
    if (cross(ring[(i + ring.length - 1) % ring.length], p, ring[(i + 1) % ring.length]).sign() < 0) reflex++;
  });
  const sorted = polygon.rings[0].slice().sort((p, q) => p.x.compare(q.x) || p.y.compare(q.y));
  const chain = (points: Point[]): Point[] => {
    const hull: Point[] = [];
    for (const p of points) {
      while (hull.length >= 2 && cross(hull[hull.length - 2], hull[hull.length - 1], p).sign() <= 0) hull.pop();
      hull.push(p);
    }
    return hull;
  };
  const hull = chain(sorted).slice(0, -1).concat(chain(sorted.slice().reverse()).slice(0, -1));
  const hullArea = Number(twiceIntegerArea(hull)) / 2;
  return [`input ${orientations.join(' ')}`, `reflex ${reflex}`, `hull ${hull.length} ${fixed(hullArea)} solidity ${fixed(area / hullArea, 6)}`];
}

function clipCrosscheck(source: Polygon, window: Polygon, result: Region[]): string {
  const clipped: Ring[] = [];
  for (const ring of source.rings) {
    let list = ring.slice();
    window.rings[0].forEach((first, edge) => {
      const second = window.rings[0][(edge + 1) % window.rings[0].length], next: Ring = [];
      list.forEach((cur, i) => {
        const prev = list[(i + list.length - 1) % list.length];
        const prevInside = cross(first, second, prev).sign() > 0, curInside = cross(first, second, cur).sign() > 0;
        if (prevInside !== curInside) next.push(lineIntersection(prev, cur, first, second));
        if (curInside) next.push(cur);
      });
      list = next;
    });
    const clean = list.filter((p, i) => !equal(p, list[(i + list.length - 1) % list.length]));
    if (clean.length >= 3) clipped.push(clean);
  }
  const cyclicEqual = (first: Ring, second: Ring): boolean => first.length === second.length && second.some((p, start) =>
    equal(first[0], p) && first.every((q, i) => equal(q, second[(start + i) % second.length])));
  const output = rings.flatten(result), match = output.length === clipped.length && output.every(ring => clipped.some(other => cyclicEqual(ring, other)));
  let vertices = 0;
  for (const ring of clipped) vertices += ring.length;
  return `crosscheck ${match ? 'match' : 'mismatch'} rings ${clipped.length} vertices ${vertices}`;
}

function locate(target: ResultTarget, p: Point): string[] {
  let decision = null;
  for (let k = 0; k < target.result.length && decision === null; k++) {
    const polygon = target.result[k];
    if (rings.boundary(p, polygon.outer)) decision = `boundary outer ${k + 1}`;
    else for (let j = 0; j < polygon.holes.length; j++) {
      if (rings.boundary(p, polygon.holes[j])) { decision = `boundary hole ${k + 1} ${j + 1}`; break; }
    }
  }
  if (decision === null) {
    const polygon = target.result.findIndex(candidate => rings.inside(p, candidate.outer) && !candidate.holes.some(hole => rings.inside(p, hole)));
    decision = polygon < 0 ? 'outside' : `inside polygon ${polygon + 1}`;
  }
  const lines = [`location ${decision}`];
  if (target.operands !== null) {
    const decisions = target.operands.map(polygon => polygon.rings.some(ring => rings.boundary(p, ring)) ? 'boundary' : rings.interior(p, polygon.rings) ? 'inside' : 'outside');
    lines.push(`operands a ${decisions[0]} b ${decisions[1]}`);
  }
  return lines;
}

function regionLines(operation: Operation, target: ResultTarget, values: PolygonValues, polygon: Polygon | null): string[] {
  const lines = [`op ${operation.number} ${operation.text}`];
  if (target.operands !== null) {
    lines.push(`relation ${target.relation} iou ${fixed(target.iou!, 6)}`, `crossings ${target.graph!.crossings.length}`);
    for (const crossing of target.graph!.crossings) lines.push(`crossing ${pointText(crossing.point)} ${crossing.nodes[0].entering ? 'in' : 'out'}`);
  }
  lines.push(`polygons ${values.polygons} rings ${values.rings.length} holes ${values.holes} vertices ${values.vertices} area ${fixed(values.area)}`);
  for (const record of values.rings) {
    const prefix = record.hole === 0 ? `outer ${record.polygon}` : `hole ${record.polygon} ${record.hole}`;
    lines.push(`${prefix} ${record.ring.length} ${fixed(record.area)} ${record.ring.map(pointText).join(' ')}`);
  }
  lines.push(values.low === null ? 'bbox none' : `bbox ${pointText(values.low)} ${pointText(values.high!)}`,
    values.centroid === null ? 'centroid none' : `centroid (${fixed(values.centroid[0])},${fixed(values.centroid[1])})`,
    `perimeter ${fixed(values.perimeter)}`, `origins a ${values.origins.a} b ${values.origins.b} crossing ${values.origins.crossing}`);
  if (polygon !== null) lines.push(...polygonProperties(polygon, values.area));
  if (operation.kind === 'CLIP') lines.push(clipCrosscheck(target.operands![0], target.operands![1], target.result));
  return lines;
}

function main(): void {
  const polygons = readPolygons(), operations = readRecords('input/operations.txt');
  const results = new Map<number, ResultTarget>();
  const output: string[] = [], areas = ['operation,rings,holes,vertices,area'];
  const drawings: string[] = [], rejected: string[] = [];
  const kindCounts = new Map<string, {total: number; accepted: number}>(KINDS.map(kind => [kind, { total: 0, accepted: 0 }]));
  let accepted = 0, defined = 0, crossingCount = 0;
  operations.forEach((record, index) => {
    const words = record.text.split(' '), operation = { number: index + 1, text: record.text, words, kind: words[0] };
    const counts = kindCounts.get(operation.kind);
    if (counts) counts.total++;
    const prepared = checkOperation(operation, polygons, results);
    if (prepared.reason) { rejected.push(`op ${operation.number} ${prepared.reason}`); return; }
    accepted++; counts!.accepted++;
    if (operation.kind === 'LOCATE') {
      output.push(`op ${operation.number} ${operation.text}`, ...locate(prepared.target!, point(Number(words[2]), Number(words[3]))));
      return;
    }
    if (operation.kind === 'RENDER') {
      const values = words.slice(2).map(Number), drawing = render(prepared.target!, values), counts = drawing.counts;
      drawings.push(`render ${operation.number} ${words[1]} cols ${values[4]} rows ${values[5]} result ${counts['#']} a ${counts.a} b ${counts.b} both ${counts['+']}`, ...drawing.grid);
      return;
    }
    let target: ResultTarget, polygon: Polygon | null = null;
    if (BINARY.has(operation.kind)) {
      target = binaryResult(operation.kind, prepared.a!, prepared.b!); crossingCount += target.graph!.crossings.length;
    } else {
      if (DEFINITIONS.has(operation.kind)) {
        polygon = makePolygon(prepared.name!, prepared.input!); polygons.used.add(prepared.name!); polygons.valid.set(prepared.name!, polygon); defined++;
      } else polygon = prepared.a!;
      target = { result: polygonResult(polygon!), operands: null };
    }
    const values = resultValues(target.result, target.operands === null ? polygon! : prepared.a!, target.operands === null ? null : prepared.b!);
    results.set(operation.number, { result: target.result, operands: target.operands });
    output.push(...regionLines(operation, target, values, polygon));
    areas.push(`${operation.number}:${words.join(':')},${values.rings.length},${values.holes},${values.vertices},${fixed(values.area)}`);
  });
  output.push(`summary polygons ${polygons.blocks} valid ${polygons.validBlocks} invalid ${polygons.rejected.length} defined ${defined}`,
    `summary operations ${operations.length} succeeded ${accepted} rejected ${rejected.length}`, `summary crossings ${crossingCount}`);
  for (const kind of KINDS) { const counts = kindCounts.get(kind)!; output.push(`kind ${kind} ${counts.total} ${counts.accepted}`); }
  const rejections = [`rejections ${polygons.rejected.length + rejected.length}`, ...polygons.rejected, ...rejected];
  mkdirSync('output', { recursive: true });
  const reports: [string, string[]][] = [['results.txt', output], ['areas.csv', areas], ['render.txt', drawings], ['rejections.txt', rejections]];
  for (const [name, lines] of reports) {
    writeFileSync('output/' + name, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
  }
}

main();
