const { readSeason, beforeRound } = require('./season');
const { expected, fitElo } = require('./elo');
const { fitColley, fitMassey } = require('./linear_models');
const { fitBradleyTerry, fitOffenseDefense } = require('./iterative_models');
const { sigma, fitLink, logLoss, brier, correctness, compareValues, kendall, spearman } = require('./evaluation');
const { real, decimalValue, fraction, fractionText, fractionReal, writeReports } = require('./report');

const RATING_MODELS = ['elo', 'colley', 'massey', 'bt', 'od', 'winpct'];
const COMPARISON_MODELS = ['standings', ...RATING_MODELS, 'rpi', 'pythag'];
const LINK_MODELS = ['colley', 'massey', 'od', 'winpct'];
const PREDICTION_MODELS = ['base', 'elo', 'colley', 'massey', 'bt', 'od', 'winpct', 'ensemble'];
const LETTERS = ['W', 'D', 'L'];
const RESULT_FIELDS = ['won', 'drawn', 'lost'];

function sum(values, valueOf = value => value) {
  let total = 0;
  for (const value of values) total += valueOf(value);
  return total;
}

function addFractions(first, second) {
  return fraction(first[0] * second[1] + second[0] * first[1], first[1] * second[1]);
}

function pointsFor(result, settings) {
  return result === 1 ? settings.winPoints : result === 0.5 ? settings.drawPoints : 0;
}

function teamRecords(data, matches) {
  const records = data.teams.map(() => ({ played: 0, won: 0, drawn: 0, lost: 0,
    scored: 0, conceded: 0, diff: 0, points: 0, home: [0, 0, 0], away: [0, 0, 0],
    close: [0, 0, 0], outcomes: [] }));
  for (const match of matches) {
    for (const atHome of [true, false]) {
      const team = atHome ? match.home : match.away;
      const opponent = atHome ? match.away : match.home;
      const scored = atHome ? match.homeScore : match.awayScore;
      const conceded = atHome ? match.awayScore : match.homeScore;
      const result = atHome ? match.result : 1 - match.result;
      const resultIndex = result === 1 ? 0 : result === 0.5 ? 1 : 2;
      const record = records[team];
      record.played += 1;
      record[RESULT_FIELDS[resultIndex]] += 1;
      record.scored += scored;
      record.conceded += conceded;
      record.points += pointsFor(result, data.settings);
      record[atHome ? 'home' : 'away'][resultIndex] += 1;
      if (Math.abs(scored - conceded) <= data.settings.closeMargin) record.close[resultIndex] += 1;
      record.outcomes.push({ round: match.round, opponent, letter: LETTERS[resultIndex] });
    }
  }
  for (const record of records) {
    record.diff = record.scored - record.conceded;
    record.winpct = fraction(2 * record.won + record.drawn, 2 * record.played);
  }
  return records;
}

function standings(data, matches, records = teamRecords(data, matches)) {
  const headPoints = data.teams.map(() => 0);
  const headDiff = data.teams.map(() => 0);
  for (const match of matches) {
    if (records[match.home].points !== records[match.away].points) continue;
    headPoints[match.home] += pointsFor(match.result, data.settings);
    headPoints[match.away] += pointsFor(1 - match.result, data.settings);
    headDiff[match.home] += match.homeScore - match.awayScore;
    headDiff[match.away] += match.awayScore - match.homeScore;
  }
  const order = data.teams.map((_, team) => team).sort((a, b) =>
    records[b].points - records[a].points || headPoints[b] - headPoints[a] || headDiff[b] - headDiff[a]
    || records[b].diff - records[a].diff || records[b].scored - records[a].scored || a - b);
  const position = Array(data.teams.length);
  const groups = [];
  for (const [index, team] of order.entries()) {
    position[team] = index + 1;
    if (groups.length === 0 || records[groups.at(-1)[0]].points !== records[team].points) groups.push([]);
    groups.at(-1).push(team);
  }
  return { records, order, position, headPoints, headDiff, groups };
}

function longestStreak(outcomes, accepts) {
  let current = 0;
  let start = 0;
  let best = { length: 0, start: 0, end: 0 };
  for (const outcome of outcomes) {
    if (!accepts(outcome.letter)) {
      current = 0;
      continue;
    }
    if (current === 0) start = outcome.round;
    current += 1;
    if (current > best.length) best = { length: current, start, end: outcome.round };
  }
  return best;
}

