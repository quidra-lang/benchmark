import { floorDiv, type Fraction } from './units.ts';
import type { Category, Forecast, Observation } from './main.ts';
import type { TimelineHour } from './taf.ts';

export const CATEGORIES: Category[] = ['VFR', 'MVFR', 'IFR', 'LIFR'];
export interface Choice {
  observation: Observation;
  taf: Forecast;
  forecast: TimelineHour;
  hit: boolean;
  temporaryHit: boolean;
}
export interface Analysis {
  table: number[][];
  rows: number[];
  columns: number[];
  total: number;
  noForecast: number;
  choices: Choice[];
  buckets: { hits: number; pairs: number }[];
  metrics: { pod: Fraction; far: Fraction }[];
  hitRate: Fraction;
  temporaryHitRate: Fraction;
  skill: Fraction;
}
export function covers(taf: Forecast, observation: Observation): boolean {
  const hour = observation.time - (observation.time % 60);
  return taf.time <= observation.time && taf.start <= hour && hour < taf.end;
}
export function select(tafs: Forecast[], observation: Observation): Forecast | null {
  let selected: Forecast | null = null;
  for (const taf of tafs) {
    if (
      covers(taf, observation) &&
      (selected === null ||
        taf.time > selected.time ||
        (taf.time === selected.time && taf.number > selected.number))
    ) {
      selected = taf;
    }
  }
  return selected;
}
export function analyze(observations: Observation[], tafs: Forecast[]): Analysis {
  const table = Array.from({ length: 4 }, () => [0, 0, 0, 0]);
  const buckets = Array.from({ length: 5 }, () => ({ hits: 0, pairs: 0 }));
  const choices: Choice[] = [];
  let noForecast = 0;
  let hits = 0;
  let temporaryHits = 0;
  for (const observation of observations) {
    const hour = observation.time - (observation.time % 60);
    const category = observation.main.category;
    for (const taf of tafs) {
      if (!covers(taf, observation)) continue;
      const bucket = buckets[floorDiv(hour - taf.start, 360)];
      bucket.pairs++;
      if (taf.timeline.get(hour)!.prevailing.category === category) bucket.hits++;
    }
    const chosen = select(tafs, observation);
    if (chosen === null) {
      noForecast++;
      continue;
    }
    const forecast = chosen.timeline.get(hour)!;
    const forecastCategory = forecast.prevailing.category;
    const hit = forecastCategory === category;
    const temporaryHit =
      hit || forecast.temporary.some((change) => change.state.category === category);
    table[CATEGORIES.indexOf(forecastCategory)][CATEGORIES.indexOf(category)]++;
    if (hit) hits++;
    if (temporaryHit) temporaryHits++;
    choices.push({ observation, taf: chosen, forecast, hit, temporaryHit });
  }
  const rows = table.map((row) => row.reduce((sum, count) => sum + count, 0));
  const columns = CATEGORIES.map((_, index) => table.reduce((sum, row) => sum + row[index], 0));
  const total = rows.reduce((sum, count) => sum + count, 0);
  let expected = 0;
  for (let index = 0; index < 4; index++) expected += rows[index] * columns[index];
  const metrics = CATEGORIES.map((_, index): Analysis['metrics'][number] => ({
    pod: [table[index][index], columns[index]],
    far: [rows[index] - table[index][index], rows[index]],
  }));
  return {
    table,
    rows,
    columns,
    total,
    noForecast,
    choices,
    buckets,
    metrics,
    hitRate: [hits, total],
    temporaryHitRate: [temporaryHits, total],
    skill: [total * hits - expected, total * total - expected],
  };
}
