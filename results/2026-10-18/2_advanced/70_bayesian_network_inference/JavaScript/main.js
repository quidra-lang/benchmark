'use strict';

const fs = require('node:fs');
const {readInputs} = require('./network_io');
const learning = require('./learning');
const factors = require('./factors');
const elimination = require('./elimination');
const {Minstd, weightedSample} = require('./sampling');

const ordered = values => [...new Set(values)].sort((a, b) => a - b);

function sum(values) {
  let result = 0;
  for (const value of values) result += value;
  return result;
}

function real(value) {
  if (Math.abs(value) >= 1e21) return BigInt(value).toString() + '.0000';
  const text = value.toFixed(4);
  return Number(text) === 0 ? '0.0000' : text;
}

function names(network, variables) {
  return variables.length === 0 ? '-' : variables.map(variable => network.variables[variable].name).join(' ');
}

function assignmentText(network, variables, assignment) {
  if (variables.length === 0) return '-';
  return variables.map(index => `${network.variables[index].name}=${network.variables[index].states[assignment[index]]}`).join(' ');
}

function closure(adjacency, seeds) {
  const found = new Set(seeds);
  const queue = [...found];
  for (let index = 0; index < queue.length; index++) {
    for (const next of adjacency[queue[index]]) {
      if (!found.has(next)) {
        found.add(next);
        queue.push(next);
      }
    }
  }
  return found;
}

function prepare(network) {
  network.all = network.variables.map((_, index) => index);
  network.parents = network.variables.map(variable => variable.parents);
  network.children = network.variables.map(() => []);
  for (const index of network.all) {
    for (const parent of network.parents[index]) network.children[parent].push(index);
  }
  const selected = new Set();
  network.topological = [];
  network.depth = Array(network.all.length).fill(0);
  while (selected.size < network.all.length) {
    const next = network.all.find(index => !selected.has(index) && network.parents[index].every(parent => selected.has(parent)));
    selected.add(next);
    network.topological.push(next);
    for (const parent of network.parents[next]) network.depth[next] = Math.max(network.depth[next], network.depth[parent] + 1);
  }
  network.ancestors = network.all.map(index => {
    const result = closure(network.parents, [index]);
    result.delete(index);
    return result;
  });
  network.descendants = network.all.map(index => {
    const result = closure(network.children, [index]);
    result.delete(index);
    return result;
  });
  network.spouses = network.all.map(index => {
    const excluded = new Set([index, ...network.parents[index], ...network.children[index]]);
    return ordered(network.children[index].flatMap(child => network.parents[child]).filter(parent => !excluded.has(parent)));
  });
  network.blankets = network.all.map(index => ordered(network.parents[index].concat(network.children[index], network.spouses[index])));
  let logLikelihood = 0;
  let parameters = 0;
  for (const index of network.all) {
    const variable = network.variables[index];
    variable.counts = learning.countsFor(network, index, variable.parents);
    variable.learned = learning.learnedTable(variable.counts, network.params.alpha);
    variable.cpt = variable.source === 'GIVEN' ? variable.given : variable.learned;
    variable.logLikelihood = learning.logLikelihood(variable.counts, variable.cpt);
    variable.parameters = learning.parameters(variable.counts);
    variable.bic = variable.logLikelihood - variable.parameters * Math.log(network.samples.length) / 2;
    logLikelihood += variable.logLikelihood;
    parameters += variable.parameters;
  }
  network.logLikelihood = logLikelihood;
  network.parameters = parameters;
  network.bic = logLikelihood - parameters * Math.log(network.samples.length) / 2;
  network.cptFactors = network.all.map(index => factors.cptFactor(network, index));
  return network;
}

