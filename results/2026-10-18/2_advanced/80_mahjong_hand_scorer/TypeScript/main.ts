import type {
  Tile, Meld, Rule, Block, RawRecord, HandSituation, Candidate,
  ScoredCandidate, Payment, WaitingHand, ScoreStatistics
} from './types.ts';

import * as fs from 'node:fs';
import * as tiles from './tiles.ts';
import * as decomposition from './decomposition.ts';
import * as yaku from './yaku.ts';
import * as scoring from './scoring.ts';
import { Calculator } from './shanten.ts';

function readRecords(name: string): RawRecord[] {
  return fs.readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n').map(line => {
    const [label, ...fields] = line.split(' ');
    const record: RawRecord = {label};
    for (const field of fields) {
      const [key, value] = field.split('=');
      record[key] = value;
    }
    return record;
  });
}

function readRules(): Rule[] {
  return readRecords('rules.txt').map(record => {
    const rule: Rule = {name: record.label, honba: Number(record.honba), open_tanyao: false, red_fives: false, double_yakuman: false, kazoe_yakuman: false, kiriage: false};
    for (const key of ['open_tanyao', 'red_fives', 'double_yakuman', 'kazoe_yakuman', 'kiriage']) {
      rule[key] = record[key] === 'yes';
    }
    return rule;
  });
}

function validMeld(meld: Meld): boolean {
  const kinds = meld.tiles.map(tile => tile.kind).sort((a, b) => a - b);
  if (meld.letter === 'C') return kinds.length === 3 && kinds[0] < 27 &&
    Math.floor(kinds[0] / 9) === Math.floor(kinds[2] / 9) && kinds[1] === kinds[0] + 1 && kinds[2] === kinds[0] + 2;
  if (meld.letter === 'P') return kinds.length === 3 && kinds.every(kind => kind === kinds[0]);
  if (meld.letter === 'K' || meld.letter === 'A') return kinds.length === 4 && kinds.every(kind => kind === kinds[0]);
  return false;
}

function copyError(values: Tile[], rule: Rule): string | null {
  if (!rule.red_fives && values.some(tile => tile.red)) return 'red five not allowed';
  const counts = tiles.counts(values);
  for (let kind = 0; kind < 34; kind++) if (counts[kind] >= 5) return 'too many copies of ' + tiles.name(kind);
  const reds = [0, 0, 0];
  for (const tile of values) if (tile.red) reds[Math.floor(tile.kind / 9)]++;
  for (let suit = 0; suit < 3; suit++) if (reds[suit] >= 2) return 'too many copies of 0' + tiles.suits[suit];
  return null;
}

function context(situation: HandSituation): HandSituation {
  situation.closed = !situation.melds.some(meld => ['C', 'P', 'K'].includes(meld.letter));
  situation.handCounts = tiles.counts(situation.hand);
  situation.concealedCounts = situation.handCounts.slice();
  situation.concealedCounts[situation.win.kind]++;
  situation.allTiles = situation.hand.concat([situation.win]);
  for (const meld of situation.melds) for (const tile of meld.tiles) situation.allTiles.push(tile);
  situation.allCounts = tiles.counts(situation.allTiles);
  return situation;
}

