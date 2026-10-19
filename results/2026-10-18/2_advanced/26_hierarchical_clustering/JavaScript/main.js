const { readDataset, writeReports } = require('./dataset');
const { prepareVectors, squaredDistance, distanceMatrix } = require('./distances');
const { agglomerate, minimumSpanningTree } = require('./agglomerative');
const { leafOrder, drawDendrogram } = require('./dendrogram');
const { correlation, contingency, adjustedRand, silhouettes } = require('./validation');

const DISTANCE_TYPES = ['euclidean', 'manhattan', 'correlation'];
const SHADES = '@%#*+=-:. ';

function real(value) {
  if (value === null) return '-';
  if (Math.abs(value) >= 1e21) return `${BigInt(value)}.0000`;
  const text = value.toFixed(4);
  return Number(text) === 0 ? '0.0000' : text;
}

function rounded(value) {
  return Number(real(value));
}

function ariText(value) {
  return `${value[0]}/${value[1]} ${real(value[0] / value[1])}`;
}

function compareFractions(first, second) {
  return first[0] * second[1] - second[0] * first[1];
}

function sum(values, valueOf = value => value) {
  let total = 0;
  for (const value of values) total += valueOf(value);
  return total;
}

function pairValues(matrix) {
  const values = [];
  for (let first = 0; first < matrix.length; first += 1) {
    for (let second = first + 1; second < matrix.length; second += 1) values.push(matrix[first][second]);
  }
  return values;
}

function groupsOf(partition, count = Math.max(...partition) + 1) {
  const groups = Array.from({ length: count }, () => []);
  partition.forEach((cluster, observation) => groups[cluster].push(observation));
  return groups;
}

function centroid(vectors, members) {
  return vectors[0].map((_, feature) => sum(members, member => vectors[member][feature]) / members.length);
}

function prepareData() {
  const data = readDataset();
  const params = data.parameters;
  const numbers = name => params.get(name).map(Number);
  const [inconsistencyDepth, lastMerges] = numbers('INCONSISTENCY');
  const [replicates, percent, seed] = numbers('SUBSAMPLES');
  data.settings = {
    distance: params.get('DISTANCE')[0], standardize: params.get('STANDARDIZE')[0],
    linkages: params.get('LINKAGES'), heights: numbers('CUT_HEIGHTS'), cuts: numbers('CUT_K'),
    inconsistencyDepth, lastMerges, gapMax: numbers('GAP_MAX_K')[0], listSize: numbers('LIST_SIZE')[0],
    width: numbers('DENDROGRAM_WIDTH')[0], compare: params.get('COMPARE_LINKAGE')[0],
    replicates, percent, seed, refineIterations: numbers('REFINE_ITERATIONS')[0],
  };
  data.count = data.observations.length;
  data.all = data.observations.map((_, index) => index);
  data.original = data.observations.map(observation => observation.values);
  data.classes = [...new Set(data.observations.map(observation => observation.label))].sort();
  data.classOf = data.observations.map(observation => data.classes.indexOf(observation.label));
  Object.assign(data, prepareVectors(data.original, data.settings.standardize === 'yes'));
  data.matrix = distanceMatrix(data.vectors, data.settings.distance);
  data.pairs = [];
  for (const first of data.all) {
    for (let second = first + 1; second < data.count; second += 1) data.pairs.push([first, second]);
  }
  return data;
}

function buildTree(matrix, method) {
  const count = matrix.length;
  const merges = agglomerate(matrix, method);
  const nodes = matrix.map((_, id) => ({ id, minimum: id, height: 0, maximum: 0, depth: 0, size: 1, members: [id] }));
  const joining = Array(count).fill(0);
  const cophenetic = matrix.map(() => Array(count).fill(0));
  merges.forEach((merge, index) => {
    const a = nodes[merge.a];
    const b = nodes[merge.b];
    const upper = a.minimum < b.minimum ? a.id : b.id;
    const lower = upper === a.id ? b.id : a.id;
    const members = [...a.members, ...b.members].sort((first, second) => first - second);
    nodes.push({ ...merge, id: count + index, upper, lower, members,
      minimum: Math.min(a.minimum, b.minimum), maximum: Math.max(merge.height, a.maximum, b.maximum),
      depth: 1 + Math.max(a.depth, b.depth) });
    if (merge.a < count) joining[merge.a] = merge.height;
    if (merge.b < count) joining[merge.b] = merge.height;
    for (const first of a.members) {
      for (const second of b.members) {
        cophenetic[first][second] = merge.height;
        cophenetic[second][first] = merge.height;
      }
    }
  });
  return { count, merges, nodes, joining, cophenetic, order: leafOrder(count, nodes) };
}

