'use strict';

const fs = require('node:fs');
const parser = require('./lp_parser');
const {Rational, zero, one, approximate, endpoint} = require('./rational');
const {Tableau} = require('./tableau');
const simplex = require('./simplex');
const branchBound = require('./branch_bound');

function append(target, lines) {
  for (const line of lines) target.push(line);
}

function dot(first, second) {
  let value = zero;
  for (let index = 0; index < first.length; index++) value = value.add(first[index].multiply(second[index]));
  return value;
}

function coefficients(terms, variables, indices) {
  const result = variables.map(() => zero);
  for (const term of terms) {
    const index = indices.get(term.name);
    result[index] = result[index].add(term.coefficient);
  }
  return result;
}

function modelData(raw) {
  if (raw.error !== null) return {name: raw.name, error: raw.error};
  const variables = [];
  const indices = new Map();
  for (const expression of [raw.objective, ...raw.constraints]) {
    for (const term of expression.terms) {
      if (!indices.has(term.name)) {
        indices.set(term.name, variables.length);
        variables.push(term.name);
      }
    }
  }
  const model = {name: raw.name, direction: raw.direction, variables, error: null,
    c: coefficients(raw.objective.terms, variables, indices),
    constraints: raw.constraints.map(constraint => ({...constraint,
      coefficients: coefficients(constraint.terms, variables, indices)})),
    lower: variables.map(() => zero), upper: variables.map(() => null), integers: []};
  const fail = (line, message) => {
    model.error = {line, message};
    return model;
  };
  const inconsistent = index => model.lower[index] !== null && model.upper[index] !== null &&
    model.lower[index].compare(model.upper[index]) > 0;
  const named = new Set();
  for (const constraint of model.constraints) {
    if (named.has(constraint.name)) return fail(constraint.line, `duplicate constraint ${constraint.name}`);
    named.add(constraint.name);
  }
  for (const bound of raw.bounds) {
    if (!indices.has(bound.name)) return fail(bound.line, `unknown variable ${bound.name}`);
    const index = indices.get(bound.name);
    if (bound.kind === 'both') {
      model.lower[index] = bound.lower;
      model.upper[index] = bound.upper;
    } else if (bound.kind === 'lower') model.lower[index] = bound.value;
    else model.upper[index] = bound.value;
    if (inconsistent(index)) return fail(bound.line, `inconsistent bounds ${bound.name}`);
  }
  const integral = variables.map(() => false);
  for (const declaration of raw.integers) {
    for (const name of declaration.names) {
      if (!indices.has(name)) return fail(declaration.line, `unknown variable ${name}`);
      const index = indices.get(name);
      integral[index] = true;
      if (model.lower[index] !== null) model.lower[index] = new Rational(model.lower[index].ceil());
      if (model.upper[index] !== null) model.upper[index] = new Rational(model.upper[index].floor());
      if (inconsistent(index)) return fail(declaration.line, `inconsistent bounds ${name}`);
    }
  }
  for (const declaration of raw.binaries) {
    for (const name of declaration.names) {
      if (!indices.has(name)) return fail(declaration.line, `unknown variable ${name}`);
      const index = indices.get(name);
      integral[index] = true;
      model.lower[index] = zero;
      model.upper[index] = one;
    }
  }
  model.integers = variables.map((_, index) => index).filter(index => integral[index]);
  return model;
}