function makeProblem(network, query, evidence, complete = false) {
  const relevantSet = complete ? new Set(network.all) : closure(network.parents, query.concat([...evidence.keys()]));
  const relevant = network.all.filter(variable => relevantSet.has(variable));
  const pruned = network.all.filter(variable => !relevantSet.has(variable));
  const kept = new Set(query.concat([...evidence.keys()]));
  const variables = relevant.filter(variable => !kept.has(variable));
  const initial = relevant.map(variable => factors.reduce(network.cptFactors[variable], evidence, network.sizes));
  const plans = {};
  for (const method of ['minfill', 'given']) {
    plans[method] = elimination.plan(initial, variables, method, network.params.order, network.sizes);
  }
  return {relevant, pruned, variables, initial, plans};
}

function posteriorFrom(network, query, problem, method) {
  const factor = elimination.execute(problem.initial, problem.plans[method], network.sizes).factor;
  const normalizer = sum(factor.values);
  const probabilities = factor.values.map(value => value / normalizer);
  const marginals = new Map(query.map(variable => [variable, Array(network.sizes[variable]).fill(0)]));
  let index = 0;
  for (const assignment of factors.assignments(factor.variables, network.sizes)) {
    for (const variable of query) marginals.get(variable)[assignment[variable]] += probabilities[index];
    index++;
  }
  return {factor, normalizer, logEvidence: Math.log(normalizer), probabilities, marginals};
}

function posterior(network, query, evidence) {
  return posteriorFrom(network, query, makeProblem(network, query, evidence), network.params.method);
}

function jointProbability(network, variables, assignment) {
  let probability = 1;
  for (const index of variables) {
    const variable = network.variables[index];
    const row = learning.combinationIndex(variable.parents, assignment, network.sizes);
    probability *= variable.cpt[row][assignment[index]];
  }
  return probability;
}

function posteriorAgreement(first, second) {
  return Math.abs(first.logEvidence - second.logEvidence) <= 1e-9 &&
    first.probabilities.every((value, index) => Math.abs(value - second.probabilities[index]) <= 1e-9);
}

function enumerateQuery(network, problem, evidence, result) {
  const free = problem.relevant.filter(variable => !evidence.has(variable));
  const count = factors.assignmentCount(free, network.sizes);
  if (count > network.params.limit) return {count, status: 'skipped'};
  const values = Array(result.probabilities.length).fill(0);
  for (const assignment of factors.assignments(free, network.sizes)) {
    for (const [variable, state] of evidence) assignment[variable] = state;
    const index = learning.combinationIndex(result.factor.variables, assignment, network.sizes);
    values[index] += jointProbability(network, problem.relevant, assignment);
  }
  const normalizer = sum(values);
  const agrees = Math.abs(Math.log(normalizer) - result.logEvidence) <= 1e-9 &&
    values.every((value, index) => Math.abs(value / normalizer - result.probabilities[index]) <= 1e-9);
  return {count, status: agrees ? 'agree' : 'disagree'};
}

function eliminationLines(network, problem, agree, enumeration) {
  const lines = [`relevant ${names(network, problem.relevant)}`, `pruned ${names(network, problem.pruned)}`,
    `eliminate ${names(network, problem.variables)}`];
  for (const method of ['minfill', 'given']) {
    lines.push(`order ${method}`);
    for (const step of problem.plans[method].steps) {
      lines.push(`step ${network.variables[step.variable].name} fill ${step.fill} scope ${names(network, step.variables)} entries ${step.size}`);
    }
    lines.push(`cost max ${problem.plans[method].maximum} total ${problem.plans[method].total}`);
  }
  lines.push(`used ${network.params.method}`, `orders_agree ${agree ? 'yes' : 'no'}`,
    `enumeration ${enumeration.count} ${enumeration.status}`);
  return lines;
}

function distributionLine(network, prefix, variable, probabilities) {
  const tokens = [prefix, network.variables[variable].name];
  for (let state = 0; state < probabilities.length; state++) tokens.push(network.variables[variable].states[state], real(probabilities[state]));
  return tokens.join(' ');
}

