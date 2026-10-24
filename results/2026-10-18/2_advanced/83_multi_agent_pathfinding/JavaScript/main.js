'use strict';

const gridMap = require('./grid_map');
const low = require('./low_level');
const cbs = require('./cbs');
const prioritized = require('./prioritized');
const report = require('./report');
const classes = ['cardinal', 'semi_cardinal', 'non_cardinal'];

function readParameters(count) {
  const parameters = {orders: [Array.from({length: count}, (_, index) => index)], runs: [], delays: []};
  for (const line of gridMap.lines('params.txt')) {
    const [kind, ...values] = line.split(' ');
    switch (kind) {
      case 'HORIZON': parameters.horizon = Number(values[0]); break;
      case 'HL_BUDGET': parameters.highBudget = Number(values[0]); break;
      case 'LL_BUDGET': parameters.lowBudget = Number(values[0]); break;
      case 'WINDOW': [parameters.window, parameters.step] = values.map(Number); break;
      case 'ORDER': parameters.orders.push(values.map(Number)); break;
      case 'RUN':
        parameters.runs.push({solver: values[0], costFunction: values[1], name: values.join('-'), order: parameters.runs.length});
        break;
      case 'ANIMATE': parameters.animation = {name: values[0], frames: Number(values[1])}; break;
      case 'DELAY':
        parameters.delays.push({agent: Number(values[0]), start: Number(values[1]), length: Number(values[2])});
        break;
    }
  }
  return parameters;
}

function buildMDD(grid, agent, length, prohibitions) {
  const forward = Array.from({length: length + 1}, () => new Set());
  forward[0].add(agent.start);
  for (let time = 1; time <= length; time++) {
    for (const from of forward[time - 1]) {
      for (const to of grid.neighbors[from]) {
        if (agent.distance[to] >= 0 && time + agent.distance[to] <= length && prohibitions.permits(from, to, time)) {
          forward[time].add(to);
        }
      }
    }
  }
  const layers = Array.from({length: length + 1}, () => new Set());
  if (forward[length].has(agent.goal)) layers[length].add(agent.goal);
  for (let time = length - 1; time >= 0; time--) {
    for (const from of forward[time]) {
      if (grid.neighbors[from].some(to => layers[time + 1].has(to) && prohibitions.permits(from, to, time + 1))) {
        layers[time].add(from);
      }
    }
  }
  let states = 0;
  let width = 0;
  for (const layer of layers) {
    states += layer.size;
    width = Math.max(width, layer.size);
  }
  return {layers, states, width};
}

function mddFor(instance, number, length, prohibitions) {
  const cache = instance.mddCache[number];
  if (!cache.has(prohibitions)) cache.set(prohibitions, new Map());
  const lengths = cache.get(prohibitions);
  if (!lengths.has(length)) lengths.set(length, buildMDD(instance.grid, instance.agents[number], length, prohibitions));
  return lengths.get(length);
}

function classify(conflict, diagrams) {
  const fixed = number => {
    const layers = diagrams[number].layers;
    const width = time => time >= layers.length ? 1 : layers[time].size;
    return width(conflict.time) === 1 && (conflict.kind === 'vertex' || width(conflict.time - 1) === 1);
  };
  const first = fixed(conflict.a);
  const second = fixed(conflict.b);
  return first && second ? 'cardinal' : first || second ? 'semi_cardinal' : 'non_cardinal';
}

function conflictGroups(count, conflicts) {
  const adjacent = Array.from({length: count}, () => new Set());
  for (const conflict of conflicts) {
    adjacent[conflict.a].add(conflict.b);
    adjacent[conflict.b].add(conflict.a);
  }
  const visited = new Set();
  const result = [];
  for (let first = 0; first < count; first++) {
    if (visited.has(first)) continue;
    const component = [first];
    visited.add(first);
    for (let index = 0; index < component.length; index++) {
      for (const next of adjacent[component[index]]) {
        if (visited.has(next)) continue;
        visited.add(next);
        component.push(next);
      }
    }
    if (component.length > 1) result.push(component.sort((a, b) => a - b).map(report.name).join(''));
  }
  return result;
}

