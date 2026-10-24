'use strict';

const fs = require('node:fs');
const {readModel} = require('./model_io');
const assembly = require('./assembly');
const solver = require('./solver');
const postprocess = require('./postprocess');
const design = require('./design');

const PI = 3.141592653589793;

function real(value, digits = 4) {
  if (Math.abs(value) >= 1e21) return BigInt(value).toString() + '.' + '0'.repeat(digits);
  const text = value.toFixed(digits);
  return Number(text) === 0 ? '0.' + '0'.repeat(digits) : text;
}

function choose(items, valueOf, minimum = false) {
  let best = null;
  for (const item of items) {
    const value = valueOf(item);
    const rounded = Number(real(value));
    if (best === null || (minimum ? rounded < best.rounded : rounded > best.rounded)) {
      best = {item, value, rounded};
    }
  }
  return best;
}

function maximumAbsolute(values) {
  let result = 0;
  for (const value of values) result = Math.max(result, Math.abs(value));
  return result;
}

function numberingMeasures(model, numbering, adjacency) {
  let bandwidth = 0;
  for (const member of model.members) {
    bandwidth = Math.max(bandwidth, Math.abs(numbering[member.start.index] - numbering[member.end.index]));
  }
  let profile = 0;
  for (const node of model.nodes) {
    let smallest = numbering[node.index];
    for (const neighbor of adjacency[node.index]) smallest = Math.min(smallest, numbering[neighbor]);
    profile += numbering[node.index] - smallest;
  }
  return {bandwidth, profile};
}

function prepareModel(model) {
  const adjacency = model.nodes.map(() => new Set());
  for (const member of model.members) {
    adjacency[member.start.index].add(member.end.index);
    adjacency[member.end.index].add(member.start.index);
  }
  const compareDegree = (a, b) => adjacency[a].size - adjacency[b].size || model.nodes[a].id - model.nodes[b].id;
  const seed = model.nodes.map(node => node.index).sort(compareDegree)[0];
  const queue = [seed];
  const seen = new Set(queue);
  for (let front = 0; front < queue.length; front++) {
    const neighbors = [...adjacency[queue[front]]].filter(index => !seen.has(index)).sort(compareDegree);
    for (const neighbor of neighbors) {
      seen.add(neighbor);
      queue.push(neighbor);
    }
  }
  model.renumbered = queue.reverse().map(index => model.nodes[index]);
  const newNumbers = Array(model.nodes.length);
  model.dofNodes = [];
  for (let index = 0; index < model.renumbered.length; index++) {
    const node = model.renumbered[index];
    newNumbers[node.index] = index;
    node.dofs = [2 * index, 2 * index + 1];
    model.dofNodes.push(node, node);
  }
  model.before = numberingMeasures(model, model.nodes.map(node => node.index), adjacency);
  model.after = numberingMeasures(model, newNumbers, adjacency);
  model.nd = 2 * model.nodes.length;
  model.fixed = Array(model.nd).fill(false);
  model.prescribed = Array(model.nd).fill(0);
  for (const support of model.supports) {
    for (let axis = 0; axis < 2; axis++) {
      if (!support.fixed[axis]) continue;
      const dof = support.node.dofs[axis];
      model.fixed[dof] = true;
      model.prescribed[dof] = support.prescribed[axis];
    }
  }
  model.free = [];
  model.restrained = [];
  for (let dof = 0; dof < model.nd; dof++) (model.fixed[dof] ? model.restrained : model.free).push(dof);
  const groups = new Map();
  for (const member of model.members) {
    if (!groups.has(member.group)) groups.set(member.group, {name: member.group, members: []});
    groups.get(member.group).members.push(member);
  }
  model.groups = [...groups.values()];
  assembly.prepareGeometry(model.members);
  return model;
}

function displacement(model, system, force, settlement = false) {
  const result = Array(model.nd).fill(0);
  for (const dof of model.restrained) result[dof] = settlement ? model.prescribed[dof] : 0;
  const right = [];
  for (const dof of model.free) {
    let value = force[dof];
    for (const restrained of model.restrained) value -= system.matrix[dof][restrained] * result[restrained];
    right.push(value);
  }
  const solution = solver.solve(system.lower, right);
  for (let index = 0; index < model.free.length; index++) result[model.free[index]] = solution[index];
  return result;
}

