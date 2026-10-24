import { mkdirSync, writeFileSync } from 'node:fs';
import { readModel } from './model_io.ts';
import {
  geometry,
  loadVectors,
  memberWeight,
  properties,
  stiffness,
  zeros,
  type Properties,
} from './assembly.ts';
import { cholesky, solve } from './solver.ts';
import {
  axialForces,
  equilibriumResidual,
  reactions,
  superpose,
  type Result,
} from './postprocess.ts';
import {
  buckling,
  pi,
  selectSection,
  slenderness,
  slendernessLimit,
  utilization,
} from './design.ts';

const { nodes, members, sections, materials, supports, cases, combinations, settings } =
  readModel();
const nodeOrder = nodes.map((_, i) => i);
const memberOrder = members.map((_, i) => i);
const nd = 2 * nodes.length;
const format = (value: number, digits = 4) => {
  if (Math.abs(value) >= 1e21) return `${BigInt(value)}.${'0'.repeat(digits)}`;
  const text = value.toFixed(digits);
  return +text === 0 ? `0.${'0'.repeat(digits)}` : text;
};
const rounded = (value: number) => +format(value);
function extreme(values: number[], largest = true): number {
  let selected = 0;
  for (let i = 1; i < values.length; i++) {
    if (
      largest
        ? rounded(values[i]) > rounded(values[selected])
        : rounded(values[i]) < rounded(values[selected])
    ) {
      selected = i;
    }
  }
  return selected;
}
const sum = (values: number[]) => {
  let result = 0;
  for (const value of values) result += value;
  return result;
};
const adjacency = nodeOrder.map(() => new Set<number>());
for (const member of members) {
  adjacency[member.i].add(member.j);
  adjacency[member.j].add(member.i);
}
const degreeOrder = (a: number, b: number) =>
  adjacency[a].size - adjacency[b].size || nodes[a].id - nodes[b].id;
const queue = [[...nodeOrder].sort(degreeOrder)[0]];
const visited = new Set(queue);
for (let head = 0; head < queue.length; head++) {
  for (const node of [...adjacency[queue[head]]]
    .filter((node) => !visited.has(node))
    .sort(degreeOrder)) {
    visited.add(node);
    queue.push(node);
  }
}
const rcm = [...queue].reverse();
const numbering = nodeOrder.map((node) => rcm.indexOf(node));
const bandwidth = (numbers: number[]) =>
  Math.max(...members.map((member) => Math.abs(numbers[member.i] - numbers[member.j])));
const profile = (numbers: number[]) =>
  sum(
    nodeOrder.map(
      (node) =>
        numbers[node] -
        Math.min(numbers[node], ...[...adjacency[node]].map((neighbor) => numbers[neighbor])),
    ),
  );
