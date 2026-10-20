import { readDataset, writeReports } from './dataset.ts';
import { prepareVectors, squaredDistance, distanceMatrix, distanceType } from './distances.ts';
import type { Matrix, DistanceType } from './distances.ts';
import { agglomerate, minimumSpanningTree, linkage } from './agglomerative.ts';
import type { Linkage } from './agglomerative.ts';
import { leafOrder, drawDendrogram } from './dendrogram.ts';
import type { Tree, TreeNode } from './dendrogram.ts';
import { correlation, contingency, adjustedRand, silhouettes } from './validation.ts';
import type { Fraction } from './validation.ts';

type Pair = [number, number];
interface Settings {
  distance: DistanceType; standardize: string; linkages: Linkage[]; heights: number[]; cuts: number[];
  inconsistencyDepth: number; lastMerges: number; gapMax: number; listSize: number; width: number;
  compare: Linkage; replicates: number; percent: number; seed: number; refineIterations: number;
}
type Data = ReturnType<typeof prepareData>;
type Evaluation = ReturnType<typeof evaluatePartition>;
type Method = ReturnType<typeof analyzeLinkage>;
interface Selection { method: Method; k: number; result: Evaluation }

function real(value: number | null): string {
  if (value === null) return '-';
  if (Math.abs(value) >= 1e21) return `${BigInt(value)}.0000`;
  const text = value.toFixed(4);
  return Number(text) === 0 ? '0.0000' : text;
}
const rounded = (value: number | null) => Number(real(value));
const ariText = (f: Fraction) => `${f[0]}/${f[1]} ${real(f[0] / f[1])}`;
const compareFractions = (a: Fraction, b: Fraction) => a[0] * b[1] - b[0] * a[1];
function sum<T>(values: T[], valueOf: (value: T) => number): number {
  let total = 0;
  for (const value of values) total += valueOf(value);
  return total;
}
function pairValues(matrix: Matrix): number[] {
  const values: number[] = [];
  for (let i = 0; i < matrix.length; i++) for (let j = i + 1; j < matrix.length; j++) values.push(matrix[i][j]);
  return values;
}
function groupsOf(partition: number[], count = Math.max(...partition) + 1): number[][] {
  const groups = Array.from({ length: count }, (): number[] => []);
  partition.forEach((cluster, observation) => groups[cluster].push(observation));
  return groups;
}
function centroid(vectors: Matrix, members: number[]): number[] {
  return vectors[0].map((_, f) => sum(members, i => vectors[i][f]) / members.length);
}

function prepareData() {
  const raw = readDataset();
  const param = (name: string) => raw.parameters.get(name)!;
  const numbers = (name: string) => param(name).map(Number);
  const [inconsistencyDepth, lastMerges] = numbers('INCONSISTENCY');
  const [replicates, percent, seed] = numbers('SUBSAMPLES');
  const settings: Settings = {
    distance: distanceType(param('DISTANCE')[0]), standardize: param('STANDARDIZE')[0],
    linkages: param('LINKAGES').map(linkage), heights: numbers('CUT_HEIGHTS'), cuts: numbers('CUT_K'),
    inconsistencyDepth, lastMerges, gapMax: numbers('GAP_MAX_K')[0], listSize: numbers('LIST_SIZE')[0],
    width: numbers('DENDROGRAM_WIDTH')[0], compare: linkage(param('COMPARE_LINKAGE')[0]),
    replicates, percent, seed, refineIterations: numbers('REFINE_ITERATIONS')[0],
  };
  const count = raw.observations.length, all = raw.observations.map((_, i) => i);
  const original = raw.observations.map(o => o.values);
  const classes = [...new Set(raw.observations.map(o => o.label))].sort();
  const classOf = raw.observations.map(o => classes.indexOf(o.label));
  const prepared = prepareVectors(original, settings.standardize === 'yes');
  const pairs: Pair[] = [];
  for (const i of all) for (let j = i + 1; j < count; j++) pairs.push([i, j]);
  return { ...raw, settings, count, all, original, classes, classOf, ...prepared,
    matrix: distanceMatrix(prepared.vectors, settings.distance), pairs };
}