function checkSituation(raw: RawRecord, rule: Rule): HandSituation | {error: string} {
  const hand = tiles.parse(raw.hand);
  const winning = tiles.parse(raw.win);
  const dora = tiles.parse(raw.dora);
  const ura = tiles.parse(raw.ura, true);
  const discards = tiles.parse(raw.discards, true);
  const melds = raw.melds === '-' ? [] : raw.melds.split(',').map(text =>
    ({letter: text[0], tiles: tiles.parse(text.slice(1))}));
  if ([hand, winning, dora, ura, discards].some(value => value === null) ||
      melds.some(meld => meld.tiles === null) || winning.length !== 1) return {error: 'bad tile notation'};
  if (melds.length >= 5 || melds.some(meld => !validMeld(meld))) return {error: 'bad meld'};
  if (hand.length !== 13 - 3 * melds.length) return {error: 'wrong tile count'};
  const situation = context({...raw, rule, hand, win: winning[0], melds, dora, ura, discards,
    flags: new Set(raw.flags === '-' ? [] : raw.flags.split(',')), honba: Number(raw.honba), sticks: Number(raw.sticks)});
  const copies = copyError(situation.allTiles.concat(dora, ura, discards), rule);
  if (copies !== null) return {error: copies};
  if ((raw.by === 'tsumo' && raw.from !== '-') ||
      (raw.by === 'ron' && (raw.from === '-' || raw.from === raw.seat))) return {error: 'invalid discarder'};
  const flags = situation.flags;
  const riichi = flags.has('riichi') || flags.has('double_riichi');
  const kans = melds.filter(meld => meld.letter === 'K' || meld.letter === 'A').length;
  const validFlags = {
    riichi: situation.closed,
    double_riichi: situation.closed && !flags.has('riichi'),
    ippatsu: riichi && !flags.has('rinshan'),
    haitei: raw.by === 'tsumo' && !flags.has('rinshan'),
    houtei: raw.by === 'ron' && !flags.has('chankan'),
    rinshan: raw.by === 'tsumo' && kans > 0,
    chankan: raw.by === 'ron',
    tenhou: raw.seat === 'E' && raw.by === 'tsumo' && melds.length === 0 && flags.size === 1,
    chiihou: raw.seat !== 'E' && raw.by === 'tsumo' && melds.length === 0 && flags.size === 1,
  };
  for (const flag of yaku.flags) if (flags.has(flag) && !validFlags[flag]) return {error: 'invalid flag ' + flag};
  if (dora.length !== 1 + kans) return {error: 'invalid dora indicators'};
  if ((riichi && ura.length !== dora.length) || (!riichi && ura.length !== 0)) return {error: 'invalid ura indicators'};
  if (riichi && situation.sticks === 0) return {error: 'invalid sticks'};
  if (!decomposition.winning(situation.concealedCounts, melds.length)) return {error: 'not a winning hand'};
  return situation;
}

function meldBlock(meld: Meld): Block {
  const kinds = meld.tiles.map(tile => tile.kind).sort((a, b) => a - b);
  const type = meld.letter === 'C' ? 'sequence' : meld.letter === 'P' ? 'triplet' : 'kan';
  return {type, start: kinds[0], kinds, concealed: meld.letter === 'A'};
}

function createCandidates(situation: HandSituation): Candidate[] {
  const result = [];
  const win = situation.win.kind;
  const counts = situation.concealedCounts;
  const melds = situation.melds.map(meldBlock);
  const meldText = situation.melds.map((meld, index) => meld.letter + tiles.block(melds[index].kinds));
  for (const split of decomposition.standard(counts, melds.length)) {
    const blocks = [{type: 'pair', start: split.pair, kinds: [split.pair, split.pair]}, ...split.sets];
    const seen = new Set();
    for (let winning = 0; winning < blocks.length; winning++) {
      const block = blocks[winning];
      const notation = tiles.block(block.kinds);
      if (!block.kinds.includes(win) || seen.has(notation)) continue;
      seen.add(notation);
      const concealed = blocks.map((part, index) => ({...part,
        concealed: part.type === 'triplet' && (index !== winning || situation.by === 'tsumo')}));
      const all = concealed.concat(melds);
      const form = ['standard', ...blocks.map((part, index) =>
        tiles.block(part.kinds) + (index === winning ? '*' : '')), ...meldText].join(' ');
      result.push({type: 'standard', pair: split.pair, sets: concealed.slice(1), blocks: all,
        triplets: all.filter(part => part.type === 'triplet' || part.type === 'kan'),
        sequences: all.filter(part => part.type === 'sequence'), form,
        wait: decomposition.waitShape('standard', block, win, situation.handCounts)});
    }
  }
  if (decomposition.sevenPairs(counts, melds.length)) {
    const parts = ['chiitoitsu'];
    for (let kind = 0; kind < 34; kind++) {
      if (counts[kind] === 2) parts.push(tiles.block([kind, kind]) + (kind === win ? '*' : ''));
    }
    result.push({type: 'chiitoitsu', form: parts.join(' '),
      wait: decomposition.waitShape('chiitoitsu', null, win, situation.handCounts)});
  }
  if (decomposition.kokushi(counts, melds.length)) {
    const parts = ['kokushi'];
    for (const kind of tiles.orphans) parts.push(tiles.block(Array(counts[kind]).fill(kind)) + (kind === win ? '*' : ''));
    result.push({type: 'kokushi', form: parts.join(' '),
      wait: decomposition.waitShape('kokushi', null, win, situation.handCounts)});
  }
  result.sort((a, b) => a.form < b.form ? -1 : a.form > b.form ? 1 : 0);
  return result;
}

