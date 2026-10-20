import { squaredDistance, meanPoint } from './kmeans.ts';
export interface Partition {
  segments: { members: number[]; center: number[] }[];
  assignment: number[];
  sse: number;
}
export interface Indices {
  silhouettes: number[];
  silhouette: number;
  calinski_harabasz: number;
  davies_bouldin: number;
}
export function distanceTable(points: number[][]): number[][] {
  const table: number[][] = points.map(() => Array(points.length).fill(0));
  for (let first = 0; first < points.length; first++) {
    for (let second = first + 1; second < points.length; second++) {
      table[first][second] = Math.sqrt(squaredDistance(points[first], points[second]));
      table[second][first] = table[first][second];
    }
  }
  return table;
}
export function clusterIndices(
  points: number[][],
  solution: Partition,
  distances: number[][],
): Indices {
  const { segments, assignment, sse } = solution;
  const silhouettes: number[] = [];
  for (let index = 0; index < points.length; index++) {
    const own = segments[assignment[index]];
    if (own.members.length === 1) {
      silhouettes.push(0);
      continue;
    }
    let within = 0;
    let other = Infinity;
    for (const member of own.members) if (member !== index) within += distances[index][member];
    within /= own.members.length - 1;
    for (let segment = 0; segment < segments.length; segment++) {
      if (segment === assignment[index]) continue;
      let total = 0;
      for (const member of segments[segment].members) total += distances[index][member];
      other = Math.min(other, total / segments[segment].members.length);
    }
    const denominator = Math.max(within, other);
    silhouettes.push(denominator === 0 ? 0 : (other - within) / denominator);
  }
  const global = meanPoint(points);
  const scatters: number[] = [];
  let between = 0;
  let totalSilhouette = 0;
  for (const value of silhouettes) totalSilhouette += value;
  for (const segment of segments) {
    between += segment.members.length * squaredDistance(segment.center, global);
    let total = 0;
    for (const member of segment.members) {
      total += Math.sqrt(squaredDistance(points[member], segment.center));
    }
    scatters.push(total / segment.members.length);
  }
  let totalDB = 0;
  for (let first = 0; first < segments.length; first++) {
    let maximum = 0;
    for (let second = 0; second < segments.length; second++) {
      if (first === second) continue;
      const value =
        (scatters[first] + scatters[second]) /
        Math.sqrt(squaredDistance(segments[first].center, segments[second].center));
      maximum = Math.max(maximum, value);
    }
    totalDB += maximum;
  }
  return {
    silhouettes,
    silhouette: totalSilhouette / points.length,
    calinski_harabasz: between / (segments.length - 1) / (sse / (points.length - segments.length)),
    davies_bouldin: totalDB / segments.length,
  };
}
export function elbow(
  k: number,
  firstK: number,
  lastK: number,
  sse: number,
  firstSSE: number,
  lastSSE: number,
) {
  const x = (k - firstK) / (lastK - firstK);
  const y = (sse - lastSSE) / (firstSSE - lastSSE);
  return (1 - x - y) / Math.sqrt(2);
}
export const hartigan = (sse: number, nextSSE: number, n: number, k: number) =>
  (sse / nextSSE - 1) * (n - k - 1);
export function adjustedRand<X, Y>(first: X[], second: Y[]): number {
  const rows = new Map<X, number>();
  const columns = new Map<Y, number>();
  const cells = new Map<X, Map<Y, number>>();
  for (let index = 0; index < first.length; index++) {
    const left = first[index];
    const right = second[index];
    rows.set(left, (rows.get(left) ?? 0) + 1);
    columns.set(right, (columns.get(right) ?? 0) + 1);
    const row = cells.get(left) ?? new Map<Y, number>();
    row.set(right, (row.get(right) ?? 0) + 1);
    cells.set(left, row);
  }
  const pairs = (value: number) => (value * (value - 1)) / 2;
  let sx = 0;
  let sy = 0;
  let sxy = 0;
  for (const value of rows.values()) sx += pairs(value);
  for (const value of columns.values()) sy += pairs(value);
  for (const row of cells.values()) for (const value of row.values()) sxy += pairs(value);
  const z = pairs(first.length);
  const numerator = 2 * (z * sxy - sx * sy);
  const denominator = z * (sx + sy) - 2 * sx * sy;
  return denominator === 0 ? 1 : numerator / denominator;
}
