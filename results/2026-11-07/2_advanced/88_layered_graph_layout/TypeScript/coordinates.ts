import type {Vertex, GapSegment, Settings, Coordinates, CoordinateVariant} from './types.ts';

export function assign(vertices: Vertex[], order: number[][], positions: number[], gaps: GapSegment[][], settings: Settings): Coordinates {
  const count = vertices.length;
  const horizontal = settings.direction === 'TB' || settings.direction === 'BT';
  for (const vertex of vertices) {
    vertex.left = horizontal ? Math.floor((vertex.width - 1) / 2) : 0;
    vertex.right = horizontal ? vertex.width - 1 - vertex.left : 0;
  }
  const marked = new Set<GapSegment>();
  const segments = new Map<string,GapSegment>();
  for (const gap of gaps) for (const segment of gap) segments.set(segment.upper + ',' + segment.lower, segment);
  for (let i = 0; i < gaps.length; i++) {
    const upper = order[i];
    const lower = order[i + 1];
    let start = 0;
    let k0 = 0;
    for (let end = 0; end < lower.length; end++) {
      const v = lower[end];
      const inner = !vertices[v].real && !vertices[vertices[v].upper[0]].real;
      if (!inner && end !== lower.length - 1) continue;
      const k1 = inner ? positions[vertices[v].upper[0]] : upper.length - 1;
      for (let p = start; p <= end; p++) {
        const w = lower[p];
        for (const u of vertices[w].upper) {
          if (positions[u] < k0 || positions[u] > k1) marked.add(segments.get(u + ',' + w)!);
        }
      }
      start = end + 1;
      k0 = k1;
    }
  }
  function separation(a: number, b: number): number {
    const gap = vertices[a].real && vertices[b].real ? settings.node_sep : settings.dummy_sep;
    return vertices[a].right + vertices[b].left + 1 + gap;
  }
  const variants: CoordinateVariant[] = [];
  for (const name of ['ul', 'ur', 'dl', 'dr']) {
    const downward = name[0] === 'u';
    const rightward = name[1] === 'r';
    const root = Array.from({length: count}, (_, v) => v);
    const align = root.slice();
    const layerNumbers = order.map((_, i) => i);
    if (!downward) layerNumbers.reverse();
    const rank = (v: number): number => rightward ? order[vertices[v].layer].length - 1 - positions[v] : positions[v];
    for (const i of layerNumbers.slice(1)) {
      const scan = rightward ? order[i].slice().reverse() : order[i];
      let rho = -1;
      for (const v of scan) {
        const references = vertices[v][downward ? 'upper' : 'lower'].slice().sort((a, b) => rank(a) - rank(b));
        if (references.length === 0) continue;
        for (const median of [Math.floor((references.length - 1) / 2), Math.floor(references.length / 2)]) {
          const u = references[median];
          const segment = segments.get(downward ? u + ',' + v : v + ',' + u);
          if (align[v] === v && !marked.has(segment!) && rho < rank(u)) {
            align[u] = v;
            root[v] = root[u];
            align[v] = root[v];
            rho = rank(u);
          }
        }
      }
    }
    const blocks = [...new Set(root)];
    const incoming = new Map<number,Map<number,number>>(blocks.map(v => [v, new Map<number,number>()]));
    const outgoing = new Map<number,Map<number,number>>(blocks.map(v => [v, new Map<number,number>()]));
    for (const layer of order) {
      const scan = rightward ? layer.slice().reverse() : layer;
      for (let j = 1; j < scan.length; j++) {
        const a = scan[j - 1];
        const b = scan[j];
        const weight = rightward ? separation(b, a) : separation(a, b);
        const previous = outgoing.get(root[a])!.get(root[b]);
        if (previous === undefined || weight > previous) {
          outgoing.get(root[a])!.set(root[b], weight);
          incoming.get(root[b])!.set(root[a], weight);
        }
      }
    }
    const first = new Map<number,number>();
    function y1(block: number): number {
      if (first.has(block)) return first.get(block)!;
      let value = 0;
      for (const [before, weight] of incoming.get(block)!) value = Math.max(value, y1(before) + weight);
      first.set(block, value);
      return value;
    }
    const second = new Map<number,number>();
    function y2(block: number): number {
      if (second.has(block)) return second.get(block)!;
      let following: number | null = null;
      for (const [after, weight] of outgoing.get(block)!) {
        const value = y2(after) - weight;
        if (following === null || value < following) following = value;
      }
      const value = following === null ? y1(block) : Math.max(y1(block), following);
      second.set(block, value);
      return value;
    }
    const coordinates = root.map(block => (rightward ? -1 : 1) * y2(block));
    let low: number | null = null;
    let high: number | null = null;
    for (let v = 0; v < count; v++) {
      const a = coordinates[v] - vertices[v].left;
      const b = coordinates[v] + vertices[v].right;
      if (low === null || a < low) low = a;
      if (high === null || b > high) high = b;
    }
    variants.push({name, coordinates, low: low!, high: high!, width: high! - low! + 1, blocks: blocks.length});
  }
  let smallest = variants[0];
  for (const variant of variants) if (variant.width < smallest.width) smallest = variant;
  for (const variant of variants) {
    const shift = variant.name[1] === 'l' ? smallest.low - variant.low : smallest.high - variant.high;
    variant.coordinates = variant.coordinates.map(value => value + shift);
  }
  let minimum: number | null = null;
  for (let v = 0; v < count; v++) {
    const aligned = variants.map(variant => variant.coordinates[v]).sort((a, b) => a - b);
    vertices[v].x = Math.floor((aligned[1] + aligned[2]) / 2);
    const edge = vertices[v].x - vertices[v].left;
    if (minimum === null || edge < minimum) minimum = edge;
  }
  for (const vertex of vertices) vertex.x -= minimum!;
  return {conflicts: marked.size, variants, smallest: smallest.name};
}

