import {mkdirSync, writeFileSync} from 'node:fs';
import * as graphIO from './graph_io.ts';
import * as layering from './acyclic_layering.ts';
import * as crossing from './crossing.ts';
import * as coordinates from './coordinates.ts';
import {Canvas} from './canvas.ts';
import type {
  Settings, Graph, GraphNode, Edge, Vertex, GapSegment, GraphAnalysis, Reduction,
  ReductionRecord, BestReduction, SiftRecord, Crossings, Geometry, Bus,
  GraphResult, GraphStatistics
} from './types.ts';

function copyOrder(order: number[][]): number[][] {
  return order.map(layer => layer.slice());
}

function positionsOf(order: number[][], count: number): number[] {
  const positions = Array(count);
  for (const layer of order) for (let j = 0; j < layer.length; j++) positions[layer[j]] = j;
  return positions;
}

function sameOrder(a: number[][], b: number[][]): boolean {
  return a.every((layer, i) => layer.every((v, j) => v === b[i][j]));
}

function analyzeGraph(count: number, edges: Edge[]): GraphAnalysis {
  const outgoing = Array.from({length: count}, ():number[] => []);
  const incoming = Array.from({length: count}, ():number[] => []);
  const undirected = Array.from({length: count}, ():number[] => []);
  for (const edge of edges) {
    outgoing[edge.from].push(edge.to);
    incoming[edge.to].push(edge.from);
    undirected[edge.from].push(edge.to);
    undirected[edge.to].push(edge.from);
  }
  let sources = 0;
  let sinks = 0;
  let isolated = 0;
  for (let v = 0; v < count; v++) {
    if (incoming[v].length === 0 && outgoing[v].length > 0) sources++;
    if (outgoing[v].length === 0 && incoming[v].length > 0) sinks++;
    if (incoming[v].length === 0 && outgoing[v].length === 0) isolated++;
  }
  const visited = Array(count).fill(false);
  let components = 0;
  for (let v = 0; v < count; v++) {
    if (visited[v]) continue;
    components++;
    const pending = [v];
    visited[v] = true;
    while (pending.length > 0) {
      const u = pending.pop();
      for (const w of undirected[u]) {
        if (visited[w]) continue;
        visited[w] = true;
        pending.push(w);
      }
    }
  }
  const indices = Array(count).fill(-1);
  const low = Array(count).fill(-1);
  const active = Array(count).fill(false);
  const stack: number[] = [];
  const scc: number[][] = [];
  let serial = 0;
  function visit(v: number): void {
    indices[v] = serial;
    low[v] = serial++;
    stack.push(v);
    active[v] = true;
    for (const w of outgoing[v]) {
      if (indices[w] === -1) { visit(w); low[v] = Math.min(low[v], low[w]); }
      else if (active[w]) low[v] = Math.min(low[v], indices[w]);
    }
    if (low[v] !== indices[v]) return;
    const component: number[] = [];
    let w: number;
    do {
      w = stack.pop();
      active[w] = false;
      component.push(w);
    } while (w !== v);
    if (component.length >= 2) scc.push(component.sort((a, b) => a - b));
  }
  for (let v = 0; v < count; v++) if (indices[v] === -1) visit(v);
  scc.sort((a, b) => a[0] - b[0]);
  return {sources, sinks, isolated, components, scc};
}

function orientEdges(count: number, edges: Edge[], sequence: number[], reduce: string): {predecessors: number[][]; successors: number[][]} {
  const position = Array(count);
  sequence.forEach((v, i) => { position[v] = i; });
  const allSuccessors = Array.from({length: count}, ():number[] => []);
  for (const edge of edges) {
    edge.reversed = position[edge.from] > position[edge.to];
    edge.upper = edge.reversed ? edge.to : edge.from;
    edge.lower = edge.reversed ? edge.from : edge.to;
    edge.transitive = false;
    allSuccessors[edge.upper].push(edge.lower);
  }
  if (reduce === 'on') {
    for (const edge of edges) {
      if (edge.reversed) continue;
      const pending = allSuccessors[edge.upper].filter(v => v !== edge.lower);
      const found = new Set();
      while (pending.length > 0) {
        const v = pending.pop();
        if (v === edge.lower) { edge.transitive = true; break; }
        if (found.has(v)) continue;
        found.add(v);
        for (const w of allSuccessors[v]) pending.push(w);
      }
    }
  }
  const predecessors = Array.from({length: count}, ():number[] => []);
  const successors = Array.from({length: count}, ():number[] => []);
  for (const edge of edges) {
    if (edge.transitive) continue;
    predecessors[edge.lower].push(edge.upper);
    successors[edge.upper].push(edge.lower);
  }
  return {predecessors, successors};
}