function ordinaryYaku(candidate: Candidate, situation: HandSituation): Set<string> {
  const found = new Set();
  for (const flag of ['riichi', 'double_riichi', 'ippatsu', 'haitei', 'houtei', 'rinshan', 'chankan']) {
    if (situation.flags.has(flag)) found.add(flag);
  }
  const kinds = situation.allTiles.map(tile => tile.kind);
  const numbered = kinds.filter(kind => kind < 27);
  const numberSuits = new Set(numbered.map(kind => Math.floor(kind / 9)));
  const hasHonor = kinds.some(tiles.honor);
  if (situation.closed && situation.by === 'tsumo') found.add('menzen_tsumo');
  if (kinds.every(tiles.simple) && (situation.closed || situation.rule.open_tanyao)) found.add('tanyao');
  if (kinds.every(tiles.yaochuu)) found.add('honroutou');
  if (numberSuits.size === 1 && hasHonor) found.add('honitsu');
  if (numberSuits.size === 1 && !hasHonor) found.add('chinitsu');
  if (candidate.type === 'chiitoitsu') found.add('chiitoitsu');
  if (candidate.type !== 'standard') return found;
  const triplets = candidate.triplets;
  const sequences = candidate.sequences;
  const tripletKinds = new Set(triplets.map(block => block.start));
  const sequenceStarts = new Set(sequences.map(block => block.start));
  const concealedCount = triplets.filter(block => block.concealed).length;
  const kans = triplets.filter(block => block.type === 'kan').length;
  const dragonCount = triplets.filter(block => block.start >= 31).length;
  const yakuhaiPair = candidate.pair >= 31 || candidate.pair === tiles.windKind(situation.seat) ||
    candidate.pair === tiles.windKind(situation.round);
  if (situation.closed && situation.melds.length === 0 && candidate.sets.every(block => block.type === 'sequence') &&
      !yakuhaiPair && candidate.wait === 'ryanmen') found.add('pinfu');
  const repetitions = new Map();
  for (const block of candidate.sets) {
    if (block.type === 'sequence') repetitions.set(block.start, (repetitions.get(block.start) || 0) + 1);
  }
  if (situation.closed && candidate.sets.length === 4 && candidate.sets.every(block => block.type === 'sequence') &&
      [...repetitions.values()].every(count => count % 2 === 0)) found.add('ryanpeikou');
  if (situation.closed && !found.has('ryanpeikou') && [...repetitions.values()].some(count => count >= 2)) found.add('iipeikou');
  for (const [kind, name] of [[31, 'haku'], [32, 'hatsu'], [33, 'chun']]) if (tripletKinds.has(kind)) found.add(name);
  if (tripletKinds.has(tiles.windKind(situation.seat))) found.add('jikaze');
  if (tripletKinds.has(tiles.windKind(situation.round))) found.add('bakaze');
  if (triplets.length === 4) found.add('toitoi');
  if (concealedCount === 3) found.add('sanankou');
  for (let start = 0; start <= 6; start++) {
    if ([0, 9, 18].every(suit => sequenceStarts.has(suit + start))) found.add('sanshoku_doujun');
  }
  for (let number = 0; number < 9; number++) {
    if ([0, 9, 18].every(suit => tripletKinds.has(suit + number))) found.add('sanshoku_doukou');
  }
  for (const suit of [0, 9, 18]) {
    if ([0, 3, 6].every(start => sequenceStarts.has(suit + start))) found.add('ittsu');
  }
  if (sequences.length > 0 && candidate.blocks.every(block => block.kinds.some(tiles.yaochuu))) {
    found.add(hasHonor ? 'chanta' : 'junchan');
  }
  if (kans === 3) found.add('sankantsu');
  if (dragonCount === 2 && candidate.pair >= 31) found.add('shousangen');
  return found;
}