const prescribed = zeros(nd);
const restrainedSet = new Set<number>();
for (const support of supports) {
  for (let direction = 0; direction < 2; direction++) {
    if (support.fixed[direction]) {
      const dof = 2 * numbering[support.node] + direction;
      restrainedSet.add(dof);
      prescribed[dof] = support.prescribed[direction];
    }
  }
}
const restrained = [...restrainedSet].sort((a, b) => a - b);
const free = Array.from({ length: nd }, (_, d) => d).filter((d) => !restrainedSet.has(d));
const shapes = geometry(nodes, members, numbering);
const groups = [...new Set(members.map((member) => member.group))];
const groupMembers = groups.map((group) => memberOrder.filter((m) => members[m].group === group));
interface StableAnalysis {
  stable: true;
  properties: Properties[];
  matrix: number[][];
  freeMatrix: number[][];
  lower: number[][];
  cases: Result[];
  combinations: Result[];
  results: Result[];
}
type Analysis = StableAnalysis | { stable: false; dof: number };
function displacements(
  matrix: number[][],
  lower: number[][],
  force: number[],
  g: number[],
): number[] {
  const displacement = zeros(nd);
  for (const r of restrained) displacement[r] = g[r];
  const b = free.map((f) => {
    let value = force[f];
    for (const r of restrained) value -= matrix[f][r] * g[r];
    return value;
  });
  solve(lower, b).forEach((value, i) => {
    displacement[free[i]] = value;
  });
  return displacement;
}
function analyze(selection: number[], removed?: number): Analysis {
  const memberProperties = properties(shapes, members, sections, materials, selection);
  const matrix = stiffness(memberProperties, nd, removed);
  const freeMatrix = free.map((i) => free.map((j) => matrix[i][j]));
  const factorization = cholesky(freeMatrix);
  if (!factorization.stable) return { stable: false, dof: free[factorization.index] };
  const lower = factorization.lower;
  const caseResults = cases.map((loadCase) => {
    const loads = loadVectors(loadCase, memberProperties, nd, numbering, removed);
    const displacement = displacements(
      matrix,
      lower,
      loads.force,
      loads.settlement ? prescribed : zeros(nd),
    );
    return {
      name: loadCase.name,
      displacement,
      axial: axialForces(memberProperties, displacement, loads.temperature, removed),
      reaction: reactions(matrix, displacement, loads.force, restrained),
      external: loads.external,
    };
  });
  const combinationResults = combinations.map((combination) => superpose(combination, caseResults));
  return {
    stable: true,
    properties: memberProperties,
    matrix,
    freeMatrix,
    lower,
    cases: caseResults,
    combinations: combinationResults,
    results: [...caseResults, ...combinationResults],
  };
}
function unitLoad(analysis: StableAnalysis, node: number): Result {
  const force = zeros(nd);
  force[2 * numbering[node] + 1] = -1000;
  const displacement = displacements(analysis.matrix, analysis.lower, force, zeros(nd));
  return {
    name: '',
    displacement,
    axial: axialForces(analysis.properties, displacement, zeros(members.length)),
    reaction: reactions(analysis.matrix, displacement, force, restrained),
    external: force,
  };
}
const magnitudes = (result: Result) =>
  nodeOrder.map((node) => {
    const x = result.displacement[2 * numbering[node]];
    const y = result.displacement[2 * numbering[node] + 1];
    return Math.sqrt(x * x + y * y);
  });
const designLines: string[] = [];
let selection = members.map((member) => member.section);
let final: StableAnalysis | undefined;
let finalRound = 0;
let converged = false;
let finalWeight = 0;
for (let round = 1; round <= 10; round++) {
  const analysis = analyze(selection);
  if (!analysis.stable) throw new Error('Unstable unmodified structure');
  final = analysis;
  finalRound = round;
  const forces = analysis.combinations.map((result) => result.axial);
  const limits = memberOrder.map((m) =>
    slendernessLimit(
      forces.map((force) => force[m]),
      settings.compressionLimit,
      settings.tensionLimit,
    ),
  );
  const chosen = groupMembers.map((group) =>
    selectSection(group, sections, analysis.properties, forces, limits),
  );
  const changed = groups
    .map((_, g) => g)
    .filter((g) => chosen[g] !== selection[groupMembers[g][0]]);
  const candidates = memberOrder.flatMap((m) =>
    analysis.combinations.map((result, c) => ({
      m,
      c,
      value: utilization(result.axial[m], analysis.properties[m]),
    })),
  );
  const governing = candidates[extreme(candidates.map((candidate) => candidate.value))];
  finalWeight = sum(analysis.properties.map(memberWeight));
  designLines.push(
    `round ${round} weight ${format(finalWeight / 1000)} max_utilization ${format(governing.value)} at ${members[governing.m].id} ${combinations[governing.c].name} changes ${changed.length}`,
  );
  for (const g of changed) {
    const values = groupMembers[g].flatMap((m) =>
      analysis.combinations.map((result) => utilization(result.axial[m], analysis.properties[m])),
    );
    const maximum = values[extreme(values)];
    designLines.push(
      `change ${groups[g]} ${sections[selection[groupMembers[g][0]]].name} ${sections[chosen[g]].name} utilization ${format(maximum)}`,
    );
  }
  if (!changed.length) {
    converged = true;
    break;
  }
  if (round < 10) selection = members.map((member, m) => chosen[groups.indexOf(member.group)]);
}
const analysis = final!;
const props = analysis.properties;
const results = analysis.results;
const combinationResults = analysis.combinations;
const resultNamed = (name: string) => results.find((result) => result.name === name)!;
const governing = memberOrder.map((m) => {
  const values = combinationResults.map((result) => utilization(result.axial[m], props[m]));
  const c = extreme(values);
  return { value: values[c], combination: c };
});
const limits = memberOrder.map((m) =>
  slendernessLimit(
    combinationResults.map((result) => result.axial[m]),
    settings.compressionLimit,
    settings.tensionLimit,
  ),
);
designLines.push(`result ${converged ? 'converged' : 'not_converged'} rounds ${finalRound}`);
groupMembers.forEach((group, g) => {
  const m = group[extreme(group.map((m) => governing[m].value))];
  designLines.push(
    `group ${groups[g]} section ${sections[selection[group[0]]].name} members ${group.length} utilization ${format(governing[m].value)} at ${members[m].id}`,
  );
});
memberOrder.forEach((m) => {
  const slender = slenderness(props[m]);
  const verdict = governing[m].value <= 1 && slender <= limits[m] ? 'ok' : 'over';
  designLines.push(
    `member ${members[m].id} group ${members[m].group} section ${sections[selection[m]].name} utilization ${format(governing[m].value)} governing ${combinations[governing[m].combination].name} slenderness ${format(slender)} limit ${format(limits[m])} ${verdict}`,
  );
});
[...memberOrder]
  .sort((a, b) => rounded(governing[b].value) - rounded(governing[a].value) || a - b)
  .slice(0, 5)
  .forEach((m, rank) =>
    designLines.push(
      `rank ${rank + 1} member ${members[m].id} utilization ${format(governing[m].value)}`,
    ),
  );
