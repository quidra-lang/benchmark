import type { Order } from './transactions.ts';

export const FEATURES = ['recency', 'frequency', 'monetary', 'basket', 'categories', 'tenure'];
export const SQUARE_ROOT = new Set([1, 2, 3]);
export interface Customer {
  id: string;
  purchases: Order[];
  spend: number;
  categorySpend: Map<string, number>;
  raw: number[];
  transformed: number[];
  point: number[];
}
export interface Scaling {
  mean: number;
  sd: number;
  rawMean: number;
  rawSD: number;
}
const transformValues = (values: number[]) =>
  values.map((value, index) => (SQUARE_ROOT.has(index) ? Math.sqrt(value) : value));

export function meanSD(values: number[]) {
  let total = 0;
  for (const value of values) total += value;
  const mean = total / values.length;
  let squared = 0;
  for (const value of values) {
    const difference = value - mean;
    squared += difference * difference;
  }
  return { mean, sd: values.length === 1 ? 0 : Math.sqrt(squared / (values.length - 1)) };
}

export function customerFeatures(orders: Order[], day: number): Customer[] {
  const groups = new Map<string, Order[]>();
  for (const order of orders) {
    if (order.net <= 0) continue;
    const purchases = groups.get(order.customer) ?? [];
    purchases.push(order);
    groups.set(order.customer, purchases);
  }
  return [...groups.keys()].sort().map((id) => {
    const purchases = groups.get(id)!;
    const categorySpend = new Map<string, number>();
    let first = purchases[0].day;
    let last = first;
    let spend = 0;
    for (const order of purchases) {
      first = Math.min(first, order.day);
      last = Math.max(last, order.day);
      spend += order.net;
      for (const row of order.rows) {
        categorySpend.set(row.category, (categorySpend.get(row.category) ?? 0) + row.amount);
      }
    }
    const monetary = spend / 100;
    const frequency = purchases.length;
    const raw = [
      day - last,
      frequency,
      monetary,
      monetary / frequency,
      [...categorySpend.values()].filter((value) => value > 0).length,
      day - first,
    ];
    return {
      id,
      purchases,
      spend,
      categorySpend,
      raw,
      transformed: transformValues(raw),
      point: [],
    };
  });
}

export function fitStandardization(customers: Customer[]): Scaling[] {
  return FEATURES.map((_, feature) => {
    const raw = meanSD(customers.map((customer) => customer.raw[feature]));
    return {
      ...meanSD(customers.map((customer) => customer.transformed[feature])),
      rawMean: raw.mean,
      rawSD: raw.sd,
    };
  });
}

export function standardize(customers: Customer[], scaling: Scaling[]) {
  for (const customer of customers) {
    customer.point = customer.transformed.map((value, feature) =>
      scaling[feature].sd === 0 ? 0 : (value - scaling[feature].mean) / scaling[feature].sd,
    );
  }
}

export function correlation(customers: Customer[]): number[][] {
  return FEATURES.map((_, first) =>
    FEATURES.map((__, second) => {
      let total = 0;
      for (const customer of customers) total += customer.point[first] * customer.point[second];
      return total / (customers.length - 1);
    }),
  );
}