function yakumanYaku(candidate: Candidate, situation: HandSituation): Set<string> {
  const found = new Set();
  for (const flag of ['tenhou', 'chiihou']) if (situation.flags.has(flag)) found.add(flag);
  const kinds = situation.allTiles.map(tile => tile.kind);
  if (kinds.every(tiles.honor)) found.add('tsuuiisou');
  if (kinds.every(tiles.terminal)) found.add('chinroutou');
  if (kinds.every(kind => tiles.green.has(kind))) found.add('ryuuiisou');
  const suit = Math.floor(kinds[0] / 9);
  if (situation.melds.length === 0 && suit < 3 && kinds.every(kind => Math.floor(kind / 9) === suit)) {
    const base = 9 * suit;
    const pattern = [3, 1, 1, 1, 1, 1, 1, 1, 3];
    if (pattern.every((count, number) => situation.allCounts[base + number] >= count)) {
      const pure = pattern.every((count, number) => situation.handCounts[base + number] === count);
      found.add(pure ? 'junsei_chuuren' : 'chuuren');
    }
  }
  if (candidate.type === 'kokushi') found.add(candidate.wait === 'thirteen' ? 'kokushi_13' : 'kokushi');
  if (candidate.type !== 'standard') return found;
  const triplets = candidate.triplets;
  const concealedCount = triplets.filter(block => block.concealed).length;
  const dragonCount = triplets.filter(block => block.start >= 31).length;
  const windCount = triplets.filter(block => block.start >= 27 && block.start <= 30).length;
  const kans = triplets.filter(block => block.type === 'kan').length;
  if (concealedCount === 4) found.add(candidate.wait === 'tanki' ? 'suuankou_tanki' : 'suuankou');
  if (dragonCount === 3) found.add('daisangen');
  if (windCount === 4) found.add('daisuushii');
  if (windCount === 3 && candidate.pair >= 27 && candidate.pair <= 30) found.add('shousuushii');
  if (kans === 4) found.add('suukantsu');
  return found;
}

function indicatorDora(indicators: Tile[], counts: number[]): number {
  let result = 0;
  for (const indicator of indicators) result += counts[tiles.nextIndicator(indicator.kind)];
  return result;
}

function evaluateCandidate(candidate: Candidate, situation: HandSituation): ScoredCandidate {
  const yakuman = yaku.yakuman(yakumanYaku(candidate, situation), situation.rule.double_yakuman);
  if (yakuman.length > 0) {
    let multiplier = 0;
    for (const item of yakuman) multiplier += item.multiplier;
    return {...candidate, yakuman: true, yaku: yakuman, multiplier, category: 'yakuman', base: 8000 * multiplier};
  }
  const found = ordinaryYaku(candidate, situation);
  const ordinary = yaku.ordinary(found, situation.closed);
  const dora = indicatorDora(situation.dora, situation.allCounts);
  const ura = indicatorDora(situation.ura, situation.allCounts);
  const aka = situation.allTiles.filter(tile => tile.red).length;
  const breakdown = scoring.fu(candidate, situation, found);
  let han = dora + ura + aka;
  for (const item of ordinary) han += item.han;
  const value = ordinary.length === 0 ? {category: null, base: 0} : scoring.limit(han, breakdown.rounded, situation.rule);
  return {...candidate, yakuman: false, yaku: ordinary, han, fu: breakdown.rounded, breakdown, dora, ura, aka, ...value};
}

function evaluatedCandidates(situation: HandSituation): ScoredCandidate[] {
  return createCandidates(situation).map(candidate => evaluateCandidate(candidate, situation));
}

function better(first: ScoredCandidate, second: ScoredCandidate | null): boolean {
  if (second === null) return true;
  if (first.base !== second.base) return first.base > second.base;
  if (first.yakuman !== second.yakuman) return first.yakuman;
  if (!first.yakuman) {
    if (first.han !== second.han) return first.han > second.han;
    if (first.fu !== second.fu) return first.fu > second.fu;
  }
  return first.form < second.form;
}

function bestCandidate(candidates: ScoredCandidate[]): ScoredCandidate | null {
  let best = null;
  for (const candidate of candidates) if (candidate.base > 0 && better(candidate, best)) best = candidate;
  return best;
}

function candidateLine(candidate: ScoredCandidate): string {
  let evaluation;
  const names = candidate.yaku.map(item => item.name).join(',');
  if (candidate.yakuman) evaluation = `yakuman ${candidate.multiplier} base ${candidate.base} yaku ${names}`;
  else if (candidate.base === 0) evaluation = 'no_yaku';
  else evaluation = `han ${candidate.han} fu ${candidate.fu} base ${candidate.base} yaku ${names}`;
  return `CANDIDATE ${candidate.form} = ${candidate.wait} ${evaluation}`;
}

