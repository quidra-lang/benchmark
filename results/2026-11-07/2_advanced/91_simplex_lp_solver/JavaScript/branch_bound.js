'use strict';

const {Rational} = require('./rational');

function solve(model, limit, solveLP) {
  const stack = [{lower: model.lower.slice(), upper: model.upper.slice(), depth: 0, parent: null,
    branch: 'root', parentValue: null}];
  const lines = [];
  const better = (first, second) => model.direction === 'maximize' ? first.compare(second) > 0 : first.compare(second) < 0;
  let root = null;
  let incumbent = null;
  let processed = 0;
  let incumbents = 0;
  let pruned = 0;
  let infeasible = 0;
  let cutoff = false;
  let unbounded = false;
  while (stack.length > 0) {
    if (processed === limit) {
      cutoff = true;
      break;
    }
    const node = stack.pop();
    const number = ++processed;
    const lp = solveLP(node.lower, node.upper, number);
    if (root === null) root = lp;
    let outcome;
    if (lp.status === 'INFEASIBLE') {
      outcome = 'infeasible';
      infeasible++;
    } else if (lp.status === 'UNBOUNDED') {
      outcome = 'unbounded';
      unbounded = true;
    } else if (incumbent !== null && !better(lp.objective, incumbent.objective)) {
      outcome = 'pruned';
      pruned++;
    } else {
      const variable = model.integers.find(index => lp.solution[index].d !== 1n);
      if (variable === undefined) {
        incumbent = {objective: lp.objective, solution: lp.solution};
        incumbents++;
        outcome = 'incumbent';
      } else {
        const value = lp.solution[variable];
        const floor = new Rational(value.floor());
        const ceil = new Rational(value.ceil());
        const child = {depth: node.depth + 1, parent: number, parentValue: lp.objective};
        const high = {...child, lower: node.lower.slice(), upper: node.upper.slice(), branch: `${model.variables[variable]}>=${ceil}`};
        high.lower[variable] = ceil;
        const low = {...child, lower: node.lower.slice(), upper: node.upper.slice(), branch: `${model.variables[variable]}<=${floor}`};
        low.upper[variable] = floor;
        stack.push(high, low);
        outcome = `branch ${model.variables[variable]} ${value}`;
      }
    }
    const relaxation = lp.status === 'OPTIMAL' ? String(lp.objective) : lp.status.toLowerCase();
    lines.push(`NODE ${number} depth ${node.depth} parent ${node.parent === null ? '-' : node.parent} ` +
      `branch ${node.branch} lp ${relaxation} pivots ${lp.pivots} action ${outcome}`);
    if (unbounded) break;
  }
  const status = unbounded ? 'UNBOUNDED' : cutoff ? 'NODE_LIMIT' : incumbent === null ? 'INFEASIBLE' : 'OPTIMAL';
  let bound = incumbent === null ? null : incumbent.objective;
  if (cutoff) {
    for (let index = stack.length - 1; index >= 0; index--) {
      const node = stack[index];
      lines.push(`OPEN parent ${node.parent} branch ${node.branch} bound ${node.parentValue}`);
      if (bound === null || better(node.parentValue, bound)) bound = node.parentValue;
    }
  }
  const objective = incumbent === null ? null : incumbent.objective;
  lines.push(`RESULT ${status} objective ${objective === null ? '-' : objective} nodes ${processed} ` +
    `incumbents ${incumbents} pruned ${pruned} infeasible ${infeasible} open ${stack.length} bound ${bound === null ? '-' : bound}`);
  return {status, root, objective, solution: incumbent === null ? null : incumbent.solution, processed, lines};
}

module.exports = {solve};
