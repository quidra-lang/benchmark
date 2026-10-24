const boards = [
  ["XXX", "OO.", "O.X"], ["X.O", ".X.", "O.."], ["XO.", ".OX", "XO."],
  ["XOX", "XOO", "OXX"], ["X.O", "XO.", "O.X"], ["XOX", "OXO", "OXX"]
];
boards.forEach((board, number) => {
  const lines = [...board];
  for (let column = 0; column < 3; column++) lines.push(board.map(row => row[column]).join(""));
  lines.push([0, 1, 2].map(i => board[i][i]).join(""));
  lines.push([0, 1, 2].map(i => board[i][2 - i]).join(""));
  const winning = lines.find(line => line[0] !== "." && [...line].every(mark => mark === line[0]));
  const result = winning ? `${winning[0]} wins` : board.some(row => row.includes(".")) ? "in progress" : "draw";
  console.log(`board ${number + 1}: ${result}`);
});
