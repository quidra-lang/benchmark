import type { Row, ScalingMethod, TrainingRow } from './dataset.ts';
export interface Scaling { centers: number[]; scales: number[] }
export function fitScaling(rows: TrainingRow[], method: ScalingMethod): Scaling {
  const centers: number[] = [], scales: number[] = [];
  for (let j = 0; j < rows[0].features.length; j++) {
    let center: number, scale: number;
    if (method === 'standard') {
      let total = 0;
      for (const row of rows) total += row.features[j];
      center = total / rows.length;
      let squared = 0;
      for (const row of rows) { const delta = row.features[j] - center; squared += delta * delta; }
      scale = rows.length === 1 ? 0 : Math.sqrt(squared / (rows.length - 1));
    } else {
      let low = rows[0].features[j], high = low;
      for (const row of rows) { low = Math.min(low, row.features[j]); high = Math.max(high, row.features[j]); }
      center = low; scale = high - low;
    }
    centers.push(center); scales.push(scale);
  }
  return { centers, scales };
}
export function transform(row: Row, scaling: Scaling, features: number[]): number[] {
  return features.map(j => scaling.scales[j] > 0 ? (row.features[j] - scaling.centers[j]) / scaling.scales[j] : 0);
}
