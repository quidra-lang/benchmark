export type Matrix = number[][];
export const matrix = (n: number): Matrix => Array.from({ length: n }, () => Array(n).fill(0));
export function cholesky(a: Matrix) {
  const l = matrix(a.length);
  for (let i = 0; i < a.length; i++) {
    for (let j = 0; j <= i; j++) {
      let sum = 0;
      for (let k = 0; k < j; k++) sum += l[i][k] * l[j][k];
      const s = a[i][j] - sum;
      l[i][j] = i === j ? Math.sqrt(s) : s / l[j][j];
    }
  }
  return l;
}
export function forward(l: Matrix, r: number[]) {
  const z: number[] = Array(r.length).fill(0);
  for (let i = 0; i < r.length; i++) {
    let sum = 0;
    for (let k = 0; k < i; k++) sum += l[i][k] * z[k];
    z[i] = (r[i] - sum) / l[i][i];
  }
  return z;
}
export function backward(l: Matrix, u: number[]) {
  const v: number[] = Array(u.length).fill(0);
  for (let i = u.length - 1; i >= 0; i--) {
    let sum = 0;
    for (let k = i + 1; k < u.length; k++) sum += l[k][i] * v[k];
    v[i] = (u[i] - sum) / l[i][i];
  }
  return v;
}
export function logDeterminant(l: Matrix) {
  let sum = 0;
  for (let i = 0; i < l.length; i++) sum += Math.log(l[i][i]);
  return 2 * sum;
}
export function quadratic(l: Matrix, r: number[]) {
  let sum = 0;
  for (const z of forward(l, r)) sum += z * z;
  return sum;
}
export function jacobi(a: Matrix) {
  const n = a.length;
  const m = a.map((row) => row.slice());
  const vectors = matrix(n);
  for (let i = 0; i < n; i++) vectors[i][i] = 1;
  let sweeps = 0;
  while (true) {
    let off = 0;
    for (let i = 0; i < n - 1; i++) for (let j = i + 1; j < n; j++) off += m[i][j] * m[i][j];
    if (Math.sqrt(off) < 1e-12 || sweeps === 50) break;
    for (let i = 0; i < n - 1; i++) {
      for (let j = i + 1; j < n; j++) {
        if (m[i][j] === 0) continue;
        const theta = (m[j][j] - m[i][i]) / (2 * m[i][j]);
        const t = (theta >= 0 ? 1 : -1) / (Math.abs(theta) + Math.sqrt(theta * theta + 1));
        const co = 1 / Math.sqrt(t * t + 1);
        const si = t * co;
        for (let k = 0; k < n; k++) {
          if (k !== i && k !== j) {
            const x = m[k][i];
            const y = m[k][j];
            m[k][i] = m[i][k] = co * x - si * y;
            m[k][j] = m[j][k] = si * x + co * y;
          }
        }
        const w = m[i][j];
        m[i][i] = m[i][i] - t * w;
        m[j][j] = m[j][j] + t * w;
        m[i][j] = m[j][i] = 0;
        for (let k = 0; k < n; k++) {
          const x = vectors[k][i];
          const y = vectors[k][j];
          vectors[k][i] = co * x - si * y;
          vectors[k][j] = si * x + co * y;
        }
      }
    }
    sweeps++;
  }
  return { values: m.map((r, i) => r[i]), vectors, sweeps };
}
