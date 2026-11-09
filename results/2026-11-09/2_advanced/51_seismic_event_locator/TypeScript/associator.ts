import type { Pick } from './picker.ts';
export interface Candidate {
  number: number;
  first: Pick;
  picks: Pick[];
}
export function associate(picks: Pick[], window: number, minimum: number) {
  const candidates: Candidate[] = [];
  for (let i = 0; i < picks.length; i++) {
    const first = picks[i];
    if (first.candidate !== null) continue;
    const stations = new Set<number>();
    const selected: Pick[] = [];
    for (let j = i; j < picks.length && picks[j].sample <= first.sample + window; j++) {
      const pick = picks[j];
      if (pick.candidate !== null || stations.has(pick.station.index)) continue;
      stations.add(pick.station.index);
      selected.push(pick);
    }
    if (selected.length < minimum) continue;
    const number = candidates.length + 1;
    for (const pick of selected) pick.candidate = number;
    candidates.push({ number, first, picks: selected });
  }
  return candidates;
}