function buildTree(matrix: Matrix, method: Linkage): Tree {
  const count = matrix.length, merges = agglomerate(matrix, method);
  const nodes: TreeNode[] = matrix.map((_, id) => ({ id, minimum: id, height: 0, maximum: 0,
    depth: 0, size: 1, members: [id], a: -1, b: -1, upper: -1, lower: -1 }));
  const joining = Array<number>(count).fill(0), cophenetic = matrix.map(() => Array<number>(count).fill(0));
  merges.forEach((merge, index) => {
    const a = nodes[merge.a], b = nodes[merge.b];
    const upper = a.minimum < b.minimum ? a.id : b.id, lower = upper === a.id ? b.id : a.id;
    nodes.push({ ...merge, id: count + index, upper, lower,
      members: [...a.members, ...b.members].sort((x, y) => x - y), minimum: Math.min(a.minimum, b.minimum),
      maximum: Math.max(merge.height, a.maximum, b.maximum), depth: 1 + Math.max(a.depth, b.depth) });
    if (merge.a < count) joining[merge.a] = merge.height;
    if (merge.b < count) joining[merge.b] = merge.height;
    for (const i of a.members) for (const j of b.members) cophenetic[i][j] = cophenetic[j][i] = merge.height;
  });
  return { count, merges, nodes, joining, cophenetic, order: leafOrder(count, nodes) };
}
function cutTree(tree: Tree, selected: (node: TreeNode, index: number) => boolean): number[] {
  const active = new Set(Array.from({ length: tree.count }, (_, i) => i));
  tree.merges.forEach((_, index) => {
    const node = tree.nodes[tree.count + index];
    if (!selected(node, index)) return;
    active.delete(node.a); active.delete(node.b); active.add(node.id);
  });
  const owner = Array<number>(tree.count), partition = Array<number>(tree.count), numbers = new Map<number, number>();
  for (const id of active) for (const member of tree.nodes[id].members) owner[member] = id;
  for (const member of tree.order) {
    if (!numbers.has(owner[member])) numbers.set(owner[member], numbers.size);
    partition[member] = numbers.get(owner[member])!;
  }
  return partition;
}
const cutNumber = (tree: Tree, count: number) => cutTree(tree, (_, index) => index < tree.count - count);

function evaluatePartition(data: Data, partition: number[], matrix = data.matrix) {
  const groups = groupsOf(partition), sizes = groups.map(group => group.length);
  const centers = groups.map(group => centroid(data.vectors, group)), overall = centroid(data.vectors, data.all);
  const values = silhouettes(matrix, partition), silhouette = values === null ? null : sum(values, v => v) / data.count;
  let diameter = 0, separation = Infinity;
  for (const [i, j] of data.pairs) {
    if (partition[i] === partition[j]) diameter = Math.max(diameter, matrix[i][j]);
    else separation = Math.min(separation, matrix[i][j]);
  }
  const dunn = groups.length >= 2 && diameter > 0 ? separation / diameter : null;
  const wss = sum(data.all, i => squaredDistance(data.vectors[i], centers[partition[i]]));
  const bss = sum(groups, group => group.length * squaredDistance(centers[partition[group[0]]], overall));
  const ch = groups.length >= 2 && groups.length < data.count
    ? (bss / (groups.length - 1)) / (wss / (data.count - groups.length)) : null;
  const table = contingency(partition, data.classOf, groups.length, data.classes.length);
  const matchCount = sum(table, row => Math.max(...row));
  return { partition, groups, sizes, centers, overall, values, silhouette, dunn, wss, ch, table,
    ari: adjustedRand(partition, data.classOf), matchCount, purity: matchCount / data.count };
}