memberOrder.forEach((m) => {
  const values = combinationResults.map((result) => result.axial[m] / 1000);
  const maximum = extreme(values);
  const minimum = extreme(values, false);
  designLines.push(
    `envelope ${members[m].id} max ${format(values[maximum])} ${combinations[maximum].name} min ${format(values[minimum])} ${combinations[minimum].name}`,
  );
});
sections.forEach((section, s) => {
  const used = memberOrder.filter((m) => selection[m] === s);
  if (used.length) {
    designLines.push(
      `section ${section.name} members ${used.length} length ${format(sum(used.map((m) => props[m].length)))}`,
    );
  }
});
designLines.push(`weight ${format(finalWeight / 1000)}`);

const analysisLines = [
  `model nodes ${nodes.length} members ${members.length} supports ${supports.length} free_dofs ${free.length} restrained_dofs ${restrained.length} indeterminacy ${members.length + restrained.length - nd}`,
  `renumbering ${rcm.map((node) => nodes[node].id).join(' ')}`,
  `bandwidth before ${bandwidth(nodeOrder)} after ${bandwidth(numbering)}`,
  `profile before ${profile(nodeOrder)} after ${profile(numbering)}`,
  ...members.map(
    (member, m) =>
      `member ${member.id} nodes ${nodes[member.i].id} ${nodes[member.j].id} length ${format(props[m].length)} cos ${format(props[m].c, 6)} sin ${format(props[m].s, 6)}`,
  ),
];
const displacementLines = ['case,node,dx,dy'];
const forceLines = ['case,member,force,stress,utilization'];
const reactionLines = ['case,node,rx,ry'];
results.forEach((result, r) => {
  const displacement = magnitudes(result);
  const maximum = extreme(displacement);
  const energy =
    sum(
      memberOrder.map(
        (m) =>
          (result.axial[m] * result.axial[m] * props[m].length) /
          (2 * props[m].material.young * props[m].area),
      ),
    ) / 1000;
  const reactionX = sum(nodeOrder.map((node) => result.reaction[2 * numbering[node]])) / 1000;
  const reactionY = sum(nodeOrder.map((node) => result.reaction[2 * numbering[node] + 1])) / 1000;
  const externalX = sum(nodeOrder.map((node) => result.external[2 * numbering[node]])) / 1000;
  const externalY = sum(nodeOrder.map((node) => result.external[2 * numbering[node] + 1])) / 1000;
  const tolerance =
    0.000001 * Math.max(1, ...result.external.map(Math.abs), ...result.reaction.map(Math.abs));
  analysisLines.push(
    `${r < cases.length ? 'case' : 'combination'} ${result.name} equilibrium ${equilibriumResidual(result, props) <= tolerance ? 'ok' : 'failed'} max_displacement ${format(displacement[maximum])} at ${nodes[maximum].id} energy ${format(energy)} reactions ${format(reactionX)} ${format(reactionY)} loads ${format(externalX)} ${format(externalY)}`,
  );
  for (const node of nodeOrder) {
    displacementLines.push(
      [
        result.name,
        nodes[node].id,
        format(result.displacement[2 * numbering[node]]),
        format(result.displacement[2 * numbering[node] + 1]),
      ].join(','),
    );
  }
  for (const m of memberOrder) {
    forceLines.push(
      [
        result.name,
        members[m].id,
        format(result.axial[m] / 1000),
        format(result.axial[m] / props[m].area),
        format(utilization(result.axial[m], props[m])),
      ].join(','),
    );
  }
  for (const support of supports) {
    reactionLines.push(
      [
        result.name,
        nodes[support.node].id,
        format(result.reaction[2 * numbering[support.node]] / 1000),
        format(result.reaction[2 * numbering[support.node] + 1] / 1000),
      ].join(','),
    );
  }
});
const reactionDofs: { node: number; direction: number; dof: number }[] = [];
for (const support of supports) {
  for (let direction = 0; direction < 2; direction++) {
    if (support.fixed[direction]) {
      const dof = 2 * numbering[support.node] + direction;
      const values = combinationResults.map((result) => result.reaction[dof] / 1000);
      const maximum = extreme(values);
      const minimum = extreme(values, false);
      analysisLines.push(
        `reaction_envelope ${nodes[support.node].id} ${direction ? 'y' : 'x'} max ${format(values[maximum])} ${combinations[maximum].name} min ${format(values[minimum])} ${combinations[minimum].name}${direction ? ` uplift ${values.some((value) => value < 0) ? 'yes' : 'no'}` : ''}`,
      );
      reactionDofs.push({ node: support.node, direction, dof });
    }
  }
}
nodeOrder.forEach((node) => {
  const values = combinationResults.map((result) => magnitudes(result)[node]);
  const maximum = extreme(values);
  analysisLines.push(
    `displacement_envelope ${nodes[node].id} max ${format(values[maximum])} ${combinations[maximum].name}`,
  );
});
const deflectionResult = resultNamed(settings.deflection.name);
const deck = settings.deck;
const deckX = deck.map((node) => nodes[node].x);
const deckSupports = deck
  .map((node, k) => ({ node, k }))
  .filter(({ node }) => supports.some((support) => support.node === node && support.fixed[1]));
