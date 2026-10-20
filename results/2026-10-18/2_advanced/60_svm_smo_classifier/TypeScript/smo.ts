import type { Point, Kernel, Parameters } from './dataset.ts';
import { value } from './kernels.ts';
interface Pass { number: number; examined: number; changed: number }
export type PassRecord = Pass & ({ kind: 'full'; alpha: number[] } | { kind: 'nonbound' });
export class Trainer {
    alpha: number[]; errors: number[]; b = 0; full = 0; nonbound = 0; examined = 0; steps = 0; converged = false;
    choice = { heuristic: 0, nonbound_loop: 0, full_loop: 0 }; clipping = { none: 0, lower: 0, upper: 0 }; records: PassRecord[] = [];
    constructor(public points: Point[], public labels: number[], public Q: number[][], public C: number, public kernel: Kernel, private params: Parameters) { this.alpha = points.map(() => 0); this.errors = labels.map(y => -y); }
    nonBound(a: number) { return a > 0 && a < this.C; }
    snap(a: number) { return a < 1e-8 ? 0 : a > this.C - 1e-8 ? this.C : a; }
    take(i1: number, i2: number) {
        if (i1 === i2) return false;
        const old1 = this.alpha[i1], old2 = this.alpha[i2], y1 = this.labels[i1], y2 = this.labels[i2], e1 = this.errors[i1], e2 = this.errors[i2], C = this.C;
        const lo = y1 !== y2 ? Math.max(0, old2 - old1) : Math.max(0, old2 + old1 - C), hi = y1 !== y2 ? Math.min(C, C + old2 - old1) : Math.min(C, old2 + old1); if (lo === hi) return false;
        const k11 = this.Q[i1][i1], k12 = this.Q[i1][i2], k22 = this.Q[i2][i2], eta = k11 + k22 - 2 * k12; if (eta <= 0) return false;
        let a2 = old2 + y2 * (e1 - e2) / eta, clipping: keyof Trainer['clipping'] = 'none';
        if (a2 < lo) { a2 = lo; clipping = 'lower'; } else if (a2 > hi) { a2 = hi; clipping = 'upper'; } a2 = this.snap(a2);
        if (Math.abs(a2 - old2) < this.params.eps * (a2 + old2 + this.params.eps)) return false;
        const a1 = this.snap(old1 + y1 * y2 * (old2 - a2)), t1 = y1 * (a1 - old1), t2 = y2 * (a2 - old2), b1 = e1 + t1 * k11 + t2 * k12 + this.b, b2 = e2 + t1 * k12 + t2 * k22 + this.b;
        const nextB = this.nonBound(a1) ? b1 : this.nonBound(a2) ? b2 : (b1 + b2) / 2, delta = nextB - this.b;
        for (let i = 0; i < this.points.length; i++) this.errors[i] = this.errors[i] + (t1 * this.Q[i1][i] + t2 * this.Q[i2][i] - delta);
        if (this.nonBound(a1)) this.errors[i1] = 0; if (this.nonBound(a2)) this.errors[i2] = 0;
        this.alpha[i1] = a1; this.alpha[i2] = a2; this.b = nextB; this.steps++; this.clipping[clipping]++; return true;
    }
    examine(i2: number) {
        this.examined++; const r2 = this.errors[i2] * this.labels[i2], a2 = this.alpha[i2];
        if (!((r2 < -this.params.tau && a2 < this.C) || (r2 > this.params.tau && a2 > 0))) return 0;
        let partner = -1, largest = -1;
        for (let i = 0; i < this.points.length; i++) if (i !== i2 && this.nonBound(this.alpha[i])) { const d = Math.abs(this.errors[i] - this.errors[i2]); if (d > largest) { partner = i; largest = d; } }
        if (partner >= 0 && this.take(partner, i2)) { this.choice.heuristic++; return 1; }
        for (let i = 0; i < this.points.length; i++) if (this.nonBound(this.alpha[i]) && this.take(i, i2)) { this.choice.nonbound_loop++; return 1; }
        for (let i = 0; i < this.points.length; i++) if (this.take(i, i2)) { this.choice.full_loop++; return 1; } return 0;
    }
    run() {
        let all = true;
        while (true) {
            const before = this.examined; let changed = 0; for (let i = 0; i < this.points.length; i++) if (all || this.nonBound(this.alpha[i])) changed += this.examine(i);
            if (all) this.full++; else this.nonbound++;
            const record = { number: this.full + this.nonbound, examined: this.examined - before, changed };
            this.records.push(all ? { ...record, kind: 'full', alpha: this.alpha.slice() } : { ...record, kind: 'nonbound' });
            if (all && changed === 0) { this.converged = true; break; } if (this.full + this.nonbound === this.params.maxPasses) break;
            if (all) all = false; else if (changed === 0) all = true;
        } return this;
    }
}
export const train = (points: Point[], labels: number[], Q: number[][], C: number, kernel: Kernel, params: Parameters) => new Trainer(points, labels, Q, C, kernel, params).run();
export function decision(model: Trainer, point: Point) { let sum = 0; for (let j = 0; j < model.alpha.length; j++) if (model.alpha[j] > 0) sum += model.alpha[j] * model.labels[j] * value(model.kernel, model.points[j], point); return sum - model.b; }
export function trainingSums(model: Trainer, alpha = model.alpha) { return model.points.map((_, i) => { let sum = 0; for (let j = 0; j < alpha.length; j++) if (alpha[j] > 0) sum += alpha[j] * model.labels[j] * model.Q[i][j]; return sum; }); }
