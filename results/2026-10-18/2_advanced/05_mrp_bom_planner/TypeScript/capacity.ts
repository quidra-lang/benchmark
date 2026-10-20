import { csvRows, compareIds, type Item } from './items.ts';
import { floorRatio } from './report.ts';
export interface Center { id: string; minutes: number; efficiency: number; available: number; description: string }
export interface Operation { operation: number; center: string; setup: number; run: number }
export function loadCenters(path: string, errors: string[]): Map<string, Center> {
  const centers = new Map<string, Center>();
  for (const { line, fields: [id, minutesText, efficiencyText, description] } of csvRows(path)) {
    const minutes = Number(minutesText), efficiency = Number(efficiencyText);
    if (centers.has(id)) errors.push(`workcenters.csv line ${line}: duplicate center ${id}`);
    else if (efficiency < 50 || efficiency > 150) errors.push(`workcenters.csv line ${line}: bad efficiency ${efficiency}`);
    else centers.set(id, { id, minutes, efficiency, available: floorRatio(minutes * efficiency, 100), description });
  }
  return centers;
}
export function loadRoutings(path: string, items: Map<string, Item>, centers: Map<string, Center>, errors: string[]): void {
  for (const { line, fields: [id, operationText, center, setupText, runText] } of csvRows(path)) {
    const operation = Number(operationText), setup = Number(setupText), run = Number(runText), item = items.get(id);
    if (!item) errors.push(`routings.csv line ${line}: unknown item ${id}`);
    else if (!centers.has(center)) errors.push(`routings.csv line ${line}: unknown center ${center}`);
    else if (item.children.length === 0) errors.push(`routings.csv line ${line}: purchased item ${id}`);
    else if (run < 1) errors.push(`routings.csv line ${line}: bad run time ${run}`);
    else if (item.routing.some(r => r.operation === operation)) errors.push(`routings.csv line ${line}: duplicate ${id} operation ${operation}`);
    else item.routing.push({ operation, center, setup, run });
  }
  for (const item of items.values()) item.routing.sort((a, b) => a.operation - b.operation);
}
export const operationWeek = (receipt: number, leadTime: number, index: number, count: number): number => Math.max(1, receipt - leadTime + floorRatio(index * leadTime, count));
export function levelLoad(load: number[], available: number): { leveled: number[]; backlog: number } {
  const leveled: number[] = Array(load.length).fill(0); let carry = 0;
  for (let week = load.length - 1; week >= 2; week--) { const x = load[week] + carry; leveled[week] = Math.min(x, available); carry = x - leveled[week]; }
  leveled[1] = load[1] + carry;
  return { leveled, backlog: Math.max(0, leveled[1] - available) };
}
export const orderedCenters = (centers: Map<string, Center>): Center[] => [...centers.values()].sort((a, b) => compareIds(a.id, b.id));
