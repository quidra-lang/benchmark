'use strict';

const low = require('./low_level');

function planOrder(grid, agents, order, budget, horizon, record) {
  const prohibitions = new low.Prohibitions(grid.size);
  const paths = Array(agents.length);
  const before = budget.expansions;
  let planned = 0;
  for (const number of order) {
    const result = low.plan(grid, agents[number], prohibitions, budget, horizon);
    record(number, result);
    if (result.path === null) return {paths: null, planned, failed: number, expansions: budget.expansions - before};
    paths[number] = result.path;
    planned++;
    prohibitions.reserve(result.path, 0, true);
  }
  return {paths, planned, failed: null, expansions: budget.expansions - before};
}

module.exports = {planOrder};