function overview(instance) {
  const {grid, agents, parameters} = instance;
  const degrees = [0, 0, 0, 0];
  let free = 0;
  for (let cell = 0; cell < grid.size; cell++) {
    if (!grid.free[cell]) continue;
    free++;
    degrees[Math.min(grid.degree(cell), 3)]++;
  }
  const visited = new Set();
  let components = 0;
  for (let first = 0; first < grid.size; first++) {
    if (!grid.free[first] || visited.has(first)) continue;
    components++;
    const queue = [first];
    visited.add(first);
    for (let index = 0; index < queue.length; index++) {
      for (const next of grid.neighbors[queue[index]]) {
        if (visited.has(next)) continue;
        visited.add(next);
        queue.push(next);
      }
    }
  }
  const prohibitions = agents.map(() => new low.Prohibitions(grid.size));
  const diagrams = agents.map(agent => mddFor(instance, agent.number, agent.shortest, prohibitions[agent.number]));
  const budget = low.counter();
  const paths = agents.map(agent => low.plan(grid, agent, prohibitions[agent.number], budget, parameters.horizon).path);
  const conflicts = cbs.conflicts(paths);
  const classCounts = Object.fromEntries(classes.map(name => [name, 0]));
  for (const conflict of conflicts) {
    conflict.class = classify(conflict, diagrams);
    classCounts[conflict.class]++;
  }
  let soc = 0;
  let makespan = 0;
  for (const agent of agents) {
    soc += agent.shortest;
    makespan = Math.max(makespan, agent.shortest);
  }
  return {free, degrees, components, diagrams, paths, conflicts, classCounts,
    bounds: {soc, makespan}, groups: conflictGroups(agents.length, conflicts)};
}

function runPP(instance, run) {
  const {grid, agents, parameters} = instance;
  try {
    for (let index = 0; index < parameters.orders.length; index++) {
      const order = parameters.orders[index];
      const number = index + 1;
      run.highLevel++;
      const result = prioritized.planOrder(grid, agents, order, run.budget, parameters.horizon, (agent, search) => {
        const outcome = search.path === null ? 'failed' : `cost ${search.path.length - 1}`;
        run.trace.push(`order ${number} agent ${report.name(agent)} ${outcome} expansions ${search.expansions}`);
      });
      const prefix = `order ${number} ${order.map(report.name).join('')} planned ${result.planned} expansions ${result.expansions}`;
      if (result.paths !== null) {
        run.specific.push(`${prefix} ok`);
        run.paths = result.paths;
        run.trace.push(`end OK order ${number}`);
        return;
      }
      run.specific.push(`${prefix} failed ${report.name(result.failed)}`);
    }
    run.reason = 'orders';
  } catch (error) {
    if (!(error instanceof low.BudgetExceeded)) throw error;
    run.reason = 'll_budget';
  }
  run.trace.push(`end FAIL ${run.reason}`);
}

function constraintOrder(grid, first, second) {
  return first.agent - second.agent || first.time - second.time ||
    (first.kind === 'vertex' ? 0 : 1) - (second.kind === 'vertex' ? 0 : 1) ||
    first.u % grid.width - second.u % grid.width ||
    Math.floor(first.u / grid.width) - Math.floor(second.u / grid.width) ||
    first.v % grid.width - second.v % grid.width ||
    Math.floor(first.v / grid.width) - Math.floor(second.v / grid.width);
}

