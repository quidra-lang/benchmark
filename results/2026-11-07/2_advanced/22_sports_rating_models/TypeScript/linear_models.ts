import type { Match } from './season.ts';
export interface HomeRatings {
  values: number[];
  home: number;
}
function cholesky(matrix: number[][], right: number[]): number[] {
  const n = right.length;
  const lower: number[][] = Array.from({ length: n }, () => Array(n).fill(0));
  for (let i = 0; i < n; i++) {
    for (let j = 0; j <= i; j++) {
      let sum = 0;
      for (let k = 0; k < j; k++) sum += lower[i][k] * lower[j][k];
      lower[i][j] = i === j ? Math.sqrt(matrix[i][i] - sum) : (matrix[i][j] - sum) / lower[j][j];
    }
  }
  const z: number[] = Array(n);
  const values: number[] = Array(n);
  for (let i = 0; i < n; i++) {
    let sum = 0;
    for (let k = 0; k < i; k++) sum += lower[i][k] * z[k];
    z[i] = (right[i] - sum) / lower[i][i];
  }
  for (let i = n - 1; i >= 0; i--) {
    let sum = 0;
    for (let k = i + 1; k < n; k++) sum += lower[k][i] * values[k];
    values[i] = (z[i] - sum) / lower[i][i];
  }
  return values;
}
export function fitColley(n: number, matches: Match[]): number[] {
  const matrix = Array.from({ length: n }, (_, i) =>
    Array.from({ length: n }, (_, j) => (i === j ? 2 : 0)),
  );
  const right: number[] = Array(n).fill(1);
  for (const { home: i, away: j, result: y } of matches) {
    matrix[i][i]++;
    matrix[j][j]++;
    matrix[i][j]--;
    matrix[j][i]--;
    right[i] += y - 0.5;
    right[j] += 0.5 - y;
  }
  return cholesky(matrix, right);
}
function eliminate(matrix: number[][], right: number[]): number[] {
  const n = right.length;
  for (let k = 0; k < n; k++) {
    let pivot = k;
    for (let i = k + 1; i < n; i++) {
      if (Math.abs(matrix[i][k]) > Math.abs(matrix[pivot][k])) pivot = i;
    }
    [matrix[k], matrix[pivot]] = [matrix[pivot], matrix[k]];
    [right[k], right[pivot]] = [right[pivot], right[k]];
    for (let i = k + 1; i < n; i++) {
      const scale = matrix[i][k] / matrix[k][k];
      for (let j = k; j < n; j++) matrix[i][j] -= scale * matrix[k][j];
      right[i] -= scale * right[k];
    }
  }
  const values: number[] = Array(n);
  for (let i = n - 1; i >= 0; i--) {
    let sum = 0;
    for (let j = i + 1; j < n; j++) sum += matrix[i][j] * values[j];
    values[i] = (right[i] - sum) / matrix[i][i];
  }
  return values;
}
export function fitMassey(n: number, matches: Match[]): HomeRatings {
  const matrix: number[][] = Array.from({ length: n + 1 }, () => Array(n + 1).fill(0));
  const right: number[] = Array(n + 1).fill(0);
  for (const { home: i, away: j, homeScore, awayScore } of matches) {
    const g = homeScore - awayScore;
    matrix[i][i]++;
    matrix[j][j]++;
    matrix[i][j]--;
    matrix[j][i]--;
    matrix[i][n]++;
    matrix[n][i]++;
    matrix[j][n]--;
    matrix[n][j]--;
    matrix[n][n]++;
    right[i] += g;
    right[j] -= g;
    right[n] += g;
  }
  for (let k = 0; k < n; k++) matrix[n - 1][k] = 1;
  matrix[n - 1][n] = 0;
  right[n - 1] = 0;
  const solution = eliminate(matrix, right);
  return { values: solution.slice(0, n), home: solution[n] };
}