function analyze(model, removed = null, selectedCombination = null) {
  const matrix = assembly.stiffness(model, removed);
  const freeMatrix = model.free.map(row => model.free.map(column => matrix[row][column]));
  const factor = solver.cholesky(freeMatrix);
  const system = {matrix, freeMatrix, lower: factor.lower,
    unstable: factor.unstable === null ? null : model.free[factor.unstable]};
  if (system.unstable !== null) return system;
  const combinations = selectedCombination === null ? model.combinations
    : model.combinations.filter(combination => combination.name === selectedCombination);
  const neededCases = selectedCombination === null ? null : new Set(combinations[0].terms.map(term => term.name));
  system.byName = new Map();
  system.results = [];
  system.combinations = [];
  for (const loadCase of model.cases) {
    if (neededCases !== null && !neededCases.has(loadCase.name)) continue;
    const load = assembly.loads(model, loadCase, removed);
    const movement = displacement(model, system, load.force, load.settlement);
    const result = {name: loadCase.name, kind: 'case', displacement: movement,
      forces: postprocess.axialForces(model, movement, load.temperature, removed),
      reactions: postprocess.reactions(model, matrix, movement, load.force), external: load.external};
    system.byName.set(result.name, result);
    system.results.push(result);
  }
  for (const combination of combinations) {
    const result = postprocess.superpose(combination, system.byName);
    system.byName.set(result.name, result);
    system.results.push(result);
    system.combinations.push(result);
  }
  return system;
}

function utilizationMaximum(members, combinations) {
  const candidates = [];
  for (const member of members) {
    for (const result of combinations) candidates.push({member, result, value: design.utilization(member, result.forces[member.index])});
  }
  return choose(candidates, candidate => candidate.value);
}

function designSections(model) {
  const lines = [];
  for (let round = 1; round <= 10; round++) {
    const system = analyze(model);
    const changes = [];
    for (const group of model.groups) {
      const current = group.members[0].section;
      const chosen = design.selectSection(group, model.sections, system.combinations, model.params.slenderness);
      if (chosen !== current) {
        const maximum = utilizationMaximum(group.members, system.combinations);
        changes.push({group, current, chosen, utilization: maximum.value});
      }
    }
    let weight = 0;
    for (const member of model.members) weight += assembly.weight(member);
    const maximum = utilizationMaximum(model.members, system.combinations);
    lines.push(`round ${round} weight ${real(weight / 1000)} max_utilization ${real(maximum.value)}`
      + ` at ${maximum.item.member.id} ${maximum.item.result.name} changes ${changes.length}`);
    for (const change of changes) {
      lines.push(`change ${change.group.name} ${change.current.name} ${change.chosen.name} utilization ${real(change.utilization)}`);
    }
    if (changes.length === 0 || round === 10) {
      const converged = changes.length === 0;
      lines.push(`result ${converged ? 'converged' : 'not_converged'} rounds ${round}`);
      return {system, weight, lines};
    }
    for (const change of changes) {
      for (const member of change.group.members) member.section = change.chosen;
    }
  }
}

function governingMembers(model, system) {
  return model.members.map(member => {
    const governing = choose(system.combinations, result => design.utilization(member, result.forces[member.index]));
    const slenderness = design.slenderness(member);
    const limit = design.slendernessLimit(member, system.combinations, model.params.slenderness);
    return {member, utilization: governing.value, rounded: governing.rounded, combination: governing.item.name,
      slenderness, limit, verdict: governing.value <= 1 && slenderness <= limit ? 'ok' : 'over'};
  });
}