function cutTree(tree, selected) {
  const active = new Set(Array.from({ length: tree.count }, (_, index) => index));
  for (let index = 0; index < tree.merges.length; index += 1) {
    const node = tree.nodes[tree.count + index];
    if (!selected(node, index)) continue;
    active.delete(node.a);
    active.delete(node.b);
    active.add(node.id);
  }
  const owner = Array(tree.count);
  for (const id of active) for (const member of tree.nodes[id].members) owner[member] = id;
  const numbers = new Map();
  const partition = Array(tree.count);
  for (const member of tree.order) {
    if (!numbers.has(owner[member])) numbers.set(owner[member], numbers.size);
    partition[member] = numbers.get(owner[member]);
  }
  return partition;
}

function cutNumber(tree, count) {
  return cutTree(tree, (_, index) => index < tree.count - count);
}

function evaluatePartition(data, partition, matrix = data.matrix) {
  const groups = groupsOf(partition);
  const sizes = groups.map(group => group.length);
  const centers = groups.map(group => centroid(data.vectors, group));
  const overall = centroid(data.vectors, data.all);
  const values = silhouettes(matrix, partition);
  const silhouette = values === null ? null : sum(values) / data.count;
  let diameter = 0;
  let separation = null;
  for (const [first, second] of data.pairs) {
    if (partition[first] === partition[second]) diameter = Math.max(diameter, matrix[first][second]);
    else if (separation === null || matrix[first][second] < separation) separation = matrix[first][second];
  }
  const dunn = groups.length >= 2 && diameter > 0 ? separation / diameter : null;
  const wss = sum(data.all, observation => squaredDistance(data.vectors[observation], centers[partition[observation]]));
  const bss = sum(groups, group => group.length * squaredDistance(centers[partition[group[0]]], overall));
  const ch = groups.length >= 2 && groups.length < data.count
    ? (bss / (groups.length - 1)) / (wss / (data.count - groups.length)) : null;
  const table = contingency(partition, data.classOf, groups.length, data.classes.length);
  const matchCount = sum(table, row => Math.max(...row));
  return { partition, groups, sizes, centers, overall, values, silhouette, dunn, wss, ch, table,
    ari: adjustedRand(partition, data.classOf), matchCount, purity: matchCount / data.count };
}

function summarizeData(data) {
  let minimum = data.pairs[0];
  let maximum = data.pairs[0];
  for (const pair of data.pairs) {
    const value = data.matrix[pair[0]][pair[1]];
    if (value < data.matrix[minimum[0]][minimum[1]]) minimum = pair;
    if (value > data.matrix[maximum[0]][maximum[1]]) maximum = pair;
  }
  const neighbors = data.all.map(observation => {
    let nearest = null;
    for (const other of data.all) {
      if (other !== observation && (nearest === null || data.matrix[observation][other] < data.matrix[observation][nearest])) nearest = other;
    }
    return nearest;
  });
  const reciprocal = data.all.filter(observation => observation < neighbors[observation]
    && neighbors[neighbors[observation]] === observation).length;
  const maximumDistance = data.matrix[maximum[0]][maximum[1]];
  const histogram = Array(10).fill(0);
  for (const value of pairValues(data.matrix)) histogram[Math.min(9, Math.floor(10 * value / maximumDistance))] += 1;
  const columns = data.features.map((_, feature) => data.original.map(vector => vector[feature]));
  const correlations = columns.map(first => columns.map(second => correlation(first, second)));
  return { minimum, maximum, maximumDistance, neighbors, reciprocal, histogram, correlations,
    mean: sum(pairValues(data.matrix)) / data.pairs.length,
    neighborMean: sum(data.all, observation => data.matrix[observation][neighbors[observation]]) / data.count,
    labelEvaluation: evaluatePartition(data, data.classOf) };
}

function inconsistency(tree, id, depth) {
  const heights = [];
  const stack = [{ id, depth }];
  while (stack.length > 0) {
    const current = stack.pop();
    if (current.depth === 0 || current.id < tree.count) continue;
    const node = tree.nodes[current.id];
    heights.push(node.height);
    stack.push({ id: node.b, depth: current.depth - 1 }, { id: node.a, depth: current.depth - 1 });
  }
  const mean = sum(heights) / heights.length;
  const sd = heights.length === 1 ? 0 : Math.sqrt(sum(heights, value => (value - mean) * (value - mean)) / (heights.length - 1));
  return { step: id - tree.count + 1, height: tree.nodes[id].height, mean, sd, count: heights.length,
    coefficient: heights.length === 1 ? 0 : (tree.nodes[id].height - mean) / sd };
}