function standardForm(model, lower, upper) {
  const columns = [];
  const maps = [];
  function addVariableColumn(name, variable, direction) {
    const number = columns.length;
    columns.push({name, variable, direction, artificial: false});
    return number;
  }
  for (let variable = 0; variable < model.variables.length; variable++) {
    const name = model.variables[variable];
    if (lower[variable] !== null) {
      maps.push({kind: 'shift', offset: lower[variable], upperRow: null,
        columns: [addVariableColumn(name, variable, 1)]});
    } else if (upper[variable] !== null) {
      maps.push({kind: 'reflect', offset: upper[variable], upperRow: null,
        columns: [addVariableColumn(name + "'", variable, -1)]});
    } else {
      maps.push({kind: 'split', offset: zero, upperRow: null,
        columns: [addVariableColumn(name + '+', variable, 1), addVariableColumn(name + '-', variable, -1)]});
    }
  }
  const offsets = maps.map(mapping => mapping.offset);
  const rows = model.constraints.map(constraint => ({name: constraint.name, op: constraint.op,
    values: columns.map(column => constraint.coefficients[column.variable].multiply(column.direction)),
    rhs: constraint.rhs.subtract(dot(constraint.coefficients, offsets)), sigma: 1, slack: null, artificial: null}));
  for (let variable = 0; variable < maps.length; variable++) {
    if (maps[variable].kind !== 'shift' || upper[variable] === null) continue;
    const values = columns.map(() => zero);
    values[maps[variable].columns[0]] = one;
    maps[variable].upperRow = rows.length;
    rows.push({name: model.variables[variable] + '.ub', op: '<=', values,
      rhs: upper[variable].subtract(lower[variable]), sigma: 1, slack: null, artificial: null});
  }
  for (const row of rows) {
    if (row.rhs.n >= 0n) continue;
    row.values = row.values.map(value => value.negate());
    row.rhs = row.rhs.negate();
    row.op = row.op === '<=' ? '>=' : row.op === '>=' ? '<=' : '=';
    row.sigma = -1;
  }
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index];
    if (row.op === '=') continue;
    row.slack = columns.length;
    columns.push({name: 's:' + row.name, variable: null, direction: 0, artificial: false});
    for (let other = 0; other < rows.length; other++) {
      rows[other].values.push(other === index ? one.multiply(row.op === '<=' ? 1 : -1) : zero);
    }
  }
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index];
    if (row.op === '<=') continue;
    row.artificial = columns.length;
    columns.push({name: 'a:' + row.name, variable: null, direction: 0, artificial: true});
    for (let other = 0; other < rows.length; other++) rows[other].values.push(other === index ? one : zero);
  }
  for (const row of rows) row.initial = row.op === '<=' ? row.slack : row.artificial;
  const sign = model.direction === 'minimize' ? 1 : -1;
  const phase1 = columns.map(column => column.artificial ? one : zero);
  const phase2 = columns.map(column => column.variable === null ? zero :
    model.c[column.variable].multiply(column.direction * sign));
  return {model, lower, upper, columns, maps, rows, phase1, phase2, sign,
    constant: dot(model.c, offsets), artificialCount: columns.filter(column => column.artificial).length};
}

function originalValues(form, values, includeOffset = true) {
  return form.maps.map(mapping => {
    let value = includeOffset ? mapping.offset : zero;
    for (const column of mapping.columns) value = value.add(values[column].multiply(form.columns[column].direction));
    return value;
  });
}

function solveLP(model, lower, upper, node, logLevel) {
  const form = standardForm(model, lower, upper);
  const tableau = new Tableau(form);
  const lines = [];
  const emit = (level, line) => {
    if (level <= logLevel) lines.push(line);
  };
  const phaseLines = lines_ => {
    if (logLevel >= 1) append(lines, lines_);
  };
  const display = (heading, costs, objective) => {
    if (logLevel >= 2) append(lines, tableau.display(heading, costs, objective));
  };
  const objective = value => form.constant.add(value.multiply(form.sign));
  const identity = value => value;
  const result = {form, tableau, lines, phase1: 0, phase2: 0, drives: 0, redundant: 0,
    objective: null, solution: null, w: zero};
  const finish = status => {
    result.status = status;
    result.pivots = result.phase1 + result.phase2 + result.drives;
    emit(0, `RESULT ${status} objective ${result.objective === null ? '-' : result.objective} ` +
      `phase1 ${result.phase1} phase2 ${result.phase2} drives ${result.drives} redundant ${result.redundant}`);
    return result;
  };
  emit(0, `SOLVE node ${node} rows ${form.rows.length} columns ${form.columns.length} artificials ${form.artificialCount}`);
  for (let variable = 0; variable < model.variables.length; variable++) {
    const mapping = form.maps[variable];
    let line = `MAP ${model.variables[variable]} ${mapping.kind}`;
    if (mapping.kind === 'shift') line += ` ${lower[variable]}` + (upper[variable] === null ? '' : ` upper ${upper[variable]}`);
    else if (mapping.kind === 'reflect') line += ` ${upper[variable]}`;
    emit(1, line);
  }
  for (const row of form.rows) if (row.sigma === -1) emit(1, `FLIP ${row.name}`);
  if (form.artificialCount > 0) {
    emit(1, 'PHASE 1');
    display('phase 1 start', form.phase1, identity);
    const phase = simplex.phase(tableau, form.phase1, form.columns.map((_, index) => index), identity);
    result.phase1 = phase.iterations;
    phaseLines(phase.lines);
    const reduced = tableau.reduced(form.phase1);
    result.w = reduced.value;
    emit(1, `PHASE 1 END objective ${result.w} iterations ${result.phase1}`);
    if (result.w.n > 0n) {
      result.farkas = form.rows.map(row => form.phase1[row.initial].subtract(reduced.costs[row.initial]).multiply(row.sigma));
      display('final', form.phase1, identity);
      return finish('INFEASIBLE');
    }
    for (let row = 0; row < form.rows.length; row++) {
      const leaving = tableau.basis[row];
      if (!form.columns[leaving].artificial) continue;
      const entering = form.columns.findIndex((column, index) => !column.artificial && tableau.T[row][index].n !== 0n);
      if (entering === -1) {
        result.redundant++;
        emit(1, `REDUNDANT row ${form.rows[row].name}`);
      } else {
        emit(1, `DRIVE row ${form.rows[row].name} enter ${form.columns[entering].name} leave ${form.columns[leaving].name}`);
        tableau.pivot(row, entering);
        result.drives++;
      }
    }
  }
  emit(1, 'PHASE 2');
  display('phase 2 start', form.phase2, objective);
  const candidates = form.columns.map((_, index) => index).filter(index => !form.columns[index].artificial);
  const phase = simplex.phase(tableau, form.phase2, candidates, objective);
  result.phase2 = phase.iterations;
  phaseLines(phase.lines);
  if (phase.status === 'unbounded') emit(1, `UNBOUNDED enter ${form.columns[phase.entering].name}`);
  const value = objective(tableau.reduced(form.phase2).value);
  emit(1, `PHASE 2 END objective ${value} iterations ${result.phase2}`);
  display('final', form.phase2, objective);
  result.solution = originalValues(form, tableau.solution());
  if (phase.status === 'optimal') {
    result.objective = value;
    return finish('OPTIMAL');
  }
  const delta = form.columns.map(() => zero);
  delta[phase.entering] = one;
  for (let row = 0; row < form.rows.length; row++) delta[tableau.basis[row]] = tableau.T[row][phase.entering].negate();
  result.ray = originalValues(form, delta, false);
  result.rate = dot(model.c, result.ray);
  return finish('UNBOUNDED');
}

