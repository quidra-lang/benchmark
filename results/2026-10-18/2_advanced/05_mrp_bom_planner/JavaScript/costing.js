const { compareIds } = require('./items');
const { roundRatio } = require('./report');

function rollup(planningOrder, plan) {
  const costs = new Map();
  for (const item of planningOrder.slice().reverse()) {
    let material = item.material;
    let labor = item.labor;
    for (const row of item.children) {
      const childCost = costs.get(row.child);
      const multiplier = row.quantity * (100 + row.scrap);
      material += roundRatio(multiplier * childCost.material, 100);
      labor += roundRatio(multiplier * childCost.labor, 100);
    }
    let usage = 0;
    for (const quantity of plan.items.get(item.id).gross) usage += quantity;
    const total = material + labor;
    costs.set(item.id, { material, labor, total, usage, value: usage * total, classification: 'C' });
  }
  const ranked = planningOrder.slice().sort((first, second) =>
    costs.get(second.id).value - costs.get(first.id).value || compareIds(first.id, second.id));
  let totalValue = 0;
  for (const cost of costs.values()) totalValue += cost.value;
  let previous = 0;
  for (const item of ranked) {
    const cost = costs.get(item.id);
    if (cost.value > 0) {
      if (100 * previous < 80 * totalValue) cost.classification = 'A';
      else if (100 * previous < 95 * totalValue) cost.classification = 'B';
    }
    previous += cost.value;
  }
  return costs;
}

module.exports = { rollup };