for (let span = 0; span < deckSupports.length - 1; span++) {
  const a = deckSupports[span].k;
  const b = deckSupports[span + 1].k;
  const va = deflectionResult.displacement[2 * numbering[deck[a]] + 1];
  const vb = deflectionResult.displacement[2 * numbering[deck[b]] + 1];
  const indices = Array.from({ length: b - a + 1 }, (_, k) => a + k);
  const deltas = indices.map((k) =>
    Math.abs(
      deflectionResult.displacement[2 * numbering[deck[k]] + 1] -
        (va + ((vb - va) * (deckX[k] - deckX[a])) / (deckX[b] - deckX[a])),
    ),
  );
  const chosen = extreme(deltas);
  const node = deck[indices[chosen]];
  const limit = (deckX[b] - deckX[a]) / settings.deflection.ratio;
  const unit = unitLoad(analysis, node);
  const virtual = sum(
    memberOrder.map(
      (m) =>
        (deflectionResult.axial[m] * (unit.axial[m] / 1000) * props[m].length) /
        (props[m].material.young * props[m].area),
    ),
  );
  const direct = -deflectionResult.displacement[2 * numbering[node] + 1];
  analysisLines.push(
    `deflection ${deflectionResult.name} span ${nodes[deck[a]].id} ${nodes[deck[b]].id} max ${format(deltas[chosen])} at ${nodes[node].id} limit ${format(limit)} ${deltas[chosen] <= limit ? 'ok' : 'exceeded'}`,
    `virtual_work ${deflectionResult.name} node ${nodes[node].id} stiffness ${format(direct)} virtual ${format(virtual)} ${Math.abs(virtual - direct) <= 0.000001 * Math.max(1, Math.abs(direct)) ? 'ok' : 'failed'}`,
  );
}
for (const removed of memberOrder) {
  const study = analyze(selection, removed);
  if (!study.stable) {
    analysisLines.push(
      `removal ${members[removed].id} unstable at ${nodes[rcm[Math.floor(study.dof / 2)]].id} ${study.dof % 2 ? 'y' : 'x'}`,
    );
    continue;
  }
  const result = study.combinations.find((result) => result.name === settings.removal)!;
  const remaining = memberOrder.filter((m) => m !== removed);
  const utilizations = remaining.map((m) => utilization(result.axial[m], study.properties[m]));
  const chosen = extreme(utilizations);
  const displacement = magnitudes(result);
  const node = extreme(displacement);
  analysisLines.push(
    `removal ${members[removed].id} stable max_utilization ${format(utilizations[chosen])} at ${members[remaining[chosen]].id} max_displacement ${format(displacement[node])} at ${nodes[node].id}`,
  );
}

