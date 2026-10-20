import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { orient, d2, dot, incircle, circumcenter, fraction } from './predicates.ts';
import type { Point, RationalPoint, Pair, TriangleSites } from './predicates.ts';
import { key, directedEdges, Triangulation } from './triangulation.ts';
import type { Insertion } from './triangulation.ts';
import {
  radiusSquared,
  position,
  neighborOrder,
  outward,
  boundedArea,
  clippedArea,
} from './voronoi.ts';
import type { Vertex } from './voronoi.ts';
import {
  DisjointSet,
  nearestNeighbors,
  nearestComponents,
  minimumTree,
  gabriel,
  relativeNeighborhood,
  greedyRoute,
  dijkstra,
} from './proximity.ts';
import { Canvas, voronoiPlot } from './plot.ts';

type Layer = 'edges' | 'mst' | 'hull' | 'sites' | 'circle';
type Section =
  | 'input'
  | 'summary'
  | 'insertions'
  | 'triangles'
  | 'edges'
  | 'hull'
  | 'convex_layers'
  | 'quality'
  | 'vertices'
  | 'voronoi_edges'
  | 'cells'
  | 'nearest'
  | 'components'
  | 'mst'
  | 'proximity'
  | 'degrees'
  | 'empty_circle'
  | 'extent'
  | 'spanner'
  | 'alpha'
  | 'sites'
  | 'queries'
  | 'delaunay_plot'
  | 'voronoi_plot';
