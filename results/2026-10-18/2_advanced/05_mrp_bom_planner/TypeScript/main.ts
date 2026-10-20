import { readLines, csvRows, compareIds, loadItems, type Item, type Requirement } from './items.ts';
import { need, loadBom, computeStructure } from './bom.ts';
import { lotSize } from './lot_sizing.ts';
import { loadCenters, loadRoutings, operationWeek, levelLoad, orderedCenters, type Center } from './capacity.ts';
import { rollup, type Cost } from './costing.ts';
import { money, percentage, tableRow, writeReports } from './report.ts';

interface Inquiry extends Requirement { id: string }
type Demand = (Requirement & { kind: 'MPS' }) | (Requirement & { kind: 'ORDER'; order: string })
  | { kind: 'DEPENDENT'; item: string; week: number; quantity: number; parent: string; parentOrder: number };
interface Safety { kind: 'SAFETY'; item: string; week: number; quantity: number }
interface Root { kind: 'MPS' | 'ORDER' | 'SAFETY'; item: string; week: number; order: string }
interface Allocation { demand: Demand | Safety; share: number }
interface Supply { quantity: number; excess: number; allocations: Allocation[] }
interface ReceiptSupply extends Supply { kind: 'RECEIPT'; line: number; receipt: number }
interface PlannedOrder extends Supply { kind: 'PLANNED'; item: string; number: number; receipt: number; originalRelease: number; release: number; roots: Root[] }
interface ItemPlan {
  item: Item; gross: number[]; scheduled: number[]; onHand: number[]; net: number[]; plannedReceipt: number[]; plannedRelease: number[];
  demands: Demand[]; orders: PlannedOrder[]; pastDue: number; stock: Supply | null; receiptSupplies: ReceiptSupply[];
}
interface Plan { items: Map<string, ItemPlan>; loads: Map<string, number[]> }
interface Placement { inquiry: Inquiry; week: number }
interface PromiseResult { inquiry: Inquiry; week: number | null; material: number | null; reason: string | null; status: 'on_time' | 'late' | 'rejected' }
interface Planning { base: Plan; final: Plan; results: PromiseResult[] }
function total(values: number[]): number { let result = 0; for (const value of values) result += value; return result; }
function readParameters() {
  const lines = readLines('input/params.txt');
  return { horizon: Number(lines[0].split(' ')[1]), peg: lines[1].split(' ').slice(1), treeQuantity: Number(lines[2].split(' ')[1]) };
}
function readRequirements(filename: string, items: Map<string, Item>, horizon: number, errors: string[], unique: boolean): Requirement[] {
  const accepted: Requirement[] = [], pairs = new Set<string>();
  for (const { line, fields: [item, weekText, quantityText] } of csvRows(`input/${filename}`)) {
    const week = Number(weekText), quantity = Number(quantityText), key = `${item}:${week}`;
    let error: string | null = null;
    if (!items.has(item)) error = `unknown item ${item}`;
    else if (week < 1 || week > horizon) error = `week ${week} outside horizon`;
    else if (quantity < 1) error = `bad quantity ${quantity}`;
    else if (unique && pairs.has(key)) error = `duplicate ${item} week ${week}`;
    if (error) errors.push(`${filename} line ${line}: ${error}`);
    else { accepted.push({ item, week, quantity, line }); pairs.add(key); }
  }
  return accepted;
}
function readInquiries(items: Map<string, Item>, horizon: number, errors: string[]): Inquiry[] {
  const inquiries: Inquiry[] = [], seen = new Set<string>();
  for (const { line, fields: [id, item, quantityText, weekText] } of csvRows('input/orders.csv')) {
    const quantity = Number(quantityText), week = Number(weekText);
    let error: string | null = null;
    if (seen.has(id)) error = `duplicate order ${id}`;
    else if (!items.has(item)) error = `unknown item ${item}`;
    else if (week < 1 || week > horizon) error = `week ${week} outside horizon`;
    else if (quantity < 1) error = `bad quantity ${quantity}`;
    if (error) errors.push(`orders.csv line ${line}: ${error}`);
    else { inquiries.push({ id, item, quantity, week, line }); seen.add(id); }
  }
  return inquiries;
}
function loadInput() {
  const parameters = readParameters(), errors: string[] = [], items = loadItems('input/items.csv', errors);
  loadBom('input/bom.csv', items, errors);
  const centerMap = loadCenters('input/workcenters.csv', errors);
  loadRoutings('input/routings.csv', items, centerMap, errors);
  const mps = readRequirements('mps.csv', items, parameters.horizon, errors, true);
  const receipts = readRequirements('receipts.csv', items, parameters.horizon, errors, false);
  const inquiries = readInquiries(items, parameters.horizon, errors);
  for (const row of receipts) items.get(row.item)!.receipts.push(row);
  for (const item of items.values()) item.receipts.sort((a, b) => a.week - b.week || a.line - b.line);
  return { ...parameters, errors, items, mps, inquiries, planning: computeStructure(items), centers: orderedCenters(centerMap),
    orderedItems: [...items.values()].sort((a, b) => compareIds(a.id, b.id)) };
}
type Input = ReturnType<typeof loadInput>;
function emptyItemPlan(item: Item, horizon: number): ItemPlan {
  const zeros = (): number[] => Array(horizon + 1).fill(0);
  const plan: ItemPlan = { item, gross: zeros(), scheduled: zeros(), onHand: zeros(), net: zeros(), plannedReceipt: zeros(), plannedRelease: zeros(),
    demands: [], orders: [], pastDue: 0, stock: null, receiptSupplies: [] };
  plan.onHand[0] = item.onHand;
  for (const receipt of item.receipts) plan.scheduled[receipt.week] += receipt.quantity;
  return plan;
}
function totalLoads(data: Input, plan: Plan): Map<string, number[]> {
  const loads = new Map<string, number[]>(data.centers.map(c => [c.id, Array(data.horizon + 1).fill(0)]));
  for (const item of data.planning) for (const order of plan.items.get(item.id)!.orders) item.routing.forEach((operation, index) => {
    const week = operationWeek(order.receipt, item.leadTime, index, item.routing.length);
    loads.get(operation.center)![week] += operation.setup + order.quantity * operation.run;
  });
  return loads;
}
function runMrp(data: Input, promised: Placement[]): Plan {
  const plan: Plan = { items: new Map(), loads: new Map() };
  for (const item of data.planning) plan.items.set(item.id, emptyItemPlan(item, data.horizon));
  for (const row of data.mps) plan.items.get(row.item)!.demands.push({ ...row, kind: 'MPS' });
  for (const { inquiry, week } of promised) plan.items.get(inquiry.item)!.demands.push({
    kind: 'ORDER', order: inquiry.id, item: inquiry.item, quantity: inquiry.quantity, line: inquiry.line, week,
  });
  for (const item of data.planning) {
    const grid = plan.items.get(item.id)!;
    for (const demand of grid.demands) grid.gross[demand.week] += demand.quantity;
    for (let week = 1; week <= data.horizon; week++) {
      const available = grid.onHand[week - 1] + grid.scheduled[week] - grid.gross[week];
      if (available >= item.safety) { grid.onHand[week] = available; continue; }
      const net = item.safety - available, quantity = lotSize(item, net, available, week, grid.gross, grid.scheduled, data.horizon);
      const originalRelease = week - item.leadTime, release = Math.max(1, originalRelease);
      grid.orders.push({ kind: 'PLANNED', item: item.id, number: grid.orders.length + 1, receipt: week, quantity, originalRelease, release,
        allocations: [], excess: quantity, roots: [] });
      grid.net[week] = net; grid.plannedReceipt[week] = quantity; grid.plannedRelease[release] += quantity; grid.onHand[week] = available + quantity;
      if (originalRelease < 1) grid.pastDue += quantity;
    }
    for (const order of grid.orders) for (const row of item.children) plan.items.get(row.child)!.demands.push({ kind: 'DEPENDENT', item: row.child,
      week: order.release, quantity: need(row, order.quantity), parent: item.id, parentOrder: order.number });
  }
  plan.loads = totalLoads(data, plan);
  return plan;
}
const overload = (plan: Plan, center: Center, week: number): number => Math.max(0, plan.loads.get(center.id)![week] - center.available);
function promiseInquiries(data: Input): Planning {
  const base = runMrp(data, []), promised: Placement[] = [], results: PromiseResult[] = [];
  let current = base;
  for (const inquiry of data.inquiries) {
    const result: PromiseResult = { inquiry, week: null, material: null, reason: null, status: 'rejected' };
    for (let week = inquiry.week; week <= data.horizon; week++) {
      const placement = { inquiry, week }, trial = runMrp(data, [...promised, placement]);
      let reason: string | null = null;
      for (const item of data.planning) if (trial.items.get(item.id)!.pastDue > current.items.get(item.id)!.pastDue) { reason = item.id; break; }
      if (reason === null) {
        if (result.material === null) result.material = week;
        for (const center of data.centers) {
          for (let t = 1; t <= data.horizon; t++) if (overload(trial, center, t) > overload(current, center, t)) { reason = `${center.id} week ${t}`; break; }
          if (reason !== null) break;
        }
      }
      if (week === inquiry.week) result.reason = reason;
      if (reason === null) { result.week = week; result.status = week === inquiry.week ? 'on_time' : 'late'; promised.push(placement); current = trial; break; }
    }
    results.push(result);
  }
  return { base, final: current, results };
}
function compareDemands(a: Demand, b: Demand): number {
  const rank = { MPS: 0, ORDER: 1, DEPENDENT: 2 }, first = a.week - b.week || rank[a.kind] - rank[b.kind];
  if (first) return first;
  if (a.kind === 'ORDER' && b.kind === 'ORDER') return a.line - b.line;
  if (a.kind === 'DEPENDENT' && b.kind === 'DEPENDENT') return compareIds(a.parent, b.parent) || a.parentOrder - b.parentOrder;
  return 0;
}
function compareRoots(a: Root, b: Root): number {
  const rank = { MPS: 0, ORDER: 1, SAFETY: 2 };
  return compareIds(a.item, b.item) || rank[a.kind] - rank[b.kind] || a.week - b.week || compareIds(a.order, b.order);
}
function allocateSupplies(data: Input, plan: Plan): void {
  for (const item of data.planning) {
    const grid = plan.items.get(item.id)!, demands: (Demand | Safety)[] = grid.demands.slice().sort(compareDemands);
    if (item.safety > 0) demands.unshift({ kind: 'SAFETY', item: item.id, week: 0, quantity: item.safety });
    const receipts: ReceiptSupply[] = item.receipts.map(r => ({ kind: 'RECEIPT', line: r.line, receipt: r.week, quantity: r.quantity, excess: r.quantity, allocations: [] }));
    const timed = [...receipts, ...grid.orders].sort((a, b) => a.receipt - b.receipt || (a.kind === 'RECEIPT' ? 0 : 1) - (b.kind === 'RECEIPT' ? 0 : 1)
      || (a.kind === 'RECEIPT' ? a.line : 0) - (b.kind === 'RECEIPT' ? b.line : 0));
    const stock: Supply | null = item.onHand > 0 ? { quantity: item.onHand, excess: item.onHand, allocations: [] } : null;
    const supplies: Supply[] = stock ? [stock, ...timed] : timed;
    let index = 0;
    for (const demand of demands) {
      let remaining = demand.quantity;
      while (remaining > 0) {
        while (supplies[index].excess === 0) index++;
        const supply = supplies[index], share = Math.min(remaining, supply.excess);
        supply.allocations.push({ demand, share }); supply.excess -= share; remaining -= share;
      }
    }
    grid.stock = stock; grid.receiptSupplies = receipts;
    for (const order of grid.orders) {
      const roots = new Map<string, Root>();
      for (const { demand } of order.allocations) {
        const inherited: Root[] = demand.kind === 'DEPENDENT' ? plan.items.get(demand.parent)!.orders[demand.parentOrder - 1].roots
          : [{ kind: demand.kind, item: demand.item, week: demand.week, order: demand.kind === 'ORDER' ? demand.order : '' }];
        for (const root of inherited) roots.set(`${root.kind}:${root.item}:${root.week}:${root.order}`, root);
      }
      order.roots = [...roots.values()].sort(compareRoots);
    }
  }
}
function ruleLabel(item: Item): string {
  const lot = item.lot;
  return lot.rule === 'FOQ' ? `FOQ ${lot.fixed}` : lot.rule === 'POQ' ? `POQ ${lot.periods}` : lot.rule === 'MIN' ? `MIN ${lot.minimum}/${lot.multiple}` : 'LFL';
}
function gridReport(data: Input, plan: Plan): string[] {
  const lines: string[] = [], weeks = Array.from({ length: data.horizon }, (_, i) => i + 1);
  for (const item of data.planning) {
    const g = plan.items.get(item.id)!;
    lines.push(`ITEM ${item.id} LLC ${item.lowLevel} LT ${item.leadTime} LOT ${ruleLabel(item)} SS ${item.safety} OH ${item.onHand} ${item.description}`, tableRow('WEEK', weeks, 6));
    const rows: [string, number[]][] = [['GROSS', g.gross], ['RECEIPTS', g.scheduled], ['ON_HAND', g.onHand], ['NET', g.net], ['PLAN_RCPT', g.plannedReceipt], ['PLAN_REL', g.plannedRelease]];
    for (const [label, values] of rows) lines.push(tableRow(label, values.slice(1), 6));
    lines.push(`TOTAL gross ${total(g.gross)} receipts ${total(g.scheduled)} planned ${total(g.plannedReceipt)} orders ${g.orders.length} ending ${g.onHand[data.horizon]}`);
  }
  return lines;
}
function whereUsed(lines: string[], data: Input, item: Item, depth: number, cumulative: number): void {
  for (const row of item.parents) { const extended = cumulative * row.quantity;
    lines.push(`${'.'.repeat(depth)}${depth} ${row.parent} qty ${row.quantity} ext ${extended}`);
    whereUsed(lines, data, data.items.get(row.parent)!, depth + 1, extended); }
}
function allocationLines(lines: string[], plan: Plan, supply: Supply, depth: number, recursive: boolean): void {
  for (const { demand: d, share } of supply.allocations) {
    let text: string;
    if (d.kind === 'SAFETY') text = `SAFETY ${d.item}`;
    else if (d.kind === 'MPS') text = `MPS ${d.item} week ${d.week}`;
    else if (d.kind === 'ORDER') text = `ORDER ${d.order} ${d.item} week ${d.week}`;
    else text = `${d.parent} order ${d.parentOrder} week ${d.week}`;
    lines.push(`${' '.repeat(2 * depth)}ALLOC ${share} ${text}`);
    if (recursive && d.kind === 'DEPENDENT') allocationLines(lines, plan, plan.items.get(d.parent)!.orders[d.parentOrder - 1], depth + 1, true);
  }
}
function excessLine(lines: string[], supply: Supply): void { if (supply.excess > 0) lines.push(`  EXCESS ${supply.excess}`); }
function peggingReport(data: Input, plan: Plan): string[] {
  const lines: string[] = [];
  for (const id of data.peg) {
    const item = data.items.get(id)!, grid = plan.items.get(id)!;
    lines.push(`PEG ${id} orders ${grid.orders.length}`); whereUsed(lines, data, item, 1, 1);
    if (grid.stock) { lines.push(`STOCK quantity ${item.onHand}`); allocationLines(lines, plan, grid.stock, 1, false); excessLine(lines, grid.stock); }
    for (const r of grid.receiptSupplies) { lines.push(`RECEIPT line ${r.line} week ${r.receipt} quantity ${r.quantity}`); allocationLines(lines, plan, r, 1, false); excessLine(lines, r); }
    for (const order of grid.orders) {
      lines.push(`ORDER ${order.number} receipt ${order.receipt} release ${order.release} quantity ${order.quantity}`);
      allocationLines(lines, plan, order, 1, true); excessLine(lines, order);
      for (const root of order.roots) lines.push(root.kind === 'SAFETY' ? `  ROOT SAFETY ${root.item}`
        : root.kind === 'MPS' ? `  ROOT MPS ${root.item} week ${root.week}` : `  ROOT ORDER ${root.order} ${root.item} week ${root.week}`);
    }
  }
  return lines;
}
function treeReport(data: Input): string[] {
  const lines: string[] = [];
  for (const top of data.orderedItems) {
    if (!top.children.length || top.parents.length) continue;
    const totals = new Map<string, number>();
    lines.push(`TREE ${top.id} quantity ${data.treeQuantity}`, `0 ${top.id} ext 1 gross ${data.treeQuantity} lt ${top.leadTime} cum ${top.cumulativeLead} ${top.description}`);
    function descend(item: Item, gross: number, cumulative: number, depth: number): void {
      for (const row of item.children) {
        const child = data.items.get(row.child)!, extended = cumulative * row.quantity, quantity = need(row, gross);
        lines.push(`${'.'.repeat(depth)}${depth} ${child.id} qty ${row.quantity} scrap ${row.scrap} ext ${extended} gross ${quantity} lt ${child.leadTime} cum ${child.cumulativeLead} ${child.description}`);
        totals.set(child.id, (totals.get(child.id) ?? 0) + quantity); descend(child, quantity, extended, depth + 1);
      }
    }
    descend(top, data.treeQuantity, 1, 1);
    for (const id of [...totals.keys()].sort(compareIds)) lines.push(`SUM ${id} ${totals.get(id)}`);
    const critical = [top.id]; let current = top;
    while (current.children.length) {
      let selected = data.items.get(current.children[0].child)!;
      for (const row of current.children.slice(1)) { const child = data.items.get(row.child)!; if (child.cumulativeLead > selected.cumulativeLead) selected = child; }
      critical.push(selected.id); current = selected;
    }
    lines.push(`CRITICAL ${critical.join(' -> ')} cum ${top.cumulativeLead}`);
  }
  return lines;
}
function costReport(data: Input, costs: Map<string, Cost>): string[] {
  const lines = ['item,material,labor,total,usage,value,class'];
  for (const item of data.orderedItems) { const c = costs.get(item.id)!;
    lines.push(`${item.id},${money(c.material)},${money(c.labor)},${money(c.total)},${c.usage},${money(c.value)},${c.classification}`); }
  return lines;
}
function exceptionReport(data: Input, plan: Plan): string[] {
  const lines = data.errors.map(e => `ERROR ${e}`), counts = { BELOW_SAFETY: 0, PAST_DUE: 0, RELEASE: 0, EXPEDITE: 0, DEFER: 0, CANCEL: 0, NO_ROUTING: 0, NO_DEMAND: 0, OVERLOAD: 0 };
  function record(code: keyof typeof counts, text: string): void { lines.push(`${code} ${text}`); counts[code]++; }
  for (const item of data.planning) {
    const grid = plan.items.get(item.id)!;
    if (item.onHand < item.safety) record('BELOW_SAFETY', `${item.id} on hand ${item.onHand} safety ${item.safety}`);
    for (const order of grid.orders) {
      const prefix = `${item.id} order ${order.number} receipt ${order.receipt}`;
      if (order.originalRelease < 1) record('PAST_DUE', `${prefix} release ${order.originalRelease} late ${1 - order.originalRelease} quantity ${order.quantity}`);
      else if (order.originalRelease === 1) record('RELEASE', `${prefix} quantity ${order.quantity}`);
    }
    const balance: number[] = [item.onHand];
    for (let t = 1; t <= data.horizon; t++) balance[t] = balance[t - 1] - grid.gross[t];
    let previousReceipts = 0;
    for (const receipt of item.receipts) {
      let needed: number | null = null;
      for (let t = 1; t <= data.horizon; t++) if (balance[t] + previousReceipts < item.safety) { needed = t; break; }
      const detail = `${item.id} receipt line ${receipt.line} week ${receipt.week} quantity ${receipt.quantity}`;
      if (needed === null) record('CANCEL', detail);
      else if (needed < receipt.week) record('EXPEDITE', `${detail} to ${needed}`);
      else if (needed > receipt.week) record('DEFER', `${detail} to ${needed}`);
      previousReceipts += receipt.quantity;
    }
    if (item.children.length && !item.routing.length) record('NO_ROUTING', item.id);
    if (total(grid.gross) === 0 && item.onHand > 0) record('NO_DEMAND', `${item.id} on hand ${item.onHand}`);
  }
  for (const center of data.centers) for (let t = 1; t <= data.horizon; t++) if (overload(plan, center, t) > 0)
    record('OVERLOAD', `${center.id} week ${t} load ${plan.loads.get(center.id)![t]} available ${center.available}`);
  lines.push(`SUMMARY errors ${data.errors.length} ${Object.entries(counts).map(([code, n]) => `${code.toLowerCase()} ${n}`).join(' ')}`);
  return lines;
}
function capacityReport(data: Input, plan: Plan): string[] {
  const lines: string[] = [], summaries: { center: Center; load: number; utilization: number }[] = [], weeks = Array.from({ length: data.horizon }, (_, i) => i + 1);
  for (const center of data.centers) {
    const load = plan.loads.get(center.id)!, over = weeks.map(t => overload(plan, center, t)), { leveled, backlog } = levelLoad(load, center.available);
    const loadTotal = total(load), utilization = percentage(loadTotal, center.available * data.horizon);
    let peak = 0; for (const t of weeks) if (load[t] > load[peak]) peak = t;
    lines.push(`CENTER ${center.id} minutes ${center.minutes} efficiency ${center.efficiency} available ${center.available} ${center.description}`,
      tableRow('WEEK', weeks, 7), tableRow('LOAD', load.slice(1), 7), tableRow('UTIL', weeks.map(t => percentage(load[t], center.available)), 7),
      tableRow('OVER', over, 7), tableRow('LEVELED', leveled.slice(1), 7),
      `TOTAL load ${loadTotal} available ${center.available * data.horizon} utilization ${utilization} overloaded ${over.filter(n => n > 0).length} peak ${peak} backlog ${backlog}`);
    summaries.push({ center, load: loadTotal, utilization });
  }
  summaries.sort((a, b) => {
    const left = BigInt(a.load) * BigInt(b.center.available), right = BigInt(b.load) * BigInt(a.center.available);
    return left > right ? -1 : left < right ? 1 : compareIds(a.center.id, b.center.id);
  });
  summaries.forEach((s, i) => lines.push(`RANK ${i + 1} ${s.center.id} load ${s.load} utilization ${s.utilization}`));
  return lines;
}
function promisesReport(data: Input, planning: Planning): string[] {
  const lines: string[] = [], counts = { on_time: 0, late: 0, rejected: 0 };
  for (const result of planning.results) {
    const inquiry = result.inquiry, prefix = `ORDER ${inquiry.id} ${inquiry.item} quantity ${inquiry.quantity} requested ${inquiry.week}`;
    if (result.status === 'on_time') lines.push(`${prefix} promised ${result.week}`);
    else if (result.status === 'late' && result.week !== null) lines.push(`${prefix} promised ${result.week} late ${result.week - inquiry.week} material ${result.material} reason ${result.reason}`);
    else lines.push(`${prefix} rejected material ${result.material ?? 'none'} reason ${result.reason}`);
    counts[result.status]++;
    if (result.status !== 'rejected') for (const item of data.planning) for (const order of planning.final.items.get(item.id)!.orders)
      if (order.roots.some(r => r.kind === 'ORDER' && r.order === inquiry.id))
        lines.push(`  SUPPLY ${item.id} order ${order.number} receipt ${order.receipt} release ${order.release} quantity ${order.quantity}`);
  }
  for (const item of data.planning) {
    const before = planning.base.items.get(item.id)!, after = planning.final.items.get(item.id)!;
    for (let t = 1; t <= data.horizon; t++) if (before.plannedReceipt[t] !== after.plannedReceipt[t]) {
      lines.push(`CHANGE ${item.id} from ${t} planned ${total(before.plannedReceipt)} -> ${total(after.plannedReceipt)} orders ${before.orders.length} -> ${after.orders.length}`); break;
    }
  }
  lines.push(`SUMMARY orders ${planning.results.length} on_time ${counts.on_time} late ${counts.late} rejected ${counts.rejected}`);
  return lines;
}
function releasesReport(data: Input, plan: Plan): string[] {
  const lines: string[] = [], available = new Map(data.planning.map(item => [item.id, item.onHand + plan.items.get(item.id)!.scheduled[1]]));
  const orders = data.planning.flatMap(item => plan.items.get(item.id)!.orders.filter(o => o.release === 1));
  orders.sort((a, b) => a.originalRelease - b.originalRelease || compareIds(a.item, b.item) || a.number - b.number);
  const counts = { make: 0, ready: 0, short: 0, buy: 0, value: 0 };
  for (const order of orders) {
    const item = data.items.get(order.item)!, late = order.originalRelease < 1 ? ` late ${1 - order.originalRelease}` : '';
    const detail = `${item.id} order ${order.number} receipt ${order.receipt} quantity ${order.quantity}${late}`;
    if (!item.children.length) { const value = order.quantity * item.material; lines.push(`BUY ${detail} value ${money(value)}`); counts.buy++; counts.value += value; continue; }
    const picks = item.children.map(r => ({ child: r.child, required: need(r, order.quantity), available: available.get(r.child)! }));
    const ready = picks.every(p => p.required <= p.available);
    lines.push(`MAKE ${detail} ${ready ? 'READY' : 'SHORT'}`); counts.make++; counts[ready ? 'ready' : 'short']++;
    for (const pick of picks) { lines.push(`  PICK ${pick.child} need ${pick.required} available ${pick.available} short ${Math.max(0, pick.required - pick.available)}`);
      if (ready) available.set(pick.child, pick.available - pick.required); }
    item.routing.forEach((op, j) => lines.push(`  OPERATION ${op.operation} ${op.center} week ${operationWeek(order.receipt, item.leadTime, j, item.routing.length)} minutes ${op.setup + order.quantity * op.run}`));
  }
  lines.push(`SUMMARY make ${counts.make} ready ${counts.ready} short ${counts.short} buy ${counts.buy} value ${money(counts.value)}`);
  return lines;
}
function valueReport(data: Input, plan: Plan, costs: Map<string, Cost>): string[] {
  const lines = ['week,inventory,purchases,labor'];
  for (let t = 1; t <= data.horizon; t++) {
    let inventory = 0, purchases = 0, labor = 0;
    for (const item of data.planning) { const grid = plan.items.get(item.id)!; inventory += grid.onHand[t] * costs.get(item.id)!.total;
      if (!item.children.length) purchases += grid.plannedRelease[t] * item.material; else labor += grid.plannedRelease[t] * item.labor; }
    lines.push(`${t},${money(inventory)},${money(purchases)},${money(labor)}`);
  }
  return lines;
}
function main(): void {
  const data = loadInput(), planning = promiseInquiries(data), plan = planning.final;
  allocateSupplies(data, plan);
  const costs = rollup(data.planning, new Map([...plan.items].map(([id, grid]) => [id, grid.gross])));
  writeReports({ 'mrp_grid.txt': gridReport(data, plan), 'pegging.txt': peggingReport(data, plan), 'bom_tree.txt': treeReport(data),
    'cost_rollup.csv': costReport(data, costs), 'exceptions.txt': exceptionReport(data, plan), 'capacity.txt': capacityReport(data, plan),
    'promises.txt': promisesReport(data, planning), 'releases.txt': releasesReport(data, plan), 'value_plan.csv': valueReport(data, plan, costs) });
}
main();