function paymentLine(payment: Payment): string {
  if (payment.kind === 'ron') return `PAY ron ${payment.ron}`;
  if (payment.kind === 'all') return `PAY tsumo all ${payment.all}`;
  return `PAY tsumo dealer ${payment.dealer} nondealer ${payment.nondealer}`;
}

function winLines(situation: HandSituation, candidate: ScoredCandidate, payment: Payment): string[] {
  const lines = [`FORM ${candidate.form}`, `WAIT ${candidate.wait}`];
  if (candidate.yakuman) {
    for (const item of candidate.yaku) lines.push(`YAKUMAN ${item.name} ${item.multiplier}`);
    lines.push(`SCORE yakuman ${candidate.multiplier} base ${candidate.base}`);
  } else {
    for (const item of candidate.yaku) lines.push(`YAKU ${item.name} ${item.han}`);
    lines.push(`DORA dora ${candidate.dora} aka ${candidate.aka} ura ${candidate.ura}`);
    for (const item of candidate.breakdown.items) lines.push(`FU ${item.name} ${item.value}`);
    lines.push(`FU total ${candidate.breakdown.total} ${candidate.fu}`);
    lines.push(`SCORE han ${candidate.han} fu ${candidate.fu} limit ${candidate.category} base ${candidate.base}`);
  }
  const honba = situation.honba * situation.rule.honba;
  const sticks = situation.sticks * 1000;
  const gain = payment.points + honba + sticks;
  lines.push(paymentLine(payment));
  lines.push(`BONUS honba ${honba} sticks ${sticks}`);
  lines.push(`TOTAL points ${payment.points} gain ${gain}`);
  const delta = Object.fromEntries([...tiles.winds].map(wind => [wind, 0]));
  delta[situation.seat] = gain;
  if (situation.by === 'ron') delta[situation.from] = -(payment.ron + honba);
  else {
    for (const wind of tiles.winds) {
      if (wind === situation.seat) continue;
      const amount = payment.kind === 'all' ? payment.all : wind === 'E' ? payment.dealer : payment.nondealer;
      delta[wind] = -(amount + honba / 3);
    }
  }
  const changes = [...tiles.winds].map(wind => `${wind} ${delta[wind] > 0 ? '+' : ''}${delta[wind]}`);
  lines.push('DELTA ' + changes.join(' '));
  return lines;
}

function increment<K>(counts: Map<K, number>, key: K): void {
  counts.set(key, (counts.get(key) || 0) + 1);
}

function scoreStatistics(rules: Rule[]): ScoreStatistics {
  return {wins: 0, furiten: 0, noYaku: 0, errors: 0,
    methods: new Map(['dealer_ron', 'dealer_tsumo', 'nondealer_ron', 'nondealer_tsumo'].map(key => [key, 0])),
    waits: new Map(yaku.waitShapes.map(key => [key, 0])), han: new Map(), fu: new Map(),
    categories: new Map(yaku.categories.map(key => [key, 0])), yaku: new Map(), points: 0, maximum: 0, hand: '-',
    rules: new Map(rules.map(rule => [rule.name, {hands: 0, wins: 0, points: 0}]))};
}

function recordWin(stats: ScoreStatistics, situation: HandSituation, candidate: ScoredCandidate, points: number): void {
  stats.wins++;
  increment(stats.methods, (situation.seat === 'E' ? 'dealer_' : 'nondealer_') + situation.by);
  increment(stats.waits, candidate.wait);
  increment(stats.categories, candidate.category);
  if (!candidate.yakuman) {
    increment(stats.han, candidate.han);
    increment(stats.fu, candidate.fu);
  }
  for (const item of candidate.yaku) increment(stats.yaku, item.name);
  stats.points += points;
  if (points > stats.maximum) {
    stats.maximum = points;
    stats.hand = situation.label;
  }
  const rule = stats.rules.get(situation.rule.name);
  rule.wins++;
  rule.points += points;
}