function createVertices(nodes: GraphNode[], edges: Edge[], height: number[]): {vertices:Vertex[];gaps:GapSegment[][];layerCount:number} {
  const maximum = Math.max(...height);
  const levels = height.map(value => maximum - value);
  const used = new Set(levels);
  for (const edge of edges) {
    if (edge.transitive) continue;
    for (let level = levels[edge.upper] + 1; level < levels[edge.lower]; level++) used.add(level);
  }
  const layerNumbers = new Map([...used].sort((a, b) => a - b).map((level, index) => [level, index]));
  const vertices: Vertex[] = nodes.map((node, v) => ({name: String(node.id), label: node.label,
    real: true, layer: layerNumbers.get(levels[v])!, width: node.label.length + 2,
    upper: [], lower: [], x: 0, left: 0, right: 0}));
  const gaps: GapSegment[][] = Array.from({length: layerNumbers.size - 1}, ():GapSegment[] => []);
  for (const edge of edges) {
    if (edge.transitive) continue;
    const upper = vertices[edge.upper].layer;
    const lower = vertices[edge.lower].layer;
    edge.span = lower - upper;
    edge.chain = [edge.upper];
    for (let layer = upper + 1; layer < lower; layer++) {
      edge.chain.push(vertices.length);
      vertices.push({name: 'd' + (vertices.length - nodes.length + 1), real: false,
        layer, width: 1, upper: [], lower: [], x:0, left:0, right:0});
    }
    edge.chain.push(edge.lower);
    edge.segments = [];
    for (let j = 1; j < edge.chain.length; j++) {
      const p = edge.chain[j - 1];
      const q = edge.chain[j];
      const segment: GapSegment = {upper: p, lower: q, edge: edge.number, gap: vertices[p].layer, offset: 0};
      gaps[segment.gap].push(segment);
      edge.segments.push(segment);
      vertices[p].lower.push(q);
      vertices[q].upper.push(p);
    }
  }
  return {vertices, gaps, layerCount: layerNumbers.size};
}

function initialOrder(vertices: Vertex[], nodeCount: number, layerCount: number): number[][] {
  const order: number[][] = Array.from({length: layerCount}, ():number[] => []);
  const visited = Array(vertices.length).fill(false);
  function visit(v: number): void {
    if (visited[v]) return;
    visited[v] = true;
    order[vertices[v].layer].push(v);
    for (const w of vertices[v].lower) visit(w);
  }
  for (let v = 0; v < nodeCount; v++) visit(v);
  return order;
}

function reorderLayer(layer: number[], side: 'upper'|'lower', vertices: Vertex[], positions: number[], heuristic: string): void {
  const movable: {vertex:number;numerator:number;denominator:number;previous:number}[] = [];
  for (let j = 0; j < layer.length; j++) {
    const v = layer[j];
    const references = vertices[v][side];
    if (references.length === 0) continue;
    let numerator = 0;
    let denominator = 1;
    if (heuristic === 'barycenter') {
      for (const u of references) numerator += positions[u];
      denominator = references.length;
    } else {
      const ordered = references.map(u => positions[u]).sort((a, b) => a - b);
      numerator = ordered[Math.floor((ordered.length - 1) / 2)] + ordered[Math.floor(ordered.length / 2)];
    }
    movable.push({vertex: v, numerator, denominator, previous: j});
  }
  movable.sort((a, b) => a.numerator * b.denominator - b.numerator * a.denominator || a.previous - b.previous);
  let next = 0;
  for (let j = 0; j < layer.length; j++) {
    if (vertices[layer[j]][side].length > 0) layer[j] = movable[next++].vertex;
  }
  for (let j = 0; j < layer.length; j++) positions[layer[j]] = j;
}