function queryAnswer(network, query, evidence) {
  const problem = makeProblem(network, query, evidence);
  const minfill = posteriorFrom(network, query, problem, 'minfill');
  const given = posteriorFrom(network, query, problem, 'given');
  const result = network.params.method === 'minfill' ? minfill : given;
  const lines = [`log_evidence ${real(result.logEvidence)}`];
  if (evidence.size > 0) {
    let conflict = 0;
    for (const entry of evidence) conflict += posterior(network, [], new Map([entry])).logEvidence;
    lines.push(`conflict ${real(conflict - result.logEvidence)}`);
  }
  if (query.length >= 2) {
    let index = 0;
    for (const assignment of factors.assignments(result.factor.variables, network.sizes)) {
      lines.push(`joint ${assignmentText(network, result.factor.variables, assignment)} ${real(result.probabilities[index++])}`);
    }
  }
  for (const variable of query) lines.push(distributionLine(network, 'marginal', variable, result.marginals.get(variable)));
  for (const [removed, state] of evidence) {
    const reduced = new Map(evidence);
    reduced.delete(removed);
    const without = posterior(network, query, reduced);
    let influence = 0;
    for (const variable of query) {
      for (let s = 0; s < network.sizes[variable]; s++) {
        influence = Math.max(influence, Math.abs(result.marginals.get(variable)[s] - without.marginals.get(variable)[s]));
      }
    }
    lines.push(`drop ${network.variables[removed].name}=${network.variables[removed].states[state]} shift ${real(influence)}`);
  }
  const enumeration = enumerateQuery(network, problem, evidence, result);
  return {lines, elimination: eliminationLines(network, problem, posteriorAgreement(minfill, given), enumeration)};
}

function enumerateMpe(network, problem, evidence, assignment, probability) {
  const count = factors.assignmentCount(problem.variables, network.sizes);
  if (count > network.params.limit) return {count, status: 'skipped'};
  let maximum = -Infinity;
  let best = null;
  for (const candidate of factors.assignments(problem.variables, network.sizes)) {
    for (const [variable, state] of evidence) candidate[variable] = state;
    const value = jointProbability(network, network.all, candidate);
    if (value > maximum) {
      maximum = value;
      best = candidate;
    }
  }
  const agrees = best.every((state, index) => state === assignment[index]) && Math.abs(Math.log(maximum) - Math.log(probability)) <= 1e-9;
  return {count, status: agrees ? 'agree' : 'disagree'};
}

function mpeAnswer(network, evidence) {
  const problem = makeProblem(network, [], evidence, true);
  const results = {};
  for (const method of ['minfill', 'given']) {
    const result = elimination.execute(problem.initial, problem.plans[method], network.sizes, true);
    results[method] = {assignment: elimination.traceback(result, evidence, network.sizes), probability: result.factor.values[0]};
  }
  const result = results[network.params.method];
  const evidenceProbability = evidence.size === 0 ? 1 : posterior(network, [], evidence).normalizer;
  const logJoint = Math.log(result.probability);
  const lines = [`assignment ${assignmentText(network, network.all, result.assignment)}`,
    `log_joint ${real(logJoint)}`, `log_evidence ${real(Math.log(evidenceProbability))}`,
    `posterior ${real(result.probability / evidenceProbability)}`];
  for (const variable of problem.variables) {
    const eliminated = problem.variables.filter(index => index !== variable);
    const plan = elimination.plan(problem.initial, eliminated, network.params.method, network.params.order, network.sizes);
    const factor = elimination.execute(problem.initial, plan, network.sizes, true).factor;
    let second = null;
    for (let state = 0; state < network.sizes[variable]; state++) {
      if (state !== result.assignment[variable] && (second === null || factor.values[state] > factor.values[second])) second = state;
    }
    lines.push(`margin ${network.variables[variable].name} ${network.variables[variable].states[second]} ${real(logJoint - Math.log(factor.values[second]))}`);
  }
  const agree = results.minfill.assignment.every((state, index) => state === results.given.assignment[index]) &&
    Math.abs(Math.log(results.minfill.probability) - Math.log(results.given.probability)) <= 1e-9;
  const enumeration = enumerateMpe(network, problem, evidence, result.assignment, result.probability);
  return {lines, elimination: eliminationLines(network, problem, agree, enumeration)};
}

