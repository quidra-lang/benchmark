const { readLines, csvRows, compareIds, loadItems } = require('./items');
const { need, loadBom, computeStructure } = require('./bom');
const { lotSize } = require('./lot_sizing');
const { loadCenters, loadRoutings, operationWeek, levelLoad, orderedCenters } = require('./capacity');
const { rollup } = require('./costing');
const { money, percentage, tableRow, writeReports } = require('./report');

function total(values) {
  let quantity = 0;
  for (const value of values) quantity += value;
  return quantity;
}

function readParameters() {
  const lines = readLines('input/params.txt');
  return {
    horizon: Number(lines[0].split(' ')[1]),
    peg: lines[1].split(' ').slice(1),
    treeQuantity: Number(lines[2].split(' ')[1]),
  };
}

function readRequirements(filename, items, horizon, errors, unique) {
  const accepted = [];
  const pairs = new Set();
  for (const { line, fields } of csvRows(`input/${filename}`)) {
    const [id, weekText, quantityText] = fields;
    const week = Number(weekText);
    const quantity = Number(quantityText);
    const key = `${id}:${week}`;
    let error = null;
    if (!items.has(id)) error = `unknown item ${id}`;
    else if (week < 1 || week > horizon) error = `week ${week} outside horizon`;
    else if (quantity < 1) error = `bad quantity ${quantity}`;
    else if (unique && pairs.has(key)) error = `duplicate ${id} week ${week}`;
    if (error !== null) {
      errors.push(`${filename} line ${line}: ${error}`);
    } else {
      accepted.push({ item: id, week, quantity, line });
      pairs.add(key);
    }
  }
  return accepted;
}

function readInquiries(items, horizon, errors) {
  const inquiries = [];
  const identifiers = new Set();
  for (const { line, fields } of csvRows('input/orders.csv')) {
    const [id, item, quantityText, weekText] = fields;
    const quantity = Number(quantityText);
    const week = Number(weekText);
    let error = null;
    if (identifiers.has(id)) error = `duplicate order ${id}`;
    else if (!items.has(item)) error = `unknown item ${item}`;
    else if (week < 1 || week > horizon) error = `week ${week} outside horizon`;
    else if (quantity < 1) error = `bad quantity ${quantity}`;
    if (error !== null) {
      errors.push(`orders.csv line ${line}: ${error}`);
    } else {
      inquiries.push({ id, item, quantity, week, line });
      identifiers.add(id);
    }
  }
  return inquiries;
}

function loadInput() {
  const parameters = readParameters();
  const errors = [];
  const items = loadItems('input/items.csv', errors);
  loadBom('input/bom.csv', items, errors);
  const centerMap = loadCenters('input/workcenters.csv', errors);
  loadRoutings('input/routings.csv', items, centerMap, errors);
  const mps = readRequirements('mps.csv', items, parameters.horizon, errors, true);
  const receipts = readRequirements('receipts.csv', items, parameters.horizon, errors, false);
  const inquiries = readInquiries(items, parameters.horizon, errors);
  for (const receipt of receipts) items.get(receipt.item).receipts.push(receipt);
  for (const item of items.values()) {
    item.receipts.sort((first, second) => first.week - second.week || first.line - second.line);
  }
  return {
    ...parameters, errors, items, mps, inquiries,
    planning: computeStructure(items), centers: orderedCenters(centerMap),
    orderedItems: [...items.values()].sort((first, second) => compareIds(first.id, second.id)),
  };
}

function emptyItemPlan(item, horizon) {
  const zeroes = () => Array(horizon + 1).fill(0);
  const plan = {
    item, gross: zeroes(), scheduled: zeroes(), onHand: zeroes(), net: zeroes(),
    plannedReceipt: zeroes(), plannedRelease: zeroes(), demands: [], orders: [], pastDue: 0,
  };
  plan.onHand[0] = item.onHand;
  for (const receipt of item.receipts) plan.scheduled[receipt.week] += receipt.quantity;
  return plan;
}

function totalLoads(data, plan) {
  const loads = new Map(data.centers.map(center => [center.id, Array(data.horizon + 1).fill(0)]));
  for (const item of data.planning) {
    for (const order of plan.items.get(item.id).orders) {
      item.routing.forEach((operation, index) => {
        const week = operationWeek(order.receipt, item.leadTime, index, item.routing.length);
        loads.get(operation.center)[week] += operation.setup + order.quantity * operation.run;
      });
    }
  }
  return loads;
}