function extrema(values) {
  let minimum = null;
  let maximum = null;
  for (const value of values) {
    if (value === null || value.n === 0n) continue;
    const absolute = value.abs();
    if (minimum === null || absolute.compare(minimum) < 0) minimum = absolute;
    if (maximum === null || absolute.compare(maximum) > 0) maximum = absolute;
  }
  return minimum === null ? '- -' : `${minimum} ${maximum}`;
}

function coefficientStatistics(model) {
  const matrix = model.constraints.flatMap(constraint => constraint.coefficients);
  const nonzeros = matrix.filter(value => value.n !== 0n).length;
  return `STATS nonzeros ${nonzeros} matrix ${extrema(matrix)} objective ${extrema(model.c)} ` +
    `rhs ${extrema(model.constraints.map(constraint => constraint.rhs))} bounds ${extrema(model.lower.concat(model.upper))}`;
}

function shiftedRange(base, inequalities) {
  let lower = null;
  let upper = null;
  for (const [current, slope] of inequalities) {
    if (slope.n === 0n) continue;
    const limit = current.negate().divide(slope);
    if (slope.n > 0n) {
      if (lower === null || limit.compare(lower) > 0) lower = limit;
    } else if (upper === null || limit.compare(upper) < 0) upper = limit;
  }
  return [lower === null ? null : base.add(lower), upper === null ? null : base.add(upper)];
}

function basisStatus(form, variable, basic) {
  const mapping = form.maps[variable];
  if (mapping.kind === 'split') return mapping.columns.every(column => !basic.has(column)) ? 'zero' : 'basic';
  const present = basic.has(mapping.columns[0]);
  if (mapping.kind === 'reflect') return present ? 'basic' : 'upper';
  if (!present) return 'lower';
  if (mapping.upperRow !== null && !basic.has(form.rows[mapping.upperRow].slack)) return 'upper';
  return 'basic';
}

