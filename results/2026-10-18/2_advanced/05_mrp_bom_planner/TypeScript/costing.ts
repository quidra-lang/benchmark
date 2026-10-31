import { compareIds, type Item } from './items.ts';
import { roundRatio } from './report.ts';
export interface Cost {
  material: number;
  labor: number;
  total: number;
  usage: number;
  value: number;
  classification: 'A' | 'B' | 'C';
}
export function rollup(planning: Item[], gross: Map<string, number[]>): Map<string, Cost> {
  const costs = new Map<string, Cost>();
  for (const item of planning.slice().reverse()) {
    let material = item.material;
    let labor = item.labor;
    let usage = 0;
    for (const row of item.children) {
      const child = costs.get(row.child)!;
      const multiplier = row.quantity * (100 + row.scrap);
      material += roundRatio(multiplier * child.material, 100);
      labor += roundRatio(multiplier * child.labor, 100);
    }
    for (const quantity of gross.get(item.id)!) usage += quantity;
    const total = material + labor;
    costs.set(item.id, {
      material,
      labor,
      total,
      usage,
      value: usage * total,
      classification: 'C',
    });
  }
  const ranked = planning
    .slice()
    .sort((a, b) => costs.get(b.id)!.value - costs.get(a.id)!.value || compareIds(a.id, b.id));
  let totalValue = 0;
  let previous = 0;
  for (const cost of costs.values()) totalValue += cost.value;
  for (const item of ranked) {
    const cost = costs.get(item.id)!;
    if (cost.value > 0) {
      if (100 * previous < 80 * totalValue) cost.classification = 'A';
      else if (100 * previous < 95 * totalValue) cost.classification = 'B';
    }
    previous += cost.value;
  }
  return costs;
}