function finishDesign(model, designResult, governing) {
  const lines = designResult.lines.slice();
  const combinations = designResult.system.combinations;
  for (const group of model.groups) {
    const maximum = choose(group.members, member => governing[member.index].utilization);
    lines.push(`group ${group.name} section ${group.members[0].section.name} members ${group.members.length}`
      + ` utilization ${real(maximum.value)} at ${maximum.item.id}`);
  }
  for (const record of governing) {
    const member = record.member;
    lines.push(`member ${member.id} group ${member.group} section ${member.section.name} utilization ${real(record.utilization)}`
      + ` governing ${record.combination} slenderness ${real(record.slenderness)} limit ${real(record.limit)} ${record.verdict}`);
  }
  const ranking = governing.slice().sort((a, b) => b.rounded - a.rounded || a.member.index - b.member.index).slice(0, 5);
  for (let index = 0; index < ranking.length; index++) {
    lines.push(`rank ${index + 1} member ${ranking[index].member.id} utilization ${real(ranking[index].utilization)}`);
  }
  for (const member of model.members) {
    const maximum = choose(combinations, result => result.forces[member.index] / 1000);
    const minimum = choose(combinations, result => result.forces[member.index] / 1000, true);
    lines.push(`envelope ${member.id} max ${real(maximum.value)} ${maximum.item.name} min ${real(minimum.value)} ${minimum.item.name}`);
  }
  for (const section of model.sections) {
    const used = model.members.filter(member => member.section === section);
    if (used.length === 0) continue;
    let length = 0;
    for (const member of used) length += member.length;
    lines.push(`section ${section.name} members ${used.length} length ${real(length)}`);
  }
  lines.push(`weight ${real(designResult.weight / 1000)}`);
  return lines;
}

function magnitude(result, node) {
  const x = result.displacement[node.dofs[0]];
  const y = result.displacement[node.dofs[1]];
  return Math.sqrt(x * x + y * y);
}

function resultSummary(model, result) {
  const maximum = choose(model.nodes, node => magnitude(result, node));
  let energy = 0;
  for (const member of model.members) {
    const force = result.forces[member.index];
    energy += force * force * member.length / (2 * member.material.young * member.section.area);
  }
  let reactionX = 0;
  let reactionY = 0;
  let externalX = 0;
  let externalY = 0;
  for (const node of model.nodes) {
    reactionX += result.reactions[node.dofs[0]];
    reactionY += result.reactions[node.dofs[1]];
    externalX += result.external[node.dofs[0]];
    externalY += result.external[node.dofs[1]];
  }
  const tolerance = 0.000001 * Math.max(1, maximumAbsolute(result.external), maximumAbsolute(result.reactions));
  const equilibrium = postprocess.equilibriumMaximum(model, result) <= tolerance ? 'ok' : 'failed';
  return `${result.kind} ${result.name} equilibrium ${equilibrium} max_displacement ${real(maximum.value)} at ${maximum.item.id}`
    + ` energy ${real(energy / 1000)} reactions ${real(reactionX / 1000)} ${real(reactionY / 1000)}`
    + ` loads ${real(externalX / 1000)} ${real(externalY / 1000)}`;
}

function resultEnvelopes(model, system) {
  const lines = [];
  for (const support of model.supports) {
    for (let axis = 0; axis < 2; axis++) {
      if (!support.fixed[axis]) continue;
      const dof = support.node.dofs[axis];
      const maximum = choose(system.combinations, result => result.reactions[dof] / 1000);
      const minimum = choose(system.combinations, result => result.reactions[dof] / 1000, true);
      let line = `reaction_envelope ${support.node.id} ${axis === 0 ? 'x' : 'y'} max ${real(maximum.value)} ${maximum.item.name}`
        + ` min ${real(minimum.value)} ${minimum.item.name}`;
      if (axis === 1) line += ` uplift ${system.combinations.some(result => result.reactions[dof] < 0) ? 'yes' : 'no'}`;
      lines.push(line);
    }
  }
  for (const node of model.nodes) {
    const maximum = choose(system.combinations, result => magnitude(result, node));
    lines.push(`displacement_envelope ${node.id} max ${real(maximum.value)} ${maximum.item.name}`);
  }
  return lines;
}

function unitResponse(model, system, node) {
  const force = Array(model.nd).fill(0);
  force[node.dofs[1]] = -1000;
  const movement = displacement(model, system, force);
  const temperature = Array(model.members.length).fill(0);
  return {displacement: movement, forces: postprocess.axialForces(model, movement, temperature),
    reactions: postprocess.reactions(model, system.matrix, movement, force)};
}

