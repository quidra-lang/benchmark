let board = [
  ".#......", "..#.....", "###.....", "........",
  "........", "........", ".....###", "........"
];
for (let generation = 0; generation <= 4; generation++) {
  console.log(`generation ${generation}`);
  for (const line of board) console.log(line);
  if (generation === 4) break;
  const nextBoard = [];
  for (let row = 0; row < 8; row++) {
    let line = "";
    for (let column = 0; column < 8; column++) {
      let neighbors = 0;
      for (let dr = -1; dr <= 1; dr++) {
        for (let dc = -1; dc <= 1; dc++) {
          const r = row + dr, c = column + dc;
          if ((dr !== 0 || dc !== 0) && r >= 0 && r < 8 && c >= 0 && c < 8 && board[r][c] === "#") neighbors++;
        }
      }
      const alive = neighbors === 3 || (board[row][column] === "#" && neighbors === 2);
      line += alive ? "#" : ".";
    }
    nextBoard.push(line);
  }
  board = nextBoard;
}
const alive = board.reduce((sum, row) => sum + [...row].filter(cell => cell === "#").length, 0);
console.log(`alive: ${alive}`);