function sensitivity(model, root) {
  const {form, tableau} = root;
  const reduced = tableau.reduced(form.phase2).costs;
  const basic = new Set(tableau.basis);
  const dual = model.constraints.map((_, index) => reduced[form.rows[index].initial].multiply(-form.sign * form.rows[index].sigma));
  const variableReduced = model.variables.map((_, variable) => {
    let value = model.c[variable];
    for (let row = 0; row < model.constraints.length; row++) {
      value = value.subtract(dual[row].multiply(model.constraints[row].coefficients[variable]));
    }
    return value;
  });
  const coefficientRanges = model.variables.map((_, variable) => {
    const h = form.columns.map(column => column.variable === variable ? one.multiply(form.sign * column.direction) : zero);
    const eta = tableau.reduced(h).costs;
    const inequalities = [];
    for (let column = 0; column < form.columns.length; column++) {
      if (!basic.has(column) && !form.columns[column].artificial) inequalities.push([reduced[column], eta[column]]);
    }
    return shiftedRange(model.c[variable], inequalities);
  });
  const rhsRanges = model.constraints.map((constraint, index) => {
    const row = form.rows[index];
    const rho = tableau.T.map(values => values[row.initial].multiply(row.sigma));
    for (let other = 0; other < form.rows.length; other++) {
      if (rho[other].n !== 0n && form.columns[tableau.basis[other]].artificial) return [constraint.rhs, constraint.rhs];
    }
    return shiftedRange(constraint.rhs, tableau.beta.map((value, other) => [value, rho[other]]));
  });
  let primalDegeneracy = 0;
  for (let row = 0; row < form.rows.length; row++) {
    if (!form.columns[tableau.basis[row]].artificial && tableau.beta[row].n === 0n) primalDegeneracy++;
  }
  let dualDegeneracy = 0;
  for (let column = 0; column < form.columns.length; column++) {
    if (!basic.has(column) && !form.columns[column].artificial && reduced[column].n === 0n) dualDegeneracy++;
  }
  const dualObjective = dot(dual, model.constraints.map(constraint => constraint.rhs)).add(dot(variableReduced, root.solution));
  return {dual, variableReduced, coefficientRanges, rhsRanges, primalDegeneracy, dualDegeneracy, dualObjective,
    statuses: model.variables.map((_, variable) => basisStatus(form, variable, basic))};
}

function solveModel(model, settings) {
  const counts = {solves: 0, phase1: 0, phase2: 0, drives: 0};
  if (model.error !== null) return {model, status: 'ERROR', root: null, objective: null, solution: null,
    lines: [`MODEL ${model.name} error`], tree: [], counts, pivots: 0};
  const level = settings.logs.get(model.name) ?? settings.log_level;
  const limit = settings.limits.get(model.name) ?? settings.node_limit;
  const lines = [`MODEL ${model.name} level ${level}`];
  const solveNode = (lower, upper, number) => {
    const lp = solveLP(model, lower, upper, number, level);
    append(lines, lp.lines);
    counts.solves++;
    counts.phase1 += lp.phase1;
    counts.phase2 += lp.phase2;
    counts.drives += lp.drives;
    return lp;
  };
  let result;
  let tree = [];
  if (model.integers.length > 0) {
    result = branchBound.solve(model, limit, solveNode);
    tree = [`MODEL ${model.name} ${model.direction} integers ${model.integers.length} node_limit ${limit}`];
    append(tree, result.lines);
  } else {
    const root = solveNode(model.lower, model.upper, 1);
    result = {status: root.status, root, objective: root.objective,
      solution: root.status === 'OPTIMAL' ? root.solution : null, processed: 1};
  }
  return {model, status: result.status, root: result.root, objective: result.objective, solution: result.solution,
    lines, tree, counts, pivots: counts.phase1 + counts.phase2 + counts.drives};
}

function solutionLines(result) {
  const {model, root} = result;
  if (model.error !== null) return [`MODEL ${model.name}`, `STATUS ERROR line ${model.error.line} ${model.error.message}`];
  const lines = [`MODEL ${model.name} ${model.direction} variables ${model.variables.length} ` +
    `constraints ${model.constraints.length} integers ${model.integers.length}`,
  coefficientStatistics(model), `STATUS ${result.status}`];
  if (result.solution !== null) lines.push(`OBJECTIVE ${result.objective} approx ${approximate(result.objective)}`);
  if (model.integers.length > 0 && root.status === 'OPTIMAL') {
    lines.push(`RELAXATION ${root.objective} approx ${approximate(root.objective)}`);
  }
  if (root.status === 'INFEASIBLE') {
    lines.push(`INFEASIBILITY ${root.w}`);
    for (let row = 0; row < root.form.rows.length; row++) lines.push(`FARKAS ${root.form.rows[row].name} ${root.farkas[row]}`);
  }
  if (result.solution !== null || result.status === 'UNBOUNDED') {
    const values = result.solution === null ? root.solution : result.solution;
    for (let variable = 0; variable < model.variables.length; variable++) lines.push(`VALUE ${model.variables[variable]} ${values[variable]}`);
  }
  if (result.status === 'UNBOUNDED') {
    for (let variable = 0; variable < model.variables.length; variable++) lines.push(`RAY ${model.variables[variable]} ${root.ray[variable]}`);
    lines.push(`RATE ${root.rate}`);
  }
  if (result.solution !== null) {
    for (const constraint of model.constraints) {
      const value = dot(constraint.coefficients, result.solution);
      const margin = constraint.op === '<=' ? constraint.rhs.subtract(value) : value.subtract(constraint.rhs);
      lines.push(`ROW ${constraint.name} ${value} ${margin}`);
    }
  }
  if (model.integers.length > 0) lines.push(`NODES ${result.counts.solves}`);
  lines.push(`PIVOTS ${result.pivots}`);
  return lines;
}

