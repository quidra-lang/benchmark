import type { ThermalModel } from './transient.ts';

export type Solver = 'jacobi' | 'gauss_seidel' | 'sor' | 'sor_estimated';
export interface Iteration { field: number[]; deltas: number[]; converged: boolean }
export function numerator(model: ThermalModel, field: number[], source: number[], p: number): number {
    let value = 0, first = true;
    for (const face of model.faces[p]) {
        if (face.q < 0 && face.theta === null) continue;
        const term = face.g * (face.q >= 0 ? field[face.q] : face.theta!); value = first ? term : value + term; first = false;
    }
    return value + source[p];
}
export function iterate(model: ThermalModel, source: number[], method: Solver, initial: number, tolerance: number, maximum: number, omega = 1): Iteration {
    let field: number[] = Array(model.count).fill(initial); const deltas: number[] = []; let converged = false;
    for (let iteration = 1; iteration <= maximum; iteration++) {
        const previous = field.slice();
        if (method === 'jacobi') field = previous.map((_, p) => numerator(model, previous, source, p) / model.diagonal[p]);
        else for (let p = 0; p < model.count; p++) { const y = numerator(model, field, source, p) / model.diagonal[p]; field[p] = method === 'gauss_seidel' ? y : field[p] + omega * (y - field[p]); }
        let delta = 0; for (let p = 0; p < model.count; p++) delta = Math.max(delta, Math.abs(field[p] - previous[p])); deltas.push(delta);
        if (delta < tolerance) { converged = true; break; }
    }
    return { field, deltas, converged };
}
export function bandSolve(model: ThermalModel, rightSides: number[][]): number[][] {
    const n = model.count, width = model.width, matrix: number[][] = Array.from({ length: n }, () => Array(2 * width + 1).fill(0));
    for (let p = 0; p < n; p++) { matrix[p][width] = model.diagonal[p]; for (const face of model.faces[p]) if (face.q >= 0) matrix[p][face.q - p + width] = -face.g; }
    const vectors = rightSides.map(vector => vector.slice());
    for (let k = 0; k < n; k++) {
        const end = Math.min(n - 1, k + width);
        for (let i = k + 1; i <= end; i++) {
            const factor = matrix[i][k - i + width] / matrix[k][width]; matrix[i][k - i + width] = 0;
            for (let j = k + 1; j <= end; j++) matrix[i][j - i + width] -= factor * matrix[k][j - k + width];
            for (const vector of vectors) vector[i] -= factor * vector[k];
        }
    }
    return vectors.map(vector => {
        const field: number[] = Array(n);
        for (let i = n - 1; i >= 0; i--) { let value = vector[i]; for (let j = i + 1; j <= Math.min(n - 1, i + width); j++) value -= matrix[i][j - i + width] * field[j]; field[i] = value / matrix[i][width]; }
        return field;
    });
}
export function maxResidual(model: ThermalModel, rhs: number[], field: number[]): number {
    let maximum = 0;
    for (let p = 0; p < model.count; p++) { let value = rhs[p]; for (const face of model.faces[p]) if (face.q >= 0) value += face.g * field[face.q]; value -= model.diagonal[p] * field[p]; maximum = Math.max(maximum, Math.abs(value)); }
    return maximum;
}
