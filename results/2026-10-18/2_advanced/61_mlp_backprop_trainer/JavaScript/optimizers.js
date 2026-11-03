'use strict';

class Optimizer {
    constructor(run, parameterCount) {
        this.run = run;
        this.velocity = Array(parameterCount).fill(0);
        this.first = Array(parameterCount).fill(0);
        this.second = Array(parameterCount).fill(0);
        this.pi1 = 1;
        this.pi2 = 1;
    }

    update(theta, gradient, rate) {
        const run = this.run;
        if (run.optimizer === 'ADAM') {
            this.pi1 *= run.beta1;
            this.pi2 *= run.beta2;
        }
        for (let p = 0; p < theta.length; p++) {
            const value = gradient[p];
            if (run.optimizer === 'SGD') theta[p] -= rate * value;
            else if (run.optimizer === 'MOMENTUM') {
                this.velocity[p] = run.mu * this.velocity[p] + value;
                theta[p] -= rate * this.velocity[p];
            } else {
                this.first[p] = run.beta1 * this.first[p] + (1 - run.beta1) * value;
                this.second[p] = run.beta2 * this.second[p] + (1 - run.beta2) * value * value;
                const first = this.first[p] / (1 - this.pi1);
                const second = this.second[p] / (1 - this.pi2);
                theta[p] -= rate * first / (Math.sqrt(second) + run.epsilon);
            }
        }
    }
}

function learningRate(run, settings, epoch) {
    let rate = run.eta;
    const steps = Math.floor((epoch - 1) / settings.step);
    for (let step = 0; step < steps; step++) rate *= settings.gamma;
    return rate;
}

module.exports = {Optimizer, learningRate};
