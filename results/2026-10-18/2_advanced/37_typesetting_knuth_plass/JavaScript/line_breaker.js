'use strict';

function lineClass(line) {
  if (line.last) return 1;
  if (line.slack <= 1) return 0;
  if (line.slack <= 3) return 1;
  if (line.slack <= 6) return 2;
  return 3;
}

function lineCost(problem, line, previousClass, parameters) {
  let cost = parameters.line_penalty;
  cost += line.slack < 0 ? parameters.overfull_penalty : line.last ? 0 : line.slack * line.slack;
  if (problem.points[line.b].mid) {
    cost += parameters.hyphen_penalty;
    if (problem.points[line.a].mid) cost += parameters.double_hyphen_demerit;
  }
  if (line.last && problem.points[line.a].mid) cost += parameters.final_hyphen_demerit;
  if (Math.abs(lineClass(line) - previousClass) >= 2) cost += parameters.fitness_demerit;
  return cost;
}

function breakingCost(problem, breaks, parameters) {
  let total = 0;
  let previous = 0;
  let previousClass = 1;
  for (const end of breaks) {
    const line = problem.measure(previous, end);
    total += lineCost(problem, line, previousClass, parameters);
    previousClass = lineClass(line);
    previous = end;
  }
  return total;
}

function optimal(problem, parameters) {
  const end = problem.points.length - 1;
  const table = Array.from({ length: end + 1 }, () => Array(4).fill(null));
  table[0][1] = { cost: 0 };
  for (let b = 1; b <= end; b++) {
    function consider(a, line) {
      if (line.slack < 0 && b !== a + 1) return;
      const currentClass = lineClass(line);
      for (let previousClass = 0; previousClass < 4; previousClass++) {
        const earlier = table[a][previousClass];
        if (earlier === null) continue;
        const cost = earlier.cost + lineCost(problem, line, previousClass, parameters);
        const best = table[b][currentClass];
        if (best === null || cost < best.cost || (cost === best.cost && (a < best.a || (a === best.a && previousClass < best.previousClass)))) {
          table[b][currentClass] = { cost, a, previousClass };
        }
      }
    }
    consider(0, problem.measure(0, b));
    for (let a = b - 1; a >= 1; a--) {
      const line = problem.measure(a, b);
      // All positive starts use the same capacity; earlier starts can only add length.
      if (line.slack < 0 && b !== a + 1) break;
      consider(a, line);
    }
  }
  const breaks = [];
  let position = end;
  let currentClass = 1;
  while (position > 0) {
    breaks.push(position);
    const previous = table[position][currentClass];
    position = previous.a;
    currentClass = previous.previousClass;
  }
  breaks.reverse();
  return { breaks, cost: table[end][1].cost };
}

function greedy(problem, parameters) {
  const end = problem.points.length - 1;
  const breaks = [];
  let start = 0;
  while (start < end) {
    let selected = start + 1;
    if (problem.measure(start, selected).slack >= 0) {
      for (let candidate = selected + 1; candidate <= end; candidate++) {
        if (problem.measure(start, candidate).slack < 0) break;
        selected = candidate;
      }
    }
    breaks.push(selected);
    start = selected;
  }
  return { breaks, cost: breakingCost(problem, breaks, parameters) };
}

module.exports = { optimal, greedy };
