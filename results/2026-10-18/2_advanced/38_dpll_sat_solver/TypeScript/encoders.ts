import type { Formula, Model } from './cnf_io.ts';

export interface Graph {
    name: string; vertices: number; edges: [number, number][]; reason: string | null;
    maximumDegree: number; greedy: { used: number; colors: number[] };
}
export function queens(size: number): Formula {
    const variables = size * size, clauses: number[][] = [];
    for (let r = 0; r < size; r++) clauses.push(Array.from({ length: size }, (_, c) => r * size + c + 1));
    for (let a = 1; a <= variables; a++) for (let b = a + 1; b <= variables; b++) {
        const r = Math.floor((a - 1) / size), c = (a - 1) % size, s = Math.floor((b - 1) / size), d = (b - 1) % size;
        if (r === s || c === d || Math.abs(r - s) === Math.abs(c - d)) clauses.push([-a, -b]);
    }
    return { variables, clauses };
}
export function pigeon(pigeons: number, holes: number): Formula {
    const clauses: number[][] = [], variable = (i: number, j: number) => (i - 1) * holes + j;
    for (let i = 1; i <= pigeons; i++) clauses.push(Array.from({ length: holes }, (_, j) => variable(i, j + 1)));
    for (let i = 1; i <= pigeons; i++) for (let a = 1; a <= holes; a++) for (let b = a + 1; b <= holes; b++) clauses.push([-variable(i, a), -variable(i, b)]);
    for (let j = 1; j <= holes; j++) for (let a = 1; a <= pigeons; a++) for (let b = a + 1; b <= pigeons; b++) clauses.push([-variable(a, j), -variable(b, j)]);
    return { variables: pigeons * holes, clauses };
}
export function coloring(graph: Graph, colors: number): Formula {
    const clauses: number[][] = [], variable = (v: number, c: number) => (v - 1) * colors + c;
    for (let v = 1; v <= graph.vertices; v++) clauses.push(Array.from({ length: colors }, (_, c) => variable(v, c + 1)));
    for (let v = 1; v <= graph.vertices; v++) for (let a = 1; a <= colors; a++) for (let b = a + 1; b <= colors; b++) clauses.push([-variable(v, a), -variable(v, b)]);
    for (const [a, b] of graph.edges) for (let c = 1; c <= colors; c++) clauses.push([-variable(a, c), -variable(b, c)]);
    return { variables: graph.vertices * colors, clauses };
}
export function positions(model: Model, rows: number, width: number): number[] {
    const result: number[] = [];
    for (let r = 0; r < rows; r++) for (let c = 1; c <= width; c++) if (model[r * width + c]) { result.push(c); break; }
    return result;
}
