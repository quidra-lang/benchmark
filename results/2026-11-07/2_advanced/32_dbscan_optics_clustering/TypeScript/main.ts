import { readDataset, type Point } from './dataset.ts';
import { dbscan, type Clustering } from './dbscan.ts';
import { distance, gridIndex } from './grid_index.ts';
import { optics } from './optics.ts';
import { ariValue, fraction, frame, gcd, root, writeReport } from './report.ts';

const { points, params } = readDataset();
const n = points.length;
const m = params.minPts;
const k = m - 1;
const indices = points.map((_, i) => i);
const neighborDistances = points.map((p, i) =>
  points
    .filter((_, j) => j !== i)
    .map((q) => distance(p, q))
    .sort((a, b) => a - b)
    .slice(0, 2 * m),
);
interface Curve {
  order: number[];
  values: number[];
  knee: number;
  cross: number;
  eps: number;
}
function curve(j: number): Curve {
  const order = [...indices].sort(
    (a, b) =>
      neighborDistances[b][j - 1] - neighborDistances[a][j - 1] || points[a].id - points[b].id,
  );
  const values = order.map((p) => neighborDistances[p][j - 1]);
  let knee = 0;
  let cross = -1;
  values.forEach((value, r) => {
    const c = Math.abs((n - 1) * (value - values[0]) - (values[n - 1] - values[0]) * r);
    if (c > cross) {
      knee = r;
      cross = c;
    }
  });
  let eps = 1;
  while (eps * eps < values[knee]) eps++;
  return { order, values, knee, cross, eps };
}
const kneeTable = Array.from({ length: 2 * m }, (_, j) => curve(j + 1));
const kdCurve = kneeTable[k - 1];
const suggested = kdCurve.eps;
const kd = neighborDistances.map((row) => row[k - 1]);
const radii = [...new Set([...params.eps, suggested, params.maxEps])].sort((a, b) => a - b);
const grids = new Map(radii.map((e) => [e, gridIndex(points, e)]));
function grid(e: number) {
  const result = grids.get(e);
  if (!result) throw new Error('Missing grid');
  return result;
}
interface Setting extends Clustering {
  name: string;
  radius: number;
  db: boolean;
  members: number[][];
  noise: number;
}
function setting(name: string, radius: number, clustering: Clustering, db = false): Setting {
  const members = Array.from({ length: Math.max(...clustering.labels) + 1 }, (): number[] => []);
  clustering.labels.forEach((label, p) => {
    if (label >= 0) members[label].push(p);
  });
  return {
    name,
    radius,
    ...clustering,
    db,
    members,
    noise: clustering.labels.filter((label) => label < 0).length,
  };
}
const dbSettings = [
  ...params.eps.map((e) => setting(`db${e}`, e, dbscan(grid(e).neighborhoods, m), true)),
  setting(`knee${suggested}`, suggested, dbscan(grid(suggested).neighborhoods, m), true),
];
const kneeSetting = dbSettings[dbSettings.length - 1];
const ordering = optics(points, grid(params.maxEps).neighborhoods, m);
function extract(eps: number): Clustering {
  const labels = Array<number>(n).fill(-1);
  const core = ordering.core.map((value) => value <= eps * eps);
  let label = -1;
  for (const p of ordering.order) {
    if (ordering.reach[p] > eps * eps) {
      if (core[p]) labels[p] = ++label;
    } else labels[p] = label;
  }
  return { labels, core };
}
const extractionSettings = params.extract.map((e) => setting(`op${e}`, e, extract(e)));
const reach = [...ordering.order.map((p) => ordering.reach[p]), Infinity];
const [u, v] = params.xi;
const alpha = (v - u) ** 2;
const beta = v * v;
const xle = (a: number, b: number) => b === Infinity || (a !== Infinity && beta * a <= alpha * b);
const steepUp = indices.map(
  (i) => !(reach[i] === Infinity && reach[i + 1] === Infinity) && xle(reach[i], reach[i + 1]),
);
const steepDown = indices.map(
  (i) => !(reach[i] === Infinity && reach[i + 1] === Infinity) && xle(reach[i + 1], reach[i]),
);
const up = indices.map((i) => steepUp[i] || reach[i] < reach[i + 1]);
const down = indices.map((i) => steepDown[i] || reach[i] > reach[i + 1]);
function extend(start: number, descending: boolean): number {
  let end = start;
  let count = 0;
  for (let i = start; i < n; i++) {
    if ((descending ? steepDown : steepUp)[i]) {
      end = i;
      count = 0;
    } else if ((descending ? up : down)[i]) break;
    else if (++count > m) break;
  }
  return end;
}
interface DownArea {
  start: number;
  end: number;
  maximum: number;
}
interface XiCluster {
  start: number;
  end: number;
  label?: number;
  parent?: number;
}
const xiClusters: XiCluster[] = [];
const steepAreas: { kind: string; start: number; end: number }[] = [];
let downAreas: DownArea[] = [];
let scanIndex = 0;
let mib = 0;
for (let s = 0; s < n; s++) {
  if (s < scanIndex || (!steepUp[s] && !steepDown[s])) continue;
  for (let i = scanIndex; i <= s; i++) mib = Math.max(mib, reach[i]);
  if (mib === Infinity) downAreas = [];
  else {
    downAreas = downAreas.filter((area) => xle(mib, reach[area.start]));
    for (const area of downAreas) area.maximum = Math.max(area.maximum, mib);
  }
  if (steepDown[s]) {
    const end = extend(s, true);
    downAreas.push({ start: s, end, maximum: 0 });
    steepAreas.push({ kind: 'down', start: s, end });
    scanIndex = end + 1;
    mib = reach[scanIndex];
  } else {
    const end = extend(s, false);
    const candidates: XiCluster[] = [];
    steepAreas.push({ kind: 'up', start: s, end });
    scanIndex = end + 1;
    mib = reach[scanIndex];
    for (const area of downAreas) {
      let cs = area.start;
      let ce = end;
      if (!xle(area.maximum, reach[ce + 1])) continue;
      const wall = reach[area.start];
      if (xle(reach[ce + 1], wall)) {
        while (cs < area.end && reach[cs + 1] > reach[ce + 1]) cs++;
      } else if (xle(wall, reach[ce + 1])) {
        while (ce > s && reach[ce - 1] > wall) ce--;
      }
      if (ce - cs + 1 >= params.minSize && cs <= area.end && ce >= s) {
        candidates.push({ start: cs, end: ce });
      }
    }
    xiClusters.push(...candidates.reverse());
  }
}
const xiLabels = Array<number>(n).fill(-1);
let nextLabel = 0;
xiClusters.forEach((cluster, j) => {
  if (ordering.order.slice(cluster.start, cluster.end + 1).every((p) => xiLabels[p] === -1)) {
    cluster.label = nextLabel++;
    for (let i = cluster.start; i <= cluster.end; i++) xiLabels[ordering.order[i]] = cluster.label;
  }
  let parent: number | undefined;
  xiClusters.forEach((candidate, i) => {
    const size = candidate.end - candidate.start;
    const childSize = cluster.end - cluster.start;
    if (
      i === j ||
      candidate.start > cluster.start ||
      candidate.end < cluster.end ||
      (size === childSize && i <= j)
    ) {
      return;
    }
    if (parent === undefined || size < xiClusters[parent].end - xiClusters[parent].start) {
      parent = i;
    }
  });
  cluster.parent = parent;
});
const xiSetting = setting('xi', params.maxEps, {
  labels: xiLabels,
  core: ordering.core.map((value) => value !== Infinity),
});
const settings = [...dbSettings, ...extractionSettings, xiSetting];
const character = (label: number) =>
  label < 0
    ? '.'
    : label < 26
      ? String.fromCharCode(65 + label)
      : label < 52
        ? String.fromCharCode(97 + label - 26)
        : '#';