function runCBS(instance, run) {
  const {grid, agents, parameters} = instance;
  const open = new low.Heap(cbs.compareNodes);
  const classCounts = Object.fromEntries(classes.map(name => [name, 0]));
  let pruned = 0;
  let answer = null;
  run.generated = 0;
  try {
    const prohibitions = agents.map(() => new low.Prohibitions(grid.size));
    const paths = agents.map(agent => low.plan(grid, agent, prohibitions[agent.number], run.budget, parameters.horizon).path);
    open.push(new cbs.Node(paths, prohibitions, run.costFunction, run.generated++));
    while (open.size > 0) {
      const node = open.pop();
      if (node.conflicts.length === 0) {
        answer = node;
        run.paths = node.paths;
        break;
      }
      if (run.highLevel === parameters.highBudget) {
        run.reason = 'hl_budget';
        break;
      }
      run.highLevel++;
      let split = node.conflicts[0];
      let chosenClass = null;
      if (run.solver === 'ICBS') {
        const diagrams = agents.map(agent => mddFor(instance, agent.number,
          node.paths[agent.number].length - 1, node.prohibitions[agent.number]));
        let bestClass = classes.length;
        for (const conflict of node.conflicts) {
          const classification = classify(conflict, diagrams);
          const rank = classes.indexOf(classification);
          if (rank < bestClass) {
            bestClass = rank;
            split = conflict;
            chosenClass = classification;
          }
        }
        classCounts[chosenClass]++;
      }
      const children = [];
      for (const constraint of cbs.constraints(split)) {
        const number = constraint.agent;
        const childProhibitions = node.prohibitions.slice();
        childProhibitions[number] = childProhibitions[number].withConstraint(constraint);
        const search = low.plan(grid, agents[number], childProhibitions[number], run.budget, parameters.horizon);
        if (search.path === null) {
          pruned++;
          children.push('-');
          continue;
        }
        const childPaths = node.paths.slice();
        childPaths[number] = search.path;
        const child = new cbs.Node(childPaths, childProhibitions, run.costFunction, run.generated++, node);
        open.push(child);
        children.push(child.number);
      }
      const parent = node.parent === null ? '-' : node.parent.number;
      let notation = report.conflict(grid, split);
      if (chosenClass !== null) notation += ` class ${chosenClass}`;
      run.trace.push(`expand ${run.highLevel} node ${node.number} parent ${parent} depth ${node.depth} ` +
        `cost ${node.cost} conflicts ${node.conflicts.length} split ${notation} children ${children.join(' ')}`);
    }
    if (answer === null && run.reason === null) run.reason = 'exhausted';
  } catch (error) {
    if (!(error instanceof low.BudgetExceeded)) throw error;
    run.reason = 'll_budget';
  }
  run.specific.push(`search expanded ${run.highLevel} generated ${run.generated} pruned ${pruned} open ${open.size}`);
  if (run.solver === 'ICBS') {
    run.specific.push(`classes cardinal ${classCounts.cardinal} semi_cardinal ${classCounts.semi_cardinal} non_cardinal ${classCounts.non_cardinal}`);
  }
  if (answer === null) run.trace.push(`end FAIL ${run.reason}`);
  else {
    run.specific.push(`solution node ${answer.number} depth ${answer.depth}`);
    const constraints = answer.prohibitions.flatMap(prohibition => prohibition.entries).sort((a, b) => constraintOrder(grid, a, b));
    for (const constraint of constraints) {
      const prefix = `constraint ${report.name(constraint.agent)} ${constraint.kind}`;
      const cells = constraint.kind === 'vertex' ? report.cell(grid, constraint.v) :
        `${report.cell(grid, constraint.u)} ${report.cell(grid, constraint.v)}`;
      run.specific.push(`${prefix} ${cells} t ${constraint.time}`);
    }
    run.trace.push(`end OK node ${answer.number} cost ${answer.cost}`);
  }
}

function runWHCA(instance, run) {
  const {grid, agents, parameters} = instance;
  const current = agents.map(agent => agent.start);
  const executed = current.map(cell => [cell]);
  let time = 0;
  try {
    while (true) {
      if (agents.every(agent => current[agent.number] === agent.goal)) {
        for (const agent of agents) {
          const path = executed[agent.number];
          while (path.length > 1 && path.at(-2) === agent.goal) path.pop();
        }
        run.paths = executed;
        break;
      }
      if (time >= parameters.horizon) {
        run.reason = 'timeout';
        break;
      }
      run.highLevel++;
      const order = agents.filter(agent => current[agent.number] !== agent.goal)
        .concat(agents.filter(agent => current[agent.number] === agent.goal));
      const prohibitions = new low.Prohibitions(grid.size);
      const windows = Array(agents.length);
      let blocked = false;
      for (const agent of order) {
        const search = low.search(grid, agent, prohibitions, run.budget, current[agent.number],
          time, time + parameters.window, true);
        const prefix = `round ${run.highLevel} time ${time} agent ${agent.name}`;
        if (search.path === null) {
          run.trace.push(`${prefix} blocked expansions ${search.expansions}`);
          blocked = true;
          break;
        }
        const path = search.path;
        while (path.length <= parameters.window) path.push(path.at(-1));
        windows[agent.number] = path;
        prohibitions.reserve(path, time);
        run.trace.push(`${prefix} moves ${report.actions(grid, path)} expansions ${search.expansions}`);
      }
      if (blocked) {
        run.reason = 'blocked';
        break;
      }
      for (const agent of agents) {
        const path = windows[agent.number];
        for (let index = 1; index <= parameters.step; index++) executed[agent.number].push(path[index]);
        current[agent.number] = path[parameters.step];
      }
      time += parameters.step;
    }
  } catch (error) {
    if (!(error instanceof low.BudgetExceeded)) throw error;
    run.reason = 'll_budget';
  }
  run.specific.push(`window ${parameters.window} step ${parameters.step} rounds ${run.highLevel}`);
  run.trace.push(run.paths === null ? `end FAIL ${run.reason}` : `end OK rounds ${run.highLevel}`);
}