function deflectionLines(model, system) {
  const {name, ratio} = model.params.deflection;
  const result = system.byName.get(name);
  const deck = model.params.deck;
  const supportPositions = [];
  for (let index = 0; index < deck.length; index++) if (model.fixed[deck[index].dofs[1]]) supportPositions.push(index);
  const lines = [];
  for (let span = 0; span + 1 < supportPositions.length; span++) {
    const start = supportPositions[span];
    const end = supportPositions[span + 1];
    const first = deck[start];
    const last = deck[end];
    const firstY = result.displacement[first.dofs[1]];
    const lastY = result.displacement[last.dofs[1]];
    const maximum = choose(deck.slice(start + 1, end), node => Math.abs(result.displacement[node.dofs[1]]
      - (firstY + (lastY - firstY) * (node.x - first.x) / (last.x - first.x))));
    const limit = (last.x - first.x) / ratio;
    const target = maximum.item;
    lines.push(`deflection ${name} span ${first.id} ${last.id} max ${real(maximum.value)} at ${target.id}`
      + ` limit ${real(limit)} ${maximum.value <= limit ? 'ok' : 'exceeded'}`);
    const virtual = unitResponse(model, system, target);
    let work = 0;
    for (const member of model.members) {
      work += result.forces[member.index] * (virtual.forces[member.index] / 1000) * member.length
        / (member.material.young * member.section.area);
    }
    const stiffness = -result.displacement[target.dofs[1]];
    const verdict = Math.abs(work - stiffness) <= 0.000001 * Math.max(1, Math.abs(stiffness)) ? 'ok' : 'failed';
    lines.push(`virtual_work ${name} node ${target.id} stiffness ${real(stiffness)} virtual ${real(work)} ${verdict}`);
  }
  return lines;
}

function removalLines(model) {
  const lines = [];
  for (const removed of model.members) {
    const system = analyze(model, removed, model.params.removal);
    if (system.unstable !== null) {
      const dof = system.unstable;
      lines.push(`removal ${removed.id} unstable at ${model.dofNodes[dof].id} ${dof % 2 === 0 ? 'x' : 'y'}`);
      continue;
    }
    const result = system.byName.get(model.params.removal);
    const members = model.members.filter(member => member !== removed);
    const maximum = choose(members, member => design.utilization(member, result.forces[member.index]));
    const movement = choose(model.nodes, node => magnitude(result, node));
    lines.push(`removal ${removed.id} stable max_utilization ${real(maximum.value)} at ${maximum.item.id}`
      + ` max_displacement ${real(movement.value)} at ${movement.item.id}`);
  }
  return lines;
}

function interpolate(deck, ordinates, position) {
  if (position < deck[0].x || position > deck.at(-1).x) return 0;
  if (position === deck.at(-1).x) return ordinates.at(-1);
  for (let index = 0; index + 1 < deck.length; index++) {
    if (position < deck[index + 1].x) {
      return ordinates[index] + (ordinates[index + 1] - ordinates[index]) * (position - deck[index].x)
        / (deck[index + 1].x - deck[index].x);
    }
  }
}

function vehicleEnvelope(model, ordinates, positions) {
  const effects = [];
  for (const position of positions) {
    let effect = 0;
    for (const axle of model.params.vehicle.axles) effect += axle.load * interpolate(model.params.deck, ordinates, position - axle.offset);
    effects.push({position, effect});
  }
  return {maximum: choose(effects, item => item.effect), minimum: choose(effects, item => item.effect, true)};
}

function effectText(envelope) {
  return `max ${real(envelope.maximum.value)} at ${envelope.maximum.item.position}`
    + ` min ${real(envelope.minimum.value)} at ${envelope.minimum.item.position}`;
}

