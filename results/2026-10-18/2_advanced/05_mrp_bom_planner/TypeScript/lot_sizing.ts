import type { Item } from './items.ts';
import { ceilRatio } from './report.ts';
export function lotSize(item: Item, net: number, available: number, week: number, gross: number[], receipts: number[], horizon: number): number {
  const lot = item.lot;
  if (lot.rule === 'LFL') return net;
  if (lot.rule === 'FOQ') return ceilRatio(net, lot.fixed) * lot.fixed;
  if (lot.rule === 'MIN') return ceilRatio(Math.max(net, lot.minimum), lot.multiple) * lot.multiple;
  let balance = available, quantity = net;
  for (let u = week + 1; u <= Math.min(week + lot.periods - 1, horizon); u++) { balance += receipts[u] - gross[u]; quantity = Math.max(quantity, item.safety - balance); }
  return quantity;
}