function addFormAndStreaks(records, settings) {
  for (const record of records) {
    const last = record.outcomes.at(-1).letter;
    let length = 0;
    for (let index = record.outcomes.length - 1; index >= 0; index -= 1) {
      if (record.outcomes[index].letter !== last) break;
      length += 1;
    }
    record.form = record.outcomes.slice(-settings.formLength).map(outcome => outcome.letter).join('');
    record.streak = last + length;
    record.longestWin = longestStreak(record.outcomes, letter => letter === 'W');
    record.longestUnbeaten = longestStreak(record.outcomes, letter => letter !== 'L');
  }
}

function scheduleAverage(record, values) {
  let total = fraction(0, 1);
  for (const outcome of record.outcomes) total = addFractions(total, values[outcome.opponent]);
  return fraction(total[0], total[1] * record.played);
}

function winningIndicators(records, settings) {
  const winpct = records.map(record => record.winpct);
  const sos = records.map(record => scheduleAverage(record, winpct));
  const sos2 = records.map(record => scheduleAverage(record, sos));
  const rpi = records.map((_, team) => {
    const twiceSos = fraction(2 * sos[team][0], sos[team][1]);
    const total = addFractions(addFractions(winpct[team], twiceSos), sos2[team]);
    return fraction(total[0], 4 * total[1]);
  });
  const pythag = records.map(record => 1 / (1 + (record.conceded / record.scored) ** settings.exponent));
  const luck = winpct.map((value, team) => value[0] / value[1] - pythag[team]);
  return { sos, sos2, rpi, pythag, luck };
}

function fitModels(data, matches) {
  const count = data.teams.length;
  const settings = data.settings;
  const records = teamRecords(data, matches);
  const elo = fitElo(count, matches, settings.eloK, settings.eloHome, settings.eloInitial);
  const colley = fitColley(count, matches);
  const massey = fitMassey(count, matches);
  const bt = fitBradleyTerry(count, matches, settings.btIterations);
  const od = fitOffenseDefense(count, matches, settings.odIterations);
  const values = { elo: elo.values, colley, massey: massey.values, bt: bt.values,
    od: od.values, winpct: records.map(record => record.winpct) };
  return { records, elo, colley, massey, bt, od, values };
}

function competitionRanks(values) {
  return values.map(value => 1 + values.filter(other => compareValues(other, value) > 0).length);
}

function modelRanks(data, fit, table, indicators) {
  const comparisons = { standings: table.position.map(position => -position) };
  for (const name of RATING_MODELS) {
    const digits = name === 'elo' || name === 'od' ? 2 : 4;
    comparisons[name] = name === 'winpct' ? fit.values.winpct
      : fit.values[name].map(value => decimalValue(value, digits));
  }
  comparisons.rpi = indicators.rpi;
  comparisons.pythag = indicators.pythag.map(value => decimalValue(value));
  const ranks = Object.fromEntries(RATING_MODELS.map(name => [name, competitionRanks(comparisons[name])]));
  const totals = data.teams.map((_, team) => sum(RATING_MODELS, name => ranks[name][team]));
  const order = data.teams.map((_, team) => team).sort((a, b) => totals[a] - totals[b] || a - b);
  return { comparisons, ranks, totals, order };
}

function roundProgression(data, fit) {
  const history = [];
  const leaders = [];
  let previous = data.teams.map(() => data.settings.eloInitial);
  let leader = null;
  for (let round = 1; round <= data.rounds; round += 1) {
    const elo = fit.elo.rounds.get(round);
    const change = elo.map((value, team) => value - previous[team]);
    const rank = competitionRanks(elo.map(value => decimalValue(value, 2)));
    const table = standings(data, beforeRound(data.matches, round + 1));
    history.push({ round, elo, change, rank, table });
    if (leader !== table.order[0]) {
      leader = table.order[0];
      leaders.push({ round, team: leader, points: table.records[leader].points });
    }
    previous = elo;
  }
  const extremes = data.teams.map((_, team) => {
    const result = { peak: 0, low: 0, best: 0, worst: 0 };
    for (let index = 1; index < history.length; index += 1) {
      const value = decimalValue(history[index].elo[team], 2);
      if (value > decimalValue(history[result.peak].elo[team], 2)) result.peak = index;
      if (value < decimalValue(history[result.low].elo[team], 2)) result.low = index;
      const position = history[index].table.position[team];
      if (position < history[result.best].table.position[team]) result.best = index;
      if (position > history[result.worst].table.position[team]) result.worst = index;
    }
    return result;
  });
  return { history, leaders, extremes };
}

