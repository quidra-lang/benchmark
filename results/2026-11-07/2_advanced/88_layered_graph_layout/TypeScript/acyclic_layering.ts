import type {RawEdge, Settings, LayerHeights} from './types.ts';

export function acyclicOrder(count: number, edges: RawEdge[]): number[] {
  const remaining = Array(count).fill(true);
  const head: number[] = [];
  const tail: number[] = [];
  for (let step = 0; step < count; step++) {
    const incoming = Array(count).fill(0);
    const outgoing = Array(count).fill(0);
    for (const edge of edges) {
      if (remaining[edge.from] && remaining[edge.to]) {
        outgoing[edge.from]++;
        incoming[edge.to]++;
      }
    }
    let chosen = -1;
    for (let v = 0; v < count; v++) {
      if (remaining[v] && outgoing[v] === 0) { chosen = v; break; }
    }
    if (chosen !== -1) tail.unshift(chosen);
    else {
      for (let v = 0; v < count; v++) {
        if (remaining[v] && incoming[v] === 0) { chosen = v; break; }
      }
      if (chosen === -1) {
        for (let v = 0; v < count; v++) {
          if (remaining[v] && (chosen === -1 || outgoing[v] - incoming[v] > outgoing[chosen] - incoming[chosen])) chosen = v;
        }
      }
      head.push(chosen);
    }
    remaining[chosen] = false;
  }
  return head.concat(tail);
}

function compareSequences(a: number[], b: number[]): number {
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

export function heights(predecessors: number[][], successors: number[][], settings: Settings): LayerHeights {
  const count = predecessors.length;
  let height = Array(count).fill(-1);
  const labels = Array(count).fill(0);
  if (settings.layering === 'longest') {
    function longest(v: number): number {
      if (height[v] !== -1) return height[v];
      height[v] = 0;
      for (const w of successors[v]) height[v] = Math.max(height[v], longest(w) + 1);
      return height[v];
    }
    for (let v = 0; v < count; v++) longest(v);
  } else {
    for (let k = 1; k <= count; k++) {
      let chosen = -1;
      let best: number[] | null = null;
      for (let v = 0; v < count; v++) {
        if (labels[v] !== 0 || predecessors[v].some(u => labels[u] === 0)) continue;
        const sequence = predecessors[v].map(u => labels[u]).sort((a, b) => b - a);
        if (best === null || compareSequences(sequence, best) < 0) { chosen = v; best = sequence; }
      }
      labels[chosen] = k;
    }
    let current = 0;
    let occupied = 0;
    for (let k = 0; k < count; k++) {
      let chosen = -1;
      for (let v = 0; v < count; v++) {
        if (height[v] === -1 && successors[v].every(w => height[w] !== -1)
          && (chosen === -1 || labels[v] > labels[chosen])) chosen = v;
      }
      if (occupied === settings.width || successors[chosen].some(w => height[w] === current)) {
        current++;
        occupied = 0;
      }
      height[chosen] = current;
      occupied++;
    }
  }
  let dummyBefore = 0;
  for (let v = 0; v < count; v++) for (const w of successors[v]) dummyBefore += height[v] - height[w] - 1;
  const promotions: LayerHeights['promotions'] = [];
  let rounds = 0;
  function promote(v: number): number {
    let difference = 0;
    for (const u of predecessors[v]) if (height[u] === height[v] + 1) difference += promote(u);
    height[v]++;
    return difference + successors[v].length - predecessors[v].length;
  }
  if (settings.promotion === 'on') {
    let changed;
    do {
      changed = false;
      rounds++;
      for (let v = 0; v < count; v++) {
        if (predecessors[v].length === 0) continue;
        const saved = height.slice();
        const difference = promote(v);
        if (difference < 0) {
          promotions.push({round: rounds, vertex: v, difference});
          changed = true;
        } else height = saved;
      }
    } while (changed);
  }
  return {height, labels, dummyBefore, promotions, rounds};
}

