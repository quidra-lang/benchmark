'use strict';

function distance(point, station) {
  const dx = point.x - station.x;
  const dy = point.y - station.y;
  const dz = point.z + station.elevation;
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

function evaluate(point, observations, velocity) {
  const distances = [];
  const residuals = [];
  let squares = 0;
  for (const observation of observations) {
    const length = distance(point, observation.station);
    const residual = observation.time - point.t0 - length / velocity;
    distances.push(length);
    residuals.push(residual);
    squares += residual * residual;
  }
  return { distances, residuals, squares, rms: Math.sqrt(squares / observations.length) };
}

function normalEquations(point, observations, velocity) {
  const evaluation = evaluate(point, observations, velocity);
  const gradients = observations.map((observation, j) => {
    const station = observation.station;
    const denominator = velocity * evaluation.distances[j];
    return [(point.x - station.x) / denominator, (point.y - station.y) / denominator,
      (point.z + station.elevation) / denominator, 1];
  });
  const matrix = Array.from({ length: 4 }, () => Array(4).fill(0));
  const rhs = Array(4).fill(0);
  for (let a = 0; a < 4; a++) {
    for (let c = 0; c < 4; c++) {
      for (let j = 0; j < observations.length; j++) matrix[a][c] += gradients[j][a] * gradients[j][c];
    }
    for (let j = 0; j < observations.length; j++) rhs[a] += gradients[j][a] * evaluation.residuals[j];
  }
  return { matrix, rhs, evaluation };
}

function cholesky(matrix) {
  const lower = Array.from({ length: 4 }, () => Array(4).fill(0));
  for (let a = 0; a < 4; a++) {
    for (let c = 0; c <= a; c++) {
      let total = 0;
      for (let k = 0; k < c; k++) total += lower[a][k] * lower[c][k];
      lower[a][c] = a === c ? Math.sqrt(matrix[a][a] - total) : (matrix[a][c] - total) / lower[c][c];
    }
  }
  return lower;
}

function solveCholesky(lower, rhs) {
  const forward = Array(4).fill(0);
  for (let a = 0; a < 4; a++) {
    let total = 0;
    for (let k = 0; k < a; k++) total += lower[a][k] * forward[k];
    forward[a] = (rhs[a] - total) / lower[a][a];
  }
  const solution = Array(4).fill(0);
  for (let a = 3; a >= 0; a--) {
    let total = 0;
    for (let k = a + 1; k < 4; k++) total += lower[k][a] * solution[k];
    solution[a] = (forward[a] - total) / lower[a][a];
  }
  return solution;
}

function gridSearch(observations, params) {
  const [xmin, xmax, xstep] = params.gridX;
  const [ymin, ymax, ystep] = params.gridY;
  const [zmin, zmax, zstep] = params.gridZ;
  const profile = Array(Math.floor((zmax - zmin) / zstep) + 1).fill(null);
  let best = null;
  for (let a = 0; xmin + a * xstep <= xmax; a++) {
    for (let b = 0; ymin + b * ystep <= ymax; b++) {
      for (let c = 0; zmin + c * zstep <= zmax; c++) {
        const point = { x: xmin + a * xstep, y: ymin + b * ystep, z: zmin + c * zstep };
        const deltas = [];
        let total = 0;
        for (const observation of observations) {
          const delta = observation.time - distance(point, observation.station) / params.velocity;
          deltas.push(delta);
          total += delta;
        }
        point.t0 = total / observations.length;
        let squares = 0;
        for (const delta of deltas) squares += (delta - point.t0) * (delta - point.t0);
        if (best === null || squares < best.squares) best = { point, squares };
        if (profile[c] === null || squares < profile[c]) profile[c] = squares;
      }
    }
  }
  return { point: best.point, rms: Math.sqrt(best.squares / observations.length),
    profile: profile.map(value => Math.sqrt(value / observations.length)) };
}

function geiger(initial, observations, velocity) {
  let point = { ...initial };
  const iterations = [];
  let evaluation;
  for (let iteration = 0; iteration < 8; iteration++) {
    const equations = normalEquations(point, observations, velocity);
    const delta = solveCholesky(cholesky(equations.matrix), equations.rhs);
    point = { x: point.x + delta[0], y: point.y + delta[1], z: point.z + delta[2], t0: point.t0 + delta[3] };
    if (point.z < 0) point.z = 0;
    evaluation = evaluate(point, observations, velocity);
    iterations.push({ point, rms: evaluation.rms });
  }
  return { point, iterations, ...evaluation };
}

function locationRun(observations, params) {
  const grid = gridSearch(observations, params);
  return { grid, observations, ...geiger(grid.point, observations, params.velocity) };
}

function uncertainty(point, observations, velocity) {
  const { matrix, evaluation } = normalEquations(point, observations, velocity);
  const lower = cholesky(matrix);
  const variance = evaluation.squares / (observations.length - 4);
  const covariance = Array.from({ length: 4 }, () => Array(4).fill(0));
  for (let c = 0; c < 4; c++) {
    const unit = Array(4).fill(0);
    unit[c] = 1;
    const column = solveCholesky(lower, unit);
    for (let a = 0; a < 4; a++) covariance[a][c] = variance * column[a];
  }
  const xx = covariance[0][0];
  const yy = covariance[1][1];
  const xy = covariance[0][1];
  const mu = (xx + yy) / 2;
  const halfDifference = (xx - yy) / 2;
  const rho = Math.sqrt(halfDifference * halfDifference + xy * xy);
  const theta = Math.atan2(2 * xy, xx - yy) / 2 * 180 / 3.141592653589793;
  let az = 90 - theta;
  if (az >= 180) az -= 180;
  return { smaj: Math.sqrt(mu + rho), smin: Math.sqrt(mu - rho), az,
    erz: Math.sqrt(covariance[2][2]), ert: Math.sqrt(covariance[3][3]) };
}

module.exports = { distance, evaluate, normalEquations, cholesky, solveCholesky, gridSearch, geiger, locationRun, uncertainty };