function analyzeLinkage(data, name, index) {
  const tree = buildTree(data.matrix, name);
  const copheneticValues = pairValues(tree.cophenetic);
  const heights = tree.merges.map(merge => merge.height);
  const subtreeHeights = tree.nodes.slice(data.count).map(node => node.maximum).sort((a, b) => a - b);
  const inversions = [];
  for (let step = 1; step < heights.length; step += 1) {
    if (heights[step] < heights[step - 1]) inversions.push({ step: step + 1, height: heights[step], previous: heights[step - 1] });
  }
  const gaps = [];
  for (let k = 2; k <= data.settings.gapMax; k += 1) gaps.push({ k, value: subtreeHeights[data.count - k] - subtreeHeights[data.count - k - 1] });
  let suggested = gaps[0];
  for (const gap of gaps) if (rounded(gap.value) > rounded(suggested.value)) suggested = gap;
  let leafPath = 0;
  for (let position = 1; position < tree.order.length; position += 1) leafPath += data.matrix[tree.order[position - 1]][tree.order[position]];
  const late = data.all.slice().sort((a, b) => tree.joining[b] - tree.joining[a] || a - b).slice(0, data.settings.listSize);
  const kinds = [0, 0, 0];
  for (const merge of tree.merges) kinds[2 - Number(merge.a < data.count) - Number(merge.b < data.count)] += 1;
  const inconsistencies = tree.nodes.slice(-data.settings.lastMerges)
    .map(node => inconsistency(tree, node.id, data.settings.inconsistencyDepth));
  const heightCuts = data.settings.heights.map(height => ({ height,
    result: evaluatePartition(data, cutTree(tree, node => node.maximum <= height)) }));
  const numberCuts = data.settings.cuts.map(k => ({ k, result: evaluatePartition(data, cutNumber(tree, k)) }));
  return { name, index, tree, copheneticValues, cophenetic: correlation(pairValues(data.matrix), copheneticValues),
    heights, inversions, gaps, suggested: suggested.k, leafPath, late, kinds, inconsistencies, heightCuts, numberCuts,
    labelCut: evaluatePartition(data, cutNumber(tree, data.classes.length)) };
}

function spanningTreeChecks(data, summary, methods) {
  const single = methods.find(method => method.name === 'single');
  if (single === undefined) return null;
  const edges = minimumSpanningTree(data.matrix);
  const sorted = edges.slice().sort((a, b) => a.weight - b.weight || a.number - b.number);
  const heightMatch = sorted.every((edge, index) => Math.abs(edge.weight - single.heights[index]) <= 0.000000001);
  const key = (a, b) => `${Math.min(a, b)},${Math.max(a, b)}`;
  const edgeSet = new Set(edges.map(edge => key(edge.a, edge.b)));
  const neighborEdges = data.all.filter(observation => edgeSet.has(key(observation, summary.neighbors[observation]))).length;
  const partitions = single.numberCuts.map(cut => {
    const parents = data.all.slice();
    function find(observation) {
      while (parents[observation] !== observation) {
        parents[observation] = parents[parents[observation]];
        observation = parents[observation];
      }
      return observation;
    }
    for (const edge of sorted.slice(0, data.count - cut.k)) parents[find(edge.b)] = find(edge.a);
    const matches = data.pairs.every(([a, b]) => (find(a) === find(b)) === (cut.result.partition[a] === cut.result.partition[b]));
    return { k: cut.k, matches };
  });
  return { total: sum(edges, edge => edge.weight), heightMatch, neighborEdges, partitions };
}

function compareDistanceTypes(data) {
  return DISTANCE_TYPES.map(name => {
    const matrix = distanceMatrix(data.vectors, name);
    const tree = buildTree(matrix, data.settings.compare);
    const result = evaluatePartition(data, cutNumber(tree, data.classes.length), matrix);
    return { name, cophenetic: correlation(pairValues(matrix), pairValues(tree.cophenetic)),
      silhouette: result.silhouette, ari: result.ari };
  });
}

