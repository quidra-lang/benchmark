import type { Kernel, Point } from './dataset.ts';
import { fixed } from './evaluation.ts';
export function value(kernel: Kernel, a: Point, b: Point) { if (kernel.kind === 'linear') return a[0] * b[0] + a[1] * b[1]; if (kernel.kind === 'poly') { const s = kernel.gamma * (a[0] * b[0] + a[1] * b[1]) + kernel.coef0; let result = 1; for (let i = 0; i < kernel.degree; i++) result *= s; return result; } const e1 = a[0] - b[0], e2 = a[1] - b[1]; return Math.exp(-kernel.gamma * (e1 * e1 + e2 * e2)); }
export const matrix = (kernel: Kernel, points: Point[]) => points.map(a => points.map(b => value(kernel, a, b)));
export const subset = (matrix: number[][], indices: number[]) => indices.map(i => indices.map(j => matrix[i][j]));
export function description(kernel: Kernel) { return kernel.kind === 'linear' ? 'linear' : kernel.kind === 'poly' ? `poly degree ${kernel.degree} gamma ${fixed(kernel.gamma, 4)} coef0 ${fixed(kernel.coef0, 4)}` : `rbf gamma ${fixed(kernel.gamma, 4)}`; }