function upsetMatches(data, fit) {
  return fit.elo.records.filter(record => record.match.result !== 0.5).map(record => {
    const homeWon = record.match.result === 1;
    return { ...record, homeWon, probability: homeWon ? record.expected : 1 - record.expected };
  }).sort((a, b) => decimalValue(a.probability) - decimalValue(b.probability) || a.index - b.index)
    .slice(0, data.settings.upsets);
}

function rankCorrelations(comparisons) {
  const tau = COMPARISON_MODELS.map(a => COMPARISON_MODELS.map(b => kendall(comparisons[a], comparisons[b])));
  const rho = COMPARISON_MODELS.map(a => COMPARISON_MODELS.map(b => spearman(comparisons[a], comparisons[b])));
  let most = null;
  let least = null;
  for (let a = 0; a < COMPARISON_MODELS.length; a += 1) {
    for (let b = a + 1; b < COMPARISON_MODELS.length; b += 1) {
      const pair = { a: COMPARISON_MODELS[a], b: COMPARISON_MODELS[b], value: tau[a][b] };
      if (most === null || compareValues(pair.value, most.value) > 0) most = pair;
      if (least === null || compareValues(pair.value, least.value) < 0) least = pair;
    }
  }
  return { tau, rho, most, least };
}

function feature(model, fit, match) {
  const values = fit.values[model];
  if (model === 'od') return Math.log(values[match.home]) - Math.log(values[match.away]);
  if (model === 'winpct') {
    const home = values[match.home];
    const away = values[match.away];
    return home[0] / home[1] - away[0] / away[1];
  }
  return values[match.home] - values[match.away];
}

function validationPredictions(data) {
  const rounds = [];
  const records = [];
  let initialFit = null;
  for (let round = data.settings.holdout; round <= data.rounds; round += 1) {
    const training = beforeRound(data.matches, round);
    const fit = fitModels(data, training);
    if (initialFit === null) initialFit = fit;
    const results = training.map(match => match.result);
    const base = sum(results) / training.length;
    const links = {};
    for (const name of LINK_MODELS) {
      const features = training.map(match => feature(name, fit, match));
      links[name] = fitLink(features, results, data.settings.linkIterations);
    }
    const roundRecords = [];
    for (const match of data.matches.filter(item => item.round === round)) {
      const probabilities = {
        base, elo: expected(fit.elo.values[match.home], fit.elo.values[match.away], data.settings.eloHome),
        bt: fit.bt.home * fit.bt.values[match.home] / (fit.bt.home * fit.bt.values[match.home] + fit.bt.values[match.away]),
      };
      for (const name of LINK_MODELS) {
        probabilities[name] = sigma(links[name].alpha + links[name].beta * feature(name, fit, match));
      }
      probabilities.ensemble = sum(RATING_MODELS, name => probabilities[name]) / 6;
      const margin = fit.massey.values[match.home] - fit.massey.values[match.away] + fit.massey.home;
      const record = { match, probabilities, marginError: (match.homeScore - match.awayScore) - margin };
      records.push(record);
      roundRecords.push(record);
    }
    rounds.push({ round, training: training.length, base, btHome: fit.bt.home, links, records: roundRecords });
  }
  return { rounds, records, initialFit };
}

