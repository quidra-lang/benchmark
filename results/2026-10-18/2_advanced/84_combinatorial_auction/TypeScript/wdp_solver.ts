import { Fraction } from './report.ts';
import type { Auction, Bid, Bound, Share, WdpStats, WdpResult } from './types.ts';
const shareScale = 27720;

export function lexicographic(first: number[], second: number[]): number {
  for (let index = 0; index < Math.min(first.length, second.length); index++) {
    if (first[index] !== second[index]) return first[index] - second[index];
  }
  return first.length - second.length;
}

function stateBound(auction: Auction, bids: Bid[], decided: number, used: number, welfare: number): Bound {
  const usable = bids.filter(bid => (bid.mask & decided) === 0 && (!bid.xor || (used & bid.bidder.bit) === 0));
  const shares: Share[] = [];
  let bound = welfare * shareScale;
  for (const item of auction.items) {
    if ((decided & item.bit) !== 0) continue;
    let value = item.reserve * shareScale;
    let source: number | null = null;
    for (const bid of usable) {
      if ((bid.mask & item.bit) === 0) continue;
      const proposed = bid.amount * (shareScale / bid.size);
      if (proposed > value) {
        value = proposed;
        source = bid.number;
      }
    }
    shares.push({item, value, source});
    bound += value;
  }
  return {usable, shares, bound};
}

export function solve(auction: Auction, source: Bid[] = auction.eligible): WdpResult {
  const bids = source.slice().sort((a, b) => a.number - b.number);
  const root = stateBound(auction, bids, 0, 0, 0);
  const stats: WdpStats = {nodes: 0, pruned: 0, leaves: 0, improvements: []};
  let incumbent: {welfare: number; numbers: number[]} | null = null;
  function visit(decided: number, used: number, welfare: number, chosen: Bid[]): void {
    stats.nodes++;
    if (decided === auction.mask) {
      stats.leaves++;
      const numbers = chosen.map(bid => bid.number).sort((a, b) => a - b);
      if (incumbent === null || welfare > incumbent.welfare ||
          (welfare === incumbent.welfare && lexicographic(numbers, incumbent.numbers) < 0)) {
        incumbent = {welfare, numbers};
        stats.improvements.push({node: stats.nodes, welfare, numbers});
      }
      return;
    }
    const state = stateBound(auction, bids, decided, used, welfare);
    if (incumbent !== null && state.bound < incumbent.welfare * shareScale) {
      stats.pruned++;
      return;
    }
    const first = auction.items.find(item => (decided & item.bit) === 0);
    for (const bid of state.usable) {
      if ((bid.mask & first!.bit) === 0) continue;
      visit(decided | bid.mask, bid.xor ? used | bid.bidder.bit : used, welfare + bid.amount, chosen.concat(bid));
    }
    visit(decided | first.bit, used, welfare + first.reserve, chosen);
  }
  visit(0, 0, 0, []);
  const best = incumbent as {welfare: number; numbers: number[]};
  const selected = new Set<number>(best.numbers);
  return {...best, bids: bids.filter(bid => selected.has(bid.number)), stats,
    rootBound: new Fraction(root.bound, shareScale),
    rootShares: root.shares.map(share => ({...share, value: new Fraction(share.value, shareScale)}))};
}

export function greedyOrder(bids: Bid[]): Bid[] {
  return bids.slice().sort((a, b) => {
    const first = a.amount * a.amount * b.size;
    const second = b.amount * b.amount * a.size;
    return second - first || a.number - b.number;
  });
}

export function greedySelection(order: Bid[]): Bid[] {
  const selected: Bid[] = [];
  let items = 0;
  let used = 0;
  for (const bid of order) {
    if ((items & bid.mask) !== 0 || (bid.xor && (used & bid.bidder.bit) !== 0)) continue;
    selected.push(bid);
    items |= bid.mask;
    if (bid.xor) used |= bid.bidder.bit;
  }
  return selected;
}

