import type { Match } from './season.ts';
import type { HomeRatings } from './linear_models.ts';
export interface ODRatings { offense: number[]; defense: number[]; values: number[] }
export function fitBradleyTerry(n: number, matches: Match[], iterations: number): HomeRatings {
  let strengths: number[] = Array(n).fill(1), home = 1;
  const wins: number[] = Array(n).fill(0);
  let homeWins = 0;
  for (const m of matches) { wins[m.home] += m.result; wins[m.away] += 1 - m.result; homeWins += m.result; }
  for (let iteration = 0; iteration < iterations; iteration++) {
    const denominators: number[] = Array(n).fill(0);
    for (const m of matches) {
      const q = home * strengths[m.home] + strengths[m.away];
      denominators[m.home] += home / q; denominators[m.away] += 1 / q;
    }
    strengths = wins.map((w, i) => w / denominators[i]);
    let total = 0;
    for (const s of strengths) total += s;
    strengths = strengths.map(s => s * n / total);
    let denominator = 0;
    for (const m of matches) denominator += strengths[m.home] / (home * strengths[m.home] + strengths[m.away]);
    home = homeWins / denominator;
  }
  return { values: strengths, home };
}
export function fitOffenseDefense(n: number, matches: Match[], iterations: number): ODRatings {
  const matrix: number[][] = Array.from({ length: n }, () => Array(n).fill(0));
  for (const m of matches) { matrix[m.home][m.away] += m.awayScore; matrix[m.away][m.home] += m.homeScore; }
  const defense: number[] = Array(n).fill(1);
  let offense: number[] = Array(n).fill(0);
  for (let iteration = 0; iteration < iterations; iteration++) {
    offense = Array(n).fill(0);
    for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) offense[j] += matrix[i][j] / defense[i];
    for (let i = 0; i < n; i++) {
      let value = 0;
      for (let j = 0; j < n; j++) value += matrix[i][j] / offense[j];
      defense[i] = value;
    }
  }
  return { offense, defense, values: offense.map((o, i) => o / defense[i]) };
}