function adjacentExchanges(order: number[][], vertices: Vertex[], positions: number[]): number {
  let swaps = 0;
  let changed;
  do {
    changed = false;
    for (const layer of order) {
      for (let j = 0; j + 1 < layer.length; j++) {
        const v = layer[j];
        const w = layer[j + 1];
        if (crossing.incidentCost(v, w, vertices, positions) <= crossing.incidentCost(w, v, vertices, positions)) continue;
        [layer[j], layer[j + 1]] = [w, v];
        positions[w] = j;
        positions[v] = j + 1;
        swaps++;
        changed = true;
      }
    }
  } while (changed);
  return swaps;
}

function reduceCrossings(initial: number[][], vertices: Vertex[], gaps: GapSegment[][], settings: Settings): Reduction {
  const records: ReductionRecord[] = [];
  let state = settings.seed;
  let best: BestReduction | null = null;
  for (let run = 0; run <= settings.restarts; run++) {
    const order = copyOrder(initial);
    if (run > 0) {
      for (const layer of order) {
        for (let j = layer.length - 1; j >= 1; j--) {
          state = 48271 * state % 2147483647;
          const k = state % (j + 1);
          [layer[j], layer[k]] = [layer[k], layer[j]];
        }
      }
    }
    const positions = positionsOf(order, vertices.length);
    let count = crossing.total(gaps, order, positions);
    const history = [copyOrder(order)];
    let runBest = {run, sweep: 0, crossings: count, order: copyOrder(order)};
    records.push({run, sweep: 0, crossings: count});
    for (let sweep = 1; ; sweep++) {
      if (count === 0 || sweep - 1 === settings.sweeps) break;
      if (sweep >= 3 && sameOrder(history[sweep - 1], history[sweep - 3])) break;
      const before = positions.slice();
      const downward = sweep % 2 === 1;
      if (downward) {
        for (let i = 1; i < order.length; i++) reorderLayer(order[i], 'upper', vertices, positions, settings.heuristic);
      } else {
        for (let i = order.length - 2; i >= 0; i--) reorderLayer(order[i], 'lower', vertices, positions, settings.heuristic);
      }
      let moved = 0;
      for (let v = 0; v < vertices.length; v++) if (positions[v] !== before[v]) moved++;
      const swaps = adjacentExchanges(order, vertices, positions);
      count = crossing.total(gaps, order, positions);
      records.push({run, sweep, direction: downward ? 'down' : 'up', moved, swaps, crossings: count});
      history.push(copyOrder(order));
      if (count < runBest.crossings) runBest = {run, sweep, crossings: count, order: copyOrder(order)};
    }
    if (best === null || runBest.crossings < best.crossings) best = runBest;
  }
  return {records, best: best!};
}

function sift(order: number[][], vertices: Vertex[], gaps: GapSegment[][], positions: number[]): SiftRecord[] {
  const records: SiftRecord[] = [];
  let moves;
  do {
    moves = 0;
    for (let v = 0; v < vertices.length; v++) {
      const i = vertices[v].layer;
      const layer = order[i];
      const original = positions[v];
      layer.splice(original, 1);
      let minimum: number | null = null;
      let originalCost;
      let bestPosition = 0;
      const length = layer.length;
      for (let p = 0; p <= length; p++) {
        layer.splice(p, 0, v);
        for (let j = 0; j < layer.length; j++) positions[layer[j]] = j;
        let cost = 0;
        if (i > 0) cost += crossing.accumulator(gaps[i - 1], positions, layer.length);
        if (i < gaps.length) cost += crossing.accumulator(gaps[i], positions, order[i + 1].length);
        if (p === original) originalCost = cost;
        if (minimum === null || cost < minimum) { minimum = cost; bestPosition = p; }
        layer.splice(p, 1);
      }
      const chosen = originalCost === minimum ? original : bestPosition;
      layer.splice(chosen, 0, v);
      for (let j = 0; j < layer.length; j++) positions[layer[j]] = j;
      if (chosen !== original) moves++;
    }
    records.push({round: records.length + 1, moves, crossings: crossing.total(gaps, order, positions)});
  } while (moves > 0);
  return records;
}

