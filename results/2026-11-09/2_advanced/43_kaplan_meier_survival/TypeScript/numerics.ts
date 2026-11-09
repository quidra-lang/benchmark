export const z95 = 1.959963984540054;
export function solve(matrix: number[][], vector: number[]): number[] {
  const a = matrix.map((row) => [...row]);
  const b = [...vector];
  const n = b.length;
  const x = Array<number>(n).fill(0);
  for (let k = 0; k < n; k++) {
    for (let i = k + 1; i < n; i++) {
      const factor = a[i][k] / a[k][k];
      for (let j = k; j < n; j++) a[i][j] = a[i][j] - factor * a[k][j];
      b[i] = b[i] - factor * b[k];
    }
  }
  for (let i = n - 1; i >= 0; i--) {
    let value = b[i];
    for (let j = i + 1; j < n; j++) value = value - a[i][j] * x[j];
    x[i] = value / a[i][i];
  }
  return x;
}
export function inverse(matrix: number[][]): number[][] {
  const n = matrix.length;
  const result = Array.from({ length: n }, () => Array<number>(n).fill(0));
  for (let c = 0; c < n; c++) {
    const solution = solve(
      matrix,
      Array.from({ length: n }, (_, i) => (i === c ? 1 : 0)),
    );
    for (let a = 0; a < n; a++) result[a][c] = solution[a];
  }
  return result;
}
function logGamma(a: number): number {
  const coefficients = [
    76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155,
    0.001208650973866179, -0.000005395239384953,
  ];
  const x0 = a + 5.5;
  const x1 = x0 - (a + 0.5) * Math.log(x0);
  let sigma = 1.000000000190015;
  let y = a;
  for (const coefficient of coefficients) {
    y = y + 1;
    sigma = sigma + coefficient / y;
  }
  return -x1 + Math.log((2.5066282746310005 * sigma) / a);
}
export function gammaQ(a: number, x: number): number {
  if (x === 0) return 1;
  const prefactor = Math.exp(-x + a * Math.log(x) - logGamma(a));
  if (x < a + 1) {
    let alpha = a;
    let xi = 1 / a;
    let sigma = xi;
    for (let i = 0; i < 1000; i++) {
      alpha = alpha + 1;
      xi = xi * (x / alpha);
      sigma = sigma + xi;
      if (Math.abs(xi) < Math.abs(sigma) * 1e-15) break;
    }
    return 1 - sigma * prefactor;
  }
  const eps = 1e-300;
  let b = x + 1 - a;
  let c = 1 / eps;
  let d = 1 / b;
  let h = d;
  for (let i = 1; i <= 1000; i++) {
    const an = -i * (i - a);
    b = b + 2;
    d = an * d + b;
    if (Math.abs(d) < eps) d = eps;
    c = b + an / c;
    if (Math.abs(c) < eps) c = eps;
    d = 1 / d;
    const delta = d * c;
    h = h * delta;
    if (Math.abs(delta - 1) < 1e-15) break;
  }
  return prefactor * h;
}
export const pValue = (chi2: number, df: number) => gammaQ(df / 2, chi2 / 2);