function summarizeData(data: Data) {
  let minimum = data.pairs[0], maximum = data.pairs[0];
  for (const pair of data.pairs) {
    const value = data.matrix[pair[0]][pair[1]];
    if (value < data.matrix[minimum[0]][minimum[1]]) minimum = pair;
    if (value > data.matrix[maximum[0]][maximum[1]]) maximum = pair;
  }
  const neighbors = data.all.map(i => {
    let nearest = i === 0 ? 1 : 0;
    for (const j of data.all) if (j !== i && data.matrix[i][j] < data.matrix[i][nearest]) nearest = j;
    return nearest;
  });
  const reciprocal = data.all.filter(i => i < neighbors[i] && neighbors[neighbors[i]] === i).length;
  const maximumDistance = data.matrix[maximum[0]][maximum[1]], histogram = Array<number>(10).fill(0);
  for (const value of pairValues(data.matrix)) histogram[Math.min(9, Math.floor(10 * value / maximumDistance))]++;
  const columns = data.features.map((_, f) => data.original.map(v => v[f]));
  return { minimum, maximum, maximumDistance, neighbors, reciprocal, histogram,
    correlations: columns.map(a => columns.map(b => correlation(a, b))),
    mean: sum(pairValues(data.matrix), v => v) / data.pairs.length,
    neighborMean: sum(data.all, i => data.matrix[i][neighbors[i]]) / data.count,
    labelEvaluation: evaluatePartition(data, data.classOf) };
}
function inconsistency(tree: Tree, id: number, depth: number) {
  const heights: number[] = [], stack = [{ id, depth }];
  while (stack.length > 0) {
    const current = stack.pop()!;
    if (current.depth === 0 || current.id < tree.count) continue;
    const node = tree.nodes[current.id];
    heights.push(node.height);
    stack.push({ id: node.b, depth: current.depth - 1 }, { id: node.a, depth: current.depth - 1 });
  }
  const mean = sum(heights, h => h) / heights.length;
  const sd = heights.length === 1 ? 0 : Math.sqrt(sum(heights, h => (h - mean) * (h - mean)) / (heights.length - 1));
  return { step: id - tree.count + 1, height: tree.nodes[id].height, mean, sd, count: heights.length,
    coefficient: heights.length === 1 ? 0 : (tree.nodes[id].height - mean) / sd };
}
function analyzeLinkage(data: Data, name: Linkage, index: number) {
  const tree = buildTree(data.matrix, name), copheneticValues = pairValues(tree.cophenetic);
  const heights = tree.merges.map(m => m.height);
  const subtreeHeights = tree.nodes.slice(data.count).map(n => n.maximum).sort((a, b) => a - b);
  const inversions: { step: number; height: number; previous: number }[] = [];
  for (let i = 1; i < heights.length; i++) if (heights[i] < heights[i - 1]) {
    inversions.push({ step: i + 1, height: heights[i], previous: heights[i - 1] });
  }
  const gaps = Array.from({ length: data.settings.gapMax - 1 }, (_, i) => {
    const k = i + 2;
    return { k, value: subtreeHeights[data.count - k] - subtreeHeights[data.count - k - 1] };
  });
  let suggested = gaps[0], leafPath = 0;
  for (const gap of gaps) if (rounded(gap.value) > rounded(suggested.value)) suggested = gap;
  for (let i = 1; i < tree.order.length; i++) leafPath += data.matrix[tree.order[i - 1]][tree.order[i]];
  const late = data.all.slice().sort((a, b) => tree.joining[b] - tree.joining[a] || a - b).slice(0, data.settings.listSize);
  const kinds = [0, 0, 0];
  for (const m of tree.merges) kinds[2 - Number(m.a < data.count) - Number(m.b < data.count)]++;
  return { name, index, tree, copheneticValues, heights, inversions, gaps, suggested: suggested.k, leafPath, late, kinds,
    cophenetic: correlation(pairValues(data.matrix), copheneticValues),
    inconsistencies: tree.nodes.slice(-data.settings.lastMerges).map(n => inconsistency(tree, n.id, data.settings.inconsistencyDepth)),
    heightCuts: data.settings.heights.map(height => ({ height, result: evaluatePartition(data, cutTree(tree, n => n.maximum <= height)) })),
    numberCuts: data.settings.cuts.map(k => ({ k, result: evaluatePartition(data, cutNumber(tree, k)) })),
    labelCut: evaluatePartition(data, cutNumber(tree, data.classes.length)) };
}

