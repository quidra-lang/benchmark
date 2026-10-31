import { readFileSync } from 'node:fs';

const FACES = [1, 2, 3, 4, 5, 6];
const CATEGORIES = [
  'ONES', 'TWOS', 'THREES', 'FOURS', 'FIVES', 'SIXES',
  'THREEKIND', 'FOURKIND', 'FULLHOUSE', 'SMALL', 'LARGE', 'YAHTZEE', 'CHANCE'
];
const UPPER = CATEGORIES.slice(0, 6);
const LOWER = CATEGORIES.slice(6);
const STRATEGIES = new Set(['KIND', 'STRAIGHT', 'HIGH', 'UPPER']);
const JOKER_MODES = new Set(['FORCED', 'FREE', 'OFF']);
const JOKER_POINTS = { FULLHOUSE: 25, SMALL: 30, LARGE: 40 };
const MODULUS = 2147483647;
const MULTIPLIER = 48271;
const PATTERNS = Array.from({ length: 32 }, (_, i) =>
  i.toString(2).padStart(5, '0').split('').map(mark => mark === '1'));
const FACTORIALS = [1, 1, 2, 6, 24, 120];

class CommandError extends Error {}
function check(condition, reason) {
  if (!condition) throw new CommandError(reason);
}
function integerWord(text, low, high) {
  check(/^-?(?:0|[1-9][0-9]*)$/.test(text) && text !== '-0', 'bad value ' + text);
  const value = Number(text);
  check(Number.isSafeInteger(value) && value >= low && value <= high, 'bad value ' + text);
  return value;
}
function playerName(text) {
  check(/^[A-Z]{1,8}$/.test(text), 'bad name ' + text);
  return text;
}
function holdPattern(text) {
  check(/^[01]{5}$/.test(text), 'bad pattern ' + text);
  return [...text].map(mark => mark === '1');
}
function categoryName(text) {
  check(CATEGORIES.includes(text), 'bad category ' + text);
  return text;
}
function strategyName(text) {
  check(STRATEGIES.has(text), 'bad strategy ' + text);
  return text;
}
function faceText(faces) {
  return faces.length ? faces.join(' ') : '-';
}
function patternText(holds) {
  return holds.map(hold => hold ? '1' : '0').join('');
}
function heldFaces(faces, holds) {
  return faces.filter((_, i) => holds[i]);
}
function gcd(a, b) {
  while (b !== 0) [a, b] = [b, a % b];
  return a;
}
function fractionText(numerator, denominator) {
  const d = gcd(numerator, denominator);
  return denominator / d === 1 ? String(numerator / d) : numerator / d + '/' + denominator / d;
}
function averageText(total, count) {
  const amount = count ? Math.floor(100 * total / count) : 0;
  return Math.floor(amount / 100) + '.' + String(amount % 100).padStart(2, '0');
}
function isYahtzee(faces) {
  return faces.every(face => face === faces[0]);
}
function normalScore(category, faces) {
  const upper = UPPER.indexOf(category);
  const counts = FACES.map(face => faces.filter(v => v === face).length);
  if (upper !== -1) return (upper + 1) * counts[upper];
  const total = faces.reduce((a, b) => a + b, 0);
  switch (category) {
    case 'THREEKIND': return Math.max(...counts) >= 3 ? total : 0;
    case 'FOURKIND': return Math.max(...counts) >= 4 ? total : 0;
    case 'FULLHOUSE': return counts.includes(3) && counts.includes(2) ? 25 : 0;
    case 'SMALL': return [1, 2, 3].some(start =>
      [0, 1, 2, 3].every(offset => faces.includes(start + offset))) ? 30 : 0;
    case 'LARGE': return [1, 2].some(start =>
      [0, 1, 2, 3, 4].every(offset => faces.includes(start + offset))) ? 40 : 0;
    case 'YAHTZEE': return isYahtzee(faces) ? 50 : 0;
    default: return total;
  }
}
function bestCandidate(candidates) {
  return candidates.reduce((best, candidate) => candidate[1] > best[1] ? candidate : best);
}
function mostFrequentFace(faces) {
  return FACES.reduce((best, f) => {
    const count = faces.filter(face => face === f).length;
    const prior = faces.filter(face => face === best).length;
    return count > prior || (count === prior && f > best) ? f : best;
  }, 1);
}
function botHolds(strategy, faces) {
  if (strategy === 'HIGH') return faces.map(face => face >= 5);
  if (strategy === 'STRAIGHT') {
    let bestStart = 0, bestLength = 0;
    for (const start of FACES) {
      let length = 0;
      while (faces.includes(start + length)) ++length;
      if (length > 0 && length >= bestLength) [bestStart, bestLength] = [start, length];
    }
    if (bestLength >= 3) {
      const holds = Array(5).fill(false);
      for (let v = bestStart; v < bestStart + bestLength; ++v) holds[faces.indexOf(v)] = true;
      return holds;
    }
  }
  const face = mostFrequentFace(faces);
  return faces.map(v => v === face);
}
function rerollOutcomes(size) {
  const result = [];
  function visit(minimum, remaining, values) {
    if (!remaining) {
      let weight = FACTORIALS[size];
      for (const face of FACES) weight /= FACTORIALS[values.filter(v => v === face).length];
      result.push([values, weight]);
      return;
    }
    for (let face = minimum; face <= 6; ++face) visit(face, remaining - 1, [...values, face]);
  }
  visit(1, size, []);
  return result;
}
const REROLLS = Array.from({ length: 6 }, (_, i) => rerollOutcomes(i));