function finalCrossings(edges: Edge[], gaps: GapSegment[][], order: number[][], positions: number[]): Crossings {
  const perGap: number[] = [];
  let brute = 0;
  for (const edge of edges) edge.crossings = 0;
  for (let i = 0; i < gaps.length; i++) {
    const segments = gaps[i];
    perGap.push(crossing.accumulator(segments, positions, order[i + 1].length));
    brute += crossing.brute(segments, positions);
    for (let a = 0; a < segments.length; a++) {
      for (let b = a + 1; b < segments.length; b++) {
        if (!crossing.crosses(segments[a], segments[b], positions)) continue;
        edges[segments[a].edge].crossings++;
        edges[segments[b].edge].crossings++;
      }
    }
  }
  return {perGap, brute, total: crossing.total(gaps, order, positions)};
}

function routingGeometry(vertices: Vertex[], order: number[][], gaps: GapSegment[][], settings: Settings): Geometry {
  const spaces: Geometry['spaces'] = [];
  for (const segments of gaps) {
    const bent = segments.filter(segment => vertices[segment.upper].x !== vertices[segment.lower].x);
    const upperCounts = new Map<number,number>();
    for (const segment of bent) upperCounts.set(segment.upper, (upperCounts.get(segment.upper) || 0) + 1);
    const buses = new Map<string,Bus>();
    for (const segment of bent) {
      const upper = upperCounts.get(segment.upper)! >= 2;
      const vertex = upper ? segment.upper : segment.lower;
      const key = (upper ? 'u' : 'l') + vertex;
      const a = vertices[segment.upper].x;
      const b = vertices[segment.lower].x;
      if (!buses.has(key)) buses.set(key, {upper, vertex, low: Math.min(a, b), high: Math.max(a, b), segments: [], track:0});
      const bus = buses.get(key)!;
      bus.low = Math.min(bus.low, a, b);
      bus.high = Math.max(bus.high, a, b);
      bus.segments.push(segment);
    }
    const ordered = [...buses.values()].sort((a, b) => a.low - b.low || a.high - b.high
      || Number(b.upper) - Number(a.upper) || vertices[a.vertex].x - vertices[b.vertex].x);
    const ends: number[] = [];
    for (const bus of ordered) {
      let track = ends.findIndex(end => end + 1 < bus.low);
      if (track === -1) track = ends.length;
      ends[track] = bus.high;
      bus.track = track + 1;
    }
    const length = Math.max(settings.layer_gap, ends.length + 2);
    for (const bus of ordered) {
      const offset = bus.track + Math.floor((length - 2 - ends.length) / 2);
      for (const segment of bus.segments) segment.offset = offset;
    }
    spaces.push({tracks: ends.length, length});
  }
  const vertical = settings.direction === 'TB' || settings.direction === 'BT';
  const bands: Geometry['bands'] = [];
  let start = 0;
  for (let i = 0; i < order.length; i++) {
    const thickness = vertical ? 1 : Math.max(...order[i].map(v => vertices[v].width));
    bands.push({start, thickness});
    start += thickness + (i < spaces.length ? spaces[i].length : 0);
  }
  let secondaryLength = 0;
  for (const vertex of vertices) secondaryLength = Math.max(secondaryLength, vertex.x + vertex.right + 1);
  return {spaces, bands, mainLength: start, secondaryLength, vertical};
}