function statisticLines(stats: ScoreStatistics, total: number, rules: Rule[]): string[] {
  const lines = [`STATS hands ${total} wins ${stats.wins} furiten ${stats.furiten} no_yaku ${stats.noYaku} errors ${stats.errors}`];
  lines.push('WINS ' + [...stats.methods].map(([name, count]) => `${name} ${count}`).join(' '));
  lines.push('WAIT_COUNT ' + [...stats.waits].map(([name, count]) => `${name} ${count}`).join(' '));
  for (const han of [...stats.han.keys()].sort((a, b) => a - b)) lines.push(`HAN_COUNT ${han} ${stats.han.get(han)}`);
  for (const fu of [...stats.fu.keys()].sort((a, b) => a - b)) lines.push(`FU_COUNT ${fu} ${stats.fu.get(fu)}`);
  for (const category of yaku.categories) lines.push(`LIMIT ${category} ${stats.categories.get(category)}`);
  for (const [name] of yaku.ordinaryTable.concat(yaku.yakumanTable)) {
    if (stats.yaku.has(name)) lines.push(`YAKU_COUNT ${name} ${stats.yaku.get(name)}`);
  }
  lines.push(`POINTS total ${stats.points} max ${stats.maximum} hand ${stats.hand}`);
  for (const rule of rules) {
    const counts = stats.rules.get(rule.name);
    lines.push(`RULE ${rule.name} hands ${counts.hands} wins ${counts.wins} points ${counts.points}`);
  }
  return lines;
}

function scoreHands(records: RawRecord[], rules: Rule[], byName: Map<string, Rule>): {lines: string[]; summary: string[]} {
  const lines = [];
  const summary = ['hand,han,fu,points,yaku'];
  const stats = scoreStatistics(rules);
  for (const raw of records) {
    lines.push('HAND ' + raw.label);
    stats.rules.get(raw.rules).hands++;
    const situation = checkSituation(raw, byName.get(raw.rules));
    if (situation.error) {
      lines.push('ERROR ' + situation.error);
      summary.push(`${raw.label},-,-,0,ERROR`);
      stats.errors++;
      continue;
    }
    const waiting = decomposition.waiting(situation.hand, situation.melds);
    lines.push('WAITS ' + waiting.map(tiles.name).join(' '));
    const candidates = evaluatedCandidates(situation);
    for (const candidate of candidates) lines.push(candidateLine(candidate));
    if (situation.by === 'ron' && situation.discards.some(tile => waiting.includes(tile.kind))) {
      lines.push('RESULT furiten');
      summary.push(`${raw.label},-,-,0,FURITEN`);
      stats.furiten++;
      continue;
    }
    const best = bestCandidate(candidates);
    if (best === null) {
      lines.push('RESULT no_yaku');
      summary.push(`${raw.label},-,-,0,NO_YAKU`);
      stats.noYaku++;
      continue;
    }
    const payment = scoring.payments(best.base, situation.by, situation.seat);
    for (const line of winLines(situation, best, payment)) lines.push(line);
    recordWin(stats, situation, best, payment.points);
    const han = best.yakuman ? 'Y' + best.multiplier : best.han;
    const fu = best.yakuman ? '-' : best.fu;
    summary.push(`${raw.label},${han},${fu},${payment.points},${best.yaku.map(item => item.name).join(';')}`);
  }
  for (const line of statisticLines(stats, records.length, rules)) lines.push(line);
  return {lines, summary};
}

function checkHand(raw: RawRecord, rule: Rule): WaitingHand | {error: string} {
  const hand = tiles.parse(raw.hand);
  const dora = tiles.parse(raw.dora);
  const discards = tiles.parse(raw.discards, true);
  const visible = tiles.parse(raw.visible, true);
  if ([hand, dora, discards, visible].some(value => value === null)) return {error: 'bad tile notation'};
  if (hand.length !== 13) return {error: 'wrong tile count'};
  const known = hand.concat(dora, discards, visible);
  const copies = copyError(known, rule);
  if (copies !== null) return {error: copies};
  return {...raw, rule, hand, dora, discards, visible, handCounts: tiles.counts(hand), knownCounts: tiles.counts(known)};
}

function acceptanceTiles(hand: WaitingHand, calculator: Calculator, shanten: number): {kind: number; left: number}[] {
  const counts = hand.handCounts.slice();
  const result = [];
  for (let kind = 0; kind < 34; kind++) {
    if (counts[kind] >= 4) continue;
    counts[kind]++;
    const advanced = calculator.numbers(counts).minimum < shanten;
    counts[kind]--;
    if (advanced) result.push({kind, left: 4 - hand.knownCounts[kind]});
  }
  return result;
}

