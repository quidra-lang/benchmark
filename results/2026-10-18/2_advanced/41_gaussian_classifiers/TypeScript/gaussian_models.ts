import { matrix, cholesky, logDeterminant, quadratic, type Matrix } from './linalg.ts';
import type { Row, Prior } from './dataset.ts';
export const MODELS = ['NB', 'LDA', 'QDA'] as const;
export type ModelType = typeof MODELS[number];
export interface ModelSettings { prior: Prior; epsilon: number; gamma: number }
export interface GroupStats { count: number; mean: number[]; scatter: Matrix; prior: number }
export interface Statistics { classes: GroupStats[]; center: number[]; variance: number[]; count: number }
export interface GaussianClass extends GroupStats { covariance: Matrix; lower: Matrix; logDeterminant: number }
export interface Model { type: ModelType; features: number[]; data: Statistics; classes: GaussianClass[]; maximumVariance: number; added: number }
export interface Prediction { predicted: number; posterior: number[]; logPosterior: number[]; confidence: number; decision: number; distances: number[] }
export function statistics(rows: Row[], features: number[], classCount: number, prior: Prior): Statistics {
    const p = features.length, groups: number[][][] = Array.from({ length: classCount }, () => []);
    for (const r of rows) groups[r.class].push(features.map(f => r.values[f]));
    const classes = groups.map(group => {
        const mean: number[] = Array(p).fill(0), scatter = matrix(p);
        for (let j = 0; j < p; j++) { let sum = 0; for (const x of group) sum += x[j]; mean[j] = sum / group.length; }
        for (let a = 0; a < p; a++) for (let b = 0; b < p; b++) { let sum = 0; for (const x of group) sum += (x[a] - mean[a]) * (x[b] - mean[b]); scatter[a][b] = sum; }
        return { count: group.length, mean, scatter, prior: prior === 'empirical' ? group.length / rows.length : 1 / classCount };
    });
    const center: number[] = [], variance: number[] = [];
    for (const f of features) { let sum = 0; for (const r of rows) sum += r.values[f]; const c = sum / rows.length; center.push(c); sum = 0; for (const r of rows) sum += (r.values[f] - c) * (r.values[f] - c); variance.push(sum / rows.length); }
    return { classes, center, variance, count: rows.length };
}
export function train(rows: Row[], features: number[], type: ModelType, s: ModelSettings, classCount: number): Model {
    const data = statistics(rows, features, classCount, s.prior), p = features.length, maximumVariance = Math.max(...data.variance), added = s.epsilon * maximumVariance, pooled = matrix(p);
    if (type === 'LDA') for (let a = 0; a < p; a++) for (let b = 0; b < p; b++) { let sum = 0; for (const g of data.classes) sum += g.scatter[a][b]; pooled[a][b] = sum / (rows.length - classCount); }
    const classes = data.classes.map(g => {
        const covariance = type === 'LDA' ? pooled : matrix(p);
        if (type === 'NB') for (let j = 0; j < p; j++) covariance[j][j] = g.scatter[j][j] / g.count + added;
        if (type === 'QDA') for (let a = 0; a < p; a++) for (let b = 0; b < p; b++) covariance[a][b] = g.scatter[a][b] / (g.count - 1) * (a === b ? 1 : 1 - s.gamma);
        const lower = cholesky(covariance); return { ...g, covariance, lower, logDeterminant: logDeterminant(lower) };
    });
    return { type, features: features.slice(), data, classes, maximumVariance, added };
}
export function predict(model: Model, vector: number[], costs: Matrix | null = null): Prediction {
    const h = model.features.length * Math.log(2 * Math.PI) / 2, distances: number[] = [], scores: number[] = [];
    for (const g of model.classes) { const q = quadratic(g.lower, vector.map((v, j) => v - g.mean[j])); distances.push(q); scores.push(Math.log(g.prior) - h - g.logDeterminant / 2 - q / 2); }
    let predicted = 0; for (let k = 1; k < scores.length; k++) if (scores[k] > scores[predicted]) predicted = k;
    const maximum = scores[predicted], exponentials = scores.map(g => Math.exp(g - maximum)); let sum = 0; for (const e of exponentials) sum += e;
    const posterior = exponentials.map(e => e / sum), logPosterior = scores.map(g => (g - maximum) - Math.log(sum)); let decision = predicted;
    if (costs) { let least = Infinity; for (let b = 0; b < scores.length; b++) { let risk = 0; for (let k = 0; k < scores.length; k++) risk += posterior[k] * costs[k][b]; if (risk < least) { least = risk; decision = b; } } }
    return { predicted, posterior, logPosterior, confidence: Math.max(...posterior), decision, distances };
}
export const predictRow = (model: Model, row: Row, costs: Matrix | null = null) => predict(model, model.features.map(f => row.values[f]), costs);
