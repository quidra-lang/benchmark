import type { Run, Settings } from './dataset.ts';
export class Optimizer {
    private velocity: number[]; private first: number[]; private second: number[]; private pi1 = 1; private pi2 = 1;
    constructor(private run: Run, count: number) { this.velocity = Array(count).fill(0); this.first = Array(count).fill(0); this.second = Array(count).fill(0); }
    update(theta: number[], gradient: number[], rate: number) {
        const run = this.run; if (run.optimizer === 'ADAM') { this.pi1 *= run.beta1; this.pi2 *= run.beta2; }
        for (let p = 0; p < theta.length; p++) { const g = gradient[p]; if (run.optimizer === 'SGD') theta[p] -= rate * g; else if (run.optimizer === 'MOMENTUM') { this.velocity[p] = run.mu * this.velocity[p] + g; theta[p] -= rate * this.velocity[p]; } else { this.first[p] = run.beta1 * this.first[p] + (1 - run.beta1) * g; this.second[p] = run.beta2 * this.second[p] + (1 - run.beta2) * g * g; const first = this.first[p] / (1 - this.pi1), second = this.second[p] / (1 - this.pi2); theta[p] -= rate * first / (Math.sqrt(second) + run.epsilon); } }
    }
}
export function learningRate(run: Run, settings: Settings, epoch: number) { let rate = run.eta; for (let i = 0; i < Math.floor((epoch - 1) / settings.step); i++) rate *= settings.gamma; return rate; }