function evaluatePredictions(data, validation) {
  const count = validation.records.length;
  const scores = {};
  for (const name of PREDICTION_MODELS) {
    const losses = validation.records.map(record => logLoss(record.probabilities[name], record.match.result));
    const brierSum = sum(validation.records, record => brier(record.probabilities[name], record.match.result));
    const correctTwice = sum(validation.records, record => 2 * correctness(record.probabilities[name], record.match.result));
    scores[name] = { losses, logLoss: sum(losses) / count, brier: brierSum / count,
      accuracy: fraction(correctTwice, 2 * count) };
  }
  for (const name of PREDICTION_MODELS) scores[name].skill = 1 - scores[name].brier / scores.base.brier;
  const orderTie = (a, b) => PREDICTION_MODELS.indexOf(a) - PREDICTION_MODELS.indexOf(b);
  const byLogLoss = PREDICTION_MODELS.slice().sort((a, b) =>
    decimalValue(scores[a].logLoss) - decimalValue(scores[b].logLoss) || orderTie(a, b));
  const byBrier = PREDICTION_MODELS.slice().sort((a, b) =>
    decimalValue(scores[a].brier) - decimalValue(scores[b].brier) || orderTie(a, b));
  const byAccuracy = PREDICTION_MODELS.slice().sort((a, b) =>
    compareValues(scores[b].accuracy, scores[a].accuracy) || orderTie(a, b));
  const reference = byLogLoss[0];
  const paired = PREDICTION_MODELS.filter(name => name !== reference).map(name => {
    const differences = scores[name].losses.map((loss, index) => loss - scores[reference].losses[index]);
    const mean = sum(differences) / count;
    const squared = sum(differences, difference => (difference - mean) * (difference - mean));
    const sd = Math.sqrt(squared / (count - 1));
    return { name, mean, sd, t: mean / (sd / Math.sqrt(count)) };
  });
  const errors = validation.records.map(record => record.marginError);
  const margin = { mae: sum(errors, value => Math.abs(value)) / count,
    rmse: Math.sqrt(sum(errors, value => value * value) / count), bias: sum(errors) / count };
  const roundLosses = validation.rounds.map(round => ({ round: round.round,
    values: PREDICTION_MODELS.map(name =>
      sum(round.records, record => logLoss(record.probabilities[name], record.match.result)) / round.records.length) }));
  const calibration = PREDICTION_MODELS.map(name => {
    const bins = Array.from({ length: data.settings.bins }, () => ({ count: 0, probability: 0, resultTwice: 0 }));
    for (const record of validation.records) {
      const probability = record.probabilities[name];
      const index = Math.min(data.settings.bins - 1, Math.floor(data.settings.bins * probability));
      bins[index].count += 1;
      bins[index].probability += probability;
      bins[index].resultTwice += 2 * record.match.result;
    }
    return { name, bins };
  });
  return { scores, byLogLoss, byBrier, byAccuracy, reference, paired, margin, roundLosses, calibration };
}

function eloGrid(data) {
  let best = null;
  const rows = data.settings.gridK.map(coefficient => {
    const losses = data.settings.gridHome.map(home => {
      const fit = fitElo(data.teams.length, data.matches, coefficient, home, data.settings.eloInitial);
      const records = fit.records.filter(record => record.match.round >= data.settings.holdout);
      const loss = sum(records, record => logLoss(record.expected, record.match.result)) / records.length;
      if (best === null || decimalValue(loss) < decimalValue(best.loss)) best = { coefficient, home, loss };
      return loss;
    });
    return { coefficient, losses };
  });
  return { rows, best };
}

function projectSeason(data, validation, finalTable) {
  const settings = data.settings;
  const training = beforeRound(data.matches, settings.holdout);
  const current = standings(data, training, validation.initialFit.records);
  const ratings = validation.initialFit.elo.values;
  const remaining = validation.records.map(record => record.match);
  const probabilities = remaining.map(match => expected(ratings[match.home], ratings[match.away], settings.eloHome));
  const totals = data.teams.map(() => ({ points: 0, title: 0, top: 0, bottom: 0 }));
  const teams = data.teams.map((_, team) => team);
  let state = settings.seed;
  for (let simulation = 0; simulation < settings.simulations; simulation += 1) {
    const points = current.records.map(record => record.points);
    for (const [index, match] of remaining.entries()) {
      state = (48271 * state) % 2147483647;
      const random = state / 2147483647;
      const winner = random < probabilities[index] ? match.home : match.away;
      points[winner] += settings.winPoints;
    }
    const order = teams.slice().sort((a, b) => points[b] - points[a] || current.position[a] - current.position[b]);
    for (const [index, team] of order.entries()) {
      totals[team].points += points[team];
      if (index === 0) totals[team].title += 1;
      if (index + 1 <= settings.top) totals[team].top += 1;
      if (index + 1 >= teams.length - settings.bottom + 1) totals[team].bottom += 1;
    }
  }
  const order = teams.slice().sort((a, b) => totals[b].points - totals[a].points || current.position[a] - current.position[b]);
  const rank = Array(teams.length);
  order.forEach((team, index) => { rank[team] = index + 1; });
  const strength = teams.map(() => 0);
  const counts = teams.map(() => 0);
  for (const match of remaining) {
    strength[match.home] += ratings[match.away];
    strength[match.away] += ratings[match.home];
    counts[match.home] += 1;
    counts[match.away] += 1;
  }
  for (const team of teams) strength[team] /= counts[team];
  const agreement = kendall(rank.map(value => -value), finalTable.position.map(value => -value));
  return { current, totals, order, rank, strength, agreement };
}

