import { d2, dot } from './predicates.ts';
import type { Point } from './predicates.ts';
import { key } from './triangulation.ts';
import type { Triangulation } from './triangulation.ts';
export interface Edge {
  i: number;
  j: number;
  length2: number;
}
export class DisjointSet {
  readonly parent: number[];
  readonly sizes: number[];
  count: number;
  constructor(size: number) {
    this.parent = Array.from({ length: size + 1 }, (_, i) => i);
    this.sizes = Array<number>(size + 1).fill(1);
    this.count = size;
  }
  find(site: number): number {
    if (this.parent[site] !== site) this.parent[site] = this.find(this.parent[site]);
    return this.parent[site];
  }
  union(a: number, b: number): boolean {
    let first = this.find(a);
    let second = this.find(b);
    if (first === second) return false;
    if (this.sizes[first] < this.sizes[second]) [first, second] = [second, first];
    this.parent[second] = first;
    this.sizes[first] += this.sizes[second];
    this.count--;
    return true;
  }
}
export function nearestNeighbors(points: Point[], neighbors: number[][]): number[] {
  return neighbors.map((adjacent, site) => {
    if (site === 0) return 0;
    let nearest = adjacent[0];
    for (const other of adjacent) {
      const distance = d2(points[site], points[other]);
      const best = d2(points[site], points[nearest]);
      if (distance < best || (distance === best && other < nearest)) nearest = other;
    }
    return nearest;
  });
}
export function nearestComponents(nearest: number[]): number[][] {
  const sets = new DisjointSet(nearest.length - 1);
  const groups = new Map<number, number[]>();
  for (let s = 1; s < nearest.length; s++) sets.union(s, nearest[s]);
  for (let s = 1; s < nearest.length; s++) {
    const root = sets.find(s);
    if (!groups.has(root)) groups.set(root, []);
    groups.get(root)!.push(s);
  }
  return [...groups.values()].sort((a, b) => a[0] - b[0]);
}
export function minimumTree<E extends Edge>(edges: E[], size: number): E[] {
  const sorted = edges.slice().sort((a, b) => a.length2 - b.length2 || a.i - b.i || a.j - b.j);
  const sets = new DisjointSet(size);
  return sorted.filter((edge) => sets.union(edge.i, edge.j));
}
export function gabriel(edge: Edge, mesh: Triangulation, points: Point[]): boolean {
  return [mesh.directed.get(key(edge.i, edge.j)), mesh.directed.get(key(edge.j, edge.i))].every(
    (s) => s === undefined || dot(points[s], points[edge.i], points[edge.j]) > 0,
  );
}
export function relativeNeighborhood(edge: Edge, points: Point[]): boolean {
  for (let s = 1; s < points.length; s++) {
    if (
      d2(points[edge.i], points[s]) < edge.length2 &&
      d2(points[edge.j], points[s]) < edge.length2
    ) {
      return false;
    }
  }
  return true;
}
export function greedyRoute(start: number, end: number, neighbors: number[][], points: Point[]) {
  const path = [start];
  let current = start;
  let length = 0;
  while (current !== end) {
    let next = neighbors[current][0];
    for (const other of neighbors[current]) {
      const distance = d2(points[other], points[end]);
      const best = d2(points[next], points[end]);
      if (distance < best || (distance === best && other < next)) next = other;
    }
    length += Math.sqrt(d2(points[current], points[next]));
    current = next;
    path.push(current);
  }
  return { path, length };
}
export function dijkstra(start: number, neighbors: number[][], points: Point[]) {
  const distances = Array<number>(points.length).fill(Infinity);
  const previous = Array<number>(points.length).fill(0);
  const visited = points.map(() => false);
  distances[start] = 0;
  for (let step = 1; step < points.length; step++) {
    let current = 0;
    for (let s = 1; s < points.length; s++) {
      if (!visited[s] && (current === 0 || distances[s] < distances[current])) current = s;
    }
    visited[current] = true;
    for (const other of neighbors[current]) {
      if (visited[other]) continue;
      const length = distances[current] + Math.sqrt(d2(points[current], points[other]));
      if (length < distances[other]) {
        distances[other] = length;
        previous[other] = current;
      }
    }
  }
  return { distances, previous };
}
