import { readFileSync } from 'node:fs';

export type Edge = 'left' | 'right' | 'top' | 'bottom';
export interface Mesh {
    width: number; height: number; dx: number; depth: number; count: number;
    codes: string[]; neighbors: number[][];
}
export function readPlate(): Mesh {
    const lines = readFileSync('input/plate.txt', 'ascii').trimEnd().split('\n');
    const [width, height, dx, depth] = lines[0].split(' ').map(Number), neighbors: number[][] = [];
    for (let r = 0; r < height; r++) for (let c = 0; c < width; c++) {
        const p = r * width + c;
        neighbors.push([c > 0 ? p - 1 : -1, c + 1 < width ? p + 1 : -1, r > 0 ? p - width : -1, r + 1 < height ? p + width : -1]);
    }
    return { width, height, dx, depth, count: width * height, codes: lines.slice(1).join('').split(''), neighbors };
}
export function segmentCells(mesh: Mesh, edge: Edge, start: number, end: number): number[] {
    const cells: number[] = [];
    for (let i = start; i <= end; i++) cells.push(edge === 'top' ? i : edge === 'bottom' ? (mesh.height - 1) * mesh.width + i : i * mesh.width + (edge === 'right' ? mesh.width - 1 : 0));
    return cells;
}
export function sourceCells(mesh: Mesh, r1: number, c1: number, r2: number, c2: number): number[] {
    const cells: number[] = [];
    for (let r = r1; r <= r2; r++) for (let c = c1; c <= c2; c++) cells.push(r * mesh.width + c);
    return cells;
}
