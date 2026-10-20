export type Matrix = number[][];
export function zeros(rows: number, columns = rows): Matrix {
  return Array.from({ length: rows }, () => Array<number>(columns).fill(0));
}
export function diagonal(values: number[]): Matrix {
  return values.map((v, i) => values.map((_, j) => (i === j ? v : 0)));
}
export function identity(size: number): Matrix {
  return diagonal(Array<number>(size).fill(1));
}
export function transpose(matrix: Matrix): Matrix {
  return matrix[0].map((_, j) => matrix.map((row) => row[j]));
}
export function product(first: Matrix, second: Matrix): Matrix {
  return first.map((row) =>
    second[0].map((_, j) => {
      let value = row[0] * second[0][j];
      for (let k = 1; k < row.length; k++) value += row[k] * second[k][j];
      return value;
    }),
  );
}
export function vectorProduct(matrix: Matrix, vector: number[]): number[] {
  return matrix.map((row) => {
    let value = row[0] * vector[0];
    for (let k = 1; k < vector.length; k++) value += row[k] * vector[k];
    return value;
  });
}
export function add(first: Matrix, second: Matrix): Matrix {
  return first.map((row, i) => row.map((v, j) => v + second[i][j]));
}
export function subtract(first: Matrix, second: Matrix): Matrix {
  return first.map((row, i) => row.map((v, j) => v - second[i][j]));
}
export function vectorAdd(first: number[], second: number[]): number[] {
  return first.map((v, i) => v + second[i]);
}
export function vectorSubtract(first: number[], second: number[]): number[] {
  return first.map((v, i) => v - second[i]);
}
export function inverse(matrix: Matrix): Matrix {
  const n = matrix.length;
  const unit = identity(n);
  const rows = matrix.map((row, i) => [...row, ...unit[i]]);
  for (let c = 0; c < n; c++) {
    const pivot = rows[c][c];
    for (let j = 0; j < 2 * n; j++) rows[c][j] /= pivot;
    for (let i = 0; i < n; i++) {
      if (i === c) continue;
      const factor = rows[i][c];
      for (let j = 0; j < 2 * n; j++) rows[i][j] -= factor * rows[c][j];
    }
  }
  return rows.map((row) => row.slice(n));
}
export function determinant2(matrix: Matrix): number {
  return matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0];
}
export function quadratic2(vector: number[], matrix: Matrix): number {
  return (
    vector[0] * (matrix[0][0] * vector[0] + matrix[0][1] * vector[1]) +
    vector[1] * (matrix[1][0] * vector[0] + matrix[1][1] * vector[1])
  );
}