function influenceLines(model, system) {
  const deck = model.params.deck;
  const memberOrdinates = model.members.map(() => []);
  const reactionOrdinates = Array.from({length: model.nd}, () => []);
  for (const node of deck) {
    const response = unitResponse(model, system, node);
    for (const member of model.members) memberOrdinates[member.index].push(response.forces[member.index] / 1000);
    for (const dof of model.restrained) reactionOrdinates[dof].push(response.reactions[dof] / 1000);
  }
  const lines = [];
  const deckIndices = deck.map((_, index) => index);
  for (const member of model.params.influences) {
    const ordinates = memberOrdinates[member.index];
    lines.push(`influence ${member.id}`);
    for (let index = 0; index < deck.length; index++) lines.push(`node ${deck[index].id} ${real(ordinates[index])}`);
    const maximum = choose(deckIndices, index => ordinates[index]);
    const minimum = choose(deckIndices, index => ordinates[index], true);
    let positive = 0;
    let negative = 0;
    for (const ordinate of ordinates) {
      if (ordinate > 0) positive += ordinate;
      else if (ordinate < 0) negative += ordinate;
    }
    lines.push(`max ${real(maximum.value)} at ${deck[maximum.item].id} min ${real(minimum.value)} at ${deck[minimum.item].id}`
      + ` positive ${real(positive)} negative ${real(negative)}`);
    const crossings = [];
    for (let index = 0; index + 1 < deck.length; index++) {
      const first = ordinates[index];
      const second = ordinates[index + 1];
      if ((first > 0 && second < 0) || (first < 0 && second > 0)) {
        crossings.push(deck[index].x + (deck[index + 1].x - deck[index].x) * first / (first - second));
      }
    }
    lines.push(`crossings ${crossings.length}` + (crossings.length === 0 ? '' : ' ' + crossings.map(value => real(value, 1)).join(' ')));
  }
  const positions = [];
  const vehicle = model.params.vehicle;
  const last = deck.at(-1).x + vehicle.axles.at(-1).offset;
  for (let position = deck[0].x; position <= last; position += vehicle.step) positions.push(position);
  lines.push(`vehicle axles ${vehicle.axles.length} positions ${positions.length}`);
  const envelopes = model.members.map(member => vehicleEnvelope(model, memberOrdinates[member.index], positions));
  for (const member of model.members) lines.push(`vehicle_member ${member.id} ${effectText(envelopes[member.index])}`);
  for (const support of model.supports) {
    for (let axis = 0; axis < 2; axis++) {
      if (!support.fixed[axis]) continue;
      const envelope = vehicleEnvelope(model, reactionOrdinates[support.node.dofs[axis]], positions);
      lines.push(`vehicle_reaction ${support.node.id} ${axis === 0 ? 'x' : 'y'} ${effectText(envelope)}`);
    }
  }
  const rating = model.params.rating;
  const dead = system.byName.get(rating.name);
  const factors = [];
  for (const member of model.members) {
    const envelope = envelopes[member.index];
    const force = dead.forces[member.index] / 1000;
    const tensionCapacity = member.section.area * member.material.yieldStress / 1000;
    const compressionCapacity = Math.min(member.section.area * member.material.yieldStress, design.buckling(member)) / 1000;
    let tension = null;
    let compression = null;
    if (envelope.maximum.rounded > 0) {
      tension = (tensionCapacity - rating.dead * force) / (rating.live * envelope.maximum.value);
      factors.push({member, kind: 'tension', value: tension});
    }
    if (envelope.minimum.rounded < 0) {
      compression = (compressionCapacity + rating.dead * force) / (rating.live * (-envelope.minimum.value));
      factors.push({member, kind: 'compression', value: compression});
    }
    lines.push(`rating ${member.id} tension ${tension === null ? 'none' : real(tension)}`
      + ` compression ${compression === null ? 'none' : real(compression)}`);
  }
  const minimum = choose(factors, factor => factor.value, true);
  lines.push(`rating_min ${real(minimum.value)} at ${minimum.item.member.id} ${minimum.item.kind}`);
  return lines;
}