class DiceRoller {
  constructor(seed) {
    this.state = seed;
    this.loaded = [];
    this.counts = Array(6).fill(0);
  }
  rollDie() {
    let face;
    if (this.loaded.length) face = this.loaded.shift();
    else {
      this.state = MULTIPLIER * this.state % MODULUS;
      face = this.state % 6 + 1;
    }
    ++this.counts[face - 1];
    return face;
  }
}
class Player {
  constructor(name, strategy = 'KIND') {
    this.name = name;
    this.strategy = strategy;
    this.boxes = Object.fromEntries(CATEGORIES.map(c => [c, null]));
    this.yahtzeeBonus = 0;
  }
  openCategories() { return CATEGORIES.filter(c => this.boxes[c] === null); }
  usedCount() { return CATEGORIES.length - this.openCategories().length; }
  round() { return this.usedCount() + 1; }
  upperSubtotal() { return UPPER.reduce((sum, c) => sum + (this.boxes[c] ?? 0), 0); }
  upperBonus() { return this.upperSubtotal() >= 63 ? 35 : 0; }
  total() {
    return Object.values(this.boxes).reduce((sum, v) => sum + (v ?? 0), 0)
      + this.upperBonus() + this.yahtzeeBonus;
  }
}
class Turn {
  constructor(seat, rolls = 0, faces = [], holds = Array(5).fill(false)) {
    this.seat = seat;
    this.rolls = rolls;
    this.faces = [...faces];
    this.holds = [...holds];
  }
  copy() { return new Turn(this.seat, this.rolls, this.faces, this.holds); }
}
class Game {
  constructor(players, rules, roller) {
    this.players = players;
    this.rules = rules;
    this.roller = roller;
    this.turn = new Turn(0);
    this.entries = [];
    this.redoList = [];
  }
  finished() { return this.turn === null; }
  currentPlayer() { return this.players[this.turn.seat]; }
  ranking() { return [...this.players].sort((a, b) => b.total() - a.total()); }
  roll() {
    const turn = this.turn;
    if (turn.rolls === 0) turn.faces = Array.from({ length: 5 }, () => this.roller.rollDie());
    else for (let i = 0; i < 5; ++i) if (!turn.holds[i]) turn.faces[i] = this.roller.rollDie();
    ++turn.rolls;
    this.redoList.length = 0;
    return `${this.currentPlayer().name} roll ${turn.rolls}: ${faceText(turn.faces)}`;
  }
  setHolds(holds) {
    this.turn.holds = [...holds];
    this.redoList.length = 0;
    return `${this.currentPlayer().name} holds ${patternText(holds)}: ${faceText(heldFaces(this.turn.faces, holds))}`;
  }
  jokerSituation(player, faces) {
    return this.rules.joker !== 'OFF' && isYahtzee(faces) && player.boxes.YAHTZEE !== null;
  }
  allowedCategories(player, faces, joker) {
    const open = player.openCategories();
    if (!joker || this.rules.joker === 'FREE') return open;
    const upper = UPPER[faces[0] - 1];
    if (player.boxes[upper] === null) return [upper];
    const lower = open.filter(c => LOWER.includes(c));
    return lower.length ? lower : open;
  }
  pointsToEnter(faces, category, joker) {
    return joker && Object.hasOwn(JOKER_POINTS, category) ? JOKER_POINTS[category]
      : normalScore(category, faces);
  }
  candidates(player, faces) {
    const joker = this.jokerSituation(player, faces);
    const allowed = new Set(this.allowedCategories(player, faces, joker));
    return player.openCategories().map(category => [category,
      allowed.has(category) ? this.pointsToEnter(faces, category, joker) : 0]);
  }
  best(player, faces) { return bestCandidate(this.candidates(player, faces)); }
  prepareEntry(category) {
    const player = this.currentPlayer(), faces = this.turn.faces;
    check(player.boxes[category] === null, `${category} already used`);
    const joker = this.jokerSituation(player, faces);
    if (!this.allowedCategories(player, faces, joker).includes(category)) {
      const upper = UPPER[faces[0] - 1];
      check(player.boxes[upper] !== null, 'joker requires ' + upper);
      throw new CommandError('joker requires lower box');
    }
    const points = this.pointsToEnter(faces, category, joker);
    const bonus = isYahtzee(faces) && player.boxes.YAHTZEE === 50 ? 100 : 0;
    return { player, category, points, bonus, joker, turn: this.turn.copy() };
  }
  scoreLine(entry, verb) {
    const player = entry.player;
    const parts = [player.name, verb, entry.points, 'in', entry.category];
    if (entry.joker) parts.push('joker');
    if (entry.bonus) parts.push('ybonus', entry.bonus);
    const subtotal = player.upperSubtotal() + (UPPER.includes(entry.category) ? entry.points : 0);
    const gained = player.upperBonus() === 0 && subtotal >= 63 ? 35 : 0;
    if (gained) parts.push('ubonus', gained);
    parts.push('total', player.total() + entry.points + entry.bonus + gained);
    return parts.join(' ');
  }
  enter(entry) {
    entry.player.boxes[entry.category] = entry.points;
    entry.player.yahtzeeBonus += entry.bonus;
    this.entries.push(entry);
  }
  score(category) {
    const entry = this.prepareEntry(category), line = this.scoreLine(entry, 'scores');
    this.enter(entry);
    this.redoList.length = 0;
    if (this.players.every(player => player.usedCount() === 13)) {
      this.turn = null;
      return [line, 'game over'];
    }
    this.turn = new Turn((this.turn.seat + 1) % this.players.length);
    const player = this.currentPlayer();
    return [line, `turn ${player.round()} ${player.name}`];
  }
  undo() {
    const entry = this.entries.pop();
    entry.player.boxes[entry.category] = null;
    entry.player.yahtzeeBonus -= entry.bonus;
    this.redoList.push([this.turn, entry]);
    this.turn = entry.turn.copy();
    return entry;
  }
  redo() {
    const [turn, entry] = this.redoList.pop();
    this.enter(entry);
    this.turn = turn;
    return entry;
  }
  botCategory() {
    const player = this.currentPlayer(), faces = this.turn.faces;
    if (player.strategy === 'UPPER') {
      const face = mostFrequentFace(faces), category = UPPER[face - 1];
      const allowed = this.allowedCategories(player, faces, this.jokerSituation(player, faces));
      if (faces.filter(v => v === face).length >= 3 && allowed.includes(category)) return category;
    }
    return this.best(player, faces)[0];
  }
  botTurn() {
    const lines = [];
    if (!this.turn.rolls) lines.push(this.roll());
    while (this.turn.rolls < this.rules.rolls) {
      const holds = botHolds(this.currentPlayer().strategy, this.turn.faces);
      if (holds.every(Boolean)) break;
      lines.push(this.setHolds(holds));
      lines.push(this.roll());
    }
    lines.push(...this.score(this.botCategory()));
    return lines;
  }
}
class Advisor {
  constructor(game, player) {
    this.game = game;
    this.player = player;
    this.values = new Map();
    this.expectations = new Map();
  }
  value(hand, level) {
    const key = level + ':' + hand.join('');
    if (this.values.has(key)) return this.values.get(key);
    const value = !level ? this.game.best(this.player, hand)[1]
      : Math.max(...PATTERNS.map(holds =>
        this.expectation(heldFaces(hand, holds).sort((a, b) => a - b), level)));
    this.values.set(key, value);
    return value;
  }
  expectation(held, level) {
    const key = level + ':' + held.join('');
    if (this.expectations.has(key)) return this.expectations.get(key);
    let total = 0;
    for (const [rolled, weight] of REROLLS[5 - held.length]) {
      total += weight * this.value([...held, ...rolled].sort((a, b) => a - b), level - 1);
    }
    const value = total * 6 ** held.length;
    this.expectations.set(key, value);
    return value;
  }
  bestHold(faces, levels) {
    let bestHolds = null, bestValue = -1;
    for (const holds of PATTERNS) {
      const value = this.expectation(heldFaces(faces, holds).sort((a, b) => a - b), levels);
      if (value > bestValue) [bestHolds, bestValue] = [holds, value];
    }
    return [bestHolds, bestValue];
  }
}
class Record {
  constructor() { this.games = 0; this.wins = 0; this.best = 0; this.total = 0; }
  add(total, won) {
    ++this.games;
    if (won) ++this.wins;
    this.best = Math.max(this.best, total);
    this.total += total;
  }
}
class SeatSummary {
  constructor(strategy) {
    this.strategy = strategy;
    this.wins = 0;
    this.total = 0;
    this.best = 0;
    this.bonus = 0;
    this.yahtzee = 0;
  }
  add(player, won) {
    const total = player.total();
    if (won) ++this.wins;
    this.total += total;
    this.best = Math.max(this.best, total);
    if (player.upperBonus() === 35) ++this.bonus;
    if (player.boxes.YAHTZEE === 50) ++this.yahtzee;
  }
}
class YahtzeeTable {
  constructor() {
    this.rules = { rolls: 3, joker: 'FORCED' };
    this.game = null;
    this.records = new Map();
    this.output = [];
    this.handlers = {
      RULE: this.setRule, GAME: this.startGame, BOT: this.setBot, LOAD: this.load,
      ROLL: this.roll, HOLD: this.hold, KEEP: this.keep, SCORE: this.score,
      WHATIF: this.whatIf, UNDO: this.undo, REDO: this.redo, SUGGEST: this.suggest,
      ODDS: this.odds, ADVISE: this.advise, AUTO: this.auto, STATUS: this.status,
      CARD: this.card, BONUS: this.bonus, STATS: this.stats, LOG: this.log,
      FACES: this.faces, STANDINGS: this.standings, END: this.end,
      RECORDS: this.showRecords, SIM: this.simulate
    };
  }
  emit(line) { this.output.push(line); }
  requireNoGame() { check(this.game === null, 'game in progress'); }
  requireGame() { check(this.game !== null, 'no game'); return this.game; }
  requireTurn() { const game = this.requireGame(); check(!game.finished(), 'game over'); return game; }
  requireRolled() { const game = this.requireTurn(); check(game.turn.rolls !== 0, 'not rolled'); return game; }
  requireRollsLeft() {
    const game = this.requireRolled();
    check(game.turn.rolls !== this.rules.rolls, 'no rolls left');
    return game;
  }
  setRule(args) {
    const [rule, value] = args;
    if (rule === 'ROLLS') {
      const rolls = integerWord(value, 1, 4);
      this.requireNoGame();
      this.rules.rolls = rolls;
    } else if (rule === 'JOKER') {
      check(JOKER_MODES.has(value), 'bad value ' + value);
      this.requireNoGame();
      this.rules.joker = value;
    } else throw new CommandError('unknown rule ' + rule);
    this.emit(`rule ${rule} ${value}`);
  }
  startGame(args) {
    const seed = integerWord(args[0], 1, MODULUS - 1);
    const names = args.slice(1).map(playerName);
    check(names.length <= 6, 'too many players');
    this.requireNoGame();
    for (let i = 0; i < names.length; ++i)
      check(!names.slice(0, i).includes(names[i]), 'duplicate name ' + names[i]);
    this.game = new Game(names.map(name => new Player(name)), this.rules, new DiceRoller(seed));
    this.emit(`game seed ${seed} players ${names.join(' ')}`);
    this.emit(`turn 1 ${names[0]}`);
  }
  setBot(args) {
    const name = playerName(args[0]), strategy = strategyName(args[1]);
    const game = this.requireGame(), player = game.players.find(player => player.name === name);
    check(player !== undefined, 'no player ' + name);
    player.strategy = strategy;
    this.emit(`bot ${name} ${strategy}`);
  }
  load(args) {
    const faces = args.map(text => integerWord(text, 1, 6));
    const game = this.requireGame();
    game.roller.loaded.push(...faces);
    this.emit(`loaded ${game.roller.loaded.length}`);
  }
  roll() {
    const game = this.requireTurn();
    check(game.turn.rolls !== this.rules.rolls, 'no rolls left');
    check(!game.turn.holds.every(Boolean), 'all dice held');
    this.emit(game.roll());
  }
  hold(args) {
    const holds = holdPattern(args[0]);
    const game = this.requireRollsLeft();
    this.emit(game.setHolds(holds));
  }
  keep(args) {
    const faces = args.map(text => integerWord(text, 1, 6));
    const game = this.requireRollsLeft(), holds = Array(5).fill(false);
    for (const face of faces) {
      const index = game.turn.faces.findIndex((v, i) => v === face && !holds[i]);
      check(index >= 0, 'not showing ' + face);
      holds[index] = true;
    }
    this.emit(game.setHolds(holds));
  }
  score(args) {
    const category = categoryName(args[0]), game = this.requireRolled();
    this.output.push(...game.score(category));
  }
  whatIf(args) {
    const category = categoryName(args[0]), game = this.requireRolled();
    this.emit(game.scoreLine(game.prepareEntry(category), 'would score'));
  }
  undo() {
    const game = this.requireGame();
    check(game.entries.length > 0, 'nothing to undo');
    const entry = game.undo();
    this.emit(`undo ${entry.player.name} ${entry.category} ${entry.points}`);
  }
  redo() {
    const game = this.requireGame();
    check(game.redoList.length > 0, 'nothing to redo');
    const entry = game.redo();
    this.emit(`redo ${entry.player.name} ${entry.category} ${entry.points}`);
  }
  suggest() {
    const game = this.requireRolled();
    const candidates = game.candidates(game.currentPlayer(), game.turn.faces);
    const best = bestCandidate(candidates);
    this.emit('suggest ' + candidates.flat().join(' ') + ' best ' + best.join(' '));
  }
  odds(args) {
    const holds = holdPattern(args[0]), game = this.requireRollsLeft();
    const player = game.currentPlayer();
    const held = heldFaces(game.turn.faces, holds);
    const open = player.openCategories(), expected = Object.fromEntries(open.map(c => [c, 0]));
    const chances = Object.fromEntries(open.map(c => [c, 0]));
    let bestTotal = 0;
    for (const [rolled, weight] of REROLLS[5 - held.length]) {
      const candidates = game.candidates(player, [...held, ...rolled]);
      for (const [category, score] of candidates) {
        expected[category] += weight * score;
        if (score > 0) chances[category] += weight;
      }
      bestTotal += weight * bestCandidate(candidates)[1];
    }
    const outcomes = 6 ** (5 - held.length);
    this.emit(`odds ${patternText(holds)} outcomes ${outcomes}`);
    for (const category of open) this.emit(`${category} expect ${fractionText(expected[category], outcomes)}`
      + ` chance ${fractionText(chances[category], outcomes)}`);
    this.emit('best expect ' + fractionText(bestTotal, outcomes));
  }
  advise() {
    const game = this.requireRollsLeft(), levels = this.rules.rolls - game.turn.rolls;
    const advisor = new Advisor(game, game.currentPlayer());
    const [holds, value] = advisor.bestHold(game.turn.faces, levels);
    this.emit(`advise ${patternText(holds)}: ${faceText(heldFaces(game.turn.faces, holds))}`
      + ` expect ${fractionText(value, 7776 ** levels)}`);
  }
  auto(args) {
    const count = integerWord(args[0], 1, 100), game = this.requireTurn();
    for (let i = 0; i < count; ++i) {
      this.output.push(...game.botTurn());
      if (game.finished()) break;
    }
  }
  status() {
    const game = this.requireGame();
    if (game.finished()) { this.emit('status game over'); return; }
    const turn = game.turn, player = game.currentPlayer();
    this.emit(`status round ${player.round()} player ${player.name} rolls ${turn.rolls}`
      + ` dice ${faceText(turn.faces)} holds ${patternText(turn.holds)}`);
  }
  card() {
    const players = this.requireGame().players;
    const widths = players.map(player => Math.max(4, player.name.length));
    const rows = [['CATEGORY', players.map(player => player.name)]];
    for (const category of CATEGORIES) rows.push([category, players.map(player =>
      player.boxes[category] === null ? '-' : String(player.boxes[category]))]);
    rows.push(['UPPER', players.map(p => String(p.upperSubtotal()))]);
    rows.push(['BONUS', players.map(p => String(p.upperBonus()))]);
    rows.push(['YBONUS', players.map(p => String(p.yahtzeeBonus))]);
    rows.push(['TOTAL', players.map(p => String(p.total()))]);
    for (const [heading, cells] of rows) {
      this.emit(heading.padEnd(9) + cells.map((cell, i) => ' ' + cell.padStart(widths[i])).join(''));
    }
  }
  bonus() {
    const game = this.requireGame();
    for (const player of game.players) {
      const subtotal = player.upperSubtotal();
      let maximum = subtotal;
      for (let i = 0; i < 6; ++i) if (player.boxes[UPPER[i]] === null) maximum += 5 * (i + 1);
      const state = subtotal >= 63 ? 'made' : maximum < 63 ? 'lost' : 'open';
      this.emit(`bonus ${player.name} upper ${subtotal} need ${Math.max(0, 63 - subtotal)}`
        + ` max ${maximum} ${state}`);
    }
  }
  stats() {
    const game = this.requireGame();
    for (const player of game.players) {
      const entries = game.entries.filter(entry => entry.player === player);
      const rolls = entries.reduce((sum, entry) => sum + entry.turn.rolls, 0);
      const zeros = entries.filter(entry => entry.points === 0).length;
      const yahtzees = entries.filter(entry => isYahtzee(entry.turn.faces)).length;
      const points = entries.reduce((sum, entry) => sum + entry.points, 0);
      this.emit(`stats ${player.name} turns ${entries.length} rolls ${rolls} zeros ${zeros}`
        + ` yahtzees ${yahtzees} average ${averageText(points, entries.length)}`);
    }
  }
  log() {
    const game = this.requireGame();
    if (!game.entries.length) this.emit('no scores');
    for (let i = 0; i < game.entries.length; ++i) {
      const entry = game.entries[i];
      const parts = ['log', i + 1, entry.player.name, faceText(entry.turn.faces),
        entry.category, entry.points];
      if (entry.joker) parts.push('joker');
      if (entry.bonus) parts.push('ybonus', entry.bonus);
      this.emit(parts.join(' '));
    }
  }
  faces() {
    const counts = this.requireGame().roller.counts, n = counts.reduce((a, b) => a + b, 0);
    const squares = counts.reduce((sum, count) => sum + count * count, 0);
    const chi2 = n ? fractionText(6 * squares - n * n, n) : '0';
    this.emit(`faces ${counts.join(' ')} total ${n} chi2 ${chi2}`);
  }
  standings() {
    const ranking = this.requireGame().ranking(), leader = ranking[0].total();
    ranking.forEach((player, index) => this.emit(`standing ${index + 1} ${player.name}`
      + ` ${player.total()} behind ${leader - player.total()}`));
  }
  end() {
    const game = this.requireGame(), finished = game.finished();
    this.emit(finished ? 'end final' : 'end abandoned');
    game.ranking().forEach((player, index) => {
      this.emit(`rank ${index + 1} ${player.name} ${player.total()}`);
      if (finished) {
        if (!this.records.has(player.name)) this.records.set(player.name, new Record());
        this.records.get(player.name).add(player.total(), index === 0);
      }
    });
    this.game = null;
  }
  showRecords() {
    if (this.records.size === 0) { this.emit('no records'); return; }
    const ordered = [...this.records.entries()].sort((a, b) => b[1].wins - a[1].wins
      || b[1].best - a[1].best || a[0].localeCompare(b[0]));
    for (const [name, r] of ordered) this.emit(`record ${name} games ${r.games} wins ${r.wins}`
      + ` best ${r.best} average ${averageText(r.total, r.games)}`);
  }
  simulate(args) {
    const seed = integerWord(args[0], 1, MODULUS - 1);
    const count = integerWord(args[1], 1, 50);
    const strategies = args.slice(2).map(strategyName);
    check(strategies.length <= 6, 'too many players');
    const roller = new DiceRoller(seed), summaries = strategies.map(s => new SeatSummary(s));
    for (let i = 0; i < count; ++i) {
      const players = strategies.map((strategy, seat) => new Player(String(seat + 1), strategy));
      const game = new Game(players, this.rules, roller);
      while (!game.finished()) game.botTurn();
      const winner = game.ranking()[0];
      for (let seat = 0; seat < strategies.length; ++seat)
        summaries[seat].add(players[seat], players[seat] === winner);
    }
    this.emit(`sim seed ${seed} games ${count} players ${strategies.length}`);
    summaries.forEach((summary, seat) => this.emit(`seat ${seat + 1} ${summary.strategy}`
      + ` wins ${summary.wins} average ${averageText(summary.total, count)}`
      + ` best ${summary.best} bonus ${summary.bonus} yahtzee ${summary.yahtzee}`));
  }
  execute(line) {
    const [command, ...args] = line.split(' ');
    try {
      check(Object.hasOwn(this.handlers, command), 'unknown command ' + command);
      this.handlers[command].call(this, args);
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      this.emit('error: ' + error.message);
    }
  }
}
const lines = readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
const table = new YahtzeeTable();
for (let i = 1; i <= Number(lines[0]); ++i) table.execute(lines[i]);
process.stdout.write(table.output.join('\n') + '\n');
