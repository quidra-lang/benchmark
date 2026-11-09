'use strict';

const kernels = require('./kernels');
const smo = require('./smo');

const pairs = [[1, 2], [1, 3], [2, 3]];

function train(rows, kernel, C, params) {
  const points = rows.map(row => row.point), Q = kernels.matrix(kernel, points);
  const ovr = [1, 2, 3].map(k => {
    const labels = rows.map(row => row.class === k ? 1 : -1);
    return smo.train(points, labels, Q, C, kernel, params);
  });
  const ovo = pairs.map(([a, b]) => {
    const indices = [];
    for (let i = 0; i < rows.length; i++) if (rows[i].class === a || rows[i].class === b) indices.push(i);
    return smo.train(indices.map(i => points[i]), indices.map(i => rows[i].class === a ? 1 : -1),
      kernels.subset(Q, indices), C, kernel, params);
  });
  return { ovr, ovo };
}

function classify(models, point) {
  const g = models.ovr.map(model => smo.decision(model, point));
  const h = models.ovo.map(model => smo.decision(model, point));
  let ovr = 0;
  for (let k = 1; k < 3; k++) if (g[k] > g[ovr]) ovr = k;
  const votes = [0, 0, 0], scores = [0, 0, 0];
  for (let i = 0; i < pairs.length; i++) {
    const [a, b] = pairs[i];
    votes[(h[i] > 0 ? a : b) - 1]++;
    scores[a - 1] += h[i]; scores[b - 1] -= h[i];
  }
  const maximum = Math.max(...votes);
  let ovo = -1, tied = 0;
  for (let k = 0; k < 3; k++) if (votes[k] === maximum) {
    tied++;
    if (ovo < 0 || scores[k] > scores[ovo]) ovo = k;
  }
  return { g, h, votes, scores, ovr: ovr + 1, ovo: ovo + 1, voteTie: tied > 1 };
}

module.exports = { pairs, train, classify };