function compareLinkages(data, methods) {
  const cophenetic = methods.map(first => methods.map(second => correlation(first.copheneticValues, second.copheneticValues)));
  const agreement = methods.map(first => methods.map(second => adjustedRand(first.labelCut.partition, second.labelCut.partition)));
  const ranking = methods.slice().sort((a, b) => rounded(b.cophenetic) - rounded(a.cophenetic) || a.index - b.index);
  const bestARI = data.settings.cuts.map(k => {
    let best = null;
    for (const method of methods) {
      const result = method.numberCuts.find(cut => cut.k === k).result;
      if (best === null || compareFractions(result.ari, best.result.ari) > 0) best = { method, k, result };
    }
    return best;
  });
  const bestSilhouette = methods.map(method => {
    let best = method.numberCuts[0];
    for (const cut of method.numberCuts) if (rounded(cut.result.silhouette) > rounded(best.result.silhouette)) best = cut;
    return { method, ...best };
  });
  let selected = null;
  for (const method of methods) {
    for (const cut of method.numberCuts) {
      if (selected === null || compareFractions(cut.result.ari, selected.result.ari) > 0) selected = { method, ...cut };
    }
  }
  return { cophenetic, agreement, ranking, bestARI, bestSilhouette, selected };
}

function describeClusters(data, selected) {
  const result = selected.result;
  return result.groups.map((members, cluster) => {
    const counts = result.table[cluster];
    const majorityCount = Math.max(...counts);
    const majority = counts.indexOf(majorityCount);
    let medoid = members[0];
    let medoidSum = null;
    for (const candidate of members) {
      const value = sum(members, other => data.matrix[candidate][other]);
      if (medoidSum === null || value < medoidSum) {
        medoid = candidate;
        medoidSum = value;
      }
    }
    let diameter = 0;
    let diameterPair = null;
    for (const [first, second] of data.pairs) {
      if (result.partition[first] !== cluster || result.partition[second] !== cluster) continue;
      if (diameterPair === null || data.matrix[first][second] > diameter) {
        diameter = data.matrix[first][second];
        diameterPair = [first, second];
      }
    }
    let nearest = null;
    let separation = null;
    result.groups.forEach((others, otherCluster) => {
      if (otherCluster === cluster) return;
      let distance = null;
      for (const member of members) {
        for (const other of others) if (distance === null || data.matrix[member][other] < distance) distance = data.matrix[member][other];
      }
      if (nearest === null || distance < separation) {
        nearest = otherCluster;
        separation = distance;
      }
    });
    const profile = data.features.map((_, feature) =>
      sum(members, member => (data.original[member][feature] - data.means[feature]) / data.deviations[feature]) / members.length);
    return { members, majority, majorityCount, medoid, diameter, diameterPair, nearest, separation, profile,
      mean: centroid(data.original, members), silhouette: sum(members, member => result.values[member]) / members.length };
  });
}

function featureRatios(data, selected) {
  const result = selected.result;
  return data.features.map((name, feature) => {
    let between = 0;
    for (let cluster = 0; cluster < result.groups.length; cluster += 1) {
      const difference = result.centers[cluster][feature] - result.overall[feature];
      between += result.sizes[cluster] * difference * difference;
    }
    const within = sum(data.all, observation => {
      const difference = data.vectors[observation][feature] - result.centers[result.partition[observation]][feature];
      return difference * difference;
    });
    return { name, feature, value: (between / (selected.k - 1)) / (within / (data.count - selected.k)) };
  }).sort((a, b) => rounded(b.value) - rounded(a.value) || a.feature - b.feature);
}

function withoutFeatures(data, selected) {
  return data.features.map((name, feature) => {
    const vectors = data.vectors.map(vector => vector.filter((_, index) => index !== feature));
    const tree = buildTree(distanceMatrix(vectors, data.settings.distance), selected.method.name);
    const partition = cutNumber(tree, selected.k);
    return { name, selectedARI: adjustedRand(partition, selected.result.partition), labelARI: adjustedRand(partition, data.classOf) };
  });
}

function refinePartition(data, selected) {
  let partition = selected.result.partition.slice();
  let centers = selected.result.centers.map(center => center.slice());
  let iterations = 0;
  for (let iteration = 1; iteration <= data.settings.refineIterations; iteration += 1) {
    const next = data.vectors.map(vector => {
      let nearest = 0;
      let distance = squaredDistance(vector, centers[0]);
      for (let cluster = 1; cluster < centers.length; cluster += 1) {
        const value = squaredDistance(vector, centers[cluster]);
        if (value < distance) {
          nearest = cluster;
          distance = value;
        }
      }
      return nearest;
    });
    iterations = iteration;
    const unchanged = next.every((cluster, observation) => cluster === partition[observation]);
    partition = next;
    if (unchanged) break;
    centers = groupsOf(partition, selected.k).map((members, cluster) =>
      members.length === 0 ? centers[cluster] : centroid(data.vectors, members));
  }
  return { iterations, changed: data.all.filter(observation => partition[observation] !== selected.result.partition[observation]).length,
    result: evaluatePartition(data, partition), selectedARI: adjustedRand(partition, selected.result.partition) };
}

