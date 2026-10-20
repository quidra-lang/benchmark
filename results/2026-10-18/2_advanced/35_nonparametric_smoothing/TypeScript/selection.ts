export function crossValidation(actual: number[], predictions: (number | null)[]): number | null {
  let total = 0;
  for (let i = 0; i < actual.length; i++) { const p = predictions[i]; if (p === null) return null; const e = actual[i] - p; total += e * e; }
  return total / actual.length;
}
export function generalized(actual: number[], fitted: number[], edf: number): number {
  let rss = 0; for (let i = 0; i < actual.length; i++) { const e = actual[i] - fitted[i]; rss += e * e; }
  const tau = 1 - edf / actual.length; return rss / actual.length / (tau * tau);
}
export function choose(candidates: { score: number | null }[]): number {
  let best = -1;
  for (let i = 0; i < candidates.length; i++) { const s = candidates[i].score; if (s !== null && (best < 0 || s < candidates[best].score!)) best = i; }
  return best;
}
