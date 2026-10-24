const games = [
  [8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10, 7, 2],
  [3, 4, 5, 2, 7, 1, 0, 6, 8, 1, 4, 4, 2, 3, 6, 2, 9, 0, 1, 5],
  [5, 5, 0, 10, 7, 3, 9, 1, 6, 4, 8, 2, 3, 7, 4, 6, 1, 9, 7, 3, 5],
  [10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10],
  [10, 9, 1, 10, 10, 7, 2, 0, 0, 10, 8, 1, 10, 6, 4, 10]
];
games.forEach((rolls, number) => {
  let index = 0, total = 0;
  const cumulative = [];
  for (let frame = 0; frame < 9; frame++) {
    if (rolls[index] === 10) {
      total += 10 + rolls[index + 1] + rolls[index + 2];
      index++;
    } else {
      const score = rolls[index] + rolls[index + 1];
      total += score + (score === 10 ? rolls[index + 2] : 0);
      index += 2;
    }
    cumulative.push(total);
  }
  total += rolls.slice(index).reduce((sum, n) => sum + n, 0);
  cumulative.push(total);
  console.log(`game ${number + 1}: ${cumulative.join(" ")}`);
});
