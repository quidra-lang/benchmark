import type { FMIndex } from './fm_index.ts';

export function lowerBound(sequence: string, reverse: FMIndex): number[] {
  const bounds: number[] = [];
  let mismatches = 0, lo = 0, hi = reverse.text.length;
  for (const base of sequence) {
    [lo, hi] = reverse.extend(lo, hi, base);
    if (lo >= hi) { mismatches++; lo = 0; hi = reverse.text.length; }
    bounds.push(mismatches);
  }
  return bounds;
}

export function backtrack(sequence: string, maximum: number, forward: FMIndex, reverse: FMIndex) {
  const bounds = lowerBound(sequence, reverse);
  const stack: [number, number, number, number][] = [[sequence.length - 1, maximum, 0, forward.text.length]];
  const leaves: { lo: number; hi: number; mismatches: number }[] = [];
  let nodes = 0, hits = 0;
  while (stack.length) {
    const [i, remaining, lo, hi] = stack.pop()!;
    nodes++;
    if (remaining < (i < 0 ? 0 : bounds[i])) continue;
    if (i === -1) {
      leaves.push({ lo, hi, mismatches: maximum - remaining });
      hits += hi - lo;
      continue;
    }
    for (const base of 'TGCA') {
      const [nextLo, nextHi] = forward.extend(lo, hi, base);
      if (nextLo >= nextHi) continue;
      if (base === sequence[i]) stack.push([i - 1, remaining, nextLo, nextHi]);
      else if (remaining >= 1) stack.push([i - 1, remaining - 1, nextLo, nextHi]);
    }
  }
  return { nodes, leaves, hits };
}
