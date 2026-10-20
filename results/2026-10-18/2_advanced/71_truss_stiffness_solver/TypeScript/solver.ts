export type Factorization = { stable: true; lower: number[][] } | { stable: false; index: number };
export function cholesky(matrix: number[][]): Factorization {
  const n = matrix.length, lower = Array.from({ length: n }, () => Array<number>(n).fill(0));
  for (let i = 0; i < n; i++) for (let j = 0; j <= i; j++) {
    let value = matrix[i][j]; for (let h = 0; h < j; h++) value -= lower[i][h] * lower[j][h];
    if (j < i) lower[i][j] = value / lower[j][j];
    else { if (value <= 0.000000001 * matrix[i][i]) return { stable: false, index: i }; lower[i][i] = Math.sqrt(value); }
  }
  return { stable: true, lower };
}
export function solve(lower: number[][], b: number[]): number[] {
  const n = b.length, y = Array<number>(n).fill(0), x = Array<number>(n).fill(0);
  for (let i = 0; i < n; i++) { let value = b[i]; for (let h = 0; h < i; h++) value -= lower[i][h] * y[h]; y[i] = value / lower[i][i]; }
  for (let i = n - 1; i >= 0; i--) { let value = y[i]; for (let h = i + 1; h < n; h++) value -= lower[h][i] * x[h]; x[i] = value / lower[i][i]; }
  return x;
}
