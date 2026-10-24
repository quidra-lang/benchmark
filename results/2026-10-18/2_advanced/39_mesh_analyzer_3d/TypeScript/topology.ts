import type { Face } from './obj_io.ts';

export interface Edge {
  a: number;
  b: number;
  key: string;
  faces: number[];
}
export interface Component {
  number: number;
  faces: number[];
  edges: Edge[];
  vertices: number[];
  vertexSet: Set<number>;
}
export interface Loop {
  number: number;
  component: number;
  vertices: number[];
  closed: boolean;
  length: number;
}
export const edgeKey = (a: number, b: number): string => (a < b ? `${a},${b}` : `${b},${a}`);
function disjointSets(values: number[]) {
  const parents = new Map(values.map((value) => [value, value]));
  function find(value: number): number {
    let root = value;
    while (parents.get(root)! !== root) root = parents.get(root)!;
    while (parents.get(value)! !== value) {
      const next = parents.get(value)!;
      parents.set(value, root);
      value = next;
    }
    return root;
  }
  const join = (a: number, b: number): void => {
    parents.set(find(b), find(a));
  };
  return { find, join };
}
export function analyze(faces: Face[]) {
  const edgeMap = new Map<string, Edge>();
  const vertexFaces = new Map<number, number[]>();
  faces.forEach((face, f) => {
    for (const vertex of face.vertices) {
      if (!vertexFaces.has(vertex)) vertexFaces.set(vertex, []);
      vertexFaces.get(vertex)!.push(f);
    }
    for (let i = 0; i < 3; i++) {
      const a = Math.min(face.vertices[i], face.vertices[(i + 1) % 3]);
      const b = Math.max(face.vertices[i], face.vertices[(i + 1) % 3]);
      const key = edgeKey(a, b);
      if (!edgeMap.has(key)) edgeMap.set(key, { a, b, key, faces: [] });
      edgeMap.get(key)!.faces.push(f);
    }
  });
  const edges = [...edgeMap.values()].sort((a, b) => a.a - b.a || a.b - b.b);
  const vertexEdges = new Map<number, Edge[]>();
  const sets = disjointSets(faces.map((_, i) => i));
  for (const edge of edges) {
    for (const vertex of [edge.a, edge.b]) {
      if (!vertexEdges.has(vertex)) vertexEdges.set(vertex, []);
      vertexEdges.get(vertex)!.push(edge);
    }
    for (let i = 1; i < edge.faces.length; i++) sets.join(edge.faces[0], edge.faces[i]);
  }
  const groups = new Map<number, Component>();
  const componentOf: number[] = [];
  faces.forEach((face, f) => {
    const root = sets.find(f);
    if (!groups.has(root)) {
      groups.set(root, {
        number: groups.size + 1,
        faces: [],
        edges: [],
        vertices: [],
        vertexSet: new Set(),
      });
    }
    const component = groups.get(root)!;
    component.faces.push(f);
    componentOf[f] = component.number;
    for (const v of face.vertices) component.vertexSet.add(v);
  });
  const components = [...groups.values()];
  for (const component of components) {
    component.vertices = [...component.vertexSet].sort((a, b) => a - b);
  }
  for (const edge of edges) components[componentOf[edge.faces[0]] - 1].edges.push(edge);
  const fans = new Map<number, number[][]>();
  for (const [vertex, incident] of vertexFaces) {
    const local = disjointSets(incident);
    for (const edge of vertexEdges.get(vertex)!) {
      for (let i = 1; i < edge.faces.length; i++) local.join(edge.faces[0], edge.faces[i]);
    }
    const parts = new Map<number, number[]>();
    for (const f of incident) {
      const root = local.find(f);
      if (!parts.has(root)) parts.set(root, []);
      parts.get(root)!.push(f);
    }
    fans.set(vertex, [...parts.values()]);
  }
  return { edges, edgeMap, components, componentOf, vertexFaces, vertexEdges, fans };
}
export type Topology = ReturnType<typeof analyze>;
export function boundaryLoops(topology: Topology): Loop[] {
  const loops: Loop[] = [];
  for (const component of topology.components) {
    const boundary = component.edges.filter((edge) => edge.faces.length === 1);
    const unused = new Set(boundary.map((edge) => edge.key));
    const incident = new Map<number, Edge[]>();
    for (const edge of boundary) {
      for (const v of [edge.a, edge.b]) {
        if (!incident.has(v)) incident.set(v, []);
        incident.get(v)!.push(edge);
      }
    }
    for (const [v, edges] of incident) {
      edges.sort((a, b) => (a.a === v ? a.b : a.a) - (b.a === v ? b.b : b.a));
    }
    for (const edge of boundary) {
      if (!unused.has(edge.key)) continue;
      unused.delete(edge.key);
      const sequence = [edge.a, edge.b];
      while (sequence[sequence.length - 1] !== sequence[0]) {
        const current = sequence[sequence.length - 1];
        const next = incident.get(current)!.find((candidate) => unused.has(candidate.key));
        if (next === undefined) break;
        unused.delete(next.key);
        sequence.push(next.a === current ? next.b : next.a);
      }
      const closed = sequence[sequence.length - 1] === sequence[0];
      const length = sequence.length - 1;
      if (closed) sequence.pop();
      loops.push({
        number: loops.length + 1,
        component: component.number,
        vertices: sequence,
        closed,
        length,
      });
    }
  }
  return loops;
}
