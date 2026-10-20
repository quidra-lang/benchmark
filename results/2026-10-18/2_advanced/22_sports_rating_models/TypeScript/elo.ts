import type { Match } from './season.ts';
export interface EloRecord { match: Match; index: number; expected: number; change: number }
export interface EloFit { values: number[]; records: EloRecord[]; rounds: Map<number, number[]> }
export function expected(home: number, away: number, advantage: number): number {
  return 1 / (1 + 10 ** ((away - home - advantage) / 400));
}
export function multiplier(match: Match, home: number, away: number, advantage: number): number {
  const margin = Math.abs(match.homeScore - match.awayScore);
  if (!margin) return 1;
  const difference = match.result === 1 ? home + advantage - away : away - home - advantage;
  return Math.log(margin + 1) * 2.2 / (0.001 * difference + 2.2);
}
export function fitElo(count: number, matches: Match[], coefficient: number, advantage: number, initial: number): EloFit {
  const values: number[] = Array(count).fill(initial);
  const records: EloRecord[] = [];
  const rounds = new Map<number, number[]>();
  for (const [index, match] of matches.entries()) {
    const home = values[match.home], away = values[match.away];
    const probability = expected(home, away, advantage);
    const change = coefficient * multiplier(match, home, away, advantage) * (match.result - probability);
    values[match.home] = home + change;
    values[match.away] = away - change;
    records.push({ match, index, expected: probability, change });
    rounds.set(match.round, values.slice());
  }
  return { values, records, rounds };
}
