import { csvRows, compareIds, type Item } from './items.ts';
import { ceilRatio } from './report.ts';
export interface BomRow {
  parent: string;
  child: string;
  quantity: number;
  scrap: number;
}
export function need(row: BomRow, quantity: number): number {
  return ceilRatio(quantity * row.quantity * (100 + row.scrap), 100);
}
function cyclePath(items: Map<string, Item>, start: string, target: string): string[] | null {
  const visited = new Set<string>();
  function visit(id: string): string[] | null {
    if (id === target) return [id];
    visited.add(id);
    for (const row of items.get(id)!.children) {
      if (visited.has(row.child)) continue;
      const path = visit(row.child);
      if (path) return [id, ...path];
    }
    return null;
  }
  return visit(start);
}
export function loadBom(path: string, items: Map<string, Item>, errors: string[]): void {
  for (const {
    line,
    fields: [parent, child, q, s],
  } of csvRows(path)) {
    const quantity = Number(q);
    const scrap = Number(s);
    const parentItem = items.get(parent);
    const childItem = items.get(child);
    let error: string | null = null;
    if (!parentItem) error = `unknown item ${parent}`;
    else if (!childItem) error = `unknown item ${child}`;
    else if (quantity < 1) error = `bad quantity ${quantity}`;
    else if (scrap > 50) error = `bad scrap ${scrap}`;
    else if (parent === child) error = `cycle ${parent} -> ${parent}`;
    else if (parentItem.children.some((r) => r.child === child)) {
      error = `duplicate ${parent} -> ${child}`;
    } else {
      const cycle = cyclePath(items, child, parent);
      if (cycle) error = `cycle ${parent} -> ${cycle.join(' -> ')}`;
    }
    if (error) {
      errors.push(`bom.csv line ${line}: ${error}`);
      continue;
    }
    const row = { parent, child, quantity, scrap };
    parentItem!.children.push(row);
    parentItem!.children.sort((a, b) => compareIds(a.child, b.child));
    childItem!.parents.push(row);
  }
  for (const item of items.values()) item.parents.sort((a, b) => compareIds(a.parent, b.parent));
}
export function computeStructure(items: Map<string, Item>): Item[] {
  function lowLevel(item: Item): number {
    if (item.lowLevel >= 0) return item.lowLevel;
    let level = 0;
    for (const row of item.parents) level = Math.max(level, lowLevel(items.get(row.parent)!) + 1);
    return (item.lowLevel = level);
  }
  function cumulative(item: Item): number {
    if (item.cumulativeLead >= 0) return item.cumulativeLead;
    let longest = 0;
    for (const row of item.children) longest = Math.max(longest, cumulative(items.get(row.child)!));
    return (item.cumulativeLead = item.leadTime + longest);
  }
  for (const item of items.values()) {
    lowLevel(item);
    cumulative(item);
  }
  return [...items.values()].sort((a, b) => a.lowLevel - b.lowLevel || compareIds(a.id, b.id));
}