const unitResults = deck.map((node) => unitLoad(analysis, node));
const axialOrdinates = memberOrder.map((m) => unitResults.map((result) => result.axial[m] / 1000));
const reactionOrdinates = reactionDofs.map(({ dof }) =>
  unitResults.map((result) => result.reaction[dof] / 1000),
);
const influenceLines: string[] = [];
for (const m of settings.influences) {
  const values = axialOrdinates[m];
  const maximum = extreme(values);
  const minimum = extreme(values, false);
  const crossings: number[] = [];
  for (let k = 0; k < deck.length - 1; k++) {
    if ((values[k] > 0 && values[k + 1] < 0) || (values[k] < 0 && values[k + 1] > 0)) {
      crossings.push(
        deckX[k] + ((deckX[k + 1] - deckX[k]) * values[k]) / (values[k] - values[k + 1]),
      );
    }
  }
  influenceLines.push(
    `influence ${members[m].id}`,
    ...deck.map((node, k) => `node ${nodes[node].id} ${format(values[k])}`),
    `max ${format(values[maximum])} at ${nodes[deck[maximum]].id} min ${format(values[minimum])} at ${nodes[deck[minimum]].id} positive ${format(sum(values.filter((value) => value > 0)))} negative ${format(sum(values.filter((value) => value < 0)))}`,
    `crossings ${crossings.length}${crossings.length ? ' ' + crossings.map((value) => format(value, 1)).join(' ') : ''}`,
  );
}
const positions: number[] = [];
for (let p = deckX[0]; p <= deckX.at(-1)! + settings.axles.at(-1)!.offset; p += settings.step) {
  positions.push(p);
}
function ordinate(values: number[], x: number): number {
  if (x < deckX[0] || x > deckX.at(-1)!) return 0;
  if (x === deckX.at(-1)) return values.at(-1)!;
  const k = deckX.findIndex((value, k) => value <= x && x < deckX[k + 1]);
  return values[k] + ((values[k + 1] - values[k]) * (x - deckX[k])) / (deckX[k + 1] - deckX[k]);
}
function vehicleEffects(values: number[]): {
  maximum: number;
  minimum: number;
  maxPosition: number;
  minPosition: number;
} {
  const effects = positions.map((p) =>
    sum(settings.axles.map((axle) => axle.load * ordinate(values, p - axle.offset))),
  );
  const maximum = extreme(effects);
  const minimum = extreme(effects, false);
  return {
    maximum: effects[maximum],
    minimum: effects[minimum],
    maxPosition: positions[maximum],
    minPosition: positions[minimum],
  };
}
const vehicleMembers = axialOrdinates.map(vehicleEffects);
const vehicleReactions = reactionOrdinates.map(vehicleEffects);
influenceLines.push(`vehicle axles ${settings.axles.length} positions ${positions.length}`);
vehicleMembers.forEach((effect, m) =>
  influenceLines.push(
    `vehicle_member ${members[m].id} max ${format(effect.maximum)} at ${effect.maxPosition} min ${format(effect.minimum)} at ${effect.minPosition}`,
  ),
);
vehicleReactions.forEach((effect, r) =>
  influenceLines.push(
    `vehicle_reaction ${nodes[reactionDofs[r].node].id} ${reactionDofs[r].direction ? 'y' : 'x'} max ${format(effect.maximum)} at ${effect.maxPosition} min ${format(effect.minimum)} at ${effect.minPosition}`,
  ),
);
const dead = resultNamed(settings.rating.name);
const ratings: { member: number; kind: 'tension' | 'compression'; value: number }[] = [];
memberOrder.forEach((m) => {
  const nd = dead.axial[m] / 1000;
  const effect = vehicleMembers[m];
  const pt = (props[m].area * props[m].material.yield) / 1000;
  const pc = Math.min(props[m].area * props[m].material.yield, buckling(props[m])) / 1000;
  const tension =
    rounded(effect.maximum) > 0
      ? (pt - settings.rating.dead * nd) / (settings.rating.live * effect.maximum)
      : undefined;
  const compression =
    rounded(effect.minimum) < 0
      ? (pc + settings.rating.dead * nd) / (settings.rating.live * -effect.minimum)
      : undefined;
  influenceLines.push(
    `rating ${members[m].id} tension ${tension === undefined ? 'none' : format(tension)} compression ${compression === undefined ? 'none' : format(compression)}`,
  );
  if (tension !== undefined) ratings.push({ member: m, kind: 'tension', value: tension });
  if (compression !== undefined) {
    ratings.push({ member: m, kind: 'compression', value: compression });
  }
});
const minimumRating =
  ratings[
    extreme(
      ratings.map((rating) => rating.value),
      false,
    )
  ];