function makeRoutes(edges: Edge[], vertices: Vertex[], geometry: Geometry, canvas: Canvas): void {
  for (const edge of edges) {
    if (edge.transitive) continue;
    const upper = vertices[edge.upper];
    const lower = vertices[edge.lower];
    edge.upperPoint = [geometry.bands[upper.layer].start + (geometry.vertical ? 1 : upper.width), upper.x];
    edge.lowerPoint = [geometry.bands[lower.layer].start - 1, lower.x];
    const points: [number,number][] = [edge.upperPoint];
    edge.bends = 0;
    for (const segment of edge.segments) {
      const a = vertices[segment.upper].x;
      const b = vertices[segment.lower].x;
      if (a === b) continue;
      const band = geometry.bands[segment.gap];
      const main = band.start + band.thickness + segment.offset;
      points.push([main, a], [main, b]);
      edge.bends += 2;
    }
    points.push(edge.lowerPoint);
    edge.route = points.map(([main, secondary]) => canvas.map(main, secondary));
    if (edge.reversed) edge.route.reverse();
    edge.length = 1;
    for (let j = 1; j < edge.route.length; j++) {
      edge.length += Math.abs(edge.route[j][0] - edge.route[j - 1][0]) + Math.abs(edge.route[j][1] - edge.route[j - 1][1]);
    }
  }
}

function shortestPath(graph: Graph, edges: Edge[], index: Map<number,number>): number[] | null {
  if (graph.path === null) return null;
  const start = index.get(graph.path[0])!;
  const end = index.get(graph.path[1])!;
  const outgoing = Array.from({length: graph.nodes.length}, ():number[] => []);
  for (const edge of edges) if (!edge.transitive) outgoing[edge.from].push(edge.to);
  for (const neighbors of outgoing) neighbors.sort((a, b) => a - b);
  const parent = Array(graph.nodes.length).fill(-1);
  parent[start] = start;
  const queue = [start];
  for (let head = 0; head < queue.length; head++) {
    const v = queue[head];
    for (const w of outgoing[v]) {
      if (parent[w] !== -1) continue;
      parent[w] = v;
      queue.push(w);
    }
  }
  if (parent[end] === -1) return null;
  const result = [end];
  while (result.at(-1) !== start) result.push(parent[result.at(-1)]);
  return result.reverse();
}

function drawGraph(vertices: Vertex[], edges: Edge[], gaps: GapSegment[][], geometry: Geometry, path: number[] | null, canvas: Canvas): void {
  for (const vertex of vertices) {
    const band = geometry.bands[vertex.layer];
    if (!vertex.real) canvas.mainLine(band.start, band.start + band.thickness - 1, vertex.x);
    else if (!geometry.vertical && vertex.lower.length > 0) {
      canvas.mainLine(band.start + vertex.width, band.start + band.thickness - 1, vertex.x);
    }
  }
  for (let i = 0; i < gaps.length; i++) {
    const start = geometry.bands[i].start + geometry.bands[i].thickness;
    const length = geometry.spaces[i].length;
    for (const segment of gaps[i]) {
      const upper = vertices[segment.upper].x;
      const lower = vertices[segment.lower].x;
      if (upper === lower) canvas.mainLine(start, start + length - 1, upper);
      else canvas.bent(start, length, segment.offset, upper, lower);
    }
  }
  const edgeByEnds = new Map<string,Edge>();
  for (const edge of edges) {
    if (edge.transitive) continue;
    const point = edge.reversed ? edge.upperPoint : edge.lowerPoint;
    canvas.arrow(point[0], point[1], edge.reversed);
    edgeByEnds.set(edge.from + ',' + edge.to, edge);
  }
  if (path !== null) {
    for (let i = 1; i < path.length; i++) canvas.highlight(edgeByEnds.get(path[i - 1] + ',' + path[i])!.route);
  }
  const highlighted = new Set(path || []);
  for (let v = 0; v < vertices.length; v++) {
    const vertex = vertices[v];
    if (!vertex.real) continue;
    const text = highlighted.has(v) ? '{' + vertex.label + '}' : '[' + vertex.label + ']';
    const start = geometry.bands[vertex.layer].start;
    let row;
    let column;
    if (geometry.vertical) [row, column] = canvas.map(start, vertex.x - vertex.left);
    else {
      row = vertex.x;
      column = canvas.direction === 'LR' ? start : geometry.mainLength - start - vertex.width;
    }
    canvas.box(row, column, text);
  }
}