function sampleAnswer(network, query, evidence, counts, random, number, csv) {
  const exact = posterior(network, query, evidence);
  const lines = query.map(variable => distributionLine(network, 'exact', variable, exact.marginals.get(variable)));
  const totals = new Map(query.map(variable => [variable, Array(network.sizes[variable]).fill(0)]));
  let weight = 0;
  let squaredWeight = 0;
  let checkpoint = 0;
  for (let count = 1; count <= counts.at(-1); count++) {
    const sample = weightedSample(network, evidence, random);
    weight += sample.weight;
    squaredWeight += sample.weight * sample.weight;
    for (const variable of query) totals.get(variable)[sample.assignment[variable]] += sample.weight;
    if (count !== counts[checkpoint]) continue;
    let maximumError = 0;
    for (const variable of query) {
      for (let state = 0; state < network.sizes[variable]; state++) {
        const estimate = totals.get(variable)[state] / weight;
        const truth = exact.marginals.get(variable)[state];
        const error = Math.abs(estimate - truth);
        maximumError = Math.max(maximumError, error);
        csv.push(`${number},${count},${network.variables[variable].name},${network.variables[variable].states[state]},${real(estimate)},${real(truth)},${real(error)}`);
      }
    }
    lines.push(`after ${count} weight ${real(weight)} ess ${real(weight * weight / squaredWeight)} max_error ${real(maximumError)}`);
    checkpoint++;
  }
  return lines;
}

function predictAnswer(network, index) {
  const variable = network.variables[index];
  const confusion = Array.from({length: network.sizes[index]}, () => Array(network.sizes[index]).fill(0));
  let logProbability = 0;
  for (const sample of network.samples) {
    const assignment = sample.slice();
    const values = [];
    for (let state = 0; state < network.sizes[index]; state++) {
      assignment[index] = state;
      let value = variable.cpt[learning.combinationIndex(variable.parents, assignment, network.sizes)][state];
      for (const child of network.children[index]) {
        const model = network.variables[child];
        value *= model.cpt[learning.combinationIndex(model.parents, assignment, network.sizes)][assignment[child]];
      }
      values.push(value);
    }
    const normalizer = sum(values);
    const probabilities = values.map(value => value / normalizer);
    let best = 0;
    for (let state = 1; state < probabilities.length; state++) if (probabilities[state] > probabilities[best]) best = state;
    confusion[sample[index]][best]++;
    logProbability += Math.log(probabilities[sample[index]]);
  }
  let correct = 0;
  for (let state = 0; state < confusion.length; state++) correct += confusion[state][state];
  const lines = [`blanket ${names(network, network.blankets[index])}`,
    `accuracy ${correct}/${network.samples.length} ${real(correct / network.samples.length)}`,
    `log_loss ${real(-logProbability / network.samples.length)}`, `predicted ${variable.states.join(' ')}`];
  for (let state = 0; state < confusion.length; state++) lines.push(`actual ${variable.states[state]} ${confusion[state].join(' ')}`);
  return lines;
}

