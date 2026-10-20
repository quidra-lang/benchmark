'use strict';

const Z = 1.959963984540054;

function solve(matrix, vector) {
  const a = matrix.map(row => row.slice());
  const b = vector.slice();
  const m = b.length;
  for (let k = 0; k < m; k++) {
    for (let i = k + 1; i < m; i++) {
      const factor = a[i][k] / a[k][k];
      for (let j = k; j < m; j++) a[i][j] -= factor * a[k][j];
      b[i] -= factor * b[k];
    }
  }
  const x = Array(m).fill(0);
  for (let i = m - 1; i >= 0; i--) {
    let value = b[i];
    for (let j = i + 1; j < m; j++) value -= a[i][j] * x[j];
    x[i] = value / a[i][i];
  }
  return x;
}

function inverse(matrix) {
  const m = matrix.length;
  const result = Array.from({ length: m }, () => Array(m).fill(0));
  for (let c = 0; c < m; c++) {
    const unit = Array(m).fill(0);
    unit[c] = 1;
    const column = solve(matrix, unit);
    for (let r = 0; r < m; r++) result[r][c] = column[r];
  }
  return result;
}

function logGamma(a) {
  const coefficients = [
    76.18009172947146, -86.50532032941677, 24.01409824083091,
    -1.231739572450155, 0.001208650973866179, -0.000005395239384953
  ];
  const xi0 = a + 5.5;
  const xi1 = xi0 - (a + 0.5) * Math.log(xi0);
  let sigma = 1.000000000190015;
  let y = a;
  for (const coefficient of coefficients) {
    y += 1;
    sigma += coefficient / y;
  }
  return -xi1 + Math.log(2.5066282746310005 * sigma / a);
}

function upperGamma(a, x) {
  if (x === 0) return 1;
  const prefactor = Math.exp(-x + a * Math.log(x) - logGamma(a));
  if (x < a + 1) {
    let alpha = a;
    let xi = 1 / a;
    let sigma = xi;
    for (let i = 0; i < 1000; i++) {
      alpha += 1;
      xi *= x / alpha;
      sigma += xi;
      if (Math.abs(xi) < Math.abs(sigma) * 1e-15) break;
    }
    return 1 - sigma * prefactor;
  }
  const epsilon = 1e-300;
  let b = x + 1 - a;
  let c = 1 / epsilon;
  let d = 1 / b;
  let h = d;
  for (let i = 1; i <= 1000; i++) {
    const an = -i * (i - a);
    b += 2;
    d = an * d + b;
    if (Math.abs(d) < epsilon) d = epsilon;
    c = b + an / c;
    if (Math.abs(c) < epsilon) c = epsilon;
    d = 1 / d;
    const delta = d * c;
    h *= delta;
    if (Math.abs(delta - 1) < 1e-15) break;
  }
  return prefactor * h;
}

function chiSquareP(chisq, degrees) {
  return upperGamma(degrees / 2, chisq / 2);
}

module.exports = { Z, solve, inverse, logGamma, upperGamma, chiSquareP };
