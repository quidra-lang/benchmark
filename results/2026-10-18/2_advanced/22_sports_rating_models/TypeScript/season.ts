import { readFileSync } from 'node:fs';

export interface Team { id: string; name: string }
export interface Match { round: number; home: number; away: number; homeScore: number; awayScore: number; result: number }
export interface Settings {
  winPoints: number; drawPoints: number; formLength: number; closeMargin: number; exponent: number;
  eloK: number; eloHome: number; eloInitial: number; gridK: number[]; gridHome: number[];
  btIterations: number; odIterations: number; linkIterations: number; holdout: number; upsets: number;
  bins: number; simulations: number; seed: number; top: number; bottom: number;
}
export interface Season { teams: Team[]; matches: Match[]; rounds: number; settings: Settings }
export function result(home: number, away: number): number { return home > away ? 1 : home < away ? 0 : 0.5; }
export function beforeRound(matches: Match[], round: number): Match[] { return matches.filter(m => m.round < round); }
export function readSeason(): Season {
  const lines = (path: string) => readFileSync(path, 'ascii').trimEnd().split('\n');
  const teams = lines('input/teams.csv').slice(1).map(line => { const [id, name] = line.split(','); return { id, name }; });
  const indices = new Map(teams.map((team, i) => [team.id, i]));
  const matches = lines('input/matches.csv').slice(1).map(line => {
    const [round, home, away, hs, as] = line.split(',');
    return { round: +round, home: indices.get(home)!, away: indices.get(away)!, homeScore: +hs, awayScore: +as, result: result(+hs, +as) };
  }).sort((a, b) => a.round - b.round);
  const params = new Map(lines('input/params.txt').map(line => { const [key, ...v] = line.split(' '); return [key, v.map(Number)]; }));
  const p = (key: string) => params.get(key)![0];
  const settings: Settings = {
    winPoints: p('WIN_POINTS'), drawPoints: p('DRAW_POINTS'), formLength: p('FORM_LENGTH'), closeMargin: p('CLOSE_MARGIN'),
    exponent: p('PYTHAGOREAN_EXPONENT'), eloK: p('ELO_K'), eloHome: p('ELO_HOME'), eloInitial: p('ELO_INITIAL'),
    gridK: params.get('ELO_GRID_K')!, gridHome: params.get('ELO_GRID_HOME')!, btIterations: p('BT_ITERATIONS'),
    odIterations: p('OD_ITERATIONS'), linkIterations: p('LINK_ITERATIONS'), holdout: p('HOLDOUT_ROUND'),
    upsets: p('UPSETS'), bins: p('CALIBRATION_BINS'), simulations: p('SIMULATIONS'), seed: p('SIM_SEED'),
    top: p('TOP_POSITIONS'), bottom: p('BOTTOM_POSITIONS'),
  };
  return { teams, matches, rounds: matches[matches.length - 1].round, settings };
}