const sum = (values: number[]) => values.reduce((a, b) => a + b, 0);
const ok = (condition: boolean) => (condition ? 'ok' : 'fail');
function hull(members: number[]): Point[] {
  const sorted = members.map((p) => points[p]).sort((a, b) => a.x - b.x || a.y - b.y);
  if (sorted.length <= 2) return sorted;
  const turn = (o: Point, a: Point, b: Point) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  const chain = (sequence: Point[]) => {
    const result: Point[] = [];
    for (const p of sequence) {
      while (
        result.length >= 2 &&
        turn(result[result.length - 2], result[result.length - 1], p) <= 0
      ) {
        result.pop();
      }
      result.push(p);
    }
    return result.slice(0, -1);
  };
  return [...chain(sorted), ...chain([...sorted].reverse())];
}
function settingLines(s: Setting): string[] {
  const coreCount = indices.filter((p) => s.labels[p] >= 0 && s.core[p]).length;
  const lines = [
    `setting ${s.name} eps ${s.radius} clusters ${s.members.length} noise ${s.noise} core ${coreCount} border ${n - s.noise - coreCount}`,
  ];
  s.members.forEach((members, label) => {
    const size = members.length;
    const sx = sum(members.map((p) => points[p].x));
    const sy = sum(members.map((p) => points[p].y));
    let medoid = members[0];
    let best = Infinity;
    for (const p of members) {
      const d = (size * points[p].x - sx) ** 2 + (size * points[p].y - sy) ** 2;
      if (d < best) {
        best = d;
        medoid = p;
      }
    }
    const xs = members.map((p) => points[p].x);
    const ys = members.map((p) => points[p].y);
    const xmin = Math.min(...xs);
    const xmax = Math.max(...xs);
    const ymin = Math.min(...ys);
    const ymax = Math.max(...ys);
    const area = (xmax - xmin + 1) * (ymax - ymin + 1);
    const vertices = hull(members);
    let twiceArea = 0;
    let diameter = 0;
    vertices.forEach((p, i) => {
      const q = vertices[(i + 1) % vertices.length];
      twiceArea += p.x * q.y - q.x * p.y;
      for (const q of vertices) diameter = Math.max(diameter, distance(p, q));
    });
    twiceArea = Math.abs(twiceArea);
    const core = members.filter((p) => s.core[p]).length;
    lines.push(
      `cluster ${label} ${character(label)} size ${size} core ${core} border ${size - core} centroid ${fraction(sx, size)} ${fraction(sy, size)} medoid ${points[medoid].id}`,
      `  bbox ${xmin} ${ymin} ${xmax} ${ymax} area ${area} density ${fraction(size, area)}`,
      `  hull ${vertices.length} hull_area ${Math.floor(twiceArea / 2)}.${twiceArea % 2 ? 5 : 0} diameter_sq ${diameter} diameter ${root(diameter)}`,
    );
  });
  if (s.db) {
    const neighbors = grid(s.radius).neighborhoods;
    const a = indices.every(
      (p) => !s.core[p] || neighbors[p].every((q) => !s.core[q] || s.labels[p] === s.labels[q]),
    );
    const b = indices.every(
      (p) =>
        s.labels[p] < 0 ||
        s.core[p] ||
        neighbors[p].some((q) => s.core[q] && s.labels[q] === s.labels[p]),
    );
    const c = indices.every((p) => s.labels[p] >= 0 || neighbors[p].every((q) => !s.core[q]));
    const ambiguous = indices
      .filter((p) => s.labels[p] >= 0 && !s.core[p])
      .map((p) => ({
        p,
        other: [
          ...new Set(
            neighbors[p]
              .filter((q) => s.core[q] && s.labels[q] !== s.labels[p])
              .map((q) => s.labels[q]),
          ),
        ].sort((a, b) => a - b),
      }))
      .filter((entry) => entry.other.length);
    lines.push(
      `check ${ok(a)} ${ok(b)} ${ok(c)}`,
      `isolated ${indices.filter((p) => s.labels[p] < 0 && neighbors[p].length === 1).length}`,
      `ambiguous ${ambiguous.length}`,
      ...ambiguous.map(
        ({ p, other }) => `  ${points[p].id} cluster ${s.labels[p]} also ${other.join(' ')}`,
      ),
    );
  }
  return lines;
}
const clusterParts: string[][] = [
  [`points ${n} min_pts ${m}`, `settings ${settings.map((s) => s.name).join(' ')}`],
];
const gridLines = ['grid'];
for (const radius of radii) {
  const g = grid(radius);
  const b = g.busiest;
  gridLines.push(
    `eps ${radius} cells ${g.cells} busiest ${b.x} ${b.y} ${b.count} candidates ${g.candidates} pairs ${g.pairs} brute_pairs ${g.brutePairs} ${g.ok ? 'ok' : 'mismatch'}`,
    `  occupancy ${[...g.occupancy]
      .sort((a, b) => a[0] - b[0])
      .map(([c, count]) => `${c}:${count}`)
      .join(' ')}`,
  );
}
clusterParts.push(gridLines, ...settings.map(settingLines));
const hierarchy = ['hierarchy'];
const sortedDb = [...dbSettings].sort((a, b) => a.radius - b.radius);
for (let i = 0; i + 1 < sortedDb.length; i++) {
  const a = sortedDb[i];
  const b = sortedDb[i + 1];
  const destinations = a.members.map((members) => b.labels[members.find((p) => a.core[p])!]);
  hierarchy.push(`${a.name} -> ${b.name}`);
  b.members.forEach((_, label) =>
    hierarchy.push(
      `  ${label} <- ${destinations.flatMap((destination, c) => (destination === label ? [c] : [])).join(' ') || '-'}`,
    ),
  );
}
clusterParts.push(hierarchy);
const comparisons = ['optics_vs_dbscan'];
for (const a of extractionSettings) {
  const b = dbSettings.find((s) => s.radius === a.radius);
  if (!b) continue;
  const pairs = new Map<number, Set<number>>();
  const reverse = new Map<number, Set<number>>();
  for (const p of indices) {
    if (a.core[p]) {
      const x = a.labels[p];
      const y = b.labels[p];
      const left = pairs.get(x) ?? new Set<number>();
      const right = reverse.get(y) ?? new Set<number>();
      left.add(y);
      right.add(x);
      pairs.set(x, left);
      reverse.set(y, right);
    }
  }
  const same =
    a.members.every((_, label) => pairs.get(label)?.size === 1) &&
    b.members.every((_, label) => reverse.get(label)?.size === 1);
  const borderNoise = indices.filter((p) => a.labels[p] < 0 && b.labels[p] >= 0).length;
  const moved = same
    ? indices.filter((p) => a.labels[p] >= 0 && [...pairs.get(a.labels[p])!][0] !== b.labels[p])
        .length
    : '-';
  comparisons.push(
    `${a.name} ${b.name} core_partition ${same ? 'same' : 'different'} border_as_noise ${borderNoise} moved ${moved}`,
  );
}
clusterParts.push(comparisons);
const components: number[] = [];
for (const p of ordering.order) {
  if (ordering.reach[p] === Infinity) components.push(0);
  components[components.length - 1]++;
}
const opticsCoreCount = ordering.core.filter((value) => value !== Infinity).length;
clusterParts.push([
  `optics max_eps ${params.maxEps} core ${opticsCoreCount} components ${components.length} singletons ${components.filter((size) => size === 1).length} largest ${Math.max(...components)}`,
]);
const sweep = ['sweep max_eps ' + params.maxEps, 'eps clusters noise largest'];
const sweepCounts: number[] = [];
for (let eps = 1; eps <= params.maxEps; eps++) {
  const s = setting('', eps, extract(eps));
  sweepCounts.push(s.members.length);
  sweep.push(
    `${eps} ${s.members.length} ${s.noise} ${Math.max(0, ...s.members.map((members) => members.length))}`,
  );
}
let stable: { start: number; end: number; clusters: number } | undefined;
for (let start = 0; start < sweepCounts.length;) {
  let end = start;
  while (end + 1 < sweepCounts.length && sweepCounts[end + 1] === sweepCounts[start]) end++;
  if (sweepCounts[start] >= 2 && (!stable || end - start > stable.end - stable.start)) {
    stable = { start, end, clusters: sweepCounts[start] };
  }
  start = end + 1;
}
sweep.push(
  stable
    ? `stable clusters ${stable.clusters} eps ${stable.start + 1} ${stable.end + 1} length ${stable.end - stable.start + 1}`
    : 'stable -',
);
clusterParts.push(sweep);
const xiLines = [
  `xi ${u}/${v} min_size ${params.minSize} steep_areas ${steepAreas.length}`,
  ...steepAreas.map((area) => `${area.kind} ${area.start + 1} ${area.end + 1}`),
  `xi_clusters ${xiClusters.length}`,
];
xiClusters.forEach((cluster, j) =>
  xiLines.push(
    `${j} start ${cluster.start + 1} end ${cluster.end + 1} size ${cluster.end - cluster.start + 1} label ${cluster.label ?? '-'} parent ${cluster.parent ?? '-'} walls ${root(reach[cluster.start])} ${root(reach[cluster.end + 1])} valley ${root(Math.min(Infinity, ...reach.slice(cluster.start + 1, cluster.end + 1)))}`,
  ),
);
clusterParts.push(xiLines);
const outliers = indices
  .filter((p) => kneeSetting.labels[p] < 0)
  .map((p) => {
    let nearest = -1;
    let minimum = Infinity;
    for (const q of indices) {
      if (kneeSetting.core[q]) {
        const d = distance(points[p], points[q]);
        if (d < minimum) {
          minimum = d;
          nearest = q;
        }
      }
    }
    return { p, nearest, minimum };
  })
  .sort((a, b) => b.minimum - a.minimum || points[a.p].id - points[b.p].id);
