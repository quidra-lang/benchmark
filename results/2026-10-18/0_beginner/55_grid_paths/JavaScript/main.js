const grid = [".......", "..#....", "....#..", ".#.....", "...#.#.", "......."];
function paths(blocked) {
  const dp = Array(grid[0].length).fill(0);
  dp[0] = 1;
  for (const row of grid) {
    for (let column = 0; column < row.length; column++) {
      if (blocked && row[column] === "#") dp[column] = 0;
      else if (column > 0) dp[column] += dp[column - 1];
    }
  }
  return dp[dp.length - 1];
}
console.log(`without obstacles: ${paths(false)}`);
console.log(`with obstacles: ${paths(true)}`);