function collectStatistics(result: Omit<GraphResult,'stats'>): GraphStatistics {
  const {graph, vertices, edges, order, gaps, canvas} = result;
  const drawn = edges.filter(edge => !edge.transitive);
  const spans = new Map<number,number>();
  let spanTotal = 0;
  let spanMaximum = 0;
  let longEdges = 0;
  let vertical = 0;
  let routeLength = 0;
  let bends = 0;
  let longest: Edge | null = null;
  for (const edge of drawn) {
    spans.set(edge.span, (spans.get(edge.span) || 0) + 1);
    spanTotal += edge.span;
    spanMaximum = Math.max(spanMaximum, edge.span);
    if (edge.span >= 2) {
      longEdges++;
      const dummyX = vertices[edge.chain[1]].x;
      if (edge.chain.slice(1, -1).every(v => vertices[v].x === dummyX)) vertical++;
    }
    routeLength += edge.length;
    bends += edge.bends;
    if (longest === null || edge.length > longest.length) longest = edge;
  }
  let segments = 0;
  let straight = 0;
  let offset = 0;
  for (const gap of gaps) {
    for (const segment of gap) {
      segments++;
      const difference = Math.abs(vertices[segment.upper].x - vertices[segment.lower].x);
      offset += difference;
      if (difference === 0) straight++;
    }
  }
  return {drawn, spans, spanTotal, spanMaximum, longEdges, vertical, routeLength, bends, longest,
    segments, straight, offset, dummies: vertices.length - graph.nodes.length,
    maxNodes: Math.max(...order.map(layer => layer.filter(v => vertices[v].real).length)),
    maxVertices: Math.max(...order.map(layer => layer.length)), crossingCells: canvas.crossingCells()};
}

function processGraph(graph: Graph): GraphResult {
  graph.nodes.sort((a, b) => a.id - b.id);
  const index = new Map<number,number>(graph.nodes.map((node, i) => [node.id, i]));
  const edges: Edge[] = graph.edges.map((edge, number) => ({
    from: index.get(edge.from)!, to: index.get(edge.to)!, number,
    reversed:false, upper:0, lower:0, transitive:false, span:0, chain:[], segments:[],
    crossings:0, upperPoint:[0,0], lowerPoint:[0,0], bends:0, route:[], length:0
  }));
  const analysis = analyzeGraph(graph.nodes.length, edges);
  const sequence = layering.acyclicOrder(graph.nodes.length, edges);
  const {predecessors, successors} = orientEdges(graph.nodes.length, edges, sequence, graph.settings.reduce);
  const heights = layering.heights(predecessors, successors, graph.settings);
  const {vertices, gaps, layerCount} = createVertices(graph.nodes, edges, heights.height);
  const initial = initialOrder(vertices, graph.nodes.length, layerCount);
  const reduction = reduceCrossings(initial, vertices, gaps, graph.settings);
  const order = copyOrder(reduction.best.order);
  const positions = positionsOf(order, vertices.length);
  const sifting = graph.settings.sifting === 'on' ? sift(order, vertices, gaps, positions) : [];
  const crossings = finalCrossings(edges, gaps, order, positions);
  const bk = coordinates.assign(vertices, order, positions, gaps, graph.settings);
  const geometry = routingGeometry(vertices, order, gaps, graph.settings);
  const canvas = new Canvas(graph.settings.direction, geometry.mainLength, geometry.secondaryLength);
  makeRoutes(edges, vertices, geometry, canvas);
  const path = shortestPath(graph, edges, index);
  drawGraph(vertices, edges, gaps, geometry, path, canvas);
  const result: Omit<GraphResult,'stats'> = {graph, edges, analysis, sequence, heights, vertices, gaps, reduction,
    order, positions, sifting, crossings, bk, geometry, canvas, path};
  return {...result, stats: collectStatistics(result)};
}