function subsampleStability(data, selected) {
  const size = Math.floor(data.count * data.settings.percent / 100);
  const replicates = [];
  let state = data.settings.seed;
  for (let replicate = 1; replicate <= data.settings.replicates; replicate += 1) {
    const shuffled = data.all.slice();
    for (let position = 0; position < size; position += 1) {
      state = (48271 * state) % 2147483647;
      const other = position + state % (data.count - position);
      [shuffled[position], shuffled[other]] = [shuffled[other], shuffled[position]];
    }
    const sample = shuffled.slice(0, size).sort((a, b) => a - b);
    const matrix = sample.map(first => sample.map(second => data.matrix[first][second]));
    const tree = buildTree(matrix, selected.method.name);
    const partition = cutNumber(tree, selected.k);
    const restricted = sample.map(observation => selected.result.partition[observation]);
    const groups = groupsOf(partition);
    const jaccard = selected.result.groups.map((_, cluster) => {
      const intersectionSize = restricted.filter(value => value === cluster).length;
      if (intersectionSize === 0) return 0;
      let best = [0, 1];
      for (const members of groups) {
        const common = members.filter(member => restricted[member] === cluster).length;
        const ratio = [common, intersectionSize + members.length - common];
        if (compareFractions(ratio, best) > 0) best = ratio;
      }
      return best[0] / best[1];
    });
    replicates.push({ replicate, size, ari: adjustedRand(partition, restricted), jaccard });
  }
  const meanARI = sum(replicates, replicate => replicate.ari[0] / replicate.ari[1]) / replicates.length;
  const meanJaccard = selected.result.groups.map((_, cluster) =>
    sum(replicates, replicate => replicate.jaccard[cluster]) / replicates.length);
  return { replicates, meanARI, meanJaccard };
}

function selectedAnalysis(data, selected) {
  const clusters = describeClusters(data, selected);
  const centroidDistances = selected.result.centers.map(first =>
    selected.result.centers.map(second => Math.sqrt(squaredDistance(first, second))));
  const misplaced = data.all.filter(observation => data.classOf[observation] !== clusters[selected.result.partition[observation]].majority);
  const weakest = data.all.slice().sort((a, b) => selected.result.values[a] - selected.result.values[b] || a - b).slice(0, data.settings.listSize);
  const classCounts = members => {
    const counts = data.classes.map(() => 0);
    for (const member of members) counts[data.classOf[member]] += 1;
    return counts;
  };
  const topMerges = selected.method.tree.nodes.slice(-data.settings.lastMerges).map(node => ({ node,
    a: selected.method.tree.nodes[node.a], b: selected.method.tree.nodes[node.b],
    aCounts: classCounts(selected.method.tree.nodes[node.a].members), bCounts: classCounts(selected.method.tree.nodes[node.b].members) }));
  return { clusters, centroidDistances, misplaced, weakest, topMerges, features: featureRatios(data, selected),
    dropped: withoutFeatures(data, selected), refinement: refinePartition(data, selected), stability: subsampleStability(data, selected) };
}

function evaluationText(result) {
  return `sizes ${result.sizes.join(' ')} silhouette ${real(result.silhouette)} dunn ${real(result.dunn)} `
    + `wss ${real(result.wss)} ch ${real(result.ch)} ari ${ariText(result.ari)}`;
}

function joinSections(sections) {
  return sections.flatMap((section, index) => index === 0 ? section : ['', ...section]);
}

function linkageReport(methods) {
  const lines = ['method,step,a,b,height,size'];
  for (const method of methods) {
    method.tree.merges.forEach((merge, index) => lines.push([method.name, index + 1, merge.a, merge.b, real(merge.height), merge.size].join(',')));
  }
  return lines;
}

function clustersReport(data, methods) {
  const columns = [];
  for (const method of methods) {
    method.heightCuts.forEach((cut, index) => columns.push({ name: `${method.name}_h${index + 1}`, partition: cut.result.partition }));
    for (const cut of method.numberCuts) columns.push({ name: `${method.name}_k${cut.k}`, partition: cut.result.partition });
  }
  const lines = [['id', 'label', ...columns.map(column => column.name)].join(',')];
  data.observations.forEach((observation, index) => {
    lines.push([observation.id, observation.label, ...columns.map(column => column.partition[index] + 1)].join(','));
  });
  return lines;
}

