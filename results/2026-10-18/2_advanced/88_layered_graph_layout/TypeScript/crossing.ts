import type {GapSegment, Vertex} from './types.ts';

export function accumulator(segments: GapSegment[], positions: number[], lowerCount: number): number {
  let capacity = 1;
  while (capacity < lowerCount) capacity *= 2;
  const tree = Array(2 * capacity - 1).fill(0);
  const pairs = segments.map(segment => [positions[segment.upper], positions[segment.lower]]);
  pairs.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  let result = 0;
  for (const pair of pairs) {
    let k = pair[1] + capacity - 1;
    tree[k]++;
    while (k > 0) {
      if (k % 2 === 1) result += tree[k + 1];
      k = Math.floor((k - 1) / 2);
      tree[k]++;
    }
  }
  return result;
}

export function crosses(a: GapSegment, b: GapSegment, positions: number[]): boolean {
  return (positions[a.upper] - positions[b.upper]) * (positions[a.lower] - positions[b.lower]) < 0;
}

export function brute(segments: GapSegment[], positions: number[]): number {
  let result = 0;
  for (let a = 0; a < segments.length; a++) {
    for (let b = a + 1; b < segments.length; b++) if (crosses(segments[a], segments[b], positions)) result++;
  }
  return result;
}

export function total(gaps: GapSegment[][], order: number[][], positions: number[]): number {
  let result = 0;
  for (let i = 0; i < gaps.length; i++) result += accumulator(gaps[i], positions, order[i + 1].length);
  return result;
}

export function incidentCost(v: number, w: number, vertices: Vertex[], positions: number[]): number {
  let result = 0;
  for (const side of ['upper', 'lower']) {
    for (const a of vertices[v][side as 'upper'|'lower']) {
      for (const b of vertices[w][side as 'upper'|'lower']) if (positions[a] > positions[b]) result++;
    }
  }
  return result;
}

