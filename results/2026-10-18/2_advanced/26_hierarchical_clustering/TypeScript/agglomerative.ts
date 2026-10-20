import type { Matrix } from './distances.ts';

export type Linkage = 'single' | 'complete' | 'average' | 'weighted' | 'centroid' | 'median' | 'ward';
export interface Merge { a: number; b: number; height: number; size: number }
export interface Edge { a: number; b: number; weight: number; number: number }

export function linkage(name: string): Linkage {
  switch (name) {
    case 'single': case 'complete': case 'average': case 'weighted':
    case 'centroid': case 'median': case 'ward': return name;
    default: throw new Error(`Unknown linkage: ${name}`);
  }
}

function coefficients(method: Linkage, na: number, nb: number, nk: number): [number, number, number, number] {
  const combined = na + nb;
  switch (method) {
    case 'single': return [0.5, 0.5, 0, -0.5];
    case 'complete': return [0.5, 0.5, 0, 0.5];
    case 'average': return [na / combined, nb / combined, 0, 0];
    case 'weighted': return [0.5, 0.5, 0, 0];
    case 'centroid': return [na / combined, nb / combined, -(na * nb) / (combined * combined), 0];
    case 'median': return [0.5, 0.5, -0.25, 0];
    case 'ward': {
      const total = combined + nk;
      return [(na + nk) / total, (nb + nk) / total, -nk / total, 0];
    }
  }
}

export function agglomerate(delta: Matrix, method: Linkage): Merge[] {
  const count = delta.length;
  const square = method === 'centroid' || method === 'median' || method === 'ward';
  const matrix = Array.from({ length: 2 * count - 1 }, () => Array<number>(2 * count - 1).fill(0));
  for (let a = 0; a < count; a++) for (let b = a + 1; b < count; b++) {
    matrix[a][b] = matrix[b][a] = square ? delta[a][b] * delta[a][b] : delta[a][b];
  }
  const sizes = Array<number>(2 * count - 1).fill(1);
  let active = delta.map((_, i) => i);
  const merges: Merge[] = [];
  for (let step = 0; step < count - 1; step++) {
    let a = active[0], b = active[1], smallest = matrix[a][b];
    for (let i = 0; i < active.length; i++) for (let j = i + 1; j < active.length; j++) {
      const value = matrix[active[i]][active[j]];
      if (value < smallest) { a = active[i]; b = active[j]; smallest = value; }
    }
    const created = count + step;
    sizes[created] = sizes[a] + sizes[b];
    merges.push({ a, b, height: square ? Math.sqrt(smallest) : smallest, size: sizes[created] });
    const remaining = active.filter(id => id !== a && id !== b);
    for (const k of remaining) {
      const [aa, ab, beta, gamma] = coefficients(method, sizes[a], sizes[b], sizes[k]);
      matrix[k][created] = matrix[created][k] = aa * matrix[a][k] + ab * matrix[b][k]
        + beta * smallest + gamma * Math.abs(matrix[a][k] - matrix[b][k]);
    }
    active = [...remaining, created];
  }
  return merges;
}

export function minimumSpanningTree(matrix: Matrix): Edge[] {
  const included = matrix.map(() => false), keys = matrix[0].slice(), parents = matrix.map(() => 0);
  included[0] = true;
  const edges: Edge[] = [];
  for (let step = 0; step < matrix.length - 1; step++) {
    let selected = -1;
    for (let v = 0; v < matrix.length; v++) {
      if (!included[v] && (selected < 0 || keys[v] < keys[selected])) selected = v;
    }
    included[selected] = true;
    edges.push({ a: parents[selected], b: selected, weight: keys[selected], number: step + 1 });
    for (let v = 0; v < matrix.length; v++) if (!included[v] && matrix[selected][v] < keys[v]) {
      keys[v] = matrix[selected][v]; parents[v] = selected;
    }
  }
  return edges;
}