influenceLines.push(
  `rating_min ${format(minimumRating.value)} at ${members[minimumRating.member].id} ${minimumRating.kind}`,
);

const massResult = resultNamed(settings.vibration.name);
const masses = nodeOrder.map((node) => -massResult.external[2 * numbering[node] + 1] / 9.81);
const freeMass = free.map((dof) => masses[rcm[Math.floor(dof / 2)]]);
const modes: number[][] = [];
const vibrationLines = [
  `vibration ${massResult.name} mass ${format(sum(masses))} iterations ${settings.vibration.iterations}`,
];
for (let mode = 1; mode <= settings.vibration.modes; mode++) {
  let x = Array<number>(free.length).fill(1);
  for (let iteration = 0; iteration < settings.vibration.iterations; iteration++) {
    for (const phi of modes) {
      const beta = sum(phi.map((value, i) => value * freeMass[i] * x[i]));
      x = x.map((value, i) => value - beta * phi[i]);
    }
    const y = solve(
      analysis.lower,
      x.map((value, i) => freeMass[i] * value),
    );
    const norm = Math.sqrt(sum(y.map((value, i) => freeMass[i] * value * value)));
    x = y.map((value) => value / norm);
  }
  modes.push(x);
  const kx = analysis.freeMatrix.map((row) => sum(row.map((value, j) => value * x[j])));
  const lambda =
    sum(x.map((value, i) => value * kx[i])) / sum(x.map((value, i) => freeMass[i] * value * value));
  const frequency = Math.sqrt(1000 * lambda) / (2 * pi);
  let largest = 0;
  for (let i = 1; i < x.length; i++) if (Math.abs(x[i]) > Math.abs(x[largest])) largest = i;
  const normalized = zeros(nd);
  free.forEach((dof, i) => {
    normalized[dof] = x[i] / x[largest];
  });
  vibrationLines.push(
    `mode ${mode} frequency ${format(frequency)} period ${format(1 / frequency)}`,
    ...nodeOrder.map(
      (node) =>
        `node ${nodes[node].id} ${format(normalized[2 * numbering[node]])} ${format(normalized[2 * numbering[node] + 1])}`,
    ),
  );
}