function runMrp(data, promised) {
  const plan = { items: new Map() };
  for (const item of data.planning) plan.items.set(item.id, emptyItemPlan(item, data.horizon));
  for (const row of data.mps) plan.items.get(row.item).demands.push({ ...row, kind: 'MPS' });
  for (const { inquiry, week } of promised) {
    plan.items.get(inquiry.item).demands.push({
      kind: 'ORDER', order: inquiry.id, item: inquiry.item, week,
      quantity: inquiry.quantity, line: inquiry.line,
    });
  }
  for (const item of data.planning) {
    const itemPlan = plan.items.get(item.id);
    for (const demand of itemPlan.demands) itemPlan.gross[demand.week] += demand.quantity;
    for (let week = 1; week <= data.horizon; week += 1) {
      const available = itemPlan.onHand[week - 1] + itemPlan.scheduled[week] - itemPlan.gross[week];
      if (available >= item.safety) {
        itemPlan.onHand[week] = available;
        continue;
      }
      const net = item.safety - available;
      const quantity = lotSize(item, net, available, week, itemPlan.gross, itemPlan.scheduled, data.horizon);
      const originalRelease = week - item.leadTime;
      const release = Math.max(1, originalRelease);
      const order = {
        kind: 'PLANNED', item: item.id, number: itemPlan.orders.length + 1,
        receipt: week, quantity, originalRelease, release,
      };
      itemPlan.orders.push(order);
      itemPlan.net[week] = net;
      itemPlan.plannedReceipt[week] = quantity;
      itemPlan.plannedRelease[release] += quantity;
      itemPlan.onHand[week] = available + quantity;
      if (originalRelease < 1) itemPlan.pastDue += quantity;
    }
    for (const order of itemPlan.orders) {
      for (const row of item.children) {
        plan.items.get(row.child).demands.push({
          kind: 'DEPENDENT', item: row.child, week: order.release, quantity: need(row, order.quantity),
          parent: item.id, parentOrder: order.number,
        });
      }
    }
  }
  plan.loads = totalLoads(data, plan);
  return plan;
}

function overload(plan, center, week) {
  return Math.max(0, plan.loads.get(center.id)[week] - center.available);
}

function promiseInquiries(data) {
  const base = runMrp(data, []);
  let current = base;
  const promised = [];
  const results = [];
  for (const inquiry of data.inquiries) {
    const result = { inquiry, week: null, material: null, reason: null, status: 'rejected' };
    for (let week = inquiry.week; week <= data.horizon; week += 1) {
      const placement = { inquiry, week };
      const trial = runMrp(data, [...promised, placement]);
      let reason = null;
      for (const item of data.planning) {
        if (trial.items.get(item.id).pastDue > current.items.get(item.id).pastDue) {
          reason = item.id;
          break;
        }
      }
      if (reason === null) {
        if (result.material === null) result.material = week;
        for (const center of data.centers) {
          for (let loadWeek = 1; loadWeek <= data.horizon; loadWeek += 1) {
            if (overload(trial, center, loadWeek) > overload(current, center, loadWeek)) {
              reason = `${center.id} week ${loadWeek}`;
              break;
            }
          }
          if (reason !== null) break;
        }
      }
      if (week === inquiry.week) result.reason = reason;
      if (reason === null) {
        result.week = week;
        result.status = week === inquiry.week ? 'on_time' : 'late';
        promised.push(placement);
        current = trial;
        break;
      }
    }
    results.push(result);
  }
  return { base, final: current, results };
}

function compareDemands(first, second) {
  const kinds = { MPS: 0, ORDER: 1, DEPENDENT: 2 };
  const initial = first.week - second.week || kinds[first.kind] - kinds[second.kind];
  if (initial !== 0) return initial;
  if (first.kind === 'ORDER') return first.line - second.line;
  if (first.kind === 'DEPENDENT') {
    return compareIds(first.parent, second.parent) || first.parentOrder - second.parentOrder;
  }
  return 0;
}

function compareRoots(first, second) {
  const kinds = { MPS: 0, ORDER: 1, SAFETY: 2 };
  return compareIds(first.item, second.item) || kinds[first.kind] - kinds[second.kind]
    || first.week - second.week || compareIds(first.order, second.order);
}

