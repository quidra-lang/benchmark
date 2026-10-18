const matrix = [[125, 340, 78, 912, 456], [603, 27, 819, 150, 384], [0, 765, 231, 498, 62], [947, 113, 586, 39, 720]];
const sum = (values: number[]): number => values.reduce((total, n) => total + n, 0);
const format = (values: number[]): string => values.map(n => String(n).padStart(6, " ")).join("");
for (const row of matrix) console.log(format([...row, sum(row)]));
const columns = matrix[0].map((_, column) => sum(matrix.map(row => row[column])));
console.log(format([...columns, sum(columns)]));
