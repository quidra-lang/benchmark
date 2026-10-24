function determinant(matrix: number[][]): number {
  if (matrix.length === 1) return matrix[0][0];
  return matrix[0].reduce((total, value, j) => {
    const minor = matrix.slice(1).map(row => row.filter((_, column) => column !== j));
    const term = value * determinant(minor);
    return total + (j % 2 === 0 ? term : -term);
  }, 0);
}
const matrices = [[[2, -3, 1], [5, 4, -2], [-1, 6, 3]], [[3, 0, -2, 5], [1, 4, 7, -3], [-6, 2, 1, 8], [9, -5, 3, 2]], [[4, -1, 7, 0, -3], [2, 8, -5, 6, 1], [-9, 3, 2, -4, 5], [6, 0, -7, 3, -2], [1, -6, 4, 9, 8]]];
for (const matrix of matrices) console.log(`det(${matrix.length}x${matrix.length}) = ${determinant(matrix)}`);