function bayesBall(network, x, y, z) {
  const observed = new Set(z);
  const sources = new Set(x);
  const ancestors = closure(network.parents, z);
  const visited = new Set();
  const queue = [];
  const add = (variable, direction) => {
    const position = 2 * variable + direction;
    if (!visited.has(position)) {
      visited.add(position);
      queue.push([variable, direction]);
    }
  };
  for (const variable of x) add(variable, 0);
  for (let index = 0; index < queue.length; index++) {
    const [variable, direction] = queue[index];
    if (direction === 0 && !observed.has(variable)) {
      for (const parent of network.parents[variable]) add(parent, 0);
      for (const child of network.children[variable]) add(child, 1);
    }
    if (direction === 1) {
      if (!observed.has(variable)) for (const child of network.children[variable]) add(child, 1);
      if (ancestors.has(variable)) for (const parent of network.parents[variable]) add(parent, 0);
    }
  }
  const reachable = network.all.filter(variable => !sources.has(variable) && !observed.has(variable) &&
    (visited.has(2 * variable) || visited.has(2 * variable + 1)));
  return {reachable, separated: y.every(variable => !reachable.includes(variable))};
}

function observedCounts(network, variables) {
  const counts = new Map();
  for (const sample of network.samples) {
    const index = learning.combinationIndex(variables, sample, network.sizes);
    counts.set(index, (counts.get(index) || 0) + 1);
  }
  return counts;
}

function conditionalInformation(network, x, y, z) {
  const all = ordered(x.concat(y, z));
  const xz = ordered(x.concat(z));
  const yz = ordered(y.concat(z));
  const counts = observedCounts(network, all);
  const countsXz = observedCounts(network, xz);
  const countsYz = observedCounts(network, yz);
  const countsZ = observedCounts(network, z);
  let information = 0;
  // Only nonzero cells contribute; mixed-radix indices retain canonical order.
  for (const index of [...counts.keys()].sort((a, b) => a - b)) {
    const assignment = factors.decode(all, index, network.sizes);
    const count = counts.get(index);
    const countXz = countsXz.get(learning.combinationIndex(xz, assignment, network.sizes));
    const countYz = countsYz.get(learning.combinationIndex(yz, assignment, network.sizes));
    const countZ = countsZ.get(learning.combinationIndex(z, assignment, network.sizes));
    information += count / network.samples.length * Math.log((count * countZ) / (countXz * countYz));
  }
  const df = (factors.assignmentCount(x, network.sizes) - 1) * (factors.assignmentCount(y, network.sizes) - 1)
    * factors.assignmentCount(z, network.sizes);
  return {cmi: information, g2: 2 * network.samples.length * information, df};
}

function dsepAnswer(network, x, y, z) {
  const result = bayesBall(network, x, y, z);
  const information = conditionalInformation(network, x, y, z);
  return [`result ${result.separated ? 'separated' : 'connected'}`, `reachable ${names(network, result.reachable)}`,
    `data cmi ${real(information.cmi)} g2 ${real(information.g2)} df ${information.df}`];
}

function blanketAnswer(network, variable) {
  const blanket = network.blankets[variable];
  const rest = network.all.filter(index => index !== variable && !blanket.includes(index));
  const separated = bayesBall(network, [variable], rest, blanket).separated;
  return [`parents ${names(network, network.parents[variable])}`, `children ${names(network, network.children[variable])}`,
    `spouses ${names(network, network.spouses[variable])}`, `blanket ${names(network, blanket)}`,
    `rest ${names(network, rest)}`, `rest_separated ${separated ? 'yes' : 'no'}`];
}

function directedPath(network, start, target, ignored = null) {
  const marked = new Set([start]);
  const queue = [start];
  const previous = Array(network.all.length);
  for (let index = 0; index < queue.length; index++) {
    const current = queue[index];
    for (const child of network.children[current]) {
      if (ignored !== null && current === ignored[0] && child === ignored[1]) continue;
      if (marked.has(child)) continue;
      marked.add(child);
      previous[child] = current;
      if (child === target) {
        const path = [target];
        while (path.at(-1) !== start) path.push(previous[path.at(-1)]);
        return path.reverse();
      }
      queue.push(child);
    }
  }
  return null;
}

