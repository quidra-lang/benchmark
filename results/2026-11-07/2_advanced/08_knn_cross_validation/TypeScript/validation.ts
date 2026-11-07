import type { Model, Row, ScalingMethod, TrainingRow } from './dataset.ts';
import { fitScaling, transform, type Scaling } from './scaling.ts';
import { compareText, neighborOrder, vote, type Neighbor, type Reference } from './neighbors.ts';
export function stratifiedSplit(rows: TrainingRow[], count: number): TrainingRow[][] {
  const sorted = [...rows].sort((a, b) => compareText(a.label, b.label) || compareText(a.id, b.id));
  const assignments = new Map(sorted.map((row, i) => [row.id, i % count]));
  return Array.from({ length: count }, (_, i) =>
    rows.filter((row) => assignments.get(row.id) === i),
  );
}
export class Predictor {
  private scalings = new Map<ScalingMethod, { scaling: Scaling; reference: Reference[] }>();
  private orders = new Map<string, Map<string, Neighbor[]>>();
  constructor(
    private rows: TrainingRow[],
    private features = rows[0].features.map((_, i) => i),
  ) {}
  order(query: Row, model: Model): Neighbor[] {
    let fitted = this.scalings.get(model.scaling);
    if (!fitted) {
      const scaling = fitScaling(this.rows, model.scaling);
      fitted = {
        scaling,
        reference: this.rows.map((row) => ({
          row,
          vector: transform(row, scaling, this.features),
        })),
      };
      this.scalings.set(model.scaling, fitted);
    }
    const key = `${model.scaling}:${model.metric}`;
    let orders = this.orders.get(key);
    if (!orders) {
      orders = new Map();
      this.orders.set(key, orders);
    }
    let order = orders.get(query.id);
    if (!order) {
      order = neighborOrder(
        fitted.reference,
        transform(query, fitted.scaling, this.features),
        model.metric,
      );
      orders.set(query.id, order);
    }
    return order;
  }
  predict(query: Row, model: Model) {
    return vote(this.order(query, model), model.k, model.weighting);
  }
}
export interface Regression {
  count: number;
  rmse: number | null;
  mae: number | null;
  r2: number | null;
}
export function regression(pairs: { target: number; estimate: number }[]): Regression {
  if (!pairs.length) return { count: 0, rmse: null, mae: null, r2: null };
  let squared = 0;
  let absolute = 0;
  let total = 0;
  for (const pair of pairs) {
    const error = pair.estimate - pair.target;
    squared += error * error;
    absolute += Math.abs(error);
    total += pair.target;
  }
  const mean = total / pairs.length;
  let variation = 0;
  for (const pair of pairs) {
    const delta = pair.target - mean;
    variation += delta * delta;
  }
  return {
    count: pairs.length,
    rmse: Math.sqrt(squared / pairs.length),
    mae: absolute / pairs.length,
    r2: variation === 0 ? null : 1 - squared / variation,
  };
}