function planStatistics(instance, paths, costFunction) {
  const {grid, agents} = instance;
  const totals = cbs.costs(paths);
  const traffic = Array(grid.size).fill(0);
  const cellWaits = Array(grid.size).fill(0);
  const details = [];
  let sumExtra = 0;
  let maxExtra = 0;
  let waits = 0;
  let turns = 0;
  for (const agent of agents) {
    const path = paths[agent.number];
    const cost = path.length - 1;
    const actions = report.actions(grid, path);
    const detail = {cost, extra: cost - agent.shortest, waits: 0, turns: 0,
      arrival: path.indexOf(agent.goal), leave: 0, actions};
    let previous = null;
    for (let time = 1; time <= cost; time++) {
      const action = actions[time - 1];
      if (action === '.') {
        detail.waits++;
        cellWaits[path[time]]++;
      } else {
        if (previous !== null && previous !== action) detail.turns++;
        previous = action;
      }
      if (path[time - 1] === agent.goal && path[time] !== agent.goal) detail.leave++;
    }
    for (const cell of new Set(path)) traffic[cell]++;
    sumExtra += detail.extra;
    maxExtra = Math.max(maxExtra, detail.extra);
    waits += detail.waits;
    turns += detail.turns;
    details.push(detail);
  }
  const arrivals = Array.from({length: totals.makespan + 1}, (_, time) => paths.filter(path => path.length - 1 <= time).length);
  const hotspots = [];
  for (let cell = 0; cell < grid.size; cell++) if (traffic[cell] > 0) hotspots.push(cell);
  hotspots.sort((a, b) => traffic[b] - traffic[a] || a - b);
  const cost = costFunction === 'SOC' ? totals.soc : totals.makespan;
  return {...totals, cost, details, sumExtra, maxExtra, waits, turns, arrivals,
    traffic, cellWaits, hotspots: hotspots.slice(0, 5)};
}

function validate(instance, name, paths, knownConflicts = null) {
  const {grid, agents} = instance;
  let start = 0;
  let goal = 0;
  let moves = 0;
  for (const agent of agents) {
    const path = paths[agent.number];
    if (path[0] !== agent.start) start++;
    if (path.at(-1) !== agent.goal) goal++;
    for (let time = 1; time < path.length; time++) if (!grid.neighbors[path[time - 1]].includes(path[time])) moves++;
  }
  const conflicts = knownConflicts === null ? cbs.conflicts(paths) : knownConflicts;
  const vertex = conflicts.filter(conflict => conflict.kind === 'vertex').length;
  const edge = conflicts.length - vertex;
  let follows = 0;
  const maximum = cbs.costs(paths).makespan;
  for (let time = 1; time <= maximum; time++) {
    for (let a = 0; a < agents.length; a++) {
      const before = cbs.position(paths[a], time - 1);
      const after = cbs.position(paths[a], time);
      if (before === after) continue;
      for (let b = 0; b < agents.length; b++) {
        if (a !== b && after === cbs.position(paths[b], time - 1) && cbs.position(paths[b], time) !== before) follows++;
      }
    }
  }
  const verdict = start + goal + moves + vertex + edge === 0 ? 'VALID' : 'INVALID';
  const lines = [`plan ${name} verdict ${verdict} start ${start} goal ${goal} moves ${moves} vertex ${vertex} edge ${edge} follows ${follows}`];
  for (const conflict of conflicts) lines.push(`  ${report.conflict(grid, conflict)}${conflict.class ? ` ${conflict.class}` : ''}`);
  return lines;
}