function edgeAnswer(network, operation, x, y) {
  const exists = network.parents[y].includes(x);
  if (operation === 'ADD' && exists) return ['result exists'];
  if (operation !== 'ADD' && !exists) return ['result missing'];
  let cycle = null;
  if (operation === 'ADD') {
    const path = directedPath(network, y, x);
    if (path !== null) cycle = [x, ...path];
  } else if (operation === 'REVERSE') {
    const path = directedPath(network, x, y, [x, y]);
    if (path !== null) cycle = [y, ...path];
  }
  if (cycle !== null) return ['result cycle ' + cycle.map(index => network.variables[index].name).join(' -> ')];
  const before = learning.familyScore(network, y, network.parents[y]);
  const changedParents = operation === 'ADD' ? network.parents[y].concat(x) : network.parents[y].filter(parent => parent !== x);
  const after = learning.familyScore(network, y, changedParents);
  let change = after - before;
  const lines = ['result ok', `family ${network.variables[y].name} before ${real(before)} after ${real(after)}`];
  if (operation === 'REVERSE') {
    const beforeX = learning.familyScore(network, x, network.parents[x]);
    const afterX = learning.familyScore(network, x, network.parents[x].concat(y));
    change += afterX - beforeX;
    lines.push(`family ${network.variables[x].name} before ${real(beforeX)} after ${real(afterX)}`);
  }
  lines.push(`delta ${real(change)} ${change > 0 ? 'improves' : 'worsens'}`);
  return lines;
}

function joinBlocks(blocks) {
  const lines = [];
  for (const block of blocks) {
    if (lines.length > 0) lines.push('');
    for (const line of block) lines.push(line);
  }
  return lines;
}

function cptLines(network) {
  const blocks = [];
  for (const index of network.all) {
    const variable = network.variables[index];
    const lines = [`variable ${variable.name} source ${variable.source}`, `states ${variable.states.join(' ')}`,
      `parents ${names(network, variable.parents)}`];
    for (let row = 0; row < variable.counts.length; row++) {
      const assignment = factors.decode(variable.parents, row, network.sizes);
      lines.push(`row ${assignmentText(network, variable.parents, assignment)} counts ${variable.counts[row].join(' ')}`
        + ` probs ${variable.cpt[row].map(value => real(value)).join(' ')}`);
    }
    lines.push(`loglik ${real(variable.logLikelihood)} parameters ${variable.parameters} bic ${real(variable.bic)}`);
    const marginal = posterior(network, [index], new Map()).marginals.get(index);
    const frequencies = Array(network.sizes[index]).fill(0);
    for (const sample of network.samples) frequencies[sample[index]]++;
    lines.push(`marginal model ${marginal.map(value => real(value)).join(' ')} data ${frequencies.map(count => real(count / network.samples.length)).join(' ')}`);
    if (variable.source === 'LEARNED') {
      let difference = 0;
      if (variable.given !== null) {
        for (let row = 0; row < variable.learned.length; row++) {
          for (let state = 0; state < network.sizes[index]; state++) {
            difference = Math.max(difference, Math.abs(variable.learned[row][state] - variable.given[row][state]));
          }
        }
      }
      lines.push(`given_difference ${variable.given === null ? '-' : real(difference)}`);
    }
    blocks.push(lines);
  }
  blocks.push([`network samples ${network.samples.length} pseudocount ${real(network.params.alpha)}`
    + ` loglik ${real(network.logLikelihood)} parameters ${network.parameters} bic ${real(network.bic)}`]);
  return joinBlocks(blocks);
}

