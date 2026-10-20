import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
export interface Group { name: string; population: number; fatality: number }
export interface Intervention { day: number; multiplier: number }
export interface Parameters {
  sigma: number; gamma: number; exposed: number; infectious: number; betaMin: number; betaMax: number; betaCount: number;
  rhoMin: number; rhoMax: number; rhoCount: number; goldenIterations: number; rounds: number; deltaBeta: number; deltaGamma: number;
  alpha: number; chi: number; psi: number; omega: number; iterations: number; holdout: number; effectWidth: number; outlier: number;
  deathLag: number; milestones: number[]; generation: number; horizon: number; threshold: number;
}
const readLines = (name: string) => readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);
export function readInputs() {
  const rows = readLines('cases.csv').slice(1).map(line => line.split(',').map(Number));
  const groups: Group[] = [], contacts: number[][] = [];
  for (const line of readLines('population.txt')) {
    const f = line.split(' ');
    if (f[0] === 'group') groups.push({ name: f[1], population: Number(f[2]), fatality: Number(f[3]) });
    else contacts.push(f.slice(1).map(Number));
  }
  const interventions: Intervention[] = readLines('interventions.txt').map(line => {
    const [day, multiplier] = line.split(' ').map(Number); return { day, multiplier };
  });
  const settings = new Map<string, number[]>(), scenarios: { name: string; multiplier: number }[] = [];
  const contactChanges: { name: string; group: string; factor: number }[] = [];
  for (const line of readLines('params.txt')) {
    const [key, ...fields] = line.split(' ');
    if (key === 'scenario') scenarios.push({ name: fields[0], multiplier: Number(fields[1]) });
    else if (key === 'contact_change') contactChanges.push({ name: fields[0], group: fields[1], factor: Number(fields[2]) });
    else settings.set(key, fields.map(Number));
  }
  const get = (name: string) => settings.get(name)!;
  const [betaMin, betaMax, betaCount] = get('beta_grid'), [rhoMin, rhoMax, rhoCount] = get('rho_grid');
  const [goldenIterations, rounds] = get('golden'), [deltaBeta, deltaGamma] = get('simplex');
  const [alpha, chi, psi, omega, iterations] = get('nelder_mead'), [exposed, infectious] = get('initial');
  const params: Parameters = { sigma: get('sigma')[0], gamma: get('gamma')[0], exposed, infectious, betaMin, betaMax, betaCount,
    rhoMin, rhoMax, rhoCount, goldenIterations, rounds, deltaBeta, deltaGamma, alpha, chi, psi, omega, iterations,
    holdout: get('holdout')[0], effectWidth: get('effect_width')[0], outlier: get('outlier')[0], deathLag: get('death_lag')[0],
    milestones: get('milestones'), generation: get('generation')[0], horizon: get('horizon')[0], threshold: get('threshold')[0] };
  return { cases: rows.map(r => r[1]), deaths: rows.map(r => r[2]), groups, contacts, interventions, params, scenarios, contactChanges };
}
export function writeOutputs(files: Record<string, string[]>): void {
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(files)) writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}
