const fs = require('node:fs');

function readLines(path) {
  return fs.readFileSync(path, 'ascii').slice(0, -1).split('\n');
}

function result(homeScore, awayScore) {
  return homeScore > awayScore ? 1 : homeScore < awayScore ? 0 : 0.5;
}

function beforeRound(matches, round) {
  return matches.filter(match => match.round < round);
}

function readSeason() {
  const teams = readLines('input/teams.csv').slice(1).map(line => {
    const [id, name] = line.split(',');
    return { id, name };
  });
  const indices = new Map(teams.map((team, index) => [team.id, index]));
  const matches = readLines('input/matches.csv').slice(1).map((line, index) => {
    const [round, home, away, homeScore, awayScore] = line.split(',');
    return { round: Number(round), home: indices.get(home), away: indices.get(away),
      homeScore: Number(homeScore), awayScore: Number(awayScore),
      result: result(Number(homeScore), Number(awayScore)), inputOrder: index };
  }).sort((first, second) => first.round - second.round || first.inputOrder - second.inputOrder);
  const params = new Map(readLines('input/params.txt').map(line => {
    const [name, ...values] = line.split(' ');
    return [name, values.map(Number)];
  }));
  const settings = {
    winPoints: params.get('WIN_POINTS')[0], drawPoints: params.get('DRAW_POINTS')[0],
    formLength: params.get('FORM_LENGTH')[0], closeMargin: params.get('CLOSE_MARGIN')[0],
    exponent: params.get('PYTHAGOREAN_EXPONENT')[0], eloK: params.get('ELO_K')[0],
    eloHome: params.get('ELO_HOME')[0], eloInitial: params.get('ELO_INITIAL')[0],
    gridK: params.get('ELO_GRID_K'), gridHome: params.get('ELO_GRID_HOME'),
    btIterations: params.get('BT_ITERATIONS')[0], odIterations: params.get('OD_ITERATIONS')[0],
    linkIterations: params.get('LINK_ITERATIONS')[0], holdout: params.get('HOLDOUT_ROUND')[0],
    upsets: params.get('UPSETS')[0], bins: params.get('CALIBRATION_BINS')[0],
    simulations: params.get('SIMULATIONS')[0], seed: params.get('SIM_SEED')[0],
    top: params.get('TOP_POSITIONS')[0], bottom: params.get('BOTTOM_POSITIONS')[0],
  };
  return { teams, matches, rounds: matches.at(-1).round, settings };
}

module.exports = { readSeason, result, beforeRound };