function structureLines(network) {
  const graph = elimination.interactionGraph(network.cptFactors);
  let moralEdges = 0;
  for (const neighbors of graph.values()) moralEdges += neighbors.size;
  const widths = {};
  for (const method of ['minfill', 'given']) {
    const plan = elimination.plan(network.cptFactors, network.all, method, network.params.order, network.sizes);
    let width = 0;
    for (const step of plan.steps) width = Math.max(width, step.variables.length - 1);
    widths[method] = width;
  }
  const roots = network.all.filter(index => network.parents[index].length === 0);
  const leaves = network.all.filter(index => network.children[index].length === 0);
  const lines = [`variables ${network.all.length} edges ${sum(network.parents.map(parents => parents.length))}`,
    `topological_order ${names(network, network.topological)}`, `roots ${names(network, roots)}`, `leaves ${names(network, leaves)}`,
    `moral_edges ${moralEdges / 2} width minfill ${widths.minfill} given ${widths.given}`];
  for (const index of network.all) {
    lines.push(`variable ${network.variables[index].name} states ${network.sizes[index]} parents ${network.parents[index].length}`
      + ` children ${network.children[index].length} depth ${network.depth[index]} ancestors ${network.ancestors[index].size}`
      + ` descendants ${network.descendants[index].size} blanket ${network.blankets[index].length}`);
  }
  return lines;
}

function parseEvidence(network, tokens) {
  return new Map(tokens.map(token => {
    const [name, state] = token.split('=');
    const variable = network.names.get(name);
    return [variable, network.stateNames[variable].get(state)];
  }));
}

function parsePosterior(network, tokens) {
  const separator = tokens.indexOf('|');
  const query = (separator < 0 ? tokens : tokens.slice(0, separator)).map(name => network.names.get(name));
  const evidence = parseEvidence(network, separator < 0 ? [] : tokens.slice(separator + 1));
  return {query, evidence};
}

function main() {
  const input = readInputs();
  const random = new Minstd(input.params.seed);
  const network = prepare(input);
  const structure = [structureLines(network)];
  const answers = [];
  const plans = [];
  const sampling = ['query,samples,variable,state,estimate,exact,abs_error'];
  for (let index = 0; index < network.queries.length; index++) {
    const line = network.queries[index];
    const tokens = line.split(' ');
    const header = `query ${index + 1} ${line}`;
    if (tokens[0] === 'QUERY') {
      const {query, evidence} = parsePosterior(network, tokens.slice(1));
      const result = queryAnswer(network, query, evidence);
      answers.push([header, ...result.lines]);
      plans.push([header, ...result.elimination]);
    } else if (tokens[0] === 'MPE') {
      const result = mpeAnswer(network, parseEvidence(network, tokens.slice(1)));
      answers.push([header, ...result.lines]);
      plans.push([header, ...result.elimination]);
    } else if (tokens[0] === 'SAMPLE') {
      const separator = tokens.lastIndexOf('COUNTS');
      const {query, evidence} = parsePosterior(network, tokens.slice(1, separator));
      const counts = tokens.slice(separator + 1).map(Number);
      answers.push([header, ...sampleAnswer(network, query, evidence, counts, random, index + 1, sampling)]);
    } else if (tokens[0] === 'PREDICT') {
      answers.push([header, ...predictAnswer(network, network.names.get(tokens[1]))]);
    } else if (tokens[0] === 'DSEP') {
      const groups = [[]];
      for (const token of tokens.slice(1)) {
        if (token === '|') groups.push([]);
        else groups.at(-1).push(network.names.get(token));
      }
      const [x, y, z = []] = groups.map(group => ordered(group));
      structure.push([header, ...dsepAnswer(network, x, y, z)]);
    } else if (tokens[0] === 'BLANKET') {
      structure.push([header, ...blanketAnswer(network, network.names.get(tokens[1]))]);
    } else {
      structure.push([header, ...edgeAnswer(network, tokens[1], network.names.get(tokens[2]), network.names.get(tokens[3]))]);
    }
  }
  const files = {'cpts.txt': cptLines(network), 'structure.txt': joinBlocks(structure),
    'answers.txt': joinBlocks(answers), 'elimination.txt': joinBlocks(plans), 'sampling.csv': sampling};
  fs.mkdirSync('output', {recursive: true});
  for (const [name, lines] of Object.entries(files)) {
    fs.writeFileSync('output/' + name, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
  }
}

main();