function joinSections(sections) {
  return sections.flatMap((section, index) => index === 0 ? section : ['', ...section]);
}

function standingsReport(data, state) {
  const lines = ['pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck'];
  for (const team of state.table.order) {
    const record = state.fit.records[team];
    const indicators = state.indicators;
    lines.push([state.table.position[team], data.teams[team].id, data.teams[team].name,
      record.played, record.won, record.drawn, record.lost, record.scored, record.conceded, record.diff, record.points,
      record.home.join('-'), record.away.join('-'), record.form, record.streak, record.close.join('-'),
      record.longestWin.length, record.longestUnbeaten.length, fractionText(record.winpct),
      fractionReal(indicators.sos[team]), fractionReal(indicators.sos2[team]), fractionReal(indicators.rpi[team]),
      real(indicators.pythag[team]), real(indicators.luck[team])].join(','));
  }
  return lines;
}

function ratingsReport(data, state) {
  const lines = ['team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank'];
  const fit = state.fit;
  const ranking = state.ranking;
  for (const team of ranking.order) {
    const ranks = RATING_MODELS.map(name => ranking.ranks[name][team]);
    lines.push([data.teams[team].id, real(fit.elo.values[team], 2), ranks[0], real(fit.colley[team]), ranks[1],
      real(fit.massey.values[team]), ranks[2], real(fit.bt.values[team]), ranks[3],
      real(fit.od.offense[team], 2), real(fit.od.defense[team]), real(fit.od.values[team], 2), ranks[4],
      fractionReal(fit.records[team].winpct), ranks[5], ranking.totals[team], Math.min(...ranks), Math.max(...ranks)].join(','));
  }
  return lines;
}

function historyReport(data, state) {
  const lines = ['round,team,elo,change,elo_rank,points,position'];
  for (const history of state.progression.history) {
    data.teams.forEach((team, index) => {
      lines.push([history.round, team.id, real(history.elo[index], 2), real(history.change[index], 2),
        history.rank[index], history.table.records[index].points, history.table.position[index]].join(','));
    });
  }
  return lines;
}

function headToHead(record, opponent) {
  const counts = [0, 0, 0];
  for (const outcome of record.outcomes) {
    if (outcome.opponent === opponent) counts[LETTERS.indexOf(outcome.letter)] += 1;
  }
  return counts.join('-');
}

