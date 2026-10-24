import type { Face } from './obj_io.ts';
import { edgeKey, type Topology, type Edge } from './topology.ts';

export function containsDirection(face: Face, a: number, b: number): boolean {
  return face.vertices.some((v, i) => v === a && face.vertices[(i + 1) % 3] === b);
}
export function flip(face: Face): void {
  [face.vertices[1], face.vertices[2]] = [face.vertices[2], face.vertices[1]];
}
export function inconsistentEdges(faces: Face[], topology: Topology): Edge[] {
  return topology.edges.filter(
    (edge) =>
      edge.faces.length === 2 &&
      containsDirection(faces[edge.faces[0]], edge.a, edge.b) ===
        containsDirection(faces[edge.faces[1]], edge.a, edge.b),
  );
}
export function orient(faces: Face[], topology: Topology): void {
  const visited = faces.map(() => false);
  for (let start = 0; start < faces.length; start++) {
    if (visited[start]) continue;
    visited[start] = true;
    const queue = [start];
    for (let head = 0; head < queue.length; head++) {
      const f = queue[head];
      const vertices = faces[f].vertices;
      for (let i = 0; i < 3; i++) {
        const a = vertices[i];
        const b = vertices[(i + 1) % 3];
        const edge = topology.edgeMap.get(edgeKey(a, b))!;
        if (edge.faces.length !== 2) continue;
        const other = edge.faces[0] === f ? edge.faces[1] : edge.faces[0];
        if (visited[other]) continue;
        if (containsDirection(faces[other], a, b)) flip(faces[other]);
        visited[other] = true;
        queue.push(other);
      }
    }
  }
}
