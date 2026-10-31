'use strict';

const {Fraction} = require('./report');
// Every possible bundle size divides this common denominator for exact bound arithmetic.
const shareScale = 27720;

function lexicographic(first, second) {
  for (let index = 0; index < Math.min(first.length, second.length); index++) {
    if (first[index] !== second[index]) return first[index] - second[index];
  }
  return first.length - second.length;
}

function stateBound(auction, bids, decided, used, welfare) {
  const usable = bids.filter(bid => (bid.mask & decided) === 0 && (!bid.xor || (used & bid.bidder.bit) === 0));
  const shares = [];
  let bound = welfare * shareScale;
  for (const item of auction.items) {
    if ((decided & item.bit) !== 0) continue;
    let value = item.reserve * shareScale;
    let source = null;
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

function solve(auction, source = auction.eligible) {
  const bids = source.slice().sort((a, b) => a.number - b.number);
  const root = stateBound(auction, bids, 0, 0, 0);
  const stats = {nodes: 0, pruned: 0, leaves: 0, improvements: []};
  let incumbent = null;
  function visit(decided, used, welfare, chosen) {
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
      if ((bid.mask & first.bit) === 0) continue;
      visit(decided | bid.mask, bid.xor ? used | bid.bidder.bit : used, welfare + bid.amount, chosen.concat(bid));
    }
    visit(decided | first.bit, used, welfare + first.reserve, chosen);
  }
  visit(0, 0, 0, []);
  const selected = new Set(incumbent.numbers);
  return {...incumbent, bids: bids.filter(bid => selected.has(bid.number)), stats,
    rootBound: new Fraction(root.bound, shareScale),
    rootShares: root.shares.map(share => ({...share, value: new Fraction(share.value, shareScale)}))};
}

function greedyOrder(bids) {
  return bids.slice().sort((a, b) => {
    const first = a.amount * a.amount * b.size;
    const second = b.amount * b.amount * a.size;
    return second - first || a.number - b.number;
  });
}

function greedySelection(order) {
  const selected = [];
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

module.exports = {lexicographic, solve, greedyOrder, greedySelection};
