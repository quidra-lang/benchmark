import type { Candidate, HandSituation, Rule, Payment, FuBreakdown, Block } from './types.ts';

import * as tiles from './tiles.ts';

export function tripletFu(block: Block): {name: string; value: number} {
  const type = (block.concealed ? 'closed_' : 'open_') + (block.type === 'kan' ? 'kan' : 'triplet');
  const values: Record<string, number> = {open_triplet: 2, closed_triplet: 4, open_kan: 8, closed_kan: 16};
  return {name: type + ' ' + tiles.block(block.kinds),
    value: values[type] * (tiles.yaochuu(block.start) ? 2 : 1)};
}

export function fu(candidate: Candidate, situation: HandSituation, found: Set<string>): FuBreakdown {
  if (candidate.type === 'chiitoitsu') return {items: [{name: 'chiitoitsu', value: 25}], total: 25, rounded: 25};
  const items = [{name: 'base', value: 20}];
  if (situation.closed && situation.by === 'ron') items.push({name: 'closed_ron', value: 10});
  if (situation.by === 'tsumo' && !found.has('pinfu')) items.push({name: 'tsumo', value: 2});
  let pair = candidate.pair! >= 31 ? 2 : 0;
  if (candidate.pair! === tiles.windKind(situation.seat)) pair += 2;
  if (candidate.pair! === tiles.windKind(situation.round)) pair += 2;
  if (pair > 0) items.push({name: 'pair ' + tiles.block([candidate.pair!, candidate.pair!]), value: pair});
  for (const block of candidate.triplets!) items.push(tripletFu(block));
  if (['kanchan', 'penchan', 'tanki'].includes(candidate.wait)) items.push({name: 'wait ' + candidate.wait, value: 2});
  let total = 0;
  for (const item of items) total += item.value;
  if (!situation.closed && total === 20) {
    items.push({name: 'open_pinfu', value: 10});
    total += 10;
  }
  return {items, total, rounded: Math.floor((total + 9) / 10) * 10};
}

export function limit(han: number, fu: number, rule: Rule): {category: string; base: number} {
  if (han >= 13 && rule.kazoe_yakuman) return {category: 'kazoe_yakuman', base: 8000};
  if (han >= 11) return {category: 'sanbaiman', base: 6000};
  if (han >= 8) return {category: 'baiman', base: 4000};
  if (han >= 6) return {category: 'haneman', base: 3000};
  const base = fu * 2 ** (han + 2);
  if (han === 5 || base >= 2000 || (rule.kiriage && base === 1920)) return {category: 'mangan', base: 2000};
  return {category: 'none', base};
}

export function round100(value: number): number {
  return Math.floor((value + 99) / 100) * 100;
}

export function payments(base: number, by: string, seat: string): Payment {
  if (by === 'ron') {
    const ron = round100((seat === 'E' ? 6 : 4) * base);
    return {kind: 'ron', ron, points: ron};
  }
  if (seat === 'E') {
    const all = round100(2 * base);
    return {kind: 'all', all, points: 3 * all};
  }
  const dealer = round100(2 * base);
  const nondealer = round100(base);
  return {kind: 'split', dealer, nondealer, points: dealer + 2 * nondealer};
}