function allocateSupplies(data, plan) {
  for (const item of data.planning) {
    const itemPlan = plan.items.get(item.id);
    const demands = itemPlan.demands.slice().sort(compareDemands);
    if (item.safety > 0) demands.unshift({ kind: 'SAFETY', item: item.id, week: 0, quantity: item.safety });
    const receipts = item.receipts.map(row => ({
      kind: 'RECEIPT', item: item.id, line: row.line, receipt: row.week, quantity: row.quantity,
    }));
    const supplies = [...receipts, ...itemPlan.orders];
    supplies.sort((first, second) => first.receipt - second.receipt
      || (first.kind === 'RECEIPT' ? 0 : 1) - (second.kind === 'RECEIPT' ? 0 : 1)
      || (first.line ?? 0) - (second.line ?? 0));
    const stock = item.onHand > 0 ? { kind: 'STOCK', item: item.id, quantity: item.onHand } : null;
    if (stock !== null) supplies.unshift(stock);
    for (const supply of supplies) {
      supply.allocations = [];
      supply.excess = supply.quantity;
    }
    let supplyIndex = 0;
    for (const demand of demands) {
      let remaining = demand.quantity;
      while (remaining > 0) {
        while (supplies[supplyIndex].excess === 0) supplyIndex += 1;
        const supply = supplies[supplyIndex];
        const share = Math.min(remaining, supply.excess);
        supply.allocations.push({ demand, share });
        supply.excess -= share;
        remaining -= share;
      }
    }
    itemPlan.stock = stock;
    itemPlan.receiptSupplies = receipts;
    for (const order of itemPlan.orders) {
      const roots = new Map();
      for (const { demand } of order.allocations) {
        const inherited = demand.kind === 'DEPENDENT'
          ? plan.items.get(demand.parent).orders[demand.parentOrder - 1].roots
          : [{ kind: demand.kind, item: demand.item, week: demand.week, order: demand.order ?? '' }];
        for (const root of inherited) roots.set(`${root.kind}:${root.item}:${root.week}:${root.order}`, root);
      }
      order.roots = [...roots.values()].sort(compareRoots);
    }
  }
}

function ruleLabel(item) {
  if (item.rule === 'FOQ') return `FOQ ${item.fixed}`;
  if (item.rule === 'POQ') return `POQ ${item.periods}`;
  if (item.rule === 'MIN') return `MIN ${item.minimum}/${item.multiple}`;
  return 'LFL';
}

function gridReport(data, plan) {
  const lines = [];
  const weeks = Array.from({ length: data.horizon }, (_, index) => index + 1);
  for (const item of data.planning) {
    const grid = plan.items.get(item.id);
    lines.push(`ITEM ${item.id} LLC ${item.lowLevel} LT ${item.leadTime} LOT ${ruleLabel(item)} SS ${item.safety} OH ${item.onHand} ${item.description}`);
    lines.push(tableRow('WEEK', weeks, 6));
    for (const [label, values] of [
      ['GROSS', grid.gross], ['RECEIPTS', grid.scheduled], ['ON_HAND', grid.onHand],
      ['NET', grid.net], ['PLAN_RCPT', grid.plannedReceipt], ['PLAN_REL', grid.plannedRelease],
    ]) lines.push(tableRow(label, values.slice(1), 6));
    lines.push(`TOTAL gross ${total(grid.gross)} receipts ${total(grid.scheduled)} planned ${total(grid.plannedReceipt)} orders ${grid.orders.length} ending ${grid.onHand[data.horizon]}`);
  }
  return lines;
}

function whereUsed(lines, data, item, depth, cumulative) {
  for (const row of item.parents) {
    const extended = cumulative * row.quantity;
    lines.push(`${'.'.repeat(depth)}${depth} ${row.parent} qty ${row.quantity} ext ${extended}`);
    whereUsed(lines, data, data.items.get(row.parent), depth + 1, extended);
  }
}

function allocationLines(lines, plan, supply, depth, recursive) {
  const indent = ' '.repeat(2 * depth);
  for (const { demand, share } of supply.allocations) {
    let description;
    if (demand.kind === 'SAFETY') description = `SAFETY ${demand.item}`;
    else if (demand.kind === 'MPS') description = `MPS ${demand.item} week ${demand.week}`;
    else if (demand.kind === 'ORDER') description = `ORDER ${demand.order} ${demand.item} week ${demand.week}`;
    else description = `${demand.parent} order ${demand.parentOrder} week ${demand.week}`;
    lines.push(`${indent}ALLOC ${share} ${description}`);
    if (recursive && demand.kind === 'DEPENDENT') {
      const parent = plan.items.get(demand.parent).orders[demand.parentOrder - 1];
      allocationLines(lines, plan, parent, depth + 1, true);
    }
  }
}

