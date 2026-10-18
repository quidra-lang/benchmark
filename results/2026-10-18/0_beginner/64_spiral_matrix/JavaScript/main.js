const rows = 5, columns = 6;
const matrix = Array.from({length: rows}, () => Array(columns).fill(0));
const directions = [[0, 1], [1, 0], [0, -1], [-1, 0]];
let row = 0, column = 0, direction = 0;
for (let value = 1; value <= rows * columns; value++) {
  matrix[row][column] = value;
  if (value === rows * columns) break;
  let [dr, dc] = directions[direction];
  const r = row + dr, c = column + dc;
  if (r < 0 || r >= rows || c < 0 || c >= columns || matrix[r][c] !== 0) {
    direction = (direction + 1) % 4;
    [dr, dc] = directions[direction];
  }
  row += dr;
  column += dc;
}
for (const values of matrix) {
  console.log(values.map(value => String(value).padStart(3, " ")).join(""));
}