function vibrationLines(model, system) {
  const settings = model.params.vibration;
  const result = system.byName.get(settings.name);
  const nodeMass = model.nodes.map(node => -result.external[node.dofs[1]] / 9.81);
  let totalMass = 0;
  for (const mass of nodeMass) totalMass += mass;
  const masses = model.free.map(dof => nodeMass[model.dofNodes[dof].index]);
  const size = model.free.length;
  const shapes = [];
  const lines = [`vibration ${settings.name} mass ${real(totalMass)} iterations ${settings.iterations}`];
  for (let mode = 1; mode <= settings.modes; mode++) {
    let vector = Array(size).fill(1);
    for (let iteration = 0; iteration < settings.iterations; iteration++) {
      for (const shape of shapes) {
        let beta = 0;
        for (let index = 0; index < size; index++) beta += shape[index] * masses[index] * vector[index];
        for (let index = 0; index < size; index++) vector[index] -= beta * shape[index];
      }
      const right = vector.map((value, index) => masses[index] * value);
      const solution = solver.solve(system.lower, right);
      let squaredNorm = 0;
      for (let index = 0; index < size; index++) squaredNorm += masses[index] * solution[index] * solution[index];
      const norm = Math.sqrt(squaredNorm);
      vector = solution.map(value => value / norm);
    }
    shapes.push(vector);
    const product = [];
    for (let row = 0; row < size; row++) {
      let value = 0;
      for (let column = 0; column < size; column++) value += system.freeMatrix[row][column] * vector[column];
      product.push(value);
    }
    let numerator = 0;
    let denominator = 0;
    for (let index = 0; index < size; index++) {
      numerator += vector[index] * product[index];
      denominator += masses[index] * vector[index] * vector[index];
    }
    const eigenvalue = numerator / denominator;
    const frequency = Math.sqrt(1000 * eigenvalue) / (2 * PI);
    let largest = 0;
    for (let index = 1; index < size; index++) if (Math.abs(vector[index]) > Math.abs(vector[largest])) largest = index;
    const normalized = Array(model.nd).fill(0);
    for (let index = 0; index < size; index++) normalized[model.free[index]] = vector[index] / vector[largest];
    lines.push(`mode ${mode} frequency ${real(frequency)} period ${real(1 / frequency)}`);
    for (const node of model.nodes) lines.push(`node ${node.id} ${real(normalized[node.dofs[0]])} ${real(normalized[node.dofs[1]])}`);
  }
  return lines;
}

function makeGrid(model, settings) {
  const left = Math.min(...model.nodes.map(node => node.x));
  const right = Math.max(...model.nodes.map(node => node.x));
  const bottom = Math.min(...model.nodes.map(node => node.y));
  const top = Math.max(...model.nodes.map(node => node.y));
  const columns = Math.floor((right - left) / settings.width + 0.5) + 5;
  const rows = Math.floor((top - bottom) / settings.height + 0.5) + 5;
  return {left, top, columns, rows, cellWidth: settings.width, cellHeight: settings.height,
    cells: Array.from({length: rows}, () => Array(columns).fill(' '))};
}

function gridPosition(grid, x, y) {
  return [Math.floor((x - grid.left) / grid.cellWidth + 0.5) + 2,
    Math.floor((grid.top - y) / grid.cellHeight + 0.5) + 2];
}

function put(grid, column, row, character) {
  if (column >= 0 && column < grid.columns && row >= 0 && row < grid.rows) grid.cells[row][column] = character;
}

function lineSegment(grid, first, last, character) {
  let [column, row] = first;
  const [endColumn, endRow] = last;
  const dc = Math.abs(endColumn - column);
  const dr = -Math.abs(endRow - row);
  const sc = column < endColumn ? 1 : -1;
  const sr = row < endRow ? 1 : -1;
  let error = dc + dr;
  for (;;) {
    put(grid, column, row, character);
    if (column === endColumn && row === endRow) break;
    const doubled = 2 * error;
    if (doubled >= dr) {
      error += dr;
      column += sc;
    }
    if (doubled <= dc) {
      error += dc;
      row += sr;
    }
  }
}

function appendGrid(lines, grid) {
  const frame = '+' + '-'.repeat(grid.columns) + '+';
  lines.push(frame);
  for (const row of grid.cells) lines.push('|' + row.join('') + '|');
  lines.push(frame);
}