function excessLine(lines, supply) {
  if (supply.excess > 0) lines.push(`  EXCESS ${supply.excess}`);
}

function peggingReport(data, plan) {
  const lines = [];
  for (const id of data.peg) {
    const item = data.items.get(id);
    const grid = plan.items.get(id);
    lines.push(`PEG ${id} orders ${grid.orders.length}`);
    whereUsed(lines, data, item, 1, 1);
    if (grid.stock !== null) {
      lines.push(`STOCK quantity ${item.onHand}`);
      allocationLines(lines, plan, grid.stock, 1, false);
      excessLine(lines, grid.stock);
    }
    for (const receipt of grid.receiptSupplies) {
      lines.push(`RECEIPT line ${receipt.line} week ${receipt.receipt} quantity ${receipt.quantity}`);
      allocationLines(lines, plan, receipt, 1, false);
      excessLine(lines, receipt);
    }
    for (const order of grid.orders) {
      lines.push(`ORDER ${order.number} receipt ${order.receipt} release ${order.release} quantity ${order.quantity}`);
      allocationLines(lines, plan, order, 1, true);
      excessLine(lines, order);
      for (const root of order.roots) {
        if (root.kind === 'SAFETY') lines.push(`  ROOT SAFETY ${root.item}`);
        else if (root.kind === 'MPS') lines.push(`  ROOT MPS ${root.item} week ${root.week}`);
        else lines.push(`  ROOT ORDER ${root.order} ${root.item} week ${root.week}`);
      }
    }
  }
  return lines;
}

function treeReport(data) {
  const lines = [];
  for (const top of data.orderedItems) {
    if (top.children.length === 0 || top.parents.length > 0) continue;
    const totals = new Map();
    lines.push(`TREE ${top.id} quantity ${data.treeQuantity}`);
    lines.push(`0 ${top.id} ext 1 gross ${data.treeQuantity} lt ${top.leadTime} cum ${top.cumulativeLead} ${top.description}`);
    function descend(item, gross, cumulative, depth) {
      for (const row of item.children) {
        const child = data.items.get(row.child);
        const extended = cumulative * row.quantity;
        const quantity = need(row, gross);
        lines.push(`${'.'.repeat(depth)}${depth} ${child.id} qty ${row.quantity} scrap ${row.scrap} ext ${extended} gross ${quantity} lt ${child.leadTime} cum ${child.cumulativeLead} ${child.description}`);
        totals.set(child.id, (totals.get(child.id) ?? 0) + quantity);
        descend(child, quantity, extended, depth + 1);
      }
    }
    descend(top, data.treeQuantity, 1, 1);
    for (const id of [...totals.keys()].sort(compareIds)) lines.push(`SUM ${id} ${totals.get(id)}`);
    const critical = [top.id];
    let current = top;
    while (current.children.length > 0) {
      let selected = data.items.get(current.children[0].child);
      for (const row of current.children.slice(1)) {
        const child = data.items.get(row.child);
        if (child.cumulativeLead > selected.cumulativeLead) selected = child;
      }
      critical.push(selected.id);
      current = selected;
    }
    lines.push(`CRITICAL ${critical.join(' -> ')} cum ${top.cumulativeLead}`);
  }
  return lines;
}

function costReport(data, costs) {
  const lines = ['item,material,labor,total,usage,value,class'];
  for (const item of data.orderedItems) {
    const cost = costs.get(item.id);
    lines.push(`${item.id},${money(cost.material)},${money(cost.labor)},${money(cost.total)},${cost.usage},${money(cost.value)},${cost.classification}`);
  }
  return lines;
}

