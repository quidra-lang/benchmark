function expected(home, away, advantage) {
  return 1 / (1 + 10 ** ((away - home - advantage) / 400));
}

function multiplier(match, home, away, advantage) {
  const margin = Math.abs(match.homeScore - match.awayScore);
  if (margin === 0) return 1;
  const difference = match.result === 1 ? home + advantage - away : away - home - advantage;
  return Math.log(margin + 1) * 2.2 / (0.001 * difference + 2.2);
}

function fitElo(count, matches, coefficient, advantage, initial) {
  const values = Array(count).fill(initial);
  const records = [];
  const rounds = new Map();
  for (const [index, match] of matches.entries()) {
    const home = values[match.home];
    const away = values[match.away];
    const probability = expected(home, away, advantage);
    const scale = multiplier(match, home, away, advantage);
    const change = coefficient * scale * (match.result - probability);
    values[match.home] = home + change;
    values[match.away] = away - change;
    records.push({ match, index, expected: probability, change });
    rounds.set(match.round, values.slice());
  }
  return { values, records, rounds };
}

module.exports = { expected, multiplier, fitElo };
