const grid = [".......", "..#....", "....#..", ".#.....", "...#.#.", "......."];
function paths(blocked) {
  const dp = grid.map(row => Array(row.length).fill(0));
  dp[0][0] = 1;
  for (let row = 0; row < grid.length; row++) for (let column = 0; column < grid[0].length; column++) {
    if (blocked && grid[row][column] === "#") dp[row][column] = 0;
    else if (row || column) dp[row][column] = (row ? dp[row - 1][column] : 0) + (column ? dp[row][column - 1] : 0);
  }
  return dp.at(-1).at(-1);
}
console.log(`without obstacles: ${paths(false)}`);
console.log(`with obstacles: ${paths(true)}`);