clusterParts.push([
  `outliers ${kneeSetting.name} count ${outliers.length}`,
  ...outliers.map(
    ({ p, nearest, minimum }) =>
      `${points[p].id} nearest_core ${points[nearest].id} cluster ${kneeSetting.labels[nearest]} dist_sq ${minimum} dist ${root(minimum)}`,
  ),
]);
const gaps = [`gaps ${kneeSetting.name}`];
for (let a = 0; a < kneeSetting.members.length; a++) {
  for (let b = a + 1; b < kneeSetting.members.length; b++) {
    let minimum = Infinity;
    let pair: [number, number] = [0, 0];
    for (const p of kneeSetting.members[a]) {
      for (const q of kneeSetting.members[b]) {
        const d = distance(points[p], points[q]);
        if (d < minimum) {
          minimum = d;
          pair = [p, q];
        }
      }
    }
    gaps.push(
      `${a} ${b} dist_sq ${minimum} dist ${root(minimum)} between ${points[pair[0]].id} ${points[pair[1]].id}`,
    );
  }
}
clusterParts.push(gaps);
const table = Array.from({ length: kneeSetting.members.length + 1 }, () =>
  Array<number>(xiSetting.members.length + 1).fill(0),
);
for (const p of indices) table[kneeSetting.labels[p] + 1][xiSetting.labels[p] + 1]++;
const contingency = [
  `contingency ${kneeSetting.name} xi`,
  `columns ${Array.from({ length: xiSetting.members.length + 1 }, (_, i) => i - 1).join(' ')}`,
  ...table.map((row, r) => `${r - 1} ${row.join(' ')}`),
];
xiSetting.members.forEach((members, c) => {
  let match = 0;
  for (let r = 1; r < kneeSetting.members.length; r++) {
    if (table[r + 1][c + 1] > table[match + 1][c + 1]) match = r;
  }
  const shared = table[match + 1][c + 1];
  contingency.push(
    `match ${c} ${match} shared ${shared} jaccard ${fraction(shared, kneeSetting.members[match].length + members.length - shared)}`,
  );
});
clusterParts.push(contingency);
const ari = ['ari'];
const choose2 = (value: number) => (value * (value - 1)) / 2;
for (let a = 0; a < settings.length; a++) {
  for (let b = a + 1; b < settings.length; b++) {
    const left = settings[a];
    const right = settings[b];
    const cells = new Map<string, number>();
    const countsA = new Map<number, number>();
    const countsB = new Map<number, number>();
    for (const p of indices) {
      const x = left.labels[p];
      const y = right.labels[p];
      const pair = `${x},${y}`;
      cells.set(pair, (cells.get(pair) ?? 0) + 1);
      countsA.set(x, (countsA.get(x) ?? 0) + 1);
      countsB.set(y, (countsB.get(y) ?? 0) + 1);
    }
    const s = sum([...cells.values()].map(choose2));
    const aa = sum([...countsA.values()].map(choose2));
    const bb = sum([...countsB.values()].map(choose2));
    const z = choose2(n);
    let numerator = 2 * (z * s - aa * bb);
    let denominator = z * (aa + bb) - 2 * aa * bb;
    if (denominator === 0) {
      numerator = 1;
      denominator = 1;
    } else {
      const divisor = gcd(Math.abs(numerator), denominator);
      numerator /= divisor;
      denominator /= divisor;
    }
    ari.push(
      `${left.name} ${right.name} ${numerator}/${denominator} ${ariValue(numerator, denominator)}`,
    );
  }
}
clusterParts.push(ari);
const kdistLines = [
  `k_distance k ${k} points ${n}`,
  'rank id kdist_sq kdist',
  ...kdCurve.order.map(
    (p, r) => `${r + 1} ${points[p].id} ${kdCurve.values[r]} ${root(kdCurve.values[r])}`,
  ),
  '',
  `knee rank ${kdCurve.knee + 1} id ${points[kdCurve.order[kdCurve.knee]].id} kdist_sq ${kdCurve.values[kdCurve.knee]} kdist ${root(kdCurve.values[kdCurve.knee])} cross ${kdCurve.cross}`,
  `suggested_eps ${suggested}`,
  '',
  'knee_table',
  ...kneeTable.map(
    (c, j) =>
      `k ${j + 1} rank ${c.knee + 1} id ${points[c.order[c.knee]].id} kdist_sq ${c.values[c.knee]} eps ${c.eps}`,
  ),
  '',
  'core_check',
];
for (const s of dbSettings) {
  const count = kd.filter((value) => value <= s.radius * s.radius).length;
  const gridCore = s.core.filter(Boolean).length;
  kdistLines.push(
    `eps ${s.radius} core ${count} non_core ${n - count} grid_core ${gridCore} ${count === gridCore ? 'ok' : 'mismatch'}`,
  );
}
kdistLines.push(
  `optics max_eps ${params.maxEps} core ${opticsCoreCount} ${indices.every((p) => ordering.core[p] === Infinity || ordering.core[p] === kd[p]) ? 'ok' : 'mismatch'}`,
);
const xmin = Math.min(...points.map((p) => p.x));
const xmax = Math.max(...points.map((p) => p.x));
const ymin = Math.min(...points.map((p) => p.y));
const ymax = Math.max(...points.map((p) => p.y));
const mapCells = Array.from({ length: params.mapWidth * params.mapHeight }, (): number[] => []);
points.forEach((p, i) => {
  const c = Math.floor(((p.x - xmin) * params.mapWidth) / (xmax - xmin + 1));
  const r = Math.floor(((ymax - p.y) * params.mapHeight) / (ymax - ymin + 1));
  mapCells[r * params.mapWidth + c].push(i);
});
function mapRows(cell: (members: number[]) => string): string[] {
  return Array.from({ length: params.mapHeight }, (_, r) =>
    mapCells
      .slice(r * params.mapWidth, (r + 1) * params.mapWidth)
      .map(cell)
      .join(''),
  );
}
const mapLines: string[] = [];
for (const s of settings) {
  const rows = mapRows((members) => {
    if (!members.length) return ' ';
    const labels = [...new Set(members.map((p) => s.labels[p]).filter((label) => label >= 0))];
    return !labels.length ? '.' : labels.length === 1 ? character(labels[0]) : '*';
  });
  mapLines.push(
    `map ${s.name} clusters ${s.members.length} noise ${s.noise}`,
    ...frame(rows),
    `legend ${s.members.map((members, label) => `${character(label)}=${members.length}`).join(' ') || '-'}`,
    '',
  );
}
mapLines.push(
  `kinds ${kneeSetting.name}`,
  ...frame(
    mapRows((members) =>
      !members.length
        ? ' '
        : members.some((p) => kneeSetting.core[p])
          ? '#'
          : members.some((p) => kneeSetting.labels[p] >= 0)
            ? '+'
            : '.',
    ),
  ),
  '',
);
let kneeColumn = 0;
const heights = Array.from({ length: params.kWidth }, (_, c) => {
  const first = Math.floor((c * n) / params.kWidth);
  const end = Math.floor(((c + 1) * n) / params.kWidth);
  if (first <= kdCurve.knee && kdCurve.knee < end) kneeColumn = c;
  let h = 0;
  while ((h + 1) ** 2 * kdCurve.values[0] <= params.kHeight ** 2 * kdCurve.values[first]) h++;
  return h;
});
const plotRows = Array.from({ length: params.kHeight }, (_, r) =>
  heights.map((h, c) => (params.kHeight - r <= h ? '#' : c === kneeColumn ? ':' : ' ')).join(''),
);
mapLines.push(
  `kdist_plot k ${k} max ${root(kdCurve.values[0])} knee_column ${kneeColumn + 1}`,
  ...frame(plotRows),
  '',
);
const rtop = Math.max(...ordering.reach.filter((value) => value !== Infinity));
const reachSettings = [...extractionSettings, xiSetting];
mapLines.push(
  `reachability width ${params.reachWidth} max_reach ${root(rtop)} columns ${reachSettings.map((s) => s.name).join(' ')}`,
);
ordering.order.forEach((p, i) => {
  let bar: string;
  if (ordering.reach[p] === Infinity) bar = '-'.repeat(params.reachWidth);
  else {
    let b = 0;
    while ((b + 1) ** 2 * rtop <= params.reachWidth ** 2 * ordering.reach[p]) b++;
    bar = '#'.repeat(b);
  }
  mapLines.push(
    `${String(i + 1).padStart(4)} ${String(points[p].id).padStart(5)} ${root(ordering.reach[p]).padStart(7)} ${reachSettings.map((s) => character(s.labels[p])).join('')} |${bar}`,
  );
});
writeReport('labels.csv', [
  `id,${settings.map((s) => s.name).join(',')}`,
  ...points.map((p, i) => `${p.id},${settings.map((s) => s.labels[i]).join(',')}`),
]);
writeReport('optics_order.csv', [
  'order,id,core_sq,reach_sq,reach,predecessor',
  ...ordering.order.map((p, i) => {
    const predecessor = ordering.predecessor[p];
    return `${i + 1},${points[p].id},${ordering.core[p] === Infinity ? '-' : ordering.core[p]},${ordering.reach[p] === Infinity ? '-' : ordering.reach[p]},${root(ordering.reach[p])},${predecessor === undefined ? '-' : points[predecessor].id}`;
  }),
]);
writeReport('kdist.txt', kdistLines);
writeReport(
  'clusters.txt',
  clusterParts.flatMap((part, i) => (i ? ['', ...part] : part)),
);
writeReport('maps.txt', mapLines);