type QueryKind = 'locate' | 'walk' | 'natural' | 'route' | 'path' | 'neighbors' | 'edge';
interface Query {
  text: string;
  kind: QueryKind;
  values: number[];
}
interface Parameters {
  width: number;
  height: number;
  layers: Layer[];
  sections: Section[];
  alpha: number[];
  queries: Query[];
}
interface Triangle {
  number: number;
  sites: TriangleSites;
  area2: number;
  kind: 'acute' | 'right' | 'obtuse';
  minimum: number;
  maximum: number;
  radius2: number;
}
interface Edge {
  i: number;
  j: number;
  left: number | undefined;
  right: number | undefined;
  kind: 'inner' | 'hull';
  length2: number;
  gabriel: boolean;
  rng: boolean;
  mst: boolean;
}
interface BoundedCell {
  site: number;
  bounded: true;
  sequence: number[];
  area: number;
  clip: number;
}
interface UnboundedCell {
  site: number;
  bounded: false;
  sequence: number[];
  clip: number;
  incoming: Pair;
  outgoing: Pair;
}
interface SupportCircle extends RationalPoint {
  support: number[];
  radius2: number;
}
type Base = ReturnType<typeof organize>;
type Geometry = Base & ReturnType<typeof triangleProperties>;
type GraphModel = Geometry & ReturnType<typeof proximityGraphs>;
type Model = ReturnType<typeof buildModel>;
type Input = ReturnType<typeof readInput>;
const GROUPS: Record<string, Section[]> = {
  'triangulation.txt': [
    'input',
    'summary',
    'insertions',
    'triangles',
    'edges',
    'hull',
    'convex_layers',
    'quality',
  ],
  'voronoi.txt': ['vertices', 'voronoi_edges', 'cells'],
  'derived.txt': [
    'nearest',
    'components',
    'mst',
    'proximity',
    'degrees',
    'empty_circle',
    'extent',
    'spanner',
    'alpha',
    'sites',
    'queries',
  ],
  'plot.txt': ['delaunay_plot', 'voronoi_plot'],
};
const sum = (values: number[]) => values.reduce((total, value) => total + value, 0);
const joined = (values: readonly (string | number)[]) => values.join(' ');
const edgeKey = (a: number, b: number) => key(Math.min(a, b), Math.max(a, b));
const yesNo = (value: boolean) => (value ? 'yes' : 'no');
function fixed(value: number): string {
  const text = Math.abs(value).toFixed(3);
  return value < 0 && text !== '0.000' ? '-' + text : text;
}
function readInput() {
  const raw = readFileSync('input/points.txt', 'ascii').split('\n').slice(0, -1);
  // Site numbers are one-based; index zero is reserved.
  const points: Point[] = [{ x: 0, y: 0 }];
  const errors: string[] = [];
  const seen = new Map<string, number>();
  raw.forEach((line, index) => {
    if (line === '' || line.startsWith('#')) return;
    const words = line.split(' ');
    if (words.length !== 2 || words.some((w) => !/^-?[0-9]+$/.test(w))) {
      errors.push(`reject ${index + 1} format`);
      return;
    }
    const [x, y] = words.map(Number);
    if (x < 0 || x > 1000 || y < 0 || y > 1000) {
      errors.push(`reject ${index + 1} range`);
      return;
    }
    const coordinate = key(x, y);
    if (seen.has(coordinate)) {
      errors.push(`reject ${index + 1} duplicate ${seen.get(coordinate)}`);
      return;
    }
    seen.set(coordinate, points.length);
    points.push({ x, y });
  });
  const parameters: Parameters = {
    width: 61,
    height: 31,
    layers: ['edges', 'hull', 'sites'],
    sections: ['summary'],
    alpha: [],
    queries: [],
  };
  const layers: Layer[] = ['edges', 'mst', 'hull', 'sites', 'circle'];
  const sections = Object.values(GROUPS).flat();
  const queryKinds: QueryKind[] = [
    'locate',
    'walk',
    'natural',
    'route',
    'path',
    'neighbors',
    'edge',
  ];
  for (const line of readFileSync('input/params.txt', 'ascii').split('\n').slice(0, -1)) {
    if (line === '' || line.startsWith('#')) continue;
    const [name, ...values] = line.split(' ');
    if (name === 'query') {
      parameters.queries.push({
        text: line.slice(6),
        kind: queryKinds.find((k) => k === values[0])!,
        values: values.slice(1).map(Number),
      });
    } else if (name === 'plot') {
      parameters.width = Number(values[0]);
      parameters.height = Number(values[1]);
    } else if (name === 'plot_layers') {
      parameters.layers = values.map((v) => layers.find((l) => l === v)!);
    } else if (name === 'sections') {
      parameters.sections = values.map((v) => sections.find((s) => s === v)!);
    } else if (name === 'alpha') parameters.alpha = values.map(Number);
  }
  return { points, parameters, errors, lines: raw.length };
}
function organize(points: Point[], mesh: Triangulation) {
  const triangles: Triangle[] = mesh.triangles().map((sites, i) => ({
    number: i + 1,
    sites,
    area2: 0,
    kind: 'acute',
    minimum: 0,
    maximum: 0,
    radius2: 0,
  }));
  const numbers = new Map(triangles.map((t) => [t.sites.join(','), t.number]));
  const directedNumbers = new Map<string, number>();
  const pairs = new Map<string, Pair>();
  for (const triangle of triangles) {
    for (const [u, v] of directedEdges(triangle.sites)) {
      directedNumbers.set(key(u, v), triangle.number);
      pairs.set(edgeKey(u, v), [Math.min(u, v), Math.max(u, v)]);
    }
  }
  const edges: Edge[] = [...pairs.values()]
    .sort((a, b) => a[0] - b[0] || a[1] - b[1])
    .map(([i, j]) => {
      const left = directedNumbers.get(key(i, j));
      const right = directedNumbers.get(key(j, i));
      return {
        i,
        j,
        left,
        right,
        kind: left !== undefined && right !== undefined ? 'inner' : 'hull',
        length2: d2(points[i], points[j]),
        gabriel: false,
        rng: false,
        mst: false,
      };
    });
  const next = new Map<number, number>();
  const previous = new Map<number, number>();
  for (const [u, v] of mesh.hullEdges()) {
    next.set(u, v);
    previous.set(v, u);
  }
  const hull: number[] = [];
  const first = Math.min(...next.keys());
  let current = first;
  do {
    hull.push(current);
    current = next.get(current)!;
  } while (current !== first);
  const adjacent = points.map((): number[] => []);
  for (const edge of edges) {
    adjacent[edge.i].push(edge.j);
    adjacent[edge.j].push(edge.i);
  }
  const neighbors = adjacent.map((list, site) =>
    site === 0 ? [] : neighborOrder(site, list, next, mesh),
  );
  let perimeter = 0;
  let area2 = 0;
  for (let i = 0; i < hull.length; i++) {
    const a = points[hull[i]];
    const b = points[hull[(i + 1) % hull.length]];
    perimeter += Math.sqrt(d2(a, b));
    area2 += a.x * b.y - b.x * a.y;
  }
  return {
    points,
    mesh,
    triangles,
    numbers,
    directedNumbers,
    edges,
    edgeMap: new Map(edges.map((e) => [key(e.i, e.j), e])),
    hull,
    next,
    previous,
    neighbors,
    perimeter,
    area2,
  };
}
function triangleProperties(model: Base) {
  const vertices: Vertex[] = [];
  for (const triangle of model.triangles) {
    const [a, b, c] = triangle.sites.map((s) => model.points[s]);
    const points = [a, b, c];
    triangle.area2 = orient(a, b, c);
    const products = points.map((p, k) => dot(p, points[(k + 1) % 3], points[(k + 2) % 3]));
    triangle.kind = products.includes(0)
      ? 'right'
      : products.some((v) => v < 0)
        ? 'obtuse'
        : 'acute';
    const lengths = points.map((_, k) => d2(points[(k + 1) % 3], points[(k + 2) % 3]));
    let shortest = 0;
    let longest = 0;
    for (let k = 1; k < 3; k++) {
      if (lengths[k] < lengths[shortest]) shortest = k;
      if (lengths[k] > lengths[longest]) longest = k;
    }
    const angles = points.map(
      (p, k) =>
        (Math.atan2(Math.abs(orient(p, points[(k + 1) % 3], points[(k + 2) % 3])), products[k]) *
          180) /
        Math.PI,
    );
    triangle.minimum = angles[shortest];
    triangle.maximum = angles[longest];
    triangle.radius2 = radiusSquared(a, b, c, triangle.area2);
    const center = circumcenter(a, b, c);
    vertices.push({
      ...center,
      number: triangle.number,
      radius2: triangle.radius2,
      position: position(center, model.hull, model.points),
    });
  }
  let smallest = model.triangles[0];
  let largest = model.triangles[0];
  const bins = Array<number>(6).fill(0);
  for (const t of model.triangles) {
    if (t.minimum < smallest.minimum) smallest = t;
    if (t.maximum > largest.maximum) largest = t;
    bins[Math.floor(t.minimum / 10)]++;
  }
  return {
    vertices,
    quality: {
      smallest,
      largest,
      mean: sum(model.triangles.map((t) => t.minimum)) / model.triangles.length,
      bins,
    },
  };
}
function voronoiCells(model: Geometry) {
  const cells: (BoundedCell | UnboundedCell)[] = [];
  let totalArea = 0;
  let clipTotal = 0;
  let largest: BoundedCell | null = null;
  for (let site = 1; site < model.points.length; site++) {
    const sequence = model.neighbors[site]
      .map((n) => model.directedNumbers.get(key(site, n)))
      .filter((n) => n !== undefined);
    const clip = clippedArea(model.points[site], model.neighbors[site], model.points);
    if (!model.next.has(site)) {
      const area = boundedArea(model.points[site], sequence, model.vertices);
      const cell: BoundedCell = { site, bounded: true, sequence, area, clip };
      cells.push(cell);
      totalArea += area;
      if (largest === null || area > largest.area) largest = cell;
    } else {
      cells.push({
        site,
        bounded: false,
        sequence,
        clip,
        incoming: outward(site, model.next.get(site)!, model.points),
        outgoing: outward(model.previous.get(site)!, site, model.points),
      });
    }
    clipTotal += clip;
  }
  return { cells, totalArea, clipTotal, largest };
}
function proximityGraphs(model: Geometry) {
  const n = model.points.length - 1;
  const nearest = nearestNeighbors(model.points, model.neighbors);
  const groups = nearestComponents(nearest);
  const componentOf = Array<number>(n + 1).fill(0);
  const components = groups.map((sites, i) => {
    sites.forEach((s) => {
      componentOf[s] = i + 1;
    });
    const first = sites.find((s) => nearest[nearest[s]] === s && s < nearest[s])!;
    return { number: i + 1, sites, pair: [first, nearest[first]] };
  });
  const mutual: Pair[] = [];
  for (let s = 1; s <= n; s++) {
    if (s < nearest[s] && nearest[nearest[s]] === s) mutual.push([s, nearest[s]]);
  }
  const mst = minimumTree(model.edges, n);
  const adopted = new Set(mst);
  const ggDegree = Array<number>(n + 1).fill(0);
  const rngDegree = Array<number>(n + 1).fill(0);
  const mstDegree = Array<number>(n + 1).fill(0);
  let closest = model.edges[0];
  for (const edge of model.edges) {
    edge.gabriel = gabriel(edge, model.mesh, model.points);
    edge.rng = relativeNeighborhood(edge, model.points);
    edge.mst = adopted.has(edge);
    if (edge.length2 < closest.length2) closest = edge;
    for (const s of [edge.i, edge.j]) {
      if (edge.gabriel) ggDegree[s]++;
      if (edge.rng) rngDegree[s]++;
      if (edge.mst) mstDegree[s]++;
    }
  }
  return {
    nearest,
    components,
    componentOf,
    mutual,
    mst,
    mstLength: sum(mst.map((e) => Math.sqrt(e.length2))),
    ggDegree,
    rngDegree,
    mstDegree,
    closest,
  };
}
function convexHull(sites: number[], points: Point[]): number[] {
  if (sites.length <= 2) return sites.slice().sort((a, b) => a - b);
  const order = sites
    .slice()
    .sort((a, b) => points[a].x - points[b].x || points[a].y - points[b].y || a - b);
  const chain = (values: number[]) => {
    const result: number[] = [];
    for (const s of values) {
      while (
        result.length >= 2 &&
        orient(points[result[result.length - 2]], points[result[result.length - 1]], points[s]) <= 0
      ) {
        result.pop();
      }
      result.push(s);
    }
    return result;
  };
  const hull = [...chain(order).slice(0, -1), ...chain(order.slice().reverse()).slice(0, -1)];
  const start = hull.indexOf(Math.min(...hull));
  return [...hull.slice(start), ...hull.slice(0, start)];
}
function convexLayers(points: Point[]) {
  let remaining = Array.from({ length: points.length - 1 }, (_, i) => i + 1);
  const layers: number[][] = [];
  const depths = Array<number>(points.length).fill(0);
  while (remaining.length) {
    const layer = convexHull(remaining, points);
    layers.push(layer);
    for (const site of layer) depths[site] = layers.length;
    const removed = new Set(layer);
    remaining = remaining.filter((s) => !removed.has(s));
  }
  return { layers, depths };
}
function supportCircle(sites: number[], points: Point[]): SupportCircle {
  if (sites.length === 1) {
    return { support: sites, X: points[sites[0]].x, Y: points[sites[0]].y, D: 1, radius2: 0 };
  }
  if (sites.length === 2) {
    const a = points[sites[0]];
    const b = points[sites[1]];
    return { support: sites, X: a.x + b.x, Y: a.y + b.y, D: 2, radius2: d2(a, b) / 4 };
  }
  let [a, b, c] = sites;
  if (orient(points[a], points[b], points[c]) < 0) [b, c] = [c, b];
  return {
    support: [a, b, c],
    ...circumcenter(points[a], points[b], points[c]),
    radius2: radiusSquared(
      points[a],
      points[b],
      points[c],
      orient(points[a], points[b], points[c]),
    ),
  };
}
function circleMembership(circle: SupportCircle, point: Point, points: Point[]): number {
  const support = circle.support.map((s) => points[s]);
  if (support.length === 1) return -d2(point, support[0]);
  if (support.length === 2) return -dot(point, support[0], support[1]);
  return incircle(support[0], support[1], support[2], point);
}
function enclosingCircle(hull: number[], points: Point[]) {
  let circle: SupportCircle | null = null;
  for (let i = 0; i < hull.length; i++) {
    if (circle !== null && circleMembership(circle, points[hull[i]], points) >= 0) continue;
    circle = supportCircle([hull[i]], points);
    for (let j = 0; j < i; j++) {
      if (circleMembership(circle, points[hull[j]], points) >= 0) continue;
      circle = supportCircle([hull[i], hull[j]], points);
      for (let k = 0; k < j; k++) {
        if (circleMembership(circle, points[hull[k]], points) < 0) {
          circle = supportCircle([hull[i], hull[j], hull[k]], points);
        }
      }
    }
  }
  const boundary: number[] = [];
  for (let s = 1; s < points.length; s++) {
    if (circleMembership(circle!, points[s], points) === 0) boundary.push(s);
  }
  let diameter: Pair | null = null;
  for (let i = 0; i < boundary.length; i++) {
    for (let j = i + 1; j < boundary.length; j++) {
      if (boundary.every((s) => dot(points[s], points[boundary[i]], points[boundary[j]]) === 0)) {
        diameter = [boundary[i], boundary[j]];
      }
    }
  }
  return { ...supportCircle(diameter ?? boundary, points), boundary };
}
function extent(model: Geometry) {
  const candidates = model.vertices.filter((v) => v.position === 'inside');
  let empty: Vertex | null = null;
  for (const vertex of candidates) {
    if (empty === null || vertex.radius2 > empty.radius2) empty = vertex;
  }
  let diameter = { i: 1, j: 2, length2: d2(model.points[1], model.points[2]) };
  for (let i = 1; i < model.points.length; i++) {
    for (let j = i + 1; j < model.points.length; j++) {
      const length2 = d2(model.points[i], model.points[j]);
      if (length2 > diameter.length2) diameter = { i, j, length2 };
    }
  }
  let width = { u: 0, v: 0, value: Infinity };
  for (let t = 0; t < model.hull.length; t++) {
    const u = model.hull[t];
    const v = model.hull[(t + 1) % model.hull.length];
    const maximum = Math.max(
      ...model.hull.map((s) => orient(model.points[u], model.points[v], model.points[s])),
    );
    const value = maximum / Math.sqrt(d2(model.points[u], model.points[v]));
    if (value < width.value) width = { u, v, value };
  }
  return {
    candidates,
    empty,
    diameter,
    width,
    enclosing: enclosingCircle(model.hull, model.points),
  };
}
function shortestPaths(model: Base) {
  const paths = model.points.map((_, s) =>
    s === 0 ? { distances: [], previous: [] } : dijkstra(s, model.neighbors, model.points),
  );
  let total = 0;
  let pairs = 0;
  let maximum = { i: 0, j: 0, stretch: -Infinity, length: 0, distance: 0 };
  for (let i = 1; i < model.points.length; i++) {
    for (let j = i + 1; j < model.points.length; j++) {
      const distance = Math.sqrt(d2(model.points[i], model.points[j]));
      const length = paths[i].distances[j];
      const stretch = length / distance;
      total += stretch;
      pairs++;
      if (stretch > maximum.stretch) maximum = { i, j, stretch, length, distance };
    }
  }
  return { paths, pairs, maximum, mean: total / pairs };
}
function alphaComplex(model: GraphModel, alpha: number) {
  const selected = model.triangles.filter((t) => t.radius2 <= alpha);
  const numbers = new Set(selected.map((t) => t.number));
  const sets = new DisjointSet(model.points.length - 1);
  const touched = new Set<number>();
  let edges = 0;
  let boundary = 0;
  let dangling = 0;
  for (const edge of model.edges) {
    const count =
      Number(edge.left !== undefined && numbers.has(edge.left)) +
      Number(edge.right !== undefined && numbers.has(edge.right));
    if (count === 0 && !(edge.gabriel && edge.length2 <= 4 * alpha)) continue;
    edges++;
    if (count === 1) boundary++;
    if (count === 0) dangling++;
    touched.add(edge.i);
    touched.add(edge.j);
    sets.union(edge.i, edge.j);
  }
  const n = model.points.length - 1;
  return {
    alpha,
    triangles: selected.length,
    edges,
    boundary,
    dangling,
    isolated: n - touched.size,
    components: sets.count,
    holes: sets.count - (n - edges + selected.length),
    area2: sum(selected.map((t) => t.area2)),
  };
}
function dualDescription(edge: Edge, model: Base): string {
  if (edge.kind === 'inner') return `segment ${edge.left} ${edge.right}`;
  const direction =
    edge.left !== undefined
      ? outward(edge.i, edge.j, model.points)
      : outward(edge.j, edge.i, model.points);
  return `ray ${edge.left ?? edge.right} ${joined(direction)}`;
}
function locate(point: Point, model: Base): string {
  let nearest = 1;
  for (let s = 2; s < model.points.length; s++) {
    if (d2(model.points[s], point) < d2(model.points[nearest], point)) nearest = s;
  }
  let place = 'outside';
  const vertex = model.points.findIndex((p, s) => s > 0 && p.x === point.x && p.y === point.y);
  if (vertex >= 1) place = 'vertex ' + vertex;
  else {
    const edge = model.edges.find(
      (e) =>
        orient(model.points[e.i], model.points[e.j], point) === 0 &&
        dot(point, model.points[e.i], model.points[e.j]) < 0,
    );
    if (edge) place = `edge ${edge.i} ${edge.j}`;
    else {
      const t = model.triangles.find(
        ({ sites: [a, b, c] }) =>
          orient(model.points[a], model.points[b], point) > 0 &&
          orient(model.points[b], model.points[c], point) > 0 &&
          orient(model.points[c], model.points[a], point) > 0,
      );
      if (t) place = 'triangle ' + joined(t.sites);
    }
  }
  return `${place} nearest ${nearest} d2 ${d2(model.points[nearest], point)}`;
}
function answerQuery(query: Query, model: Model): string {
  const { kind, values } = query;
  const [i, j] = values;
  const point = { x: i, y: j };
  if (kind === 'locate') return locate(point, model);
  if (kind === 'walk') {
    const walk = model.mesh.walk(point, model.triangles, model.numbers);
    const place = walk.outside ? 'outside ' + joined(walk.outside) : 'triangle ' + walk.triangle;
    return `steps ${walk.path.length - 1} ${place} path ${joined(walk.path)}`;
  }
  if (kind === 'natural') {
    const triangles = model.triangles.filter(
      ({ sites: [a, b, c] }) =>
        incircle(model.points[a], model.points[b], model.points[c], point) > 0,
    );
    const sites = [...new Set(triangles.flatMap((t) => t.sites))].sort((a, b) => a - b);
    return `triangles ${triangles.length} sites ${sites.length ? joined(sites) : '-'}`;
  }
  if (values.some((s) => s < 1 || s >= model.points.length)) return 'error unknown_site';
  if (kind === 'neighbors') {
    return `degree ${model.neighbors[i].length} sites ${joined(model.neighbors[i])}`;
  }
  if (kind === 'route') {
    const route = greedyRoute(i, j, model.neighbors, model.points);
    return `hops ${route.path.length - 1} length ${fixed(route.length)} path ${joined(route.path)}`;
  }
  if (kind === 'path') {
    const sequence: number[] = [];
    let current = j;
    while (current !== 0) {
      sequence.push(current);
      if (current === i) break;
      current = model.paths[i].previous[current];
    }
    sequence.reverse();
    const length = model.paths[i].distances[j];
    const stretch = i === j ? '-' : fixed(length / Math.sqrt(d2(model.points[i], model.points[j])));
    return `length ${fixed(length)} stretch ${stretch} hops ${sequence.length - 1} sites ${joined(sequence)}`;
  }
  if (i === j) return 'error same_site';
  const edge = model.edgeMap.get(edgeKey(i, j));
  if (edge) {
    return `delaunay len2 ${edge.length2} gabriel ${yesNo(edge.gabriel)} rng ${yesNo(edge.rng)} mst ${yesNo(edge.mst)} dual ${dualDescription(edge, model)}`;
  }
  const crossings = model.edges.filter(
    ({ i: u, j: v }) =>
      orient(model.points[i], model.points[j], model.points[u]) *
        orient(model.points[i], model.points[j], model.points[v]) <
        0 &&
      orient(model.points[u], model.points[v], model.points[i]) *
        orient(model.points[u], model.points[v], model.points[j]) <
        0,
  );
  return (
    `missing crossings ${crossings.length}` +
    (crossings.length ? ' ' + crossings.map((e) => `${e.i}-${e.j}`).join(' ') : '')
  );
}
function delaunayPlot(model: Model, parameters: Parameters): string[] {
  const canvas = new Canvas(parameters.width, parameters.height);
  for (const layer of parameters.layers) {
    if (layer === 'edges') {
      for (const e of model.edges) canvas.line(model.points[e.i], model.points[e.j], '.');
    } else if (layer === 'mst') {
      for (const e of model.mst) canvas.line(model.points[e.i], model.points[e.j], '*');
    } else if (layer === 'hull') {
      for (let i = 0; i < model.hull.length; i++) {
        canvas.line(
          model.points[model.hull[i]],
          model.points[model.hull[(i + 1) % model.hull.length]],
          '#',
        );
      }
    } else if (layer === 'sites') {
      for (let s = 1; s < model.points.length; s++) canvas.point(model.points[s], 'o');
    } else if (layer === 'circle' && model.empty) canvas.point(model.empty, '@');
  }
  return canvas.frame();
}
function sections(model: Model, input: Input): Record<Section, string[]> {
  const n = model.points.length - 1;
  const ts = model.triangles;
  const es = model.edges;
  const h = model.hull.length;
  let maxFlips: Model['insertions'][number] | null = null;
  for (const ins of model.insertions) {
    if (maxFlips === null || ins.flips > maxFlips.flips) maxFlips = ins;
  }
  const longest = model.mst[model.mst.length - 1];
  const degrees = model.neighbors.slice(1).map((ns) => ns.length);
  const maximum = model.maximum;
  const empty = model.empty;
  const enclosing = model.enclosing;
  return {
    input: [
      `lines ${input.lines}`,
      `accepted ${n}`,
      `rejected ${input.errors.length}`,
      ...input.errors,
    ],
    summary: [
      `sites ${n}`,
      `triangles ${ts.length}`,
      `edges ${es.length}`,
      `hull_vertices ${h}`,
      `interior_sites ${n - h}`,
      `euler ${n - es.length + ts.length}`,
      `flips ${sum(model.insertions.map((ins) => ins.flips))}`,
      `outside_insertions ${model.insertions.filter((ins) => ins.kind === 'outside').length}`,
      maxFlips ? `max_flips ${maxFlips.site} ${maxFlips.flips}` : 'max_flips none',
      ...['acute', 'right', 'obtuse'].map((k) => `${k} ${ts.filter((t) => t.kind === k).length}`),
    ],
    insertions: [
      'init ' + joined(model.mesh.initial),
      ...model.insertions.map(
        (ins) =>
          `insert ${ins.site} ${ins.kind === 'inside' ? 'inside ' + joined(ins.containing!) : 'outside ' + ins.visible} flips ${ins.flips} triangles ${ins.triangles} hull ${ins.hull}`,
      ),
    ],
    triangles: ts.map((t) => {
      const [a, b, c] = t.sites;
      const adj = [
        [c, b],
        [a, c],
        [b, a],
      ].map(([u, v]) => model.directedNumbers.get(key(u, v)) ?? '-');
      return `tri ${t.number} ${joined(t.sites)} area2 ${t.area2} ${t.kind} adj ${joined(adj)}`;
    }),
    edges: es.map(
      (e) =>
        `edge ${e.i} ${e.j} ${e.kind} len2 ${e.length2} left ${e.left ?? '-'} right ${e.right ?? '-'}`,
    ),
    hull: [
      `hull_vertices ${h}`,
      'order ' + joined(model.hull),
      'perimeter ' + fixed(model.perimeter),
      'area2 ' + model.area2,
    ],
    convex_layers: [
      'layers ' + model.layers.length,
      ...model.layers.map(
        (layer, i) => `layer ${i + 1} size ${layer.length} sites ${joined(layer)}`,
      ),
    ],
    quality: [
      `min_angle ${fixed(model.quality.smallest.minimum)} tri ${model.quality.smallest.number}`,
      `max_angle ${fixed(model.quality.largest.maximum)} tri ${model.quality.largest.number}`,
      'mean_min_angle ' + fixed(model.quality.mean),
      ...model.quality.bins.map((count, i) => `bin ${i * 10} ${(i + 1) * 10} ${count}`),
    ],
    vertices: [
      ...['inside', 'on', 'outside'].map(
        (p) => `${p} ${model.vertices.filter((v) => v.position === p).length}`,
      ),
      ...model.vertices.map(
        (v) =>
          `v ${v.number} ${fraction(v.X, v.D)} ${fraction(v.Y, v.D)} r ${fixed(Math.sqrt(v.radius2))} ${v.position}`,
      ),
    ],
    voronoi_edges: [
      `segments ${es.filter((e) => e.kind === 'inner').length}`,
      `rays ${h}`,
      ...es.map((e) => `ve ${e.i} ${e.j} ${dualDescription(e, model)}`),
    ],
    cells: [
      `bounded ${n - h}`,
      `unbounded ${h}`,
      'total_area ' + fixed(model.totalArea),
      'clip_total ' + fixed(model.clipTotal),
      model.largest
        ? `largest ${model.largest.site} area ${fixed(model.largest.area)}`
        : 'largest none',
      ...model.cells.map((c) =>
        c.bounded
          ? `cell ${c.site} bounded ${c.sequence.length} area ${fixed(c.area)} clip ${fixed(c.clip)} vertices ${joined(c.sequence)}`
          : `cell ${c.site} unbounded ${c.sequence.length} clip ${fixed(c.clip)} from ${joined(c.incoming)} vertices ${joined(c.sequence)} to ${joined(c.outgoing)}`,
      ),
    ],
    nearest: [
      'mutual_pairs ' + model.mutual.length,
      `closest_pair ${model.closest.i} ${model.closest.j} d2 ${model.closest.length2}`,
      ...model.nearest
        .slice(1)
        .map(
          (s, i) =>
            `nn ${i + 1} ${s} d2 ${d2(model.points[i + 1], model.points[s])} ${model.nearest[s] === i + 1 ? 'mutual' : '-'}`,
        ),
    ],
    components: [
      'components ' + model.components.length,
      ...model.components.map(
        (c) =>
          `component ${c.number} size ${c.sites.length} pair ${joined(c.pair)} sites ${joined(c.sites)}`,
      ),
    ],
    mst: [
      `edges ${n - 1}`,
      'total_length ' + fixed(model.mstLength),
      `longest ${longest.i} ${longest.j} len2 ${longest.length2}`,
      ...model.mst.map((e) => `mst ${e.i} ${e.j} len2 ${e.length2}`),
    ],
    proximity: [
      `delaunay ${es.length}`,
      `gabriel ${es.filter((e) => e.gabriel).length}`,
      `rng ${es.filter((e) => e.rng).length}`,
      `mst ${n - 1}`,
      `nn ${n - model.mutual.length}`,
      ...es.filter((e) => e.rng && !e.mst).map((e) => `rng_extra ${e.i} ${e.j} len2 ${e.length2}`),
    ],
    degrees: [
      'min ' + Math.min(...degrees),
      'max ' + Math.max(...degrees),
      ...[...new Set(degrees)]
        .sort((a, b) => a - b)
        .map((d) => `degree ${d} count ${degrees.filter((v) => v === d).length}`),
    ],
    empty_circle: [
      'candidates ' + model.candidates.length,
      ...(empty
        ? [
            'vertex ' + empty.number,
            `center ${fraction(empty.X, empty.D)} ${fraction(empty.Y, empty.D)}`,
            'radius ' + fixed(Math.sqrt(empty.radius2)),
            'sites ' + joined(ts[empty.number - 1].sites),
          ]
        : ['none']),
    ],
    extent: [
      `diameter ${model.diameter.i} ${model.diameter.j} d2 ${model.diameter.length2}`,
      `width ${fixed(model.width.value)} edge ${model.width.u} ${model.width.v}`,
      `enclosing_center ${fraction(enclosing.X, enclosing.D)} ${fraction(enclosing.Y, enclosing.D)}`,
      'enclosing_radius ' + fixed(Math.sqrt(enclosing.radius2)),
      'enclosing_sites ' + joined(enclosing.boundary),
    ],
    spanner: [
      `pairs ${model.pairs}`,
      `max_stretch ${fixed(maximum.stretch)} pair ${maximum.i} ${maximum.j} length ${fixed(maximum.length)} distance ${fixed(maximum.distance)}`,
      'mean_stretch ' + fixed(model.mean),
    ],
    alpha: input.parameters.alpha.map((value) => {
      const a = alphaComplex(model, value);
      return `alpha ${a.alpha} triangles ${a.triangles} edges ${a.edges} boundary ${a.boundary} dangling ${a.dangling} isolated ${a.isolated} components ${a.components} holes ${a.holes} area2 ${a.area2}`;
    }),
    sites: model.points.slice(1).map((p, i) => {
      const s = i + 1;
      return `site ${s} ${p.x} ${p.y} ${model.next.has(s) ? 'hull' : 'inner'} dt ${model.neighbors[s].length} gg ${model.ggDegree[s]} rng ${model.rngDegree[s]} mst ${model.mstDegree[s]} nn ${model.nearest[s]} comp ${model.componentOf[s]} depth ${model.depths[s]}`;
    }),
    queries: input.parameters.queries.map((q) => q.text + ' ' + answerQuery(q, model)),
    delaunay_plot: delaunayPlot(model, input.parameters),
    voronoi_plot: voronoiPlot(input.parameters.width, input.parameters.height, model.points),
  };
}
function buildModel(input: Input) {
  const mesh = new Triangulation(input.points);
  const insertions: Insertion[] = [];
  for (let s = 4; s < input.points.length; s++) insertions.push(mesh.insert(s));
  const base = organize(input.points, mesh);
  const geometry = { ...base, ...triangleProperties(base) };
  return {
    ...geometry,
    insertions,
    ...voronoiCells(geometry),
    ...proximityGraphs(geometry),
    ...convexLayers(input.points),
    ...extent(geometry),
    ...shortestPaths(base),
  };
}
function main(): void {
  const input = readInput();
  const model = buildModel(input);
  const contents = sections(model, input);
  mkdirSync('output', { recursive: true });
  for (const [file, names] of Object.entries(GROUPS)) {
    const lines: string[] = [];
    for (const name of input.parameters.sections) {
      if (names.includes(name)) lines.push(`[${name}]`, ...contents[name]);
    }
    writeFileSync('output/' + file, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
  }
}
main();