function delayedExecution(paths, delays) {
  const steps = paths.map(path => {
    const result = [{time: 0, cell: path[0]}];
    for (let time = 1; time < path.length; time++) {
      if (path[time] !== path[time - 1]) result.push({time, cell: path[time]});
    }
    return result;
  });
  const visits = new Map();
  for (let agent = 0; agent < steps.length; agent++) {
    for (let index = 0; index < steps[agent].length; index++) {
      const step = steps[agent][index];
      if (!visits.has(step.cell)) visits.set(step.cell, []);
      visits.get(step.cell).push({agent, index, time: step.time});
    }
  }
  const prerequisites = steps.map((path, agent) => path.map(step =>
    visits.get(step.cell).filter(visit => visit.agent !== agent && visit.time < step.time)));
  const progress = Array(paths.length).fill(0);
  const finish = Array(paths.length).fill(0);
  let time = 0;
  let held = 0;
  while (progress.some((value, agent) => value < steps[agent].length - 1)) {
    const advancing = [];
    let stopped = 0;
    for (let agent = 0; agent < paths.length; agent++) {
      if (progress[agent] === steps[agent].length - 1) continue;
      if (delays.some(delay => delay.agent === agent && delay.start <= time && time < delay.start + delay.length)) stopped++;
      else if (prerequisites[agent][progress[agent] + 1].every(visit => progress[visit.agent] > visit.index)) advancing.push(agent);
      else held++;
    }
    if (advancing.length === 0 && stopped === 0) return {deadlock: true, time};
    for (const agent of advancing) {
      progress[agent]++;
      finish[agent] = time + 1;
    }
    time++;
  }
  let soc = 0;
  let makespan = 0;
  for (const value of finish) {
    soc += value;
    makespan = Math.max(makespan, value);
  }
  return {deadlock: false, soc, makespan, held, finish};
}

function overviewLines(instance, information) {
  const {grid, agents} = instance;
  const degree = information.degrees;
  const lines = [`instance width ${grid.width} height ${grid.height} free ${information.free} agents ${agents.length}`,
    `map isolated ${degree[0]} dead_ends ${degree[1]} corridors ${degree[2]} junctions ${degree[3]} components ${information.components}`];
  for (const agent of agents) {
    const diagram = information.diagrams[agent.number];
    lines.push(`agent ${agent.name} start ${report.cell(grid, agent.start)} goal ${report.cell(grid, agent.goal)} ` +
      `distance ${agent.shortest} mdd ${diagram.states} width ${diagram.width}`);
  }
  lines.push(`lower_bound soc ${information.bounds.soc} makespan ${information.bounds.makespan}`);
  const vertex = information.conflicts.filter(conflict => conflict.kind === 'vertex').length;
  lines.push(`independent conflicts ${information.conflicts.length} vertex ${vertex} edge ${information.conflicts.length - vertex} ` +
    `cardinal ${information.classCounts.cardinal} semi_cardinal ${information.classCounts.semi_cardinal} non_cardinal ${information.classCounts.non_cardinal}`);
  lines.push(`groups ${information.groups.join(' ') || '-'}`);
  return lines;
}

function solutionLines(instance, run, bounds) {
  const prefix = `run ${run.name} solver ${run.solver} cost_function ${run.costFunction}`;
  if (run.paths === null) return [`${prefix} result FAIL reason ${run.reason}`, ...run.specific];
  const {grid, agents} = instance;
  const stats = run.statistics;
  const bound = run.costFunction === 'SOC' ? bounds.soc : bounds.makespan;
  const lines = [`${prefix} result OK cost ${stats.cost} soc ${stats.soc} makespan ${stats.makespan} ratio ${report.fraction(stats.cost, bound)}`,
    ...run.specific];
  for (const agent of agents) {
    const detail = stats.details[agent.number];
    lines.push(`agent ${agent.name} cost ${detail.cost} extra ${detail.extra} waits ${detail.waits} turns ${detail.turns} ` +
      `arrive ${detail.arrival} leave ${detail.leave} moves ${detail.actions}`);
  }
  lines.push(`arrivals ${stats.arrivals.join(' ')}`);
  lines.push(`hotspots ${stats.hotspots.map(cell => `${report.cell(grid, cell)}:${stats.traffic[cell]}`).join(' ')}`);
  const execution = run.execution;
  lines.push(execution.deadlock ? `execution deadlock time ${execution.time}` :
    `execution soc ${execution.soc} makespan ${execution.makespan} blocked ${execution.held} finish ${execution.finish.join(' ')}`);
  return lines;
}

function csvLine(run) {
  const succeeded = run.paths !== null;
  const values = [run.name, run.solver, run.costFunction, succeeded ? 'OK' : 'FAIL', succeeded ? '-' : run.reason];
  if (succeeded) {
    const stats = run.statistics;
    values.push(stats.cost, stats.soc, stats.makespan, stats.sumExtra, stats.maxExtra, stats.waits, stats.turns,
      run.execution.deadlock ? '-' : run.execution.soc, run.execution.deadlock ? '-' : run.execution.makespan);
  } else for (let index = 0; index < 9; index++) values.push('-');
  values.push(run.highLevel, run.generated === null ? '-' : run.generated, run.budget.searches, run.budget.expansions);
  return report.csv(values);
}

