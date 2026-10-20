export function zeros(rows: number, columns = rows): number[][] { return Array.from({ length: rows }, () => Array(columns).fill(0)); }
export function identity(size: number): number[][] { const m = zeros(size); for (let i = 0; i < size; i++) m[i][i] = 1; return m; }
export function copy(m: number[][]): number[][] { return m.map(row => [...row]); }
export function column(m: number[][], k: number): number[] { return m.map(row => row[k]); }
export function dot(a: number[], b: number[]): number { let total = 0; for (let i = 0; i < a.length; i++) total += a[i] * b[i]; return total; }
export function multiply(m: number[][], v: number[]): number[] { return m.map(row => dot(row, v)); }
export function length(v: number[]): number { return Math.sqrt(dot(v, v)); }
export function normalize(v: number[]): number[] { const n = length(v); return v.map(x => x / n); }
export function orient(v: number[]): number[] { let k = 0; for (let i = 1; i < v.length; i++) if (Math.abs(v[i]) > Math.abs(v[k])) k = i; return v[k] < 0 ? v.map(x => -x) : [...v]; }
export function difference(a: number[], b: number[]): number { let max = 0; for (let i = 0; i < a.length; i++) max = Math.max(max, Math.abs(a[i] - b[i])); return max; }
export function deflate(m: number[][], value: number, v: number[]): void { for (let i = 0; i < m.length; i++) for (let j = 0; j < m.length; j++) m[i][j] -= value * v[i] * v[j]; }
export function inverseDeterminant(m: number[][]) {
  const n = m.length, unit = identity(n), augmented = m.map((row, i) => [...row, ...unit[i]]); let determinant = 1;
  for (let k = 0; k < n; k++) {
    const pivot = augmented[k][k]; determinant *= pivot;
    for (let h = 0; h < 2 * n; h++) augmented[k][h] /= pivot;
    for (let i = 0; i < n; i++) if (i !== k) { const c = augmented[i][k]; for (let h = 0; h < 2 * n; h++) augmented[i][h] -= c * augmented[k][h]; }
  }
  return { inverse: augmented.map(row => row.slice(n)), determinant };
}