function dendrogramReport(data, methods) {
  return joinSections(methods.map(method => {
    const drawing = drawDendrogram(data.observations, method.tree, data.settings.width, data.settings.heights);
    const lines = [`dendrogram ${method.name} height_max ${real(drawing.maximum)} width ${data.settings.width}`,
      ...drawing.rows, drawing.scale];
    data.settings.heights.forEach((height, index) => {
      lines.push(`cut ${real(height)} column ${drawing.cuts[index] > data.settings.width ? '-' : drawing.cuts[index]}`);
    });
    return lines;
  }));
}

function treesReport(data, methods) {
  return methods.map(method => {
    const strings = data.observations.map(observation => observation.id);
    for (const node of method.tree.nodes.slice(data.count)) {
      const upper = method.tree.nodes[node.upper];
      const lower = method.tree.nodes[node.lower];
      strings[node.id] = `(${strings[upper.id]}:${real(node.height - upper.height)},${strings[lower.id]}:${real(node.height - lower.height)})`;
    }
    return `${method.name} ${strings.at(-1)};`;
  });
}

function dataSummaryLines(data, summary) {
  const lines = [`data n ${data.count} features ${data.features.length} classes ${data.classes.length} `
    + `distance ${data.settings.distance} standardize ${data.settings.standardize}`];
  data.features.forEach((name, feature) => lines.push(`feature ${name} mean ${real(data.means[feature])} sd ${real(data.deviations[feature])}`));
  const [minA, minB] = summary.minimum;
  const [maxA, maxB] = summary.maximum;
  lines.push(`distances pairs ${data.pairs.length} min ${real(data.matrix[minA][minB])} ${data.observations[minA].id} ${data.observations[minB].id} `
    + `max ${real(summary.maximumDistance)} ${data.observations[maxA].id} ${data.observations[maxB].id} mean ${real(summary.mean)}`,
    `nearest_neighbors mean ${real(summary.neighborMean)} reciprocal_pairs ${summary.reciprocal}`,
    `labels ${evaluationText(summary.labelEvaluation)}`);
  return lines;
}

function linkageAnalysisLines(data, method) {
  const lines = [`linkage ${method.name}`, `cophenetic ${real(method.cophenetic)} leaf_path ${real(method.leafPath)}`,
    `heights min ${real(Math.min(...method.heights))} max ${real(Math.max(...method.heights))} inversions ${method.inversions.length}`];
  for (const inversion of method.inversions) lines.push(`inversion step ${inversion.step} height ${real(inversion.height)} previous ${real(inversion.previous)}`);
  lines.push(`gaps ${method.gaps.map(gap => real(gap.value)).join(' ')}`, `suggested_k ${method.suggested}`,
    `late_joiners ${method.late.map(observation => `${data.observations[observation].id}:${real(method.tree.joining[observation])}`).join(' ')}`,
    `merges leaf_leaf ${method.kinds[0]} leaf_cluster ${method.kinds[1]} cluster_cluster ${method.kinds[2]} depth ${method.tree.nodes.at(-1).depth}`,
    `label_cut k ${data.classes.length} purity ${method.labelCut.matchCount}/${data.count} ${real(method.labelCut.purity)}`,
    `inconsistency depth ${data.settings.inconsistencyDepth}`);
  for (const item of method.inconsistencies) {
    lines.push(`step ${item.step} height ${real(item.height)} mean ${real(item.mean)} sd ${real(item.sd)} count ${item.count} coefficient ${real(item.coefficient)}`);
  }
  for (const cut of method.heightCuts) lines.push(`cut height ${real(cut.height)} clusters ${cut.result.groups.length} ${evaluationText(cut.result)}`);
  for (const cut of method.numberCuts) lines.push(`cut k ${cut.k} ${evaluationText(cut.result)}`);
  return lines;
}

