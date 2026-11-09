'use strict';

const { crossing } = require('./intersections');
const { interior } = require('./rings');

class GreinerHormann {
  constructor(first, second) {
    this.polygons = [first, second];
    const edges = this.polygons.map(rings => rings.map(ring => ring.map(() => [])));
    first.forEach((pRing, pi) => pRing.forEach((p, pe) => {
      second.forEach((qRing, qi) => qRing.forEach((q, qe) => {
        const hit = crossing(p, pRing[(pe + 1) % pRing.length], q, qRing[(qe + 1) % qRing.length]);
        if (hit === null) return;
        const record = { point: hit.point, nodes: [] };
        edges[0][pi][pe].push({ position: hit.t, crossing: record });
        edges[1][qi][qe].push({ position: hit.u, crossing: record });
      }));
    }));
    this.initialInside = [[], []]; this.crossings = [];
    this.lists = this.polygons.map((rings, side) => rings.map((ring, ri) => {
      const nodes = [];
      ring.forEach((p, edge) => {
        nodes.push({ point: p, crossing: null, side });
        const hits = edges[side][ri][edge].sort((a, b) => a.position.compare(b.position));
        for (const hit of hits) {
          const node = { point: hit.crossing.point, crossing: hit.crossing, side, entering: false };
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
  traverse(invertFirst, invertSecond) {
    const inverted = [invertFirst, invertSecond], visited = new Set(), result = [];
    for (const start of this.crossings) {
      if (visited.has(start)) continue;
      const points = [];
      let current = start.nodes[0];
      while (true) {
        visited.add(current.crossing); points.push(current.point);
        const direction = current.entering !== inverted[current.side] ? 'next' : 'prev';
        let next = current[direction];
        while (next.crossing === null) { points.push(next.point); next = next[direction]; }
        if (next.crossing === start) break;
        current = next.crossing.nodes[1 - next.side];
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

module.exports = { GreinerHormann };
