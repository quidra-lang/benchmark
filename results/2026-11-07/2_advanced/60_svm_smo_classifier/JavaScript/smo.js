'use strict';

const { value } = require('./kernels');

class Trainer {
  constructor(points, labels, Q, C, kernel, params) {
    Object.assign(this, { points, labels, Q, C, kernel, params });
    this.alpha = points.map(() => 0);
    this.errors = labels.map(y => -y);
    this.b = 0;
    this.full = 0; this.nonbound = 0; this.examined = 0; this.steps = 0;
    this.choice = { heuristic: 0, nonbound_loop: 0, full_loop: 0 };
    this.clipping = { none: 0, lower: 0, upper: 0 };
    this.records = [];
    this.converged = false;
  }

  nonBound(a) { return a > 0 && a < this.C; }
  snap(a) { return a < 0.00000001 ? 0 : a > this.C - 0.00000001 ? this.C : a; }

  take(i1, i2) {
    if (i1 === i2) return false;
    const a1Old = this.alpha[i1], a2Old = this.alpha[i2];
    const y1 = this.labels[i1], y2 = this.labels[i2];
    const e1 = this.errors[i1], e2 = this.errors[i2], C = this.C;
    const lo = y1 !== y2 ? Math.max(0, a2Old - a1Old) : Math.max(0, a2Old + a1Old - C);
    const hi = y1 !== y2 ? Math.min(C, C + a2Old - a1Old) : Math.min(C, a2Old + a1Old);
    if (lo === hi) return false;
    const k11 = this.Q[i1][i1], k12 = this.Q[i1][i2], k22 = this.Q[i2][i2];
    const eta = k11 + k22 - 2 * k12;
    if (eta <= 0) return false;
    let a2 = a2Old + y2 * (e1 - e2) / eta, clipping = 'none';
    if (a2 < lo) { a2 = lo; clipping = 'lower'; }
    else if (a2 > hi) { a2 = hi; clipping = 'upper'; }
    a2 = this.snap(a2);
    if (Math.abs(a2 - a2Old) < this.params.eps * (a2 + a2Old + this.params.eps)) return false;
    const a1 = this.snap(a1Old + y1 * y2 * (a2Old - a2));
    const t1 = y1 * (a1 - a1Old), t2 = y2 * (a2 - a2Old);
    const b1 = e1 + t1 * k11 + t2 * k12 + this.b;
    const b2 = e2 + t1 * k12 + t2 * k22 + this.b;
    const bNew = this.nonBound(a1) ? b1 : this.nonBound(a2) ? b2 : (b1 + b2) / 2;
    const delta = bNew - this.b;
    for (let i = 0; i < this.points.length; i++) {
      this.errors[i] = this.errors[i] + (t1 * this.Q[i1][i] + t2 * this.Q[i2][i] - delta);
    }
    if (this.nonBound(a1)) this.errors[i1] = 0;
    if (this.nonBound(a2)) this.errors[i2] = 0;
    this.alpha[i1] = a1; this.alpha[i2] = a2; this.b = bNew;
    this.steps++; this.clipping[clipping]++;
    return true;
  }

  examine(i2) {
    this.examined++;
    const r2 = this.errors[i2] * this.labels[i2], a2 = this.alpha[i2];
    if (!((r2 < -this.params.tau && a2 < this.C) || (r2 > this.params.tau && a2 > 0))) return 0;
    let partner = -1, largest = -1;
    for (let i = 0; i < this.points.length; i++) if (i !== i2 && this.nonBound(this.alpha[i])) {
      const difference = Math.abs(this.errors[i] - this.errors[i2]);
      if (difference > largest) { partner = i; largest = difference; }
    }
    if (partner >= 0 && this.take(partner, i2)) { this.choice.heuristic++; return 1; }
    for (let i = 0; i < this.points.length; i++) {
      if (this.nonBound(this.alpha[i]) && this.take(i, i2)) { this.choice.nonbound_loop++; return 1; }
    }
    for (let i = 0; i < this.points.length; i++) {
      if (this.take(i, i2)) { this.choice.full_loop++; return 1; }
    }
    return 0;
  }

  run() {
    let all = true;
    while (true) {
      const before = this.examined;
      let changed = 0;
      for (let i = 0; i < this.points.length; i++) {
        if (all || this.nonBound(this.alpha[i])) changed += this.examine(i);
      }
      if (all) this.full++; else this.nonbound++;
      const record = { number: this.full + this.nonbound, kind: all ? 'full' : 'nonbound',
        examined: this.examined - before, changed };
      if (all) record.alpha = this.alpha.slice();
      this.records.push(record);
      if (all && changed === 0) { this.converged = true; break; }
      if (this.full + this.nonbound === this.params.maxPasses) break;
      if (all) all = false; else if (changed === 0) all = true;
    }
    return this;
  }
}

function train(points, labels, Q, C, kernel, params) {
  return new Trainer(points, labels, Q, C, kernel, params).run();
}

function decision(model, point) {
  let sum = 0;
  for (let j = 0; j < model.alpha.length; j++) if (model.alpha[j] > 0) {
    sum += model.alpha[j] * model.labels[j] * value(model.kernel, model.points[j], point);
  }
  return sum - model.b;
}

function trainingSums(model, alpha = model.alpha) {
  return model.points.map((_, i) => {
    let sum = 0;
    for (let j = 0; j < alpha.length; j++) if (alpha[j] > 0) sum += alpha[j] * model.labels[j] * model.Q[i][j];
    return sum;
  });
}

module.exports = { train, decision, trainingSums };