function spanningTreeChecks(data: Data, summary: ReturnType<typeof summarizeData>, methods: Method[]) {
  const single = methods.find(m => m.name === 'single');
  if (!single) return null;
  const edges = minimumSpanningTree(data.matrix), sorted = edges.slice().sort((a, b) => a.weight - b.weight || a.number - b.number);
  const key = (a: number, b: number) => `${Math.min(a, b)},${Math.max(a, b)}`;
  const edgeSet = new Set(edges.map(e => key(e.a, e.b)));
  const partitions = single.numberCuts.map(cut => {
    const parents = data.all.slice();
    const find = (i: number): number => {
      while (parents[i] !== i) { parents[i] = parents[parents[i]]; i = parents[i]; }
      return i;
    };
    for (const edge of sorted.slice(0, data.count - cut.k)) parents[find(edge.b)] = find(edge.a);
    return { k: cut.k, matches: data.pairs.every(([a, b]) =>
      (find(a) === find(b)) === (cut.result.partition[a] === cut.result.partition[b])) };
  });
  return { total: sum(edges, e => e.weight), heightMatch: sorted.every((e, i) => Math.abs(e.weight - single.heights[i]) <= 1e-9),
    neighborEdges: data.all.filter(i => edgeSet.has(key(i, summary.neighbors[i]))).length, partitions };
}
function compareDistanceTypes(data: Data) {
  const types: DistanceType[] = ['euclidean', 'manhattan', 'correlation'];
  return types.map(name => {
    const matrix = distanceMatrix(data.vectors, name), tree = buildTree(matrix, data.settings.compare);
    const result = evaluatePartition(data, cutNumber(tree, data.classes.length), matrix);
    return { name, cophenetic: correlation(pairValues(matrix), pairValues(tree.cophenetic)), silhouette: result.silhouette, ari: result.ari };
  });
}
function compareLinkages(data: Data, methods: Method[]) {
  const candidates: Selection[] = methods.flatMap(method => method.numberCuts.map(cut => ({ method, ...cut })));
  const best = (items: Selection[]) => {
    let winner = items[0];
    for (const item of items) if (compareFractions(item.result.ari, winner.result.ari) > 0) winner = item;
    return winner;
  };
  return {
    cophenetic: methods.map(a => methods.map(b => correlation(a.copheneticValues, b.copheneticValues))),
    agreement: methods.map(a => methods.map(b => adjustedRand(a.labelCut.partition, b.labelCut.partition))),
    ranking: methods.slice().sort((a, b) => rounded(b.cophenetic) - rounded(a.cophenetic) || a.index - b.index),
    bestARI: data.settings.cuts.map(k => best(candidates.filter(c => c.k === k))),
    bestSilhouette: methods.map(method => {
      let best = method.numberCuts[0];
      for (const cut of method.numberCuts) if (rounded(cut.result.silhouette) > rounded(best.result.silhouette)) best = cut;
      return { method, ...best };
    }), selected: best(candidates),
  };
}

