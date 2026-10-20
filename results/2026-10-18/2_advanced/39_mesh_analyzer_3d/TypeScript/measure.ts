import type { Face, Triple } from './obj_io.ts';

export const difference = (a: Triple, b: Triple): Triple => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
export const add = (a: Triple, b: Triple): Triple => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
export const dot = (a: Triple, b: Triple): number => (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) || 0;
export const cross = (a: Triple, b: Triple): Triple => [a[1] * b[2] - a[2] * b[1] || 0, a[2] * b[0] - a[0] * b[2] || 0, a[0] * b[1] - a[1] * b[0] || 0];
export function normal(face: Pick<Face, 'vertices'>, vertices: Triple[]): Triple {
    const [a, b, c] = face.vertices.map(v => vertices[v]); return cross(difference(b, a), difference(c, a));
}
export function determinant(face: Face, vertices: Triple[]): number {
    const [a, b, c] = face.vertices.map(v => vertices[v]); return dot(a, cross(b, c));
}
export type Angle = 'acute' | 'right' | 'obtuse';
export interface Geometry { normal: Triple; q: number; determinant: number; angle: Angle }
export function angle(face: Face, vertices: Triple[]): Angle {
    const [a, b, c] = face.vertices.map(v => vertices[v]);
    const minimum = Math.min(dot(difference(b, a), difference(c, a)), dot(difference(c, b), difference(a, b)), dot(difference(a, c), difference(b, c)));
    return minimum < 0 ? 'obtuse' : minimum === 0 ? 'right' : 'acute';
}
export function faceGeometry(face: Face, vertices: Triple[]): Geometry {
    const n = normal(face, vertices); return { normal: n, q: dot(n, n), determinant: determinant(face, vertices), angle: angle(face, vertices) };
}
export function area(geometry: Geometry[]): number { let total = 0; for (const face of geometry) total += Math.sqrt(face.q); return total / 2; }
export function volume6(faces: Face[], vertices: Triple[], indices: number[]): number {
    let total = 0; for (const index of indices) total += determinant(faces[index], vertices); return total;
}
export function fraction(numerator: number, denominator: number): string {
    if (numerator === 0) return '0';
    if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
    let a = Math.abs(numerator), b = denominator;
    while (b !== 0) [a, b] = [b, a % b];
    numerator /= a; denominator /= a; return denominator === 1 ? String(numerator) : `${numerator}/${denominator}`;
}
export function centroid(faces: Face[], vertices: Triple[], indices: number[], geometry: Geometry[], volume: number): string[] {
    const totals: Triple = [0, 0, 0];
    for (const index of indices) {
        const [a, b, c] = faces[index].vertices.map(v => vertices[v]);
        for (let k = 0; k < 3; k++) totals[k] += geometry[index].determinant * (a[k] + b[k] + c[k]);
    }
    return totals.map(total => fraction(total, 4 * volume));
}
export function solidAngle(face: Face, vertices: Triple[], point: Triple): number {
    const [a, b, c] = face.vertices.map(v => difference(vertices[v], point));
    const la = Math.sqrt(dot(a, a)), lb = Math.sqrt(dot(b, b)), lc = Math.sqrt(dot(c, c));
    return 2 * Math.atan2(dot(a, cross(b, c)), la * lb * lc + dot(a, b) * lc + dot(b, c) * la + dot(c, a) * lb);
}
export function winding(faces: Face[], vertices: Triple[], indices: number[], point: Triple): number {
    let total = 0; for (const index of indices) total += solidAngle(faces[index], vertices, point);
    return Math.round(total / (4 * Math.PI)) || 0;
}
export const real = (value: number): string => value.toFixed(3);