const drawingLines: string[] = [];
const x0 = Math.min(...nodes.map((node) => node.x));
const x1 = Math.max(...nodes.map((node) => node.x));
const y0 = Math.min(...nodes.map((node) => node.y));
const y1 = Math.max(...nodes.map((node) => node.y));
function draw(
  wc: number,
  hc: number,
  name: string,
  displacement?: number[],
  magnification = 0,
): void {
  const width = Math.floor((x1 - x0) / wc + 0.5) + 5;
  const height = Math.floor((y1 - y0) / hc + 0.5) + 5;
  const grid = Array.from({ length: height }, () => Array<string>(width).fill(' '));
  const point = (node: number, deformed = false): [number, number] => {
    const ux = deformed ? magnification * displacement![2 * numbering[node]] : 0;
    const uy = deformed ? magnification * displacement![2 * numbering[node] + 1] : 0;
    return [
      Math.floor((nodes[node].x + ux - x0) / wc + 0.5) + 2,
      Math.floor((y1 - (nodes[node].y + uy)) / hc + 0.5) + 2,
    ];
  };
  const write = (c: number, r: number, character: string) => {
    if (c >= 0 && c < width && r >= 0 && r < height) grid[r][c] = character;
  };
  function line(start: [number, number], end: [number, number], character: string): void {
    let [c, r] = start;
    const [c1, r1] = end;
    const dc = Math.abs(c1 - c);
    const dr = -Math.abs(r1 - r);
    const sc = c < c1 ? 1 : -1;
    const sr = r < r1 ? 1 : -1;
    let error = dc + dr;
    while (true) {
      write(c, r, character);
      if (c === c1 && r === r1) break;
      const doubled = 2 * error;
      if (doubled >= dr) {
        error += dr;
        c += sc;
      }
      if (doubled <= dc) {
        error += dc;
        r += sr;
      }
    }
  }
  if (displacement) {
    for (const member of members) line(point(member.i), point(member.j), '.');
    for (const node of nodeOrder) {
      const [c, r] = point(node);
      write(c, r, '+');
    }
    for (const member of members) line(point(member.i, true), point(member.j, true), '*');
    for (const node of nodeOrder) {
      const [c, r] = point(node, true);
      write(c, r, 'o');
    }
  } else {
    members.forEach((member, m) =>
      line(
        point(member.i),
        point(member.j),
        governing[m].value >= 1 ? '#' : String(Math.floor(10 * governing[m].value)),
      ),
    );
    for (const node of nodeOrder) {
      const [c, r] = point(node);
      write(c, r, 'o');
    }
  }
  const frame = '+' + '-'.repeat(width) + '+';
  drawingLines.push(
    `${name} columns ${width} rows ${height}`,
    frame,
    ...grid.map((row) => '|' + row.join('') + '|'),
    frame,
  );
}
for (const drawing of settings.drawings) {
  draw(
    drawing.wc,
    drawing.hc,
    `drawing ${drawing.name} magnification ${drawing.magnification}`,
    resultNamed(drawing.name).displacement,
    drawing.magnification,
  );
}
draw(settings.map.wc, settings.map.hc, 'utilization_map');
mkdirSync('output', { recursive: true });
for (const [name, lines] of [
  ['analysis.txt', analysisLines],
  ['displacements.csv', displacementLines],
  ['member_forces.csv', forceLines],
  ['reactions.csv', reactionLines],
  ['design.txt', designLines],
  ['influence.txt', influenceLines],
  ['drawing.txt', drawingLines],
  ['vibration.txt', vibrationLines],
] as const) {
  writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}