function describeClusters(data: Data, selected: Selection) {
  const result = selected.result;
  return result.groups.map((members, cluster) => {
    const majorityCount = Math.max(...result.table[cluster]), majority = result.table[cluster].indexOf(majorityCount);
    let medoid = members[0], medoidSum = Infinity, diameter = 0;
    let diameterPair: Pair | null = null;
    for (const candidate of members) {
      const value = sum(members, other => data.matrix[candidate][other]);
      if (value < medoidSum) { medoid = candidate; medoidSum = value; }
    }
    for (const [a, b] of data.pairs) if (result.partition[a] === cluster && result.partition[b] === cluster
      && (diameterPair === null || data.matrix[a][b] > diameter)) { diameter = data.matrix[a][b]; diameterPair = [a, b]; }
    let nearest = -1, separation = Infinity;
    result.groups.forEach((others, otherCluster) => {
      if (otherCluster === cluster) return;
      let distance = Infinity;
      for (const a of members) for (const b of others) distance = Math.min(distance, data.matrix[a][b]);
      if (distance < separation) { nearest = otherCluster; separation = distance; }
    });
    return { members, majority, majorityCount, medoid, diameter, diameterPair, nearest, separation,
      profile: data.features.map((_, f) => sum(members, i => (data.original[i][f] - data.means[f]) / data.deviations[f]) / members.length),
      mean: centroid(data.original, members), silhouette: sum(members, i => result.values![i]) / members.length };
  });
}
function featureRatios(data: Data, selected: Selection) {
  const result = selected.result;
  return data.features.map((name, feature) => {
    let between = 0;
    for (let g = 0; g < result.groups.length; g++) {
      const d = result.centers[g][feature] - result.overall[feature];
      between += result.sizes[g] * d * d;
    }
    const within = sum(data.all, i => {
      const d = data.vectors[i][feature] - result.centers[result.partition[i]][feature];
      return d * d;
    });
    return { name, feature, value: (between / (selected.k - 1)) / (within / (data.count - selected.k)) };
  }).sort((a, b) => rounded(b.value) - rounded(a.value) || a.feature - b.feature);
}
function withoutFeatures(data: Data, selected: Selection) {
  return data.features.map((name, feature) => {
    const vectors = data.vectors.map(v => v.filter((_, i) => i !== feature));
    const partition = cutNumber(buildTree(distanceMatrix(vectors, data.settings.distance), selected.method.name), selected.k);
    return { name, selectedARI: adjustedRand(partition, selected.result.partition), labelARI: adjustedRand(partition, data.classOf) };
  });
}
function refinePartition(data: Data, selected: Selection) {
  let partition = selected.result.partition.slice(), centers = selected.result.centers.map(c => c.slice()), iterations = 0;
  for (let iteration = 1; iteration <= data.settings.refineIterations; iteration++) {
    const next = data.vectors.map(vector => {
      let nearest = 0, distance = squaredDistance(vector, centers[0]);
      for (let g = 1; g < centers.length; g++) {
        const value = squaredDistance(vector, centers[g]);
        if (value < distance) { nearest = g; distance = value; }
      }
      return nearest;
    });
    iterations = iteration;
    const unchanged = next.every((g, i) => g === partition[i]);
    partition = next;
    if (unchanged) break;
    centers = groupsOf(partition, selected.k).map((members, g) => members.length ? centroid(data.vectors, members) : centers[g]);
  }
  return { iterations, changed: data.all.filter(i => partition[i] !== selected.result.partition[i]).length,
    result: evaluatePartition(data, partition), selectedARI: adjustedRand(partition, selected.result.partition) };
}
function subsampleStability(data: Data, selected: Selection) {
  const size = Math.floor(data.count * data.settings.percent / 100);
  const replicates: { replicate: number; size: number; ari: Fraction; jaccard: number[] }[] = [];
  let state = data.settings.seed;
  for (let replicate = 1; replicate <= data.settings.replicates; replicate++) {
    const shuffled = data.all.slice();
    for (let t = 0; t < size; t++) {
      state = 48271 * state % 2147483647;
      const j = t + state % (data.count - t);
      [shuffled[t], shuffled[j]] = [shuffled[j], shuffled[t]];
    }
    const sample = shuffled.slice(0, size).sort((a, b) => a - b);
    const matrix = sample.map(a => sample.map(b => data.matrix[a][b]));
    const partition = cutNumber(buildTree(matrix, selected.method.name), selected.k);
    const restricted = sample.map(i => selected.result.partition[i]), groups = groupsOf(partition);
    const jaccard = selected.result.groups.map((_, g) => {
      const intersectionSize = restricted.filter(value => value === g).length;
      if (intersectionSize === 0) return 0;
      let best: Fraction = [0, 1];
      for (const members of groups) {
        const common = members.filter(i => restricted[i] === g).length;
        const ratio: Fraction = [common, intersectionSize + members.length - common];
        if (compareFractions(ratio, best) > 0) best = ratio;
      }
      return best[0] / best[1];
    });
    replicates.push({ replicate, size, ari: adjustedRand(partition, restricted), jaccard });
  }
  return { replicates, meanARI: sum(replicates, r => r.ari[0] / r.ari[1]) / replicates.length,
    meanJaccard: selected.result.groups.map((_, g) => sum(replicates, r => r.jaccard[g]) / replicates.length) };
}
function selectedAnalysis(data: Data, selected: Selection) {
  const clusters = describeClusters(data, selected);
  const classCounts = (members: number[]) => {
    const counts = data.classes.map(() => 0);
    for (const i of members) counts[data.classOf[i]]++;
    return counts;
  };
  return { clusters,
    centroidDistances: selected.result.centers.map(a => selected.result.centers.map(b => Math.sqrt(squaredDistance(a, b)))),
    misplaced: data.all.filter(i => data.classOf[i] !== clusters[selected.result.partition[i]].majority),
    weakest: data.all.slice().sort((a, b) => selected.result.values![a] - selected.result.values![b] || a - b).slice(0, data.settings.listSize),
    topMerges: selected.method.tree.nodes.slice(-data.settings.lastMerges).map(node => {
      const a = selected.method.tree.nodes[node.a], b = selected.method.tree.nodes[node.b];
      return { node, a, b, aCounts: classCounts(a.members), bCounts: classCounts(b.members) };
    }), features: featureRatios(data, selected), dropped: withoutFeatures(data, selected),
    refinement: refinePartition(data, selected), stability: subsampleStability(data, selected) };
}