function hypotheticalPoints(hand: WaitingHand, kind: number, by: string): number | 'no_yaku' {
  const situation = context({rule: hand.rule, hand: hand.hand, win: {kind, red: false}, melds: [],
    by, seat: hand.seat, round: hand.round, flags: new Set(hand.riichi === 'yes' ? ['riichi'] : []),
    dora: hand.dora, ura: [], discards: []});
  const best = bestCandidate(evaluatedCandidates(situation));
  return best === null ? 'no_yaku' : scoring.payments(best.base, by, hand.seat).points;
}

function tenpaiLines(hand: WaitingHand, acceptance: {kind: number; left: number}[], total: number, furiten: boolean): string[] {
  const lines = [`TENPAI kinds ${acceptance.length} tiles ${total} furiten ${furiten ? 'yes' : 'no'}`];
  let bestRon = null;
  let bestTsumo = null;
  for (const tile of acceptance) {
    const ron = furiten ? 'furiten' : hypotheticalPoints(hand, tile.kind, 'ron');
    const tsumo = hypotheticalPoints(hand, tile.kind, 'tsumo');
    lines.push(`WAIT ${tiles.name(tile.kind)} left ${tile.left} ron ${ron} tsumo ${tsumo}`);
    if (typeof ron === 'number' && (bestRon === null || ron > bestRon.points)) bestRon = {kind: tile.kind, points: ron};
    if (typeof tsumo === 'number' && (bestTsumo === null || tsumo > bestTsumo.points)) bestTsumo = {kind: tile.kind, points: tsumo};
  }
  const text = best => best === null ? 'none' : `${tiles.name(best.kind)} ${best.points}`;
  lines.push(`BEST ron ${text(bestRon)} tsumo ${text(bestTsumo)}`);
  return lines;
}

function analyzeHands(records: RawRecord[], rules: Map<string, Rule>): string[] {
  const lines = [];
  const counts = Array(7).fill(0);
  let errors = 0;
  let tenpai = 0;
  let furitenCount = 0;
  for (const raw of records) {
    lines.push('HAND ' + raw.label);
    const hand = checkHand(raw, rules.get(raw.rules));
    if (hand.error) {
      lines.push('ERROR ' + hand.error);
      errors++;
      continue;
    }
    const calculator = new Calculator();
    const shanten = calculator.numbers(hand.handCounts);
    counts[shanten.minimum]++;
    lines.push(`SHANTEN standard ${shanten.standard} chiitoitsu ${shanten.chiitoitsu} kokushi ${shanten.kokushi}`);
    const acceptance = acceptanceTiles(hand, calculator, shanten.minimum);
    let total = 0;
    for (const tile of acceptance) total += tile.left;
    if (shanten.minimum > 0) {
      const parts = [`ACCEPT kinds ${acceptance.length} tiles ${total}`];
      for (const tile of acceptance) parts.push(`${tiles.name(tile.kind)}:${tile.left}`);
      lines.push(parts.join(' '));
      continue;
    }
    tenpai++;
    const waitingKinds = new Set(acceptance.map(tile => tile.kind));
    const furiten = hand.discards.some(tile => waitingKinds.has(tile.kind));
    if (furiten) furitenCount++;
    for (const line of tenpaiLines(hand, acceptance, total, furiten)) lines.push(line);
  }
  lines.push(`STATS hands ${records.length} errors ${errors} tenpai ${tenpai} furiten ${furitenCount}`);
  for (let shanten = 0; shanten <= 6; shanten++) lines.push(`SHANTEN_COUNT ${shanten} ${counts[shanten]}`);
  return lines;
}

function main(): void {
  const rules = readRules();
  const byName = new Map(rules.map(rule => [rule.name, rule]));
  const scores = scoreHands(readRecords('hands.txt'), rules, byName);
  const waits = analyzeHands(readRecords('waits.txt'), byName);
  fs.mkdirSync('output', {recursive: true});
  const files = {'scores.txt': scores.lines, 'waits.txt': waits, 'summary.csv': scores.summary};
  for (const [name, lines] of Object.entries(files)) fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

main();
