const rows = [
  "800025000", "070080005", "260400070", "000001900", "010000040",
  "600200000", "900010000", "700000004", "020000036"
];
const board = rows.map(row => [...row].map(Number));
let placements = 0;
function allowed(row, column, digit) {
  if (board[row].includes(digit) || board.some(line => line[column] === digit)) return false;
  const top = Math.floor(row / 3) * 3, left = Math.floor(column / 3) * 3;
  for (let r = top; r < top + 3; r++) {
    for (let c = left; c < left + 3; c++) {
      if (board[r][c] === digit) return false;
    }
  }
  return true;
}
function solve() {
  for (let row = 0; row < 9; row++) {
    for (let column = 0; column < 9; column++) {
      if (board[row][column] !== 0) continue;
      for (let digit = 1; digit <= 9; digit++) {
        if (!allowed(row, column, digit)) continue;
        board[row][column] = digit;
        placements++;
        if (solve()) return true;
        board[row][column] = 0;
      }
      return false;
    }
  }
  return true;
}
solve();
for (const row of board) console.log(row.join(" "));
console.log(`placements: ${placements}`);
