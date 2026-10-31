'use strict';

const tiles = require('./tiles');

function standard(original, meldCount = 0) {
  const result = [];
  const counts = original.slice();
  const needed = 4 - meldCount;
  const sets = [];
  function search(pair, lastKey) {
    const first = counts.findIndex(count => count > 0);
    if (first === -1) {
      if (sets.length === needed) result.push({pair, sets: sets.slice()});
      return;
    }
    if (sets.length === needed) return;
    const tripletKey = 2 * first;
    if (counts[first] >= 3 && tripletKey >= lastKey) {
      counts[first] -= 3;
      sets.push({type: 'triplet', start: first, kinds: [first, first, first]});
      search(pair, tripletKey);
      sets.pop();
      counts[first] += 3;
    }
    const sequenceKey = tripletKey + 1;
    if (first < 27 && first % 9 <= 6 && counts[first + 1] > 0 && counts[first + 2] > 0 && sequenceKey >= lastKey) {
      counts[first]--;
      counts[first + 1]--;
      counts[first + 2]--;
      sets.push({type: 'sequence', start: first, kinds: [first, first + 1, first + 2]});
      search(pair, sequenceKey);
      sets.pop();
      counts[first]++;
      counts[first + 1]++;
      counts[first + 2]++;
    }
  }
  for (let pair = 0; pair < 34; pair++) {
    if (counts[pair] < 2) continue;
    counts[pair] -= 2;
    search(pair, -1);
    counts[pair] += 2;
  }
  return result;
}

function sevenPairs(counts, meldCount = 0) {
  return meldCount === 0 && counts.every(count => count === 0 || count === 2) &&
    counts.filter(count => count === 2).length === 7;
}

function kokushi(counts, meldCount = 0) {
  if (meldCount !== 0 || tiles.orphans.some(kind => counts[kind] === 0)) return false;
  let total = 0;
  for (let kind = 0; kind < 34; kind++) {
    if (counts[kind] && !tiles.yaochuu(kind)) return false;
    total += counts[kind];
  }
  return total === 14;
}

function winning(counts, meldCount = 0) {
  return sevenPairs(counts, meldCount) || kokushi(counts, meldCount) || standard(counts, meldCount).length > 0;
}

function waiting(hand, melds) {
  const concealed = tiles.counts(hand);
  const own = concealed.slice();
  for (const meld of melds) for (const tile of meld.tiles) own[tile.kind]++;
  const result = [];
  for (let kind = 0; kind < 34; kind++) {
    if (own[kind] >= 4) continue;
    concealed[kind]++;
    if (winning(concealed, melds.length)) result.push(kind);
    concealed[kind]--;
  }
  return result;
}

function waitShape(type, block, win, handCounts) {
  if (type === 'chiitoitsu') return 'tanki';
  if (type === 'kokushi') return tiles.orphans.every(kind => handCounts[kind] === 1) ? 'thirteen' : 'single';
  if (block.type === 'pair') return 'tanki';
  if (block.type === 'triplet') return 'shanpon';
  if (win === block.start + 1) return 'kanchan';
  if ((block.start % 9 === 0 && win === block.start + 2) || (block.start % 9 === 6 && win === block.start)) return 'penchan';
  return 'ryanmen';
}

module.exports = {standard, sevenPairs, kokushi, winning, waiting, waitShape};