function drawingLines(model, system, governing) {
  const lines = [];
  for (const settings of model.params.drawings) {
    const grid = makeGrid(model, settings);
    const result = system.byName.get(settings.name);
    const original = model.nodes.map(node => gridPosition(grid, node.x, node.y));
    const deformed = model.nodes.map(node => gridPosition(grid,
      node.x + settings.magnification * result.displacement[node.dofs[0]],
      node.y + settings.magnification * result.displacement[node.dofs[1]]));
    for (const member of model.members) lineSegment(grid, original[member.start.index], original[member.end.index], '.');
    for (const node of model.nodes) put(grid, ...original[node.index], '+');
    for (const member of model.members) lineSegment(grid, deformed[member.start.index], deformed[member.end.index], '*');
    for (const node of model.nodes) put(grid, ...deformed[node.index], 'o');
    lines.push(`drawing ${settings.name} magnification ${settings.magnification} columns ${grid.columns} rows ${grid.rows}`);
    appendGrid(lines, grid);
  }
  const grid = makeGrid(model, model.params.utilizationMap);
  const positions = model.nodes.map(node => gridPosition(grid, node.x, node.y));
  for (const member of model.members) {
    const utilization = governing[member.index].utilization;
    const character = utilization >= 1 ? '#' : String(Math.floor(10 * utilization));
    lineSegment(grid, positions[member.start.index], positions[member.end.index], character);
  }
  for (const node of model.nodes) put(grid, ...positions[node.index], 'o');
  lines.push(`utilization_map columns ${grid.columns} rows ${grid.rows}`);
  appendGrid(lines, grid);
  return lines;
}

function analysisLines(model, system) {
  const indeterminacy = model.members.length + model.restrained.length - 2 * model.nodes.length;
  const lines = [`model nodes ${model.nodes.length} members ${model.members.length} supports ${model.supports.length}`
    + ` free_dofs ${model.free.length} restrained_dofs ${model.restrained.length} indeterminacy ${indeterminacy}`,
  'renumbering ' + model.renumbered.map(node => node.id).join(' '),
  `bandwidth before ${model.before.bandwidth} after ${model.after.bandwidth}`,
  `profile before ${model.before.profile} after ${model.after.profile}`];
  for (const member of model.members) {
    lines.push(`member ${member.id} nodes ${member.start.id} ${member.end.id} length ${real(member.length)}`
      + ` cos ${real(member.cos, 6)} sin ${real(member.sin, 6)}`);
  }
  for (const result of system.results) lines.push(resultSummary(model, result));
  for (const line of resultEnvelopes(model, system)) lines.push(line);
  for (const line of deflectionLines(model, system)) lines.push(line);
  for (const line of removalLines(model)) lines.push(line);
  return lines;
}

function tabularResults(model, system) {
  const displacements = ['case,node,dx,dy'];
  const forces = ['case,member,force,stress,utilization'];
  const reactions = ['case,node,rx,ry'];
  for (const result of system.results) {
    for (const node of model.nodes) {
      displacements.push(`${result.name},${node.id},${real(result.displacement[node.dofs[0]])},${real(result.displacement[node.dofs[1]])}`);
    }
    for (const member of model.members) {
      const force = result.forces[member.index];
      forces.push(`${result.name},${member.id},${real(force / 1000)},${real(force / member.section.area)},${real(design.utilization(member, force))}`);
    }
    for (const support of model.supports) {
      reactions.push(`${result.name},${support.node.id},${real(result.reactions[support.node.dofs[0]] / 1000)},${real(result.reactions[support.node.dofs[1]] / 1000)}`);
    }
  }
  return {'displacements.csv': displacements, 'member_forces.csv': forces, 'reactions.csv': reactions};
}

function main() {
  const model = prepareModel(readModel());
  const designResult = designSections(model);
  const system = designResult.system;
  const governing = governingMembers(model, system);
  const files = {'analysis.txt': analysisLines(model, system), ...tabularResults(model, system),
    'design.txt': finishDesign(model, designResult, governing), 'influence.txt': influenceLines(model, system),
    'drawing.txt': drawingLines(model, system, governing), 'vibration.txt': vibrationLines(model, system)};
  fs.mkdirSync('output', {recursive: true});
  for (const [name, lines] of Object.entries(files)) fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

main();
