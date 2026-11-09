function fitBradleyTerry(count, matches, iterations) {
  let strengths = Array(count).fill(1);
  let homeFactor = 1;
  const wins = Array(count).fill(0);
  let homeWins = 0;
  for (const match of matches) {
    wins[match.home] += match.result;
    wins[match.away] += 1 - match.result;
    homeWins += match.result;
  }
  for (let iteration = 0; iteration < iterations; iteration += 1) {
    const denominators = Array(count).fill(0);
    for (const match of matches) {
      const q = homeFactor * strengths[match.home] + strengths[match.away];
      denominators[match.home] += homeFactor / q;
      denominators[match.away] += 1 / q;
    }
    strengths = wins.map((value, team) => value / denominators[team]);
    let total = 0;
    for (const value of strengths) total += value;
    strengths = strengths.map(value => value * count / total);
    let denominator = 0;
    for (const match of matches) {
      denominator += strengths[match.home] / (homeFactor * strengths[match.home] + strengths[match.away]);
    }
    homeFactor = homeWins / denominator;
  }
  return { values: strengths, home: homeFactor };
}

function fitOffenseDefense(count, matches, iterations) {
  const matrix = Array.from({ length: count }, () => Array(count).fill(0));
  for (const match of matches) {
    matrix[match.home][match.away] += match.awayScore;
    matrix[match.away][match.home] += match.homeScore;
  }
  const defense = Array(count).fill(1);
  let offense = Array(count).fill(0);
  for (let iteration = 0; iteration < iterations; iteration += 1) {
    offense = Array(count).fill(0);
    for (let column = 0; column < count; column += 1) {
      for (let row = 0; row < count; row += 1) offense[column] += matrix[row][column] / defense[row];
    }
    for (let row = 0; row < count; row += 1) {
      let value = 0;
      for (let column = 0; column < count; column += 1) value += matrix[row][column] / offense[column];
      defense[row] = value;
    }
  }
  return { offense, defense, values: offense.map((value, team) => value / defense[team]) };
}

module.exports = { fitBradleyTerry, fitOffenseDefense };