function validationReport(data, state) {
  const summary = state.summary;
  const featureCorrelations = [`correlation ${data.features.join(' ')}`];
  data.features.forEach((name, index) => featureCorrelations.push(`${name} ${summary.correlations[index].map(value => real(value)).join(' ')}`));
  const histogram = ['histogram'];
  const maximumCount = Math.max(...summary.histogram);
  summary.histogram.forEach((count, bin) => {
    const length = Math.floor(count * 50 / maximumCount);
    const line = `${real(bin * summary.maximumDistance / 10)} ${real((bin + 1) * summary.maximumDistance / 10)} ${count}`;
    histogram.push(line + (length === 0 ? '' : ' ' + '#'.repeat(length)));
  });
  const sections = [dataSummaryLines(data, summary), featureCorrelations, histogram];
  for (const method of state.methods) sections.push(linkageAnalysisLines(data, method));
  if (state.mst !== null) {
    const mst = state.mst;
    const lines = [`mst total ${real(mst.total)} heights ${mst.heightMatch ? 'match' : 'mismatch'} nn_edges ${mst.neighborEdges}/${data.count}`];
    for (const partition of mst.partitions) lines.push(`mst partition k ${partition.k} ${partition.matches ? 'match' : 'mismatch'}`);
    sections.push(lines);
  }
  const metrics = [`compare linkage ${data.settings.compare} k ${data.classes.length}`];
  for (const metric of state.metrics) metrics.push(`metric ${metric.name} cophenetic ${real(metric.cophenetic)} silhouette ${real(metric.silhouette)} ari ${ariText(metric.ari)}`);
  sections.push(metrics);
  const names = state.methods.map(method => method.name).join(' ');
  const cophenetic = ['cophenetic_matrix', `linkage ${names}`];
  const agreement = [`agreement k ${data.classes.length}`, `linkage ${names}`];
  state.methods.forEach((method, index) => {
    cophenetic.push(`${method.name} ${state.comparison.cophenetic[index].map(value => real(value)).join(' ')}`);
    agreement.push(`${method.name} ${state.comparison.agreement[index].map(value => real(value[0] / value[1])).join(' ')}`);
  });
  const selection = ['summary', `cophenetic_ranking ${state.comparison.ranking.map(method => method.name).join(' ')}`];
  for (const best of state.comparison.bestARI) selection.push(`best_ari k ${best.k} ${best.method.name} ${ariText(best.result.ari)}`);
  for (const best of state.comparison.bestSilhouette) selection.push(`best_silhouette ${best.method.name} k ${best.k} ${real(best.result.silhouette)}`);
  selection.push(`selected ${state.comparison.selected.method.name} k ${state.comparison.selected.k}`);
  sections.push(cophenetic, agreement, selection);
  return joinSections(sections);
}

function clusterDetailLines(data, selected, analysis) {
  const lines = [`selected linkage ${selected.method.name} k ${selected.k} ari ${ariText(selected.result.ari)} silhouette ${real(selected.result.silhouette)}`];
  analysis.clusters.forEach((cluster, index) => {
    const pair = cluster.diameterPair === null ? '- -' : cluster.diameterPair.map(observation => data.observations[observation].id).join(' ');
    lines.push(`cluster ${index + 1} size ${cluster.members.length} silhouette ${real(cluster.silhouette)} majority ${data.classes[cluster.majority]} `
      + `purity ${cluster.majorityCount}/${cluster.members.length} ${real(cluster.majorityCount / cluster.members.length)}`,
      `  mean ${cluster.mean.map(value => real(value)).join(' ')}`,
      `  medoid ${data.observations[cluster.medoid].id} diameter ${real(cluster.diameter)} ${pair} nearest ${cluster.nearest + 1} separation ${real(cluster.separation)}`);
  });
  return lines;
}

function profileBars(data, analysis) {
  const lines = ['profile_bars'];
  const width = Math.max(...data.features.map(name => name.length));
  analysis.clusters.forEach((cluster, index) => {
    lines.push(`cluster ${index + 1}`);
    data.features.forEach((name, feature) => {
      const value = cluster.profile[feature];
      const length = Math.min(10, Math.floor(Math.abs(value) * 4));
      const left = value < 0 ? ' '.repeat(10 - length) + '#'.repeat(length) : ' '.repeat(10);
      const right = value < 0 ? ' '.repeat(10) : '#'.repeat(length) + ' '.repeat(10 - length);
      lines.push(`${name.padEnd(width)} ${left}|${right} ${real(value)}`);
    });
  });
  return lines;
}

function contingencyLines(data, selected) {
  const lines = ['contingency', `cluster ${data.classes.join(' ')} total`];
  selected.result.table.forEach((row, cluster) => lines.push(`${cluster + 1} ${row.join(' ')} ${sum(row)}`));
  const totals = data.classes.map((_, column) => sum(selected.result.table, row => row[column]));
  lines.push(`total ${totals.join(' ')} ${data.count}`, `purity ${selected.result.matchCount}/${data.count} ${real(selected.result.purity)}`);
  return lines;
}

