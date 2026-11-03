import { readSeason, beforeRound, type Season, type Match, type Settings } from './season.ts';
import { expected, fitElo } from './elo.ts';
import { fitColley, fitMassey } from './linear_models.ts';
import { fitBradleyTerry, fitOffenseDefense } from './iterative_models.ts';
import {
  sigma,
  fitLink,
  logLoss,
  brier,
  correctness,
  compareValues,
  kendall,
  spearman,
  type Comparison,
} from './evaluation.ts';
import {
  real,
  decimalValue,
  fraction,
  fractionText,
  fractionReal,
  writeReports,
  type Fraction,
} from './report.ts';

const RATINGS = ['elo', 'colley', 'massey', 'bt', 'od', 'winpct'] as const;
const COMPARISONS = ['standings', ...RATINGS, 'rpi', 'pythag'] as const;
const LINKS = ['colley', 'massey', 'od', 'winpct'] as const;
const PREDICTIONS = ['base', ...RATINGS, 'ensemble'] as const;
type LinkModel = (typeof LINKS)[number];
type PredictionModel = (typeof PREDICTIONS)[number];
type Letter = 'W' | 'D' | 'L';
interface Outcome {
  round: number;
  opponent: number;
  letter: Letter;
}
interface Streak {
  length: number;
  start: number;
  end: number;
}
interface TeamRecord {
  played: number;
  won: number;
  drawn: number;
  lost: number;
  scored: number;
  conceded: number;
  diff: number;
  points: number;
  home: number[];
  away: number[];
  close: number[];
  outcomes: Outcome[];
  winpct: Fraction;
  form: string;
  streak: string;
  longestWin: Streak;
  longestUnbeaten: Streak;
}
function modelMap<K extends string, V>(keys: readonly K[], make: (key: K) => V): Record<K, V> {
  return Object.fromEntries(keys.map((key) => [key, make(key)])) as Record<K, V>;
}
function sum(values: readonly number[]): number {
  let total = 0;
  for (const v of values) total += v;
  return total;
}
function add(a: Fraction, b: Fraction): Fraction {
  return fraction(a[0] * b[1] + b[0] * a[1], a[1] * b[1]);
}
function points(y: number, s: Settings): number {
  return y === 1 ? s.winPoints : y === 0.5 ? s.drawPoints : 0;
}
function teamRecords(data: Season, matches: Match[]): TeamRecord[] {
  const records: TeamRecord[] = data.teams.map(() => ({
    played: 0,
    won: 0,
    drawn: 0,
    lost: 0,
    scored: 0,
    conceded: 0,
    diff: 0,
    points: 0,
    home: [0, 0, 0],
    away: [0, 0, 0],
    close: [0, 0, 0],
    outcomes: [],
    winpct: [0, 1],
    form: '',
    streak: '',
    longestWin: { length: 0, start: 0, end: 0 },
    longestUnbeaten: { length: 0, start: 0, end: 0 },
  }));
  for (const m of matches) {
    for (const home of [true, false]) {
      const team = home ? m.home : m.away;
      const opponent = home ? m.away : m.home;
      const scored = home ? m.homeScore : m.awayScore;
      const conceded = home ? m.awayScore : m.homeScore;
      const y = home ? m.result : 1 - m.result;
      const index = y === 1 ? 0 : y === 0.5 ? 1 : 2;
      const record = records[team];
      record.played++;
      record[y === 1 ? 'won' : y === 0.5 ? 'drawn' : 'lost']++;
      record.scored += scored;
      record.conceded += conceded;
      record.points += points(y, data.settings);
      record[home ? 'home' : 'away'][index]++;
      if (Math.abs(scored - conceded) <= data.settings.closeMargin) record.close[index]++;
      record.outcomes.push({ round: m.round, opponent, letter: (['W', 'D', 'L'] as const)[index] });
    }
  }
  for (const record of records) {
    record.diff = record.scored - record.conceded;
    record.winpct = fraction(2 * record.won + record.drawn, 2 * record.played);
  }
  return records;
}
function standings(data: Season, matches: Match[], records = teamRecords(data, matches)) {
  const headPoints = data.teams.map(() => 0);
  const headDiff = data.teams.map(() => 0);
  for (const m of matches) {
    if (records[m.home].points === records[m.away].points) {
      headPoints[m.home] += points(m.result, data.settings);
      headPoints[m.away] += points(1 - m.result, data.settings);
      headDiff[m.home] += m.homeScore - m.awayScore;
      headDiff[m.away] += m.awayScore - m.homeScore;
    }
  }
  const order = data.teams
    .map((_, i) => i)
    .sort(
      (a, b) =>
        records[b].points - records[a].points ||
        headPoints[b] - headPoints[a] ||
        headDiff[b] - headDiff[a] ||
        records[b].diff - records[a].diff ||
        records[b].scored - records[a].scored ||
        a - b,
    );
  const position: number[] = Array(data.teams.length);
  const groups: number[][] = [];
  order.forEach((team, i) => {
    position[team] = i + 1;
    if (!groups.length || records[groups[groups.length - 1][0]].points !== records[team].points) {
      groups.push([]);
    }
    groups[groups.length - 1].push(team);
  });
  return { records, order, position, headPoints, headDiff, groups };
}
function longest(outcomes: Outcome[], accepts: (letter: Letter) => boolean): Streak {
  let length = 0;
  let start = 0;
  let best = { length: 0, start: 0, end: 0 };
  for (const outcome of outcomes) {
    if (!accepts(outcome.letter)) {
      length = 0;
      continue;
    }
    if (!length) start = outcome.round;
    length++;
    if (length > best.length) best = { length, start, end: outcome.round };
  }
  return best;
}
function addForm(records: TeamRecord[], settings: Settings): void {
  for (const r of records) {
    const last = r.outcomes[r.outcomes.length - 1].letter;
    let length = 0;
    for (let i = r.outcomes.length - 1; i >= 0 && r.outcomes[i].letter === last; i--) length++;
    r.form = r.outcomes
      .slice(-settings.formLength)
      .map((o) => o.letter)
      .join('');
    r.streak = last + length;
    r.longestWin = longest(r.outcomes, (l) => l === 'W');
    r.longestUnbeaten = longest(r.outcomes, (l) => l !== 'L');
  }
}
function scheduleAverage(record: TeamRecord, values: Fraction[]): Fraction {
  let total: Fraction = [0, 1];
  for (const o of record.outcomes) total = add(total, values[o.opponent]);
  return fraction(total[0], total[1] * record.played);
}
function indicators(records: TeamRecord[], settings: Settings) {
  const wp = records.map((r) => r.winpct);
  const sos = records.map((r) => scheduleAverage(r, wp));
  const sos2 = records.map((r) => scheduleAverage(r, sos));
  const rpi = records.map((_, i) => {
    const t = add(add(wp[i], fraction(2 * sos[i][0], sos[i][1])), sos2[i]);
    return fraction(t[0], 4 * t[1]);
  });
  const pythag = records.map((r) => 1 / (1 + (r.conceded / r.scored) ** settings.exponent));
  return { sos, sos2, rpi, pythag, luck: wp.map((v, i) => v[0] / v[1] - pythag[i]) };
}
function fitModels(data: Season, matches: Match[]) {
  const n = data.teams.length;
  const s = data.settings;
  const records = teamRecords(data, matches);
  return {
    records,
    elo: fitElo(n, matches, s.eloK, s.eloHome, s.eloInitial),
    colley: fitColley(n, matches),
    massey: fitMassey(n, matches),
    bt: fitBradleyTerry(n, matches, s.btIterations),
    od: fitOffenseDefense(n, matches, s.odIterations),
  };
}
type Fit = ReturnType<typeof fitModels>;
type Table = ReturnType<typeof standings>;
function ranks(values: Comparison[]): number[] {
  return values.map((v) => 1 + values.filter((o) => compareValues(o, v) > 0).length);
}
function modelRanks(data: Season, fit: Fit, table: Table, ind: ReturnType<typeof indicators>) {
  const comparisons = {
    standings: table.position.map((v) => -v),
    elo: fit.elo.values.map((v) => decimalValue(v, 2)),
    colley: fit.colley.map((v) => decimalValue(v)),
    massey: fit.massey.values.map((v) => decimalValue(v)),
    bt: fit.bt.values.map((v) => decimalValue(v)),
    od: fit.od.values.map((v) => decimalValue(v, 2)),
    winpct: fit.records.map((r) => r.winpct),
    rpi: ind.rpi,
    pythag: ind.pythag.map((v) => decimalValue(v)),
  };
  const ranking = modelMap(RATINGS, (name) => ranks(comparisons[name]));
  const totals = data.teams.map((_, i) => sum(RATINGS.map((name) => ranking[name][i])));
  return {
    comparisons,
    ranks: ranking,
    totals,
    order: data.teams.map((_, i) => i).sort((a, b) => totals[a] - totals[b] || a - b),
  };
}
function progression(data: Season, fit: Fit) {
  const history: {
    round: number;
    elo: number[];
    change: number[];
    rank: number[];
    table: Table;
  }[] = [];
  const leaders: { round: number; team: number; points: number }[] = [];
  let previous = data.teams.map(() => data.settings.eloInitial);
  let leader = -1;
  for (let round = 1; round <= data.rounds; round++) {
    const elo = fit.elo.rounds.get(round)!;
    const table = standings(data, beforeRound(data.matches, round + 1));
    history.push({
      round,
      elo,
      change: elo.map((v, i) => v - previous[i]),
      rank: ranks(elo.map((v) => decimalValue(v, 2))),
      table,
    });
    if (leader !== table.order[0]) {
      leader = table.order[0];
      leaders.push({ round, team: leader, points: table.records[leader].points });
    }
    previous = elo;
  }
  const extremes = data.teams.map((_, t) => {
    const ex = { peak: 0, low: 0, best: 0, worst: 0 };
    for (let i = 1; i < history.length; i++) {
      const value = decimalValue(history[i].elo[t], 2);
      const pos = history[i].table.position[t];
      if (value > decimalValue(history[ex.peak].elo[t], 2)) ex.peak = i;
      if (value < decimalValue(history[ex.low].elo[t], 2)) ex.low = i;
      if (pos < history[ex.best].table.position[t]) ex.best = i;
      if (pos > history[ex.worst].table.position[t]) ex.worst = i;
    }
    return ex;
  });
  return { history, leaders, extremes };
}
function correlations(values: Record<(typeof COMPARISONS)[number], Comparison[]>) {
  const tau = COMPARISONS.map((a) => COMPARISONS.map((b) => kendall(values[a], values[b])));
  const rho = COMPARISONS.map((a) => COMPARISONS.map((b) => spearman(values[a], values[b])));
  const pairs = COMPARISONS.flatMap((a, i) =>
    COMPARISONS.slice(i + 1).map((b, j) => ({ a, b, value: tau[i][i + 1 + j] })),
  );
  let most = pairs[0];
  let least = pairs[0];
  for (const p of pairs) {
    if (compareValues(p.value, most.value) > 0) most = p;
    if (compareValues(p.value, least.value) < 0) least = p;
  }
  return { tau, rho, most, least };
}
function feature(name: LinkModel, fit: Fit, m: Match): number {
  if (name === 'winpct') {
    const a = fit.records[m.home].winpct;
    const b = fit.records[m.away].winpct;
    return a[0] / a[1] - b[0] / b[1];
  }
  if (name === 'od') return Math.log(fit.od.values[m.home]) - Math.log(fit.od.values[m.away]);
  const values = name === 'colley' ? fit.colley : fit.massey.values;
  return values[m.home] - values[m.away];
}
interface Prediction {
  match: Match;
  probabilities: Record<PredictionModel, number>;
  marginError: number;
}
function validate(data: Season) {
  const records: Prediction[] = [];
  const rounds: {
    round: number;
    training: number;
    base: number;
    btHome: number;
    links: Record<LinkModel, ReturnType<typeof fitLink>>;
    records: Prediction[];
  }[] = [];
  const initialFit = fitModels(data, beforeRound(data.matches, data.settings.holdout));
  for (let round = data.settings.holdout; round <= data.rounds; round++) {
    const training = beforeRound(data.matches, round);
    const fit = round === data.settings.holdout ? initialFit : fitModels(data, training);
    const results = training.map((m) => m.result);
    const base = sum(results) / training.length;
    const links = modelMap(LINKS, (name) =>
      fitLink(
        training.map((m) => feature(name, fit, m)),
        results,
        data.settings.linkIterations,
      ),
    );
    const rows: Prediction[] = [];
    for (const m of data.matches.filter((m) => m.round === round)) {
      const linked = modelMap(LINKS, (name) =>
        sigma(links[name].alpha + links[name].beta * feature(name, fit, m)),
      );
      const probabilities = {
        base,
        elo: expected(fit.elo.values[m.home], fit.elo.values[m.away], data.settings.eloHome),
        ...linked,
        bt:
          (fit.bt.home * fit.bt.values[m.home]) /
          (fit.bt.home * fit.bt.values[m.home] + fit.bt.values[m.away]),
        ensemble: 0,
      };
      probabilities.ensemble = sum(RATINGS.map((name) => probabilities[name])) / 6;
      const row = {
        match: m,
        probabilities,
        marginError:
          m.homeScore -
          m.awayScore -
          (fit.massey.values[m.home] - fit.massey.values[m.away] + fit.massey.home),
      };
      rows.push(row);
      records.push(row);
    }
    rounds.push({
      round,
      training: training.length,
      base,
      btHome: fit.bt.home,
      links,
      records: rows,
    });
  }
  return { rounds, records, initialFit };
}
type Validation = ReturnType<typeof validate>;
function evaluate(data: Season, validation: Validation) {
  const count = validation.records.length;
  const scores = modelMap(PREDICTIONS, (name) => {
    const losses = validation.records.map((r) => logLoss(r.probabilities[name], r.match.result));
    return {
      losses,
      logLoss: sum(losses) / count,
      brier:
        sum(validation.records.map((r) => brier(r.probabilities[name], r.match.result))) / count,
      accuracy: fraction(
        sum(validation.records.map((r) => 2 * correctness(r.probabilities[name], r.match.result))),
        2 * count,
      ),
      skill: 0,
    };
  });
  for (const name of PREDICTIONS) scores[name].skill = 1 - scores[name].brier / scores.base.brier;
  const byLogLoss = [...PREDICTIONS].sort(
    (a, b) => decimalValue(scores[a].logLoss) - decimalValue(scores[b].logLoss),
  );
  const byBrier = [...PREDICTIONS].sort(
    (a, b) => decimalValue(scores[a].brier) - decimalValue(scores[b].brier),
  );
  const byAccuracy = [...PREDICTIONS].sort((a, b) =>
    compareValues(scores[b].accuracy, scores[a].accuracy),
  );
  const reference = byLogLoss[0];
  const paired = PREDICTIONS.filter((n) => n !== reference).map((name) => {
    const delta = scores[name].losses.map((l, i) => l - scores[reference].losses[i]);
    const mean = sum(delta) / count;
    const sd = Math.sqrt(sum(delta.map((d) => (d - mean) * (d - mean))) / (count - 1));
    return { name, mean, sd, t: mean / (sd / Math.sqrt(count)) };
  });
  const errors = validation.records.map((r) => r.marginError);
  const margin = {
    mae: sum(errors.map(Math.abs)) / count,
    rmse: Math.sqrt(sum(errors.map((e) => e * e)) / count),
    bias: sum(errors) / count,
  };
  const roundLosses = validation.rounds.map((r) => ({
    round: r.round,
    values: PREDICTIONS.map(
      (n) =>
        sum(r.records.map((p) => logLoss(p.probabilities[n], p.match.result))) / r.records.length,
    ),
  }));
  const calibration = PREDICTIONS.map((name) => {
    const bins = Array.from({ length: data.settings.bins }, () => ({
      count: 0,
      probability: 0,
      resultTwice: 0,
    }));
    for (const r of validation.records) {
      const p = r.probabilities[name];
      const bin = bins[Math.min(data.settings.bins - 1, Math.floor(data.settings.bins * p))];
      bin.count++;
      bin.probability += p;
      bin.resultTwice += 2 * r.match.result;
    }
    return { name, bins };
  });
  return {
    scores,
    byLogLoss,
    byBrier,
    byAccuracy,
    reference,
    paired,
    margin,
    roundLosses,
    calibration,
  };
}
function gridSearch(data: Season) {
  const rows = data.settings.gridK.map((k) => ({
    k,
    losses: data.settings.gridHome.map((home) => {
      const fit = fitElo(data.teams.length, data.matches, k, home, data.settings.eloInitial);
      const records = fit.records.filter((r) => r.match.round >= data.settings.holdout);
      return sum(records.map((r) => logLoss(r.expected, r.match.result))) / records.length;
    }),
  }));
  let best = { k: rows[0].k, home: data.settings.gridHome[0], loss: rows[0].losses[0] };
  for (const row of rows) {
    row.losses.forEach((loss, i) => {
      if (decimalValue(loss) < decimalValue(best.loss)) {
        best = { k: row.k, home: data.settings.gridHome[i], loss };
      }
    });
  }
  return { rows, best };
}
function project(data: Season, validation: Validation, finalTable: Table) {
  const s = data.settings;
  const current = standings(
    data,
    beforeRound(data.matches, s.holdout),
    validation.initialFit.records,
  );
  const ratings = validation.initialFit.elo.values;
  const remaining = validation.records.map((r) => r.match);
  const probabilities = remaining.map((m) => expected(ratings[m.home], ratings[m.away], s.eloHome));
  const totals = data.teams.map(() => ({ points: 0, title: 0, top: 0, bottom: 0 }));
  const teams = data.teams.map((_, i) => i);
  let state = s.seed;
  for (let simulation = 0; simulation < s.simulations; simulation++) {
    const points = current.records.map((r) => r.points);
    remaining.forEach((m, i) => {
      state = (48271 * state) % 2147483647;
      points[state / 2147483647 < probabilities[i] ? m.home : m.away] += s.winPoints;
    });
    const order = [...teams].sort(
      (a, b) => points[b] - points[a] || current.position[a] - current.position[b],
    );
    order.forEach((t, i) => {
      totals[t].points += points[t];
      if (!i) totals[t].title++;
      if (i < s.top) totals[t].top++;
      if (i >= teams.length - s.bottom) totals[t].bottom++;
    });
  }
  const order = [...teams].sort(
    (a, b) => totals[b].points - totals[a].points || current.position[a] - current.position[b],
  );
  const rank: number[] = Array(teams.length);
  const strength = teams.map(() => 0);
  const counts = teams.map(() => 0);
  order.forEach((t, i) => {
    rank[t] = i + 1;
  });
  for (const m of remaining) {
    strength[m.home] += ratings[m.away];
    strength[m.away] += ratings[m.home];
    counts[m.home]++;
    counts[m.away]++;
  }
  for (const t of teams) strength[t] /= counts[t];
  return {
    current,
    totals,
    order,
    rank,
    strength,
    agreement: kendall(
      rank.map((v) => -v),
      finalTable.position.map((v) => -v),
    ),
  };
}
function buildState(data: Season) {
  const fit = fitModels(data, data.matches);
  addForm(fit.records, data.settings);
  const table = standings(data, data.matches, fit.records);
  const ind = indicators(fit.records, data.settings);
  const ranking = modelRanks(data, fit, table, ind);
  const validation = validate(data);
  const upsets = fit.elo.records
    .filter((r) => r.match.result !== 0.5)
    .map((r) => ({
      ...r,
      homeWon: r.match.result === 1,
      probability: r.match.result === 1 ? r.expected : 1 - r.expected,
    }))
    .sort((a, b) => decimalValue(a.probability) - decimalValue(b.probability) || a.index - b.index)
    .slice(0, data.settings.upsets);
  return {
    fit,
    table,
    ind,
    ranking,
    validation,
    upsets,
    progression: progression(data, fit),
    correlations: correlations(ranking.comparisons),
    evaluation: evaluate(data, validation),
    grid: gridSearch(data),
    projection: project(data, validation, table),
  };
}
type State = ReturnType<typeof buildState>;
function sections(parts: string[][]): string[] {
  return parts.flatMap((p, i) => (i ? ['', ...p] : p));
}
function standingsReport(data: Season, state: State): string[] {
  const lines = [
    'pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck',
  ];
  for (const t of state.table.order) {
    const r = state.fit.records[t];
    const ind = state.ind;
    lines.push(
      [
        state.table.position[t],
        data.teams[t].id,
        data.teams[t].name,
        r.played,
        r.won,
        r.drawn,
        r.lost,
        r.scored,
        r.conceded,
        r.diff,
        r.points,
        r.home.join('-'),
        r.away.join('-'),
        r.form,
        r.streak,
        r.close.join('-'),
        r.longestWin.length,
        r.longestUnbeaten.length,
        fractionText(r.winpct),
        fractionReal(ind.sos[t]),
        fractionReal(ind.sos2[t]),
        fractionReal(ind.rpi[t]),
        real(ind.pythag[t]),
        real(ind.luck[t]),
      ].join(','),
    );
  }
  return lines;
}
function ratingsReport(data: Season, state: State): string[] {
  const lines = [
    'team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank',
  ];
  const f = state.fit;
  const ranking = state.ranking;
  for (const t of ranking.order) {
    const rr = RATINGS.map((n) => ranking.ranks[n][t]);
    lines.push(
      [
        data.teams[t].id,
        real(f.elo.values[t], 2),
        rr[0],
        real(f.colley[t]),
        rr[1],
        real(f.massey.values[t]),
        rr[2],
        real(f.bt.values[t]),
        rr[3],
        real(f.od.offense[t], 2),
        real(f.od.defense[t]),
        real(f.od.values[t], 2),
        rr[4],
        fractionReal(f.records[t].winpct),
        rr[5],
        ranking.totals[t],
        Math.min(...rr),
        Math.max(...rr),
      ].join(','),
    );
  }
  return lines;
}
function seasonReport(data: Season, state: State): string[] {
  const ids = (ts: number[]) => ts.map((t) => data.teams[t].id).join(' ');
  const won = data.matches.filter((m) => m.result === 1).length;
  const drawn = data.matches.filter((m) => m.result === 0.5).length;
  const rate = fraction(2 * won + drawn, 2 * data.matches.length);
  const summary = [
    `season teams ${data.teams.length} matches ${data.matches.length} rounds ${data.rounds}`,
    `home won ${won} drawn ${drawn} lost ${data.matches.length - won - drawn} rate ${fractionText(rate)} ${fractionReal(rate)}`,
    `massey_home_advantage ${real(state.fit.massey.home)}`,
    `bt_home_factor ${real(state.fit.bt.home)}`,
  ];
  const upsets = [
    `upsets top ${data.settings.upsets}`,
    ...state.upsets.map((r) => {
      const m = r.match;
      const h = r.homeWon;
      return `round ${m.round} ${data.teams[h ? m.home : m.away].id} beat ${data.teams[h ? m.away : m.home].id} ${h ? m.homeScore : m.awayScore}-${h ? m.awayScore : m.homeScore} ${h ? 'home' : 'away'} expected ${real(r.probability)} gain ${real(Math.abs(r.change), 2)}`;
    }),
  ];
  const tiebreaks = ['tiebreaks'];
  for (const g of state.table.groups.filter((g) => g.length > 1)) {
    tiebreaks.push(
      `points ${state.table.records[g[0]].points} order ${ids(g)} h2h_points ${g.map((t) => state.table.headPoints[t]).join(' ')} h2h_diff ${g.map((t) => state.table.headDiff[t]).join(' ')}`,
    );
  }
  if (tiebreaks.length === 1) tiebreaks.push('none');
  const leaders = [
    'leaders',
    ...state.progression.leaders.map(
      (l) => `round ${l.round} ${data.teams[l.team].id} points ${l.points}`,
    ),
    `lead_changes ${state.progression.leaders.length - 1}`,
  ];
  const streaks: string[] = [];
  for (const [heading, field] of [
    ['longest_win_streak', 'longestWin'],
    ['longest_unbeaten_streak', 'longestUnbeaten'],
  ] as const) {
    const max = Math.max(...state.fit.records.map((r) => r[field].length));
    state.fit.records.forEach((r, t) => {
      const st = r[field];
      if (st.length === max) {
        streaks.push(
          `${heading} ${data.teams[t].id} length ${st.length} rounds ${st.start}-${st.end}`,
        );
      }
    });
  }
  const top = state.table.order.slice(0, data.settings.top);
  const cross = [`crosstable top ${data.settings.top}`, `team ${ids(top)}`];
  for (const t of top) {
    cross.push(
      `${data.teams[t].id} ${top
        .map((u) => {
          if (u === t) return '-';
          const outcomes = state.fit.records[t].outcomes.filter((o) => o.opponent === u);
          return (['W', 'D', 'L'] as const)
            .map((l) => outcomes.filter((o) => o.letter === l).length)
            .join('-');
        })
        .join(' ')}`,
    );
  }
  const trajectories = [
    'trajectories',
    ...data.teams.map((team, t) => {
      const ex = state.progression.extremes[t];
      const history = state.progression.history;
      const peak = history[ex.peak];
      const low = history[ex.low];
      const best = history[ex.best];
      const worst = history[ex.worst];
      return `${team.id} elo_peak ${real(peak.elo[t], 2)} round ${peak.round} elo_low ${real(low.elo[t], 2)} round ${low.round} best_position ${best.table.position[t]} round ${best.round} worst_position ${worst.table.position[t]} round ${worst.round}`;
    }),
  ];
  const matrices = (['kendall', 'spearman'] as const).map((name) => [
    name,
    `model ${COMPARISONS.join(' ')}`,
    ...COMPARISONS.map(
      (n, i) =>
        `${n} ${state.correlations[name === 'kendall' ? 'tau' : 'rho'][i].map(fractionText).join(' ')}`,
    ),
  ]);
  const similar = (['most', 'least'] as const).map((name) => {
    const p = state.correlations[name];
    return `${name}_similar ${p.a} ${p.b} tau ${fractionText(p.value)} ${fractionReal(p.value)}`;
  });
  return sections([
    summary,
    upsets,
    tiebreaks,
    leaders,
    streaks,
    cross,
    trajectories,
    ...matrices,
    similar,
  ]);
}
function evaluationReport(data: Season, state: State): string[] {
  const v = state.validation;
  const e = state.evaluation;
  const links = [
    'links',
    ...v.rounds.map(
      (r) =>
        `round ${r.round} train ${r.training} base ${real(r.base)} bt_home ${real(r.btHome)} ${LINKS.map((n) => `${n} ${real(r.links[n].alpha)} ${real(r.links[n].beta)}`).join(' ')}`,
    ),
  ];
  const scores = [
    'scores',
    'model log_loss brier skill accuracy',
    ...PREDICTIONS.map((n) => {
      const s = e.scores[n];
      return `${n} ${real(s.logLoss)} ${real(s.brier)} ${real(s.skill)} ${fractionText(s.accuracy)} ${fractionReal(s.accuracy)}`;
    }),
    `ranking_log_loss ${e.byLogLoss.join(' ')}`,
    `ranking_brier ${e.byBrier.join(' ')}`,
    `ranking_accuracy ${e.byAccuracy.join(' ')}`,
  ];
  const paired = [
    `paired_log_loss reference ${e.reference}`,
    ...e.paired.map(
      (p) => `${p.name} mean_diff ${real(p.mean)} sd ${real(p.sd)} t ${real(p.t, 2)}`,
    ),
  ];
  const roundLosses = [
    'round_log_loss',
    `round ${PREDICTIONS.join(' ')}`,
    ...e.roundLosses.map((r) => `${r.round} ${r.values.map((v) => real(v)).join(' ')}`),
  ];
  const calibration = [`calibration bins ${data.settings.bins}`];
  for (const m of e.calibration) {
    m.bins.forEach((b, i) =>
      calibration.push(
        `${m.name} bin ${i + 1} count ${b.count} predicted ${b.count ? real(b.probability / b.count) : '-'} observed ${b.count ? fractionText(fraction(b.resultTwice, 2 * b.count)) : '-'}`,
      ),
    );
  }
  const best = state.grid.best;
  const agreement = state.projection.agreement;
  const grid = [
    'elo_grid',
    `k ${data.settings.gridHome.map((h) => 'h' + h).join(' ')}`,
    ...state.grid.rows.map((r) => `${r.k} ${r.losses.map((v) => real(v)).join(' ')}`),
    `best k ${best.k} home ${best.home} log_loss ${real(best.loss)}`,
  ];
  return sections([
    [`holdout rounds ${data.settings.holdout}-${data.rounds} matches ${v.records.length}`],
    links,
    scores,
    paired,
    [
      `massey_margin mae ${real(e.margin.mae)} rmse ${real(e.margin.rmse)} bias ${real(e.margin.bias)}`,
    ],
    roundLosses,
    calibration,
    grid,
    [
      `projection simulations ${data.settings.simulations} kendall ${fractionText(agreement)} ${fractionReal(agreement)}`,
    ],
  ]);
}
function main(): void {
  const data = readSeason();
  const state = buildState(data);
  const history = ['round,team,elo,change,elo_rank,points,position'];
  for (const h of state.progression.history) {
    data.teams.forEach((t, i) =>
      history.push(
        [
          h.round,
          t.id,
          real(h.elo[i], 2),
          real(h.change[i], 2),
          h.rank[i],
          h.table.records[i].points,
          h.table.position[i],
        ].join(','),
      ),
    );
  }
  const predictions = [
    'round,home,away,home_score,away_score,result,base,elo,colley,massey,bt,od,winpct,ensemble',
    ...state.validation.records.map((r) => {
      const m = r.match;
      return [
        m.round,
        data.teams[m.home].id,
        data.teams[m.away].id,
        m.homeScore,
        m.awayScore,
        m.result === 1 ? 'H' : m.result === 0.5 ? 'D' : 'A',
        ...PREDICTIONS.map((n) => real(r.probabilities[n])),
      ].join(',');
    }),
  ];
  const p = state.projection;
  const projection = [
    'projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position',
    ...p.order.map((t) =>
      [
        p.rank[t],
        data.teams[t].id,
        p.current.records[t].points,
        p.current.position[t],
        real(p.strength[t], 2),
        ...(['points', 'title', 'top', 'bottom'] as const).map((n) =>
          fractionReal(fraction(p.totals[t][n], data.settings.simulations)),
        ),
        state.table.records[t].points,
        state.table.position[t],
      ].join(','),
    ),
  ];
  writeReports({
    'standings.csv': standingsReport(data, state),
    'ratings.csv': ratingsReport(data, state),
    'history.csv': history,
    'season.txt': seasonReport(data, state),
    'predictions.csv': predictions,
    'evaluation.txt': evaluationReport(data, state),
    'projection.csv': projection,
  });
}
main();