function layoutLines(result: GraphResult): string[] {
  const {graph, vertices, edges, sequence, heights, reduction, order, sifting, crossings, bk, geometry, canvas} = result;
  const name = (v: number): string => vertices[v].name;
  const lines = ['graph ' + graph.name, 'settings ' + graphIO.settingsOrder.map(key => key + '=' + graph.settings[key]).join(' ')];
  lines.push('acyclic ' + sequence.map(name).join(' '));
  if (graph.settings.layering === 'coffman') lines.push('labels ' + graph.nodes.map((_, v) => name(v) + ':' + heights.labels[v]).join(' '));
  for (const entry of heights.promotions) lines.push(`promote ${entry.round} ${name(entry.vertex)} ${entry.difference}`);
  for (const record of reduction.records) {
    if (record.sweep === 0) lines.push(`sweep ${record.run} 0 initial crossings ${record.crossings}`);
    else lines.push(`sweep ${record.run} ${record.sweep} ${record.direction} moved ${record.moved} swaps ${record.swaps} crossings ${record.crossings}`);
  }
  lines.push(`best run ${reduction.best.run} sweep ${reduction.best.sweep} crossings ${reduction.best.crossings}`);
  for (const entry of sifting) lines.push(`sift ${entry.round} moves ${entry.moves} crossings ${entry.crossings}`);
  for (let i = 0; i < order.length; i++) {
    const band = geometry.bands[i];
    const first = canvas.map(band.start, 0)[geometry.vertical ? 0 : 1];
    const last = canvas.map(band.start + band.thickness - 1, 0)[geometry.vertical ? 0 : 1];
    const low = Math.min(...order[i].map(v => vertices[v].x - vertices[v].left));
    const high = Math.max(...order[i].map(v => vertices[v].x + vertices[v].right));
    lines.push(`layer ${i} band ${Math.min(first, last)} ${Math.max(first, last)} extent ${low} ${high} : `
      + order[i].map(v => name(v) + '@' + vertices[v].x).join(' '));
  }
  for (let i = 0; i < result.gaps.length; i++) {
    lines.push(`between ${i} ${i + 1} segments ${result.gaps[i].length} crossings ${crossings.perGap[i]} tracks ${geometry.spaces[i].tracks} gap ${geometry.spaces[i].length}`);
  }
  lines.push(`bk conflicts ${bk.conflicts} ` + bk.variants.map(variant => variant.name + '=' + variant.blocks + '/' + variant.width).join(' ') + ' smallest ' + bk.smallest);
  for (let i = 0; i < order.length; i++) {
    for (let j = 0; j < order[i].length; j++) {
      const v = order[i][j];
      lines.push(`vertex ${name(v)} layer ${i} pos ${j} `
        + bk.variants.map(variant => variant.name + ' ' + variant.coordinates[v]).join(' ') + ' x ' + vertices[v].x);
    }
  }
  for (const edge of edges) {
    const prefix = `edge ${name(edge.from)} ${name(edge.to)}`;
    if (edge.transitive) { lines.push(prefix + ' transitive'); continue; }
    const chain = edge.reversed ? edge.chain.slice().reverse() : edge.chain;
    lines.push(prefix + (edge.reversed ? ' reversed' : '') + ` span ${edge.span} crossings ${edge.crossings} bends ${edge.bends} path `
      + chain.map(v => vertices[v].x).join(' ') + ' route ' + edge.route.map(point => point.join(',')).join(' '));
  }
  lines.push('end');
  return lines;
}