function exceptionReport(data, plan) {
  const lines = data.errors.map(error => `ERROR ${error}`);
  const counts = { below_safety: 0, past_due: 0, release: 0, expedite: 0, defer: 0, cancel: 0,
    no_routing: 0, no_demand: 0, overload: 0 };
  function record(code, message) {
    lines.push(`${code} ${message}`);
    counts[code.toLowerCase()] += 1;
  }
  for (const item of data.planning) {
    const grid = plan.items.get(item.id);
    if (item.onHand < item.safety) record('BELOW_SAFETY', `${item.id} on hand ${item.onHand} safety ${item.safety}`);
    for (const order of grid.orders) {
      const prefix = `${item.id} order ${order.number} receipt ${order.receipt}`;
      if (order.originalRelease < 1) {
        record('PAST_DUE', `${prefix} release ${order.originalRelease} late ${1 - order.originalRelease} quantity ${order.quantity}`);
      } else if (order.originalRelease === 1) record('RELEASE', `${prefix} quantity ${order.quantity}`);
    }
    const balance = Array(data.horizon + 1).fill(0);
    balance[0] = item.onHand;
    for (let week = 1; week <= data.horizon; week += 1) balance[week] = balance[week - 1] - grid.gross[week];
    let previousReceipts = 0;
    for (const receipt of item.receipts) {
      let needed = null;
      for (let week = 1; week <= data.horizon; week += 1) {
        if (balance[week] + previousReceipts < item.safety) {
          needed = week;
          break;
        }
      }
      const detail = `${item.id} receipt line ${receipt.line} week ${receipt.week} quantity ${receipt.quantity}`;
      if (needed === null) record('CANCEL', detail);
      else if (needed < receipt.week) record('EXPEDITE', `${detail} to ${needed}`);
      else if (needed > receipt.week) record('DEFER', `${detail} to ${needed}`);
      previousReceipts += receipt.quantity;
    }
    if (item.children.length > 0 && item.routing.length === 0) record('NO_ROUTING', item.id);
    if (total(grid.gross) === 0 && item.onHand > 0) record('NO_DEMAND', `${item.id} on hand ${item.onHand}`);
  }
  for (const center of data.centers) {
    for (let week = 1; week <= data.horizon; week += 1) {
      if (overload(plan, center, week) > 0) {
        record('OVERLOAD', `${center.id} week ${week} load ${plan.loads.get(center.id)[week]} available ${center.available}`);
      }
    }
  }
  lines.push(`SUMMARY errors ${data.errors.length} ${Object.entries(counts).map(([key, value]) => `${key} ${value}`).join(' ')}`);
  return lines;
}

function capacityReport(data, plan) {
  const lines = [];
  const summaries = [];
  const weeks = Array.from({ length: data.horizon }, (_, index) => index + 1);
  for (const center of data.centers) {
    const load = plan.loads.get(center.id);
    const over = weeks.map(week => overload(plan, center, week));
    const { leveled, backlog } = levelLoad(load, center.available);
    const loadTotal = total(load);
    const utilization = percentage(loadTotal, center.available * data.horizon);
    let peak = 0;
    for (const week of weeks) if (load[week] > load[peak]) peak = week;
    lines.push(`CENTER ${center.id} minutes ${center.minutes} efficiency ${center.efficiency} available ${center.available} ${center.description}`);
    lines.push(tableRow('WEEK', weeks, 7));
    lines.push(tableRow('LOAD', load.slice(1), 7));
    lines.push(tableRow('UTIL', weeks.map(week => percentage(load[week], center.available)), 7));
    lines.push(tableRow('OVER', over, 7));
    lines.push(tableRow('LEVELED', leveled.slice(1), 7));
    lines.push(`TOTAL load ${loadTotal} available ${center.available * data.horizon} utilization ${utilization} overloaded ${over.filter(value => value > 0).length} peak ${peak} backlog ${backlog}`);
    summaries.push({ center, load: loadTotal, utilization });
  }
  summaries.sort((first, second) => {
    const left = BigInt(first.load) * BigInt(second.center.available);
    const right = BigInt(second.load) * BigInt(first.center.available);
    return left > right ? -1 : left < right ? 1 : compareIds(first.center.id, second.center.id);
  });
  summaries.forEach((summary, index) => {
    lines.push(`RANK ${index + 1} ${summary.center.id} load ${summary.load} utilization ${summary.utilization}`);
  });
  return lines;
}

