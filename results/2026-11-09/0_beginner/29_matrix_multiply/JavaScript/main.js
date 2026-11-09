const a = [[3, -2, 5, 1], [-4, 7, 0, 6], [2, 9, -8, -3]];
const b = [[1, 4], [-5, 2], [6, -1], [0, 7]];
for (const row of a) {
  const products = b[0].map((_, j) => row.reduce((sum, n, k) => sum + n * b[k][j], 0));
  console.log(products.map(n => String(n).padStart(5, " ")).join(""));
}