function refinementLines(data, selected, refinement) {
  return [`refinement max_iterations ${data.settings.refineIterations}`,
    `iterations ${refinement.iterations} changed ${refinement.changed} wss ${real(selected.result.wss)} -> ${real(refinement.result.wss)}`,
    `sizes ${refinement.result.sizes.join(' ')} silhouette ${real(refinement.result.silhouette)}`,
    `ari_selected ${ariText(refinement.selectedARI)} ari_labels ${ariText(refinement.result.ari)}`];
}

function stabilityLines(data, stability) {
  const lines = [`stability replicates ${data.settings.replicates} percent ${data.settings.percent} seed ${data.settings.seed}`];
  for (const replicate of stability.replicates) {
    lines.push(`replicate ${replicate.replicate} size ${replicate.size} ari ${ariText(replicate.ari)} jaccard ${replicate.jaccard.map(value => real(value)).join(' ')}`);
  }
  lines.push(`mean_ari ${real(stability.meanARI)}`, `mean_jaccard ${stability.meanJaccard.map(value => real(value)).join(' ')}`);
  return lines;
}

function distanceMapLines(data, selected, maximum) {
  const border = '+' + '-'.repeat(data.count) + '+';
  const lines = [`distance_map ${selected.method.name}`, border];
  for (const first of selected.method.tree.order) {
    const cells = selected.method.tree.order.map(second => SHADES[Math.min(9, Math.floor(10 * data.matrix[first][second] / maximum))]);
    lines.push('|' + cells.join('') + '|');
  }
  lines.push(border);
  return lines;
}

function profilesReport(data, state) {
  const selected = state.comparison.selected;
  const analysis = state.selected;
  const centroids = ['centroid_distances'];
  analysis.centroidDistances.forEach((row, cluster) => centroids.push(`${cluster + 1} ${row.map(value => real(value)).join(' ')}`));
  const misplaced = ['misplaced'];
  for (const observation of analysis.misplaced) {
    const cluster = selected.result.partition[observation];
    misplaced.push(`${data.observations[observation].id} label ${data.observations[observation].label} cluster ${cluster + 1} majority ${data.classes[analysis.clusters[cluster].majority]}`);
  }
  misplaced.push(`count ${analysis.misplaced.length}`);
  const weakest = ['weakest'];
  for (const observation of analysis.weakest) {
    weakest.push(`${data.observations[observation].id} label ${data.observations[observation].label} cluster ${selected.result.partition[observation] + 1} silhouette ${real(selected.result.values[observation])}`);
  }
  const features = ['features'];
  analysis.features.forEach((feature, index) => features.push(`${index + 1} ${feature.name} f_ratio ${real(feature.value)}`));
  const merges = ['top_merges'];
  for (const merge of analysis.topMerges) {
    merges.push(`step ${merge.node.id - data.count + 1} height ${real(merge.node.height)} a ${merge.a.id} ${merge.a.size} ${merge.aCounts.join('/')} `
      + `b ${merge.b.id} ${merge.b.size} ${merge.bCounts.join('/')}`);
  }
  const dropped = ['drop_feature'];
  for (const feature of analysis.dropped) dropped.push(`${feature.name} ari_selected ${ariText(feature.selectedARI)} ari_labels ${ariText(feature.labelARI)}`);
  return joinSections([clusterDetailLines(data, selected, analysis), centroids, profileBars(data, analysis),
    contingencyLines(data, selected), misplaced, weakest, features, merges, dropped,
    refinementLines(data, selected, analysis.refinement), stabilityLines(data, analysis.stability),
    distanceMapLines(data, selected, state.summary.maximumDistance)]);
}

function main() {
  const data = prepareData();
  const summary = summarizeData(data);
  const methods = data.settings.linkages.map((name, index) => analyzeLinkage(data, name, index));
  const comparison = compareLinkages(data, methods);
  const state = { summary, methods, comparison, mst: spanningTreeChecks(data, summary, methods),
    metrics: compareDistanceTypes(data), selected: selectedAnalysis(data, comparison.selected) };
  writeReports({
    'linkage.csv': linkageReport(methods),
    'clusters.csv': clustersReport(data, methods),
    'dendrogram.txt': dendrogramReport(data, methods),
    'trees.txt': treesReport(data, methods),
    'validation.txt': validationReport(data, state),
    'profiles.txt': profilesReport(data, state),
  });
}

if (require.main === module) main();