function sensitivityLines(result) {
  const {model, root} = result;
  if (root === null || root.status !== 'OPTIMAL') return [`MODEL ${model.name} skipped ${root === null ? 'ERROR' : root.status}`];
  const data = sensitivity(model, root);
  const lines = [`MODEL ${model.name} ${model.integers.length === 0 ? 'lp' : 'relaxation'} objective ${root.objective}`,
    'BASIS ' + root.tableau.basis.map(column => root.form.columns[column].name).join(' '),
    `DEGENERACY primal ${data.primalDegeneracy} dual ${data.dualDegeneracy}`, `DUAL objective ${data.dualObjective}`];
  for (let row = 0; row < model.constraints.length; row++) {
    const constraint = model.constraints[row];
    const [lower, upper] = data.rhsRanges[row];
    lines.push(`CONSTRAINT ${constraint.name} price ${data.dual[row]} rhs ${constraint.rhs} range ${endpoint(lower, true)} ${endpoint(upper, false)}`);
  }
  for (let variable = 0; variable < model.variables.length; variable++) {
    const [lower, upper] = data.coefficientRanges[variable];
    lines.push(`VARIABLE ${model.variables[variable]} ${data.statuses[variable]} value ${root.solution[variable]} ` +
      `reduced ${data.variableReduced[variable]} cost ${model.c[variable]} range ${endpoint(lower, true)} ${endpoint(upper, false)}`);
  }
  return lines;
}

function summaryRow(result) {
  const objective = result.objective === null ? '-' : String(result.objective);
  const decimal = result.objective === null ? '-' : approximate(result.objective);
  const relaxation = result.root === null || result.root.status !== 'OPTIMAL' ? '-' : String(result.root.objective);
  return [result.model.name, result.status, objective, decimal, relaxation, result.counts.solves, result.pivots].join(',');
}

function main() {
  const {models: rawModels, settings} = parser.readInputs();
  const files = {'iterations.txt': [], 'solutions.txt': [], 'sensitivity.txt': [], 'bnb_tree.txt': [],
    'summary.csv': ['model,status,objective,approx,relaxation,nodes,pivots']};
  const totals = {solves: 0, phase1: 0, phase2: 0, drives: 0};
  const statuses = {OPTIMAL: 0, INFEASIBLE: 0, UNBOUNDED: 0, NODE_LIMIT: 0, ERROR: 0};
  let analyzed = 0;
  let integerModels = 0;
  let integerNodes = 0;
  let limited = 0;
  for (const raw of rawModels) {
    const result = solveModel(modelData(raw), settings);
    append(files['iterations.txt'], result.lines);
    append(files['solutions.txt'], solutionLines(result));
    append(files['sensitivity.txt'], sensitivityLines(result));
    append(files['bnb_tree.txt'], result.tree);
    files['summary.csv'].push(summaryRow(result));
    for (const name of Object.keys(totals)) totals[name] += result.counts[name];
    statuses[result.status]++;
    if (result.root !== null && result.root.status === 'OPTIMAL') analyzed++;
    if (result.model.error === null && result.model.integers.length > 0) {
      integerModels++;
      integerNodes += result.counts.solves;
      if (result.status === 'NODE_LIMIT') limited++;
    }
  }
  files['iterations.txt'].push(`TOTAL solves ${totals.solves} phase1 ${totals.phase1} phase2 ${totals.phase2} drives ${totals.drives} ` +
    `pivots ${totals.phase1 + totals.phase2 + totals.drives}`);
  files['solutions.txt'].push(`SUMMARY models ${rawModels.length} optimal ${statuses.OPTIMAL} infeasible ${statuses.INFEASIBLE} ` +
    `unbounded ${statuses.UNBOUNDED} node_limit ${statuses.NODE_LIMIT} error ${statuses.ERROR}`);
  files['sensitivity.txt'].push(`SUMMARY analyzed ${analyzed} skipped ${rawModels.length - analyzed}`);
  files['bnb_tree.txt'].push(`SUMMARY models ${integerModels} nodes ${integerNodes} node_limit ${limited}`);
  fs.mkdirSync('output', {recursive: true});
  for (const [name, lines] of Object.entries(files)) fs.writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}

main();