function promisesReport(data, planning) {
  const lines = [];
  const counts = { on_time: 0, late: 0, rejected: 0 };
  for (const result of planning.results) {
    const { inquiry } = result;
    const prefix = `ORDER ${inquiry.id} ${inquiry.item} quantity ${inquiry.quantity} requested ${inquiry.week}`;
    if (result.status === 'on_time') {
      lines.push(`${prefix} promised ${result.week}`);
    } else if (result.status === 'late') {
      lines.push(`${prefix} promised ${result.week} late ${result.week - inquiry.week} material ${result.material} reason ${result.reason}`);
    } else {
      lines.push(`${prefix} rejected material ${result.material ?? 'none'} reason ${result.reason}`);
    }
    counts[result.status] += 1;
    if (result.status !== 'rejected') {
      for (const item of data.planning) {
        for (const order of planning.final.items.get(item.id).orders) {
          if (order.roots.some(root => root.kind === 'ORDER' && root.order === inquiry.id)) {
            lines.push(`  SUPPLY ${item.id} order ${order.number} receipt ${order.receipt} release ${order.release} quantity ${order.quantity}`);
          }
        }
      }
    }
  }
  for (const item of data.planning) {
    const before = planning.base.items.get(item.id);
    const after = planning.final.items.get(item.id);
    for (let week = 1; week <= data.horizon; week += 1) {
      if (before.plannedReceipt[week] !== after.plannedReceipt[week]) {
        lines.push(`CHANGE ${item.id} from ${week} planned ${total(before.plannedReceipt)} -> ${total(after.plannedReceipt)} orders ${before.orders.length} -> ${after.orders.length}`);
        break;
      }
    }
  }
  lines.push(`SUMMARY orders ${planning.results.length} on_time ${counts.on_time} late ${counts.late} rejected ${counts.rejected}`);
  return lines;
}

function releasesReport(data, plan) {
  const lines = [];
  const available = new Map(data.planning.map(item => [item.id, item.onHand + plan.items.get(item.id).scheduled[1]]));
  const orders = data.planning.flatMap(item => plan.items.get(item.id).orders.filter(order => order.release === 1));
  orders.sort((first, second) => first.originalRelease - second.originalRelease
    || compareIds(first.item, second.item) || first.number - second.number);
  const counts = { make: 0, ready: 0, short: 0, buy: 0, value: 0 };
  for (const order of orders) {
    const item = data.items.get(order.item);
    const lateness = order.originalRelease < 1 ? ` late ${1 - order.originalRelease}` : '';
    const detail = `${item.id} order ${order.number} receipt ${order.receipt} quantity ${order.quantity}${lateness}`;
    if (item.children.length === 0) {
      const value = order.quantity * item.material;
      lines.push(`BUY ${detail} value ${money(value)}`);
      counts.buy += 1;
      counts.value += value;
      continue;
    }
    const picks = item.children.map(row => ({
      child: row.child, required: need(row, order.quantity), available: available.get(row.child),
    }));
    const ready = picks.every(pick => pick.required <= pick.available);
    lines.push(`MAKE ${detail} ${ready ? 'READY' : 'SHORT'}`);
    counts.make += 1;
    counts[ready ? 'ready' : 'short'] += 1;
    for (const pick of picks) {
      lines.push(`  PICK ${pick.child} need ${pick.required} available ${pick.available} short ${Math.max(0, pick.required - pick.available)}`);
      if (ready) available.set(pick.child, pick.available - pick.required);
    }
    item.routing.forEach((operation, index) => {
      const week = operationWeek(order.receipt, item.leadTime, index, item.routing.length);
      lines.push(`  OPERATION ${operation.operation} ${operation.center} week ${week} minutes ${operation.setup + order.quantity * operation.run}`);
    });
  }
  lines.push(`SUMMARY make ${counts.make} ready ${counts.ready} short ${counts.short} buy ${counts.buy} value ${money(counts.value)}`);
  return lines;
}

function valueReport(data, plan, costs) {
  const lines = ['week,inventory,purchases,labor'];
  for (let week = 1; week <= data.horizon; week += 1) {
    let inventory = 0;
    let purchases = 0;
    let labor = 0;
    for (const item of data.planning) {
      const grid = plan.items.get(item.id);
      inventory += grid.onHand[week] * costs.get(item.id).total;
      if (item.children.length === 0) purchases += grid.plannedRelease[week] * item.material;
      else labor += grid.plannedRelease[week] * item.labor;
    }
    lines.push(`${week},${money(inventory)},${money(purchases)},${money(labor)}`);
  }
  return lines;
}

function main() {
  const data = loadInput();
  const planning = promiseInquiries(data);
  const plan = planning.final;
  allocateSupplies(data, plan);
  const costs = rollup(data.planning, plan);
  writeReports({
    'mrp_grid.txt': gridReport(data, plan),
    'pegging.txt': peggingReport(data, plan),
    'bom_tree.txt': treeReport(data),
    'cost_rollup.csv': costReport(data, costs),
    'exceptions.txt': exceptionReport(data, plan),
    'capacity.txt': capacityReport(data, plan),
    'promises.txt': promisesReport(data, planning),
    'releases.txt': releasesReport(data, plan),
    'value_plan.csv': valueReport(data, plan, costs),
  });
}

if (require.main === module) main();
