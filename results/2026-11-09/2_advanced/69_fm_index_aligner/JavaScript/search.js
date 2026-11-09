'use strict';

function lowerBound(sequence, reverse) {
  const D = [];
  let z = 0, lo = 0, hi = reverse.text.length;
  for (const base of sequence) {
    [lo, hi] = reverse.extend(lo, hi, base);
    if (lo >= hi) { z++; lo = 0; hi = reverse.text.length; }
    D.push(z);
  }
  return D;
}

function backtrack(sequence, maximum, forward, reverse) {
  const D = lowerBound(sequence, reverse), stack = [[sequence.length - 1, maximum, 0, forward.text.length]];
  const leaves = [];
  let nodes = 0, hits = 0;
  while (stack.length) {
    const [i, z, lo, hi] = stack.pop(); nodes++;
    if (z < (i < 0 ? 0 : D[i])) continue;
    if (i === -1) { leaves.push({ lo, hi, mismatches: maximum - z }); hits += hi - lo; continue; }
    for (const base of 'TGCA') {
      const [nextLo, nextHi] = forward.extend(lo, hi, base);
      if (nextLo >= nextHi) continue;
      if (base === sequence[i]) stack.push([i - 1, z, nextLo, nextHi]);
      else if (z >= 1) stack.push([i - 1, z - 1, nextLo, nextHi]);
    }
  }
  return { nodes, leaves, hits };
}

module.exports = { lowerBound, backtrack };