function summaryLines(runs) {
  const successful = runs.filter(run => run.paths !== null);
  const lines = [`summary ok ${successful.length} failed ${runs.length - successful.length}`];
  if (successful.length === 0) return lines;
  for (const field of ['soc', 'makespan']) {
    let best = successful[0].statistics[field];
    for (const run of successful) best = Math.min(best, run.statistics[field]);
    lines.push(`best_${field} ${best} ${successful.filter(run => run.statistics[field] === best).map(run => run.name).join(' ')}`);
  }
  successful.sort((a, b) => a.statistics.soc - b.statistics.soc || a.statistics.makespan - b.statistics.makespan || a.order - b.order);
  lines.push(`ranking ${successful.map(run => run.name).join(' ')}`);
  return lines;
}

function pictureLines(grid, cells) {
  const result = [];
  for (let y = 0; y < grid.height; y++) result.push(cells.slice(y * grid.width, (y + 1) * grid.width).join(''));
  return result;
}

function animation(instance, run) {
  const {grid, agents, parameters} = instance;
  if (run.paths === null) return [`run ${run.name} FAIL`];
  const count = parameters.animation.frames;
  const lines = [`run ${run.name} frames ${count}`];
  for (let time = 0; time < count; time++) {
    const cells = Array.from({length: grid.size}, (_, cell) => grid.free[cell] ? '.' : '@');
    for (const agent of agents) cells[agent.goal] = agent.name.toLowerCase();
    let done = 0;
    let moving = 0;
    let waiting = 0;
    for (const agent of agents) {
      const path = run.paths[agent.number];
      cells[cbs.position(path, time)] = agent.name;
      if (time >= path.length - 1) done++;
      else if (time >= 1 && cbs.position(path, time) !== cbs.position(path, time - 1)) moving++;
      else waiting++;
    }
    lines.push('', `frame ${time} done ${done} moving ${moving} waiting ${waiting}`);
    for (const row of pictureLines(grid, cells)) lines.push(row);
  }
  for (const [title, counts] of [['traffic', run.statistics.traffic], ['waits', run.statistics.cellWaits]]) {
    const cells = counts.map((value, cell) => !grid.free[cell] ? '@' : value === 0 ? '.' : value < 10 ? String(value) : '+');
    lines.push('', title);
    for (const row of pictureLines(grid, cells)) lines.push(row);
  }
  return lines;
}

function main() {
  const instance = gridMap.readInstance();
  instance.parameters = readParameters(instance.agents.length);
  instance.mddCache = instance.agents.map(() => new WeakMap());
  const information = overview(instance);
  const runs = [];
  for (const configuration of instance.parameters.runs) {
    const run = {...configuration, budget: low.counter(instance.parameters.lowBudget), highLevel: 0, generated: null,
      paths: null, reason: null, trace: [`run ${configuration.name}`], specific: []};
    if (run.solver === 'PP') runPP(instance, run);
    else if (run.solver === 'WHCA') runWHCA(instance, run);
    else runCBS(instance, run);
    if (run.paths !== null) {
      run.statistics = planStatistics(instance, run.paths, run.costFunction);
      run.execution = delayedExecution(run.paths, instance.parameters.delays);
    }
    runs.push(run);
  }
  const solutions = overviewLines(instance, information);
  const stats = ['run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions'];
  const validation = validate(instance, 'INDEPENDENT', information.paths, information.conflicts);
  const trace = [];
  for (const run of runs) {
    solutions.push('');
    for (const line of solutionLines(instance, run, information.bounds)) solutions.push(line);
    stats.push(csvLine(run));
    if (run.paths === null) validation.push(`plan ${run.name} verdict NONE`);
    else for (const line of validate(instance, run.name, run.paths)) validation.push(line);
    if (trace.length > 0) trace.push('');
    for (const line of run.trace) trace.push(line);
  }
  solutions.push('');
  for (const line of summaryLines(runs)) solutions.push(line);
  const frames = animation(instance, runs.find(run => run.name === instance.parameters.animation.name));
  report.writeFiles({'solutions.txt': solutions, 'stats.csv': stats, 'validation.txt': validation, 'trace.txt': trace, 'frames.txt': frames});
}

main();
