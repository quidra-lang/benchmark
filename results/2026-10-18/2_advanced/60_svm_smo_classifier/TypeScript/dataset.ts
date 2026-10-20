import { readFileSync } from 'node:fs';
export type Point = [number, number];
export interface Example { id: string; point: Point; label: number }
export interface MultiExample { id: string; point: Point; class: number; role: string }
interface KernelName { name: string; index: number }
export type Kernel = KernelName & ({ kind: 'linear' } | { kind: 'poly'; degree: number; gamma: number; coef0: number } | { kind: 'rbf'; gamma: number });
export interface Parameters { cs: number[]; kernels: Kernel[]; tau: number; eps: number; maxPasses: number; folds: number; learningCurve: number[]; newtonIterations: number; multiName: string; multiC: number; pegasos: { lambda: number; iterations: number; seed: number }; xMin: number; xMax: number; yMin: number; yMax: number; width: number; height: number }
const lines = (path: string) => readFileSync(path, 'ascii').split('\n').slice(0, -1);
function examples(path: string): Example[] { return lines(path).slice(1).map(line => { const [id, x, y, label] = line.split(','); return { id, point: [Number(x), Number(y)], label: Number(label) }; }); }
export function read() {
    const rows = lines('input/params.txt').map(line => line.split(' ')), cs = rows[0].slice(1).map(Number), kernels: Kernel[] = []; let i = 1;
    while (rows[i][0] === 'KERNEL') { const [, name, kind, a, b, c] = rows[i++], base = { name, index: kernels.length }; if (kind === 'linear') kernels.push({ ...base, kind }); else if (kind === 'poly') kernels.push({ ...base, kind, degree: Number(a), gamma: Number(b), coef0: Number(c) }); else kernels.push({ ...base, kind: 'rbf', gamma: Number(a) }); }
    const r = rows.slice(i), nums = r.map(row => row.slice(1).map(Number));
    const params: Parameters = { cs, kernels, tau: nums[0][0], eps: nums[1][0], maxPasses: nums[2][0], folds: nums[3][0], learningCurve: nums[4], newtonIterations: nums[5][0], multiName: r[6][1], multiC: nums[6][1], pegasos: { lambda: nums[7][0], iterations: nums[7][1], seed: nums[7][2] }, xMin: nums[8][0], xMax: nums[8][1], yMin: nums[9][0], yMax: nums[9][1], width: nums[10][0], height: nums[10][1] };
    const multi: MultiExample[] = lines('input/multiclass.csv').slice(1).map(line => { const [id, x, y, c, role] = line.split(','); return { id, point: [Number(x), Number(y)], class: Number(c), role }; });
    return { train: examples('input/train.csv'), test: examples('input/test.csv'), multiTrain: multi.filter(row => row.role === 'train'), multiTest: multi.filter(row => row.role === 'test'), params };
}
