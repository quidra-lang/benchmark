'use strict';

function userSimilarity(first, second, shrinkage) {
  let common = 0;
  let sx = 0;
  let sy = 0;
  let sxx = 0;
  let syy = 0;
  let sxy = 0;
  for (const row of first.entries) {
    if (!second.ratings.has(row.i)) continue;
    const x = row.rating;
    const y = second.ratings.get(row.i);
    common++;
    sx += x;
    sy += y;
    sxx += x * x;
    syy += y * y;
    sxy += x * y;
  }
  if (common < 2) return null;
  const numerator = common * sxy - sx * sy;
  const dx = common * sxx - sx * sx;
  const dy = common * syy - sy * sy;
  if (dx === 0 || dy === 0) return null;
  const scaled = BigInt(numerator) * BigInt(common);
  const regularized = BigInt(common) + BigInt(shrinkage);
  const a = scaled * scaled;
  const b = BigInt(dx) * BigInt(dy) * regularized * regularized;
  const sign = numerator > 0 ? 1 : numerator < 0 ? -1 : 0;
  return { similarity: sign * Math.sqrt(Number(a) / Number(b)), common };
}

function buildNeighborhoods(data) {
  const users = Array.from({ length: data.users.length }, () => Array(data.users.length).fill(null));
  for (let first = 0; first < data.users.length; first++) {
    for (let second = first + 1; second < data.users.length; second++) {
      users[first][second] = users[second][first] = userSimilarity(data.users[first], data.users[second], data.settings.shrinkage);
    }
  }
  const items = Array.from({ length: data.items.length }, () => Array(data.items.length).fill(null));
  const common = Array.from({ length: data.items.length }, () => Array(data.items.length).fill(0));
  const difference = Array.from({ length: data.items.length }, () => Array(data.items.length).fill(0));
  for (let first = 0; first < data.items.length; first++) {
    for (let second = first + 1; second < data.items.length; second++) {
      let count = 0;
      let sum = 0;
      let numerator = 0;
      let normFirst = 0;
      let normSecond = 0;
      for (const row of data.items[first].entries) {
        if (!data.items[second].ratings.has(row.u)) continue;
        const other = data.items[second].ratings.get(row.u);
        count++;
        sum += row.rating - other;
        const x = row.rating - data.users[row.u].mean;
        const y = other - data.users[row.u].mean;
        numerator += x * y;
        normFirst += x * x;
        normSecond += y * y;
      }
      common[first][second] = common[second][first] = count;
      difference[first][second] = sum;
      difference[second][first] = -sum;
      if (count >= 2 && normFirst !== 0 && normSecond !== 0) {
        const similarity = numerator / Math.sqrt(normFirst * normSecond) * count / (count + data.settings.shrinkage);
        items[first][second] = items[second][first] = { similarity, common: count };
      }
    }
  }
  return { users, items, common, difference };
}

function select(candidates, count) {
  return candidates.sort((a, b) => b.similarity - a.similarity || a.id - b.id).slice(0, count);
}

module.exports = { buildNeighborhoods, select };
