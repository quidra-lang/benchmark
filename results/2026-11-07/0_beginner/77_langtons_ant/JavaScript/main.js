const size = 11;
const board = Array.from({length: size}, () => Array(size).fill(false));
const directions = [[-1, 0], [0, 1], [1, 0], [0, -1]];
let row = 5, column = 5, direction = 0;
for (let step = 0; step < 300; step++) {
  direction = (direction + (board[row][column] ? 3 : 1)) % 4;
  board[row][column] = !board[row][column];
  const [dr, dc] = directions[direction];
  row = (row + dr + size) % size;
  column = (column + dc + size) % size;
}
for (let r = 0; r < size; r++) {
  const line = board[r].map((black, c) => r === row && c === column ? "A" : black ? "#" : ".").join("");
  console.log(line);
}
const black = board.reduce((sum, line) => sum + line.filter(Boolean).length, 0);
console.log(`black: ${black}`);