function seasonReport(data, state) {
  const homeWins = data.matches.filter(match => match.result === 1).length;
  const draws = data.matches.filter(match => match.result === 0.5).length;
  const homeLosses = data.matches.length - homeWins - draws;
  const rate = fraction(2 * homeWins + draws, 2 * data.matches.length);
  const summary = [`season teams ${data.teams.length} matches ${data.matches.length} rounds ${data.rounds}`,
    `home won ${homeWins} drawn ${draws} lost ${homeLosses} rate ${fractionText(rate)} ${fractionReal(rate)}`,
    `massey_home_advantage ${real(state.fit.massey.home)}`, `bt_home_factor ${real(state.fit.bt.home)}`];
  const upsets = [`upsets top ${data.settings.upsets}`];
  for (const record of state.upsets) {
    const match = record.match;
    const winner = record.homeWon ? match.home : match.away;
    const loser = record.homeWon ? match.away : match.home;
    const scored = record.homeWon ? match.homeScore : match.awayScore;
    const conceded = record.homeWon ? match.awayScore : match.homeScore;
    upsets.push(`round ${match.round} ${data.teams[winner].id} beat ${data.teams[loser].id} ${scored}-${conceded} `
      + `${record.homeWon ? 'home' : 'away'} expected ${real(record.probability)} gain ${real(Math.abs(record.change), 2)}`);
  }
  const tiebreaks = ['tiebreaks'];
  for (const group of state.table.groups.filter(group => group.length > 1)) {
    tiebreaks.push(`points ${state.table.records[group[0]].points} order ${group.map(team => data.teams[team].id).join(' ')} `
      + `h2h_points ${group.map(team => state.table.headPoints[team]).join(' ')} `
      + `h2h_diff ${group.map(team => state.table.headDiff[team]).join(' ')}`);
  }
  if (tiebreaks.length === 1) tiebreaks.push('none');
  const leaders = ['leaders'];
  for (const leader of state.progression.leaders) {
    leaders.push(`round ${leader.round} ${data.teams[leader.team].id} points ${leader.points}`);
  }
  leaders.push(`lead_changes ${state.progression.leaders.length - 1}`);
  const streaks = [];
  for (const [heading, property] of [['longest_win_streak', 'longestWin'], ['longest_unbeaten_streak', 'longestUnbeaten']]) {
    const longest = Math.max(...state.fit.records.map(record => record[property].length));
    state.fit.records.forEach((record, team) => {
      const streak = record[property];
      if (streak.length === longest) {
        streaks.push(`${heading} ${data.teams[team].id} length ${streak.length} rounds ${streak.start}-${streak.end}`);
      }
    });
  }
  const top = state.table.order.slice(0, data.settings.top);
  const crosstable = [`crosstable top ${data.settings.top}`, `team ${top.map(team => data.teams[team].id).join(' ')}`];
  for (const team of top) {
    const entries = top.map(opponent => team === opponent ? '-' : headToHead(state.fit.records[team], opponent));
    crosstable.push(`${data.teams[team].id} ${entries.join(' ')}`);
  }
  const trajectories = ['trajectories'];
  data.teams.forEach((team, index) => {
    const extreme = state.progression.extremes[index];
    const history = state.progression.history;
    const peak = history[extreme.peak];
    const low = history[extreme.low];
    const best = history[extreme.best];
    const worst = history[extreme.worst];
    trajectories.push(`${team.id} elo_peak ${real(peak.elo[index], 2)} round ${peak.round} `
      + `elo_low ${real(low.elo[index], 2)} round ${low.round} best_position ${best.table.position[index]} round ${best.round} `
      + `worst_position ${worst.table.position[index]} round ${worst.round}`);
  });
  const matrices = [['kendall', state.correlations.tau], ['spearman', state.correlations.rho]].map(([name, matrix]) => {
    const lines = [name, `model ${COMPARISON_MODELS.join(' ')}`];
    COMPARISON_MODELS.forEach((model, index) => lines.push(`${model} ${matrix[index].map(fractionText).join(' ')}`));
    return lines;
  });
  const similarities = [['most_similar', state.correlations.most], ['least_similar', state.correlations.least]]
    .map(([name, pair]) => `${name} ${pair.a} ${pair.b} tau ${fractionText(pair.value)} ${fractionReal(pair.value)}`);
  return joinSections([summary, upsets, tiebreaks, leaders, streaks, crosstable, trajectories, ...matrices, similarities]);
}

function predictionsReport(data, validation) {
  const lines = ['round,home,away,home_score,away_score,result,base,elo,colley,massey,bt,od,winpct,ensemble'];
  for (const record of validation.records) {
    const match = record.match;
    const result = match.result === 1 ? 'H' : match.result === 0.5 ? 'D' : 'A';
    lines.push([match.round, data.teams[match.home].id, data.teams[match.away].id, match.homeScore, match.awayScore,
      result, ...PREDICTION_MODELS.map(name => real(record.probabilities[name]))].join(','));
  }
  return lines;
}

