import type { Point, MultiExample, Kernel, Parameters } from './dataset.ts';
import { matrix, subset } from './kernels.ts';
import { train as fit, decision } from './smo.ts';
import type { Trainer } from './smo.ts';
export const pairs = [[1, 2], [1, 3], [2, 3]];
export interface Models { ovr: Trainer[]; ovo: Trainer[] }
export function train(rows: MultiExample[], kernel: Kernel, C: number, params: Parameters): Models {
    const points = rows.map(row => row.point), Q = matrix(kernel, points), ovr = [1, 2, 3].map(k => fit(points, rows.map(row => row.class === k ? 1 : -1), Q, C, kernel, params));
    const ovo = pairs.map(([a, b]) => { const indices: number[] = []; for (let i = 0; i < rows.length; i++) if (rows[i].class === a || rows[i].class === b) indices.push(i); return fit(indices.map(i => points[i]), indices.map(i => rows[i].class === a ? 1 : -1), subset(Q, indices), C, kernel, params); }); return { ovr, ovo };
}
export function classify(models: Models, point: Point) {
    const g = models.ovr.map(model => decision(model, point)), h = models.ovo.map(model => decision(model, point)), votes = [0, 0, 0], scores = [0, 0, 0]; let ovr = 0;
    for (let k = 1; k < 3; k++) if (g[k] > g[ovr]) ovr = k;
    for (let i = 0; i < pairs.length; i++) { const [a, b] = pairs[i]; votes[(h[i] > 0 ? a : b) - 1]++; scores[a - 1] += h[i]; scores[b - 1] -= h[i]; }
    const max = Math.max(...votes); let ovo = -1, tied = 0; for (let k = 0; k < 3; k++) if (votes[k] === max) { tied++; if (ovo < 0 || scores[k] > scores[ovo]) ovo = k; }
    return { g, h, votes, scores, ovr: ovr + 1, ovo: ovo + 1, voteTie: tied > 1 };
}