function evaluationText(r: Evaluation): string {
  return `sizes ${r.sizes.join(' ')} silhouette ${real(r.silhouette)} dunn ${real(r.dunn)} wss ${real(r.wss)} ch ${real(r.ch)} ari ${ariText(r.ari)}`;
}
function joinSections(sections: string[][]): string[] {
  return sections.flatMap((section, i) => i === 0 ? section : ['', ...section]);
}
function linkageReport(methods: Method[]): string[] {
  return ['method,step,a,b,height,size', ...methods.flatMap(m => m.tree.merges.map((r, i) =>
    [m.name, i + 1, r.a, r.b, real(r.height), r.size].join(',')))];
}
function clustersReport(data: Data, methods: Method[]): string[] {
  const columns = methods.flatMap(m => [
    ...m.heightCuts.map((cut, i) => ({ name: `${m.name}_h${i + 1}`, partition: cut.result.partition })),
    ...m.numberCuts.map(cut => ({ name: `${m.name}_k${cut.k}`, partition: cut.result.partition })),
  ]);
  return [['id', 'label', ...columns.map(c => c.name)].join(','), ...data.observations.map((o, i) =>
    [o.id, o.label, ...columns.map(c => c.partition[i] + 1)].join(','))];
}
function dendrogramReport(data: Data, methods: Method[]): string[] {
  return joinSections(methods.map(m => {
    const drawing = drawDendrogram(data.observations, m.tree, data.settings.width, data.settings.heights);
    return [`dendrogram ${m.name} height_max ${real(drawing.maximum)} width ${data.settings.width}`, ...drawing.rows, drawing.scale,
      ...data.settings.heights.map((h, i) => `cut ${real(h)} column ${drawing.cuts[i] > data.settings.width ? '-' : drawing.cuts[i]}`)];
  }));
}
function treesReport(data: Data, methods: Method[]): string[] {
  return methods.map(m => {
    const strings = data.observations.map(o => o.id);
    for (const node of m.tree.nodes.slice(data.count)) {
      const upper = m.tree.nodes[node.upper], lower = m.tree.nodes[node.lower];
      strings[node.id] = `(${strings[upper.id]}:${real(node.height - upper.height)},${strings[lower.id]}:${real(node.height - lower.height)})`;
    }
    return `${m.name} ${strings[strings.length - 1]};`;
  });
}
function linkageAnalysisLines(data: Data, m: Method): string[] {
  return [`linkage ${m.name}`, `cophenetic ${real(m.cophenetic)} leaf_path ${real(m.leafPath)}`,
    `heights min ${real(Math.min(...m.heights))} max ${real(Math.max(...m.heights))} inversions ${m.inversions.length}`,
    ...m.inversions.map(i => `inversion step ${i.step} height ${real(i.height)} previous ${real(i.previous)}`),
    `gaps ${m.gaps.map(g => real(g.value)).join(' ')}`, `suggested_k ${m.suggested}`,
    `late_joiners ${m.late.map(i => `${data.observations[i].id}:${real(m.tree.joining[i])}`).join(' ')}`,
    `merges leaf_leaf ${m.kinds[0]} leaf_cluster ${m.kinds[1]} cluster_cluster ${m.kinds[2]} depth ${m.tree.nodes[m.tree.nodes.length - 1].depth}`,
    `label_cut k ${data.classes.length} purity ${m.labelCut.matchCount}/${data.count} ${real(m.labelCut.purity)}`,
    `inconsistency depth ${data.settings.inconsistencyDepth}`,
    ...m.inconsistencies.map(i => `step ${i.step} height ${real(i.height)} mean ${real(i.mean)} sd ${real(i.sd)} count ${i.count} coefficient ${real(i.coefficient)}`),
    ...m.heightCuts.map(c => `cut height ${real(c.height)} clusters ${c.result.groups.length} ${evaluationText(c.result)}`),
    ...m.numberCuts.map(c => `cut k ${c.k} ${evaluationText(c.result)}`)];
}
type State = ReturnType<typeof analyze>;
function validationReport(data: Data, state: State): string[] {
  const s = state.summary, min = s.minimum, max = s.maximum;
  const sections = [[`data n ${data.count} features ${data.features.length} classes ${data.classes.length} distance ${data.settings.distance} standardize ${data.settings.standardize}`,
    ...data.features.map((name, f) => `feature ${name} mean ${real(data.means[f])} sd ${real(data.deviations[f])}`),
    `distances pairs ${data.pairs.length} min ${real(data.matrix[min[0]][min[1]])} ${data.observations[min[0]].id} ${data.observations[min[1]].id} max ${real(s.maximumDistance)} ${data.observations[max[0]].id} ${data.observations[max[1]].id} mean ${real(s.mean)}`,
    `nearest_neighbors mean ${real(s.neighborMean)} reciprocal_pairs ${s.reciprocal}`, `labels ${evaluationText(s.labelEvaluation)}`],
  [`correlation ${data.features.join(' ')}`, ...data.features.map((name, i) => `${name} ${s.correlations[i].map(real).join(' ')}`)],
  ['histogram', ...s.histogram.map((count, b) => {
    const length = Math.floor(count * 50 / Math.max(...s.histogram));
    return `${real(b * s.maximumDistance / 10)} ${real((b + 1) * s.maximumDistance / 10)} ${count}` + (length ? ' ' + '#'.repeat(length) : '');
  })], ...state.methods.map(m => linkageAnalysisLines(data, m))];
  if (state.mst) {
    const m = state.mst;
    sections.push([`mst total ${real(m.total)} heights ${m.heightMatch ? 'match' : 'mismatch'} nn_edges ${m.neighborEdges}/${data.count}`,
      ...m.partitions.map(p => `mst partition k ${p.k} ${p.matches ? 'match' : 'mismatch'}`)]);
  }
  const names = state.methods.map(m => m.name).join(' '), c = state.comparison;
  sections.push([`compare linkage ${data.settings.compare} k ${data.classes.length}`,
    ...state.metrics.map(m => `metric ${m.name} cophenetic ${real(m.cophenetic)} silhouette ${real(m.silhouette)} ari ${ariText(m.ari)}`)],
  ['cophenetic_matrix', `linkage ${names}`, ...state.methods.map((m, i) => `${m.name} ${c.cophenetic[i].map(real).join(' ')}`)],
  [`agreement k ${data.classes.length}`, `linkage ${names}`, ...state.methods.map((m, i) => `${m.name} ${c.agreement[i].map(f => real(f[0] / f[1])).join(' ')}`)],
  ['summary', `cophenetic_ranking ${c.ranking.map(m => m.name).join(' ')}`,
    ...c.bestARI.map(b => `best_ari k ${b.k} ${b.method.name} ${ariText(b.result.ari)}`),
    ...c.bestSilhouette.map(b => `best_silhouette ${b.method.name} k ${b.k} ${real(b.result.silhouette)}`),
    `selected ${c.selected.method.name} k ${c.selected.k}`]);
  return joinSections(sections);
}
function profilesReport(data: Data, state: State): string[] {
  const selected = state.comparison.selected, a = state.selected, r = selected.result;
  const details = [`selected linkage ${selected.method.name} k ${selected.k} ari ${ariText(r.ari)} silhouette ${real(r.silhouette)}`];
  a.clusters.forEach((c, i) => {
    const pair = c.diameterPair === null ? '- -' : c.diameterPair.map(j => data.observations[j].id).join(' ');
    details.push(`cluster ${i + 1} size ${c.members.length} silhouette ${real(c.silhouette)} majority ${data.classes[c.majority]} purity ${c.majorityCount}/${c.members.length} ${real(c.majorityCount / c.members.length)}`,
      `  mean ${c.mean.map(real).join(' ')}`,
      `  medoid ${data.observations[c.medoid].id} diameter ${real(c.diameter)} ${pair} nearest ${c.nearest + 1} separation ${real(c.separation)}`);
  });
  const profile = ['profile_bars'], width = Math.max(...data.features.map(f => f.length));
  a.clusters.forEach((c, i) => {
    profile.push(`cluster ${i + 1}`);
    data.features.forEach((name, f) => {
      const v = c.profile[f], length = Math.min(10, Math.floor(Math.abs(v) * 4));
      const left = v < 0 ? ' '.repeat(10 - length) + '#'.repeat(length) : ' '.repeat(10);
      const right = v < 0 ? ' '.repeat(10) : '#'.repeat(length) + ' '.repeat(10 - length);
      profile.push(`${name.padEnd(width)} ${left}|${right} ${real(v)}`);
    });
  });
  const refinement = a.refinement, stability = a.stability;
  const border = '+' + '-'.repeat(data.count) + '+';
  return joinSections([details,
    ['centroid_distances', ...a.centroidDistances.map((row, i) => `${i + 1} ${row.map(real).join(' ')}`)], profile,
    ['contingency', `cluster ${data.classes.join(' ')} total`, ...r.table.map((row, i) => `${i + 1} ${row.join(' ')} ${sum(row, v => v)}`),
      `total ${data.classes.map((_, j) => sum(r.table, row => row[j])).join(' ')} ${data.count}`, `purity ${r.matchCount}/${data.count} ${real(r.purity)}`],
    ['misplaced', ...a.misplaced.map(i => `${data.observations[i].id} label ${data.observations[i].label} cluster ${r.partition[i] + 1} majority ${data.classes[a.clusters[r.partition[i]].majority]}`), `count ${a.misplaced.length}`],
    ['weakest', ...a.weakest.map(i => `${data.observations[i].id} label ${data.observations[i].label} cluster ${r.partition[i] + 1} silhouette ${real(r.values![i])}`)],
    ['features', ...a.features.map((f, i) => `${i + 1} ${f.name} f_ratio ${real(f.value)}`)],
    ['top_merges', ...a.topMerges.map(m => `step ${m.node.id - data.count + 1} height ${real(m.node.height)} a ${m.a.id} ${m.a.size} ${m.aCounts.join('/')} b ${m.b.id} ${m.b.size} ${m.bCounts.join('/')}`)],
    ['drop_feature', ...a.dropped.map(f => `${f.name} ari_selected ${ariText(f.selectedARI)} ari_labels ${ariText(f.labelARI)}`)],
    [`refinement max_iterations ${data.settings.refineIterations}`,
      `iterations ${refinement.iterations} changed ${refinement.changed} wss ${real(r.wss)} -> ${real(refinement.result.wss)}`,
      `sizes ${refinement.result.sizes.join(' ')} silhouette ${real(refinement.result.silhouette)}`,
      `ari_selected ${ariText(refinement.selectedARI)} ari_labels ${ariText(refinement.result.ari)}`],
    [`stability replicates ${data.settings.replicates} percent ${data.settings.percent} seed ${data.settings.seed}`,
      ...stability.replicates.map(s => `replicate ${s.replicate} size ${s.size} ari ${ariText(s.ari)} jaccard ${s.jaccard.map(real).join(' ')}`),
      `mean_ari ${real(stability.meanARI)}`, `mean_jaccard ${stability.meanJaccard.map(real).join(' ')}`],
    [`distance_map ${selected.method.name}`, border, ...selected.method.tree.order.map(i => '|' + selected.method.tree.order.map(j =>
      '@%#*+=-:. '[Math.min(9, Math.floor(10 * data.matrix[i][j] / state.summary.maximumDistance))]).join('') + '|'), border],
  ]);
}
function analyze(data: Data) {
  const summary = summarizeData(data), methods = data.settings.linkages.map((name, i) => analyzeLinkage(data, name, i));
  const comparison = compareLinkages(data, methods);
  return { summary, methods, comparison, mst: spanningTreeChecks(data, summary, methods),
    metrics: compareDistanceTypes(data), selected: selectedAnalysis(data, comparison.selected) };
}
function main(): void {
  const data = prepareData(), state = analyze(data);
  writeReports({ 'linkage.csv': linkageReport(state.methods), 'clusters.csv': clustersReport(data, state.methods),
    'dendrogram.txt': dendrogramReport(data, state.methods), 'trees.txt': treesReport(data, state.methods),
    'validation.txt': validationReport(data, state), 'profiles.txt': profilesReport(data, state) });
}
main();