function evaluationReport(data, state) {
  const validation = state.validation;
  const evaluation = state.evaluation;
  const range = [`holdout rounds ${data.settings.holdout}-${data.rounds} matches ${validation.records.length}`];
  const links = ['links'];
  for (const round of validation.rounds) {
    const parts = [`round ${round.round} train ${round.training} base ${real(round.base)} bt_home ${real(round.btHome)}`];
    for (const name of LINK_MODELS) parts.push(`${name} ${real(round.links[name].alpha)} ${real(round.links[name].beta)}`);
    links.push(parts.join(' '));
  }
  const scores = ['scores', 'model log_loss brier skill accuracy'];
  for (const name of PREDICTION_MODELS) {
    const score = evaluation.scores[name];
    scores.push(`${name} ${real(score.logLoss)} ${real(score.brier)} ${real(score.skill)} `
      + `${fractionText(score.accuracy)} ${fractionReal(score.accuracy)}`);
  }
  scores.push(`ranking_log_loss ${evaluation.byLogLoss.join(' ')}`, `ranking_brier ${evaluation.byBrier.join(' ')}`,
    `ranking_accuracy ${evaluation.byAccuracy.join(' ')}`);
  const paired = [`paired_log_loss reference ${evaluation.reference}`];
  for (const comparison of evaluation.paired) {
    paired.push(`${comparison.name} mean_diff ${real(comparison.mean)} sd ${real(comparison.sd)} t ${real(comparison.t, 2)}`);
  }
  const errors = evaluation.margin;
  const margin = [`massey_margin mae ${real(errors.mae)} rmse ${real(errors.rmse)} bias ${real(errors.bias)}`];
  const roundLosses = ['round_log_loss', `round ${PREDICTION_MODELS.join(' ')}`];
  for (const round of evaluation.roundLosses) roundLosses.push(`${round.round} ${round.values.map(value => real(value)).join(' ')}`);
  const calibration = [`calibration bins ${data.settings.bins}`];
  for (const model of evaluation.calibration) {
    model.bins.forEach((bin, index) => {
      const predicted = bin.count === 0 ? '-' : real(bin.probability / bin.count);
      const observed = bin.count === 0 ? '-' : fractionText(fraction(bin.resultTwice, 2 * bin.count));
      calibration.push(`${model.name} bin ${index + 1} count ${bin.count} predicted ${predicted} observed ${observed}`);
    });
  }
  const grid = ['elo_grid', `k ${data.settings.gridHome.map(home => 'h' + home).join(' ')}`];
  for (const row of state.grid.rows) grid.push(`${row.coefficient} ${row.losses.map(value => real(value)).join(' ')}`);
  const best = state.grid.best;
  grid.push(`best k ${best.coefficient} home ${best.home} log_loss ${real(best.loss)}`);
  const agreement = state.projection.agreement;
  const projection = [`projection simulations ${data.settings.simulations} kendall ${fractionText(agreement)} ${fractionReal(agreement)}`];
  return joinSections([range, links, scores, paired, margin, roundLosses, calibration, grid, projection]);
}

function projectionReport(data, state) {
  const lines = ['projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position'];
  const projection = state.projection;
  for (const team of projection.order) {
    const totals = projection.totals[team];
    const divisions = ['points', 'title', 'top', 'bottom']
      .map(name => fractionReal(fraction(totals[name], data.settings.simulations)));
    lines.push([projection.rank[team], data.teams[team].id, projection.current.records[team].points,
      projection.current.position[team], real(projection.strength[team], 2), ...divisions,
      state.table.records[team].points, state.table.position[team]].join(','));
  }
  return lines;
}

function main() {
  const data = readSeason();
  const fit = fitModels(data, data.matches);
  addFormAndStreaks(fit.records, data.settings);
  const table = standings(data, data.matches, fit.records);
  const indicators = winningIndicators(fit.records, data.settings);
  const ranking = modelRanks(data, fit, table, indicators);
  const state = { fit, table, indicators, ranking, progression: roundProgression(data, fit),
    upsets: upsetMatches(data, fit), correlations: rankCorrelations(ranking.comparisons) };
  state.validation = validationPredictions(data);
  state.evaluation = evaluatePredictions(data, state.validation);
  state.grid = eloGrid(data);
  state.projection = projectSeason(data, state.validation, table);
  writeReports({
    'standings.csv': standingsReport(data, state),
    'ratings.csv': ratingsReport(data, state),
    'history.csv': historyReport(data, state),
    'season.txt': seasonReport(data, state),
    'predictions.csv': predictionsReport(data, state.validation),
    'evaluation.txt': evaluationReport(data, state),
    'projection.csv': projectionReport(data, state),
  });
}

if (require.main === module) main();