function statisticsLines(result: GraphResult): string[] {
  const {graph, vertices, edges, analysis, heights, order, reduction, crossings, canvas, path, stats} = result;
  const name = v => vertices[v].name;
  const edgeName = (edge: Edge): string => name(edge.from) + '->' + name(edge.to);
  const lines = ['graph ' + graph.name, `nodes ${graph.nodes.length} edges ${edges.length} self_loops ${graph.selfLoops} duplicates ${graph.duplicates}`];
  lines.push(`sources ${analysis.sources} sinks ${analysis.sinks} isolated ${analysis.isolated} components ${analysis.components}`);
  for (const component of analysis.scc) lines.push('scc ' + component.map(name).join(' '));
  for (const kind of ['reversed', 'transitive']) {
    const selected = edges.filter(edge => edge[kind]);
    lines.push(kind + ' ' + selected.length + (selected.length > 0 ? ' ' + selected.map(edgeName).join(' ') : ''));
  }
  lines.push(`layers ${order.length} max_nodes ${stats.maxNodes} max_vertices ${stats.maxVertices}`);
  lines.push(graph.settings.promotion === 'on'
    ? `promotion rounds ${heights.rounds} accepted ${heights.promotions.length} dummies_before ${heights.dummyBefore}` : 'promotion off');
  lines.push(`dummies ${stats.dummies} span_total ${stats.spanTotal} span_max ${stats.spanMaximum}`);
  lines.push('spans ' + (stats.drawn.length === 0 ? 'none' : [...stats.spans].sort((a, b) => a[0] - b[0]).map(([span, count]) => span + ':' + count).join(' ')));
  lines.push(`long_edges ${stats.longEdges} vertical ${stats.vertical}`);
  lines.push(`crossings initial ${reduction.records[0].crossings} swept ${reduction.best.crossings} best_run ${reduction.best.run} best_sweep ${reduction.best.sweep} final ${crossings.total} brute ${crossings.brute}`);
  lines.push(`segments ${stats.segments} straight ${stats.straight} bent ${stats.segments - stats.straight} offset ${stats.offset}`);
  lines.push(`routes length ${stats.routeLength} bends ${stats.bends}` + (stats.longest === null ? '' : ' longest ' + edgeName(stats.longest) + ' ' + stats.longest.length));
  lines.push(`canvas width ${canvas.columns} height ${canvas.rows} crossing_cells ${stats.crossingCells}`);
  if (graph.path !== null) {
    lines.push(`path ${graph.path[0]} ${graph.path[1]} ` + (path === null ? 'none' : `hops ${path.length - 1} : ` + path.map(name).join(' ')));
  }
  lines.push('end');
  return lines;
}

function main(): void {
  const graphs = graphIO.readInputs();
  const layout: string[] = [];
  const statistics: string[] = [];
  const csv = ['graph,run,sweep,crossings'];
  const drawings: string[] = [];
  const totals = {laidOut: 0, errors: 0, nodes: 0, edges: 0, dummies: 0, initial: 0, final: 0};
  for (const graph of graphs) {
    if (graph.error !== null) {
      const error = ['graph ' + graph.name, `error ${graph.error.kind} line ${graph.error.line}`, 'end'];
      layout.push(...error);
      statistics.push(...error);
      drawings.push(`graph ${graph.name} error ${graph.error.kind}`);
      totals.errors++;
      continue;
    }
    const result = processGraph(graph);
    layout.push(...layoutLines(result));
    statistics.push(...statisticsLines(result));
    for (const record of result.reduction.records) csv.push(`${graph.name},${record.run},${record.sweep},${record.crossings}`);
    drawings.push([`graph ${graph.name} ${result.canvas.columns}x${result.canvas.rows}`, ...result.canvas.render()].join('\n'));
    totals.laidOut++;
    totals.nodes += graph.nodes.length;
    totals.edges += result.edges.length;
    totals.dummies += result.stats.dummies;
    totals.initial += result.reduction.records[0].crossings;
    totals.final += result.crossings.total;
  }
  statistics.push(`summary graphs ${graphs.length} laid_out ${totals.laidOut} errors ${totals.errors} nodes ${totals.nodes} edges ${totals.edges} dummies ${totals.dummies} crossings_initial ${totals.initial} crossings_final ${totals.final}`);
  mkdirSync('output', {recursive: true});
  const reports: [string,string[]][] = [['layout.txt', layout], ['stats.txt', statistics], ['crossings.csv', csv]];
  for (const [filename, lines] of reports) {
    writeFileSync('output/' + filename, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
  }
  writeFileSync('output/drawings.txt', drawings.length === 0 ? '' : drawings.join('\n\n') + '\n', 'ascii');
}

main();
