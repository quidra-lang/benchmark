import { crossing } from './intersections.ts';
import { interior } from './rings.ts';
import type { Ring, GraphNode, Crossing, EdgeHit } from './types.ts';

export class GreinerHormann {
  polygons: [Ring[], Ring[]];
  initialInside: boolean[][];
  crossings: Crossing[];
  lists: GraphNode[][][];
  nA: number;
  nB: number;
  constructor(first: Ring[], second: Ring[]) {
    this.polygons = [first, second];
    const edges: EdgeHit[][][][] = this.polygons.map(rings => rings.map(ring => ring.map((): EdgeHit[] => [])));
    first.forEach((pRing, pi) => pRing.forEach((p, pe) => {
      second.forEach((qRing, qi) => qRing.forEach((q, qe) => {
        const hit = crossing(p, pRing[(pe + 1) % pRing.length], q, qRing[(qe + 1) % qRing.length]);
        if (hit === null) return;
        const record: Crossing = { point: hit.point, nodes: [] };
        edges[0][pi][pe].push({ position: hit.t, crossing: record });
        edges[1][qi][qe].push({ position: hit.u, crossing: record });
      }));
    }));
    this.initialInside = [[], []]; this.crossings = [];
    this.lists = this.polygons.map((rings, side) => rings.map((ring, ri) => {
      const nodes: GraphNode[] = [];
      ring.forEach((p, edge) => {
        nodes.push({ point: p, crossing: null, side });
        const hits = edges[side][ri][edge].sort((a, b) => a.position.compare(b.position));
        for (const hit of hits) {
          const node: GraphNode = { point: hit.crossing.point, crossing: hit.crossing, side, entering: false };
          hit.crossing.nodes[side] = node; nodes.push(node);
          if (side === 0) this.crossings.push(hit.crossing);
        }
      });
      let state = interior(ring[0], this.polygons[1 - side]);
      this.initialInside[side].push(state);
      nodes.forEach((node, i) => {
        node.next = nodes[(i + 1) % nodes.length]; node.prev = nodes[(i + nodes.length - 1) % nodes.length];
        if (node.crossing !== null) { node.entering = !state; state = !state; }
      });
      return nodes;
    }));
    this.nA = this.initialInside[0].filter(Boolean).length;
    this.nB = this.initialInside[1].filter(Boolean).length;
  }
  traverse(invertFirst: boolean, invertSecond: boolean): Ring[] {
    const inverted = [invertFirst, invertSecond], visited = new Set<Crossing>(), result: Ring[] = [];
    for (const start of this.crossings) {
      if (visited.has(start)) continue;
      const points: Ring = [];
      let current = start.nodes[0];
      while (true) {
        visited.add(current.crossing!); points.push(current.point);
        const direction: 'next' | 'prev' = current.entering !== inverted[current.side] ? 'next' : 'prev';
        let next = current[direction]!;
        while (next.crossing === null) { points.push(next.point); next = next[direction]!; }
        if (next.crossing === start) break;
        current = next.crossing!.nodes[1 - next.side];
      }
      result.push(points);
    }
    this.lists.forEach((rings, side) => rings.forEach((nodes, index) => {
      if (nodes.some(node => node.crossing !== null)) return;
      if (this.initialInside[side][index] !== inverted[side]) result.push(this.polygons[side][index].slice());
    }));
    return result;
  }
}

