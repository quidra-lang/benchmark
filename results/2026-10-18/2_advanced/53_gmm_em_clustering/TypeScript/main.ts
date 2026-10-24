import { read, type Point, type Component, type CovarianceType, type Params } from './dataset.ts';
import * as gaussian from './gaussian.ts';
import * as em from './em.ts';
import * as km from './kmeans.ts';
import { real, frame, write } from './report.ts';

function sum(v: number[]): number {
  let total = 0;
  for (const x of v) total += x;
  return total;
}
function reals(v: number[]): string {
  return v.map((x) => real(x)).join(' ');
}
function rounded(v: number): number {
  return +real(v);
}
function maximum(v: number[]): number {
  let k = 0;
  for (let j = 1; j < v.length; j++) if (v[j] > v[k]) k = j;
  return k;
}
function sections(parts: string[][]): string[] {
  return parts.flatMap((p, i) => (i ? ['', ...p] : p));
}
function entropy(v: number[]): number {
  let total = 0;
  for (const r of v) if (r !== 0) total += r * Math.log(r);
  return -total;
}
function parameterCount(k: number, type: CovarianceType): number {
  return type === 'FULL'
    ? 6 * k - 1
    : type === 'TIED'
      ? 3 * k + 2
      : type === 'DIAG'
        ? 5 * k - 1
        : 4 * k - 1;
}
function summarize(fit: ReturnType<typeof em.fit>, type: CovarianceType, tau: number, n: number) {
  const k = fit.components.length;
  const p = parameterCount(k, type);
  const assignment = fit.responsibilities.map(maximum);
  const sizes = fit.components.map((_, j) => assignment.filter((c) => c === j).length);
  const totalEntropy = sum(fit.responsibilities.map(entropy));
  const bic = -2 * fit.loglik + p * Math.log(n);
  const aic = -2 * fit.loglik + 2 * p;
  const settled = fit.trace.findIndex((_, t) =>
    fit.trace.slice(t).every((l) => Math.abs(l - fit.loglik) <= tau),
  );
  let largest = 1;
  const violations: number[] = [];
  for (let t = 1; t < fit.trace.length; t++) {
    if (fit.trace[t] - fit.trace[t - 1] > fit.trace[largest] - fit.trace[largest - 1]) largest = t;
    if (fit.trace[t] < fit.trace[t - 1] - 0.000001 * Math.abs(fit.trace[t - 1])) violations.push(t);
  }
  return {
    ...fit,
    type,
    k,
    p,
    assignment,
    sizes,
    entropy: totalEntropy,
    bic,
    aic,
    icl: bic + 2 * totalEntropy,
    settled,
    largest,
    violations,
  };
}
type Model = ReturnType<typeof summarize>;
function rank(models: Model[], criterion: 'bic' | 'aic' | 'icl', types: CovarianceType[]): Model[] {
  return [...models].sort(
    (a, b) =>
      rounded(a[criterion]) - rounded(b[criterion]) ||
      a.p - b.p ||
      a.k - b.k ||
      types.indexOf(a.type) - types.indexOf(b.type),
  );
}
function contingency(a: number[], b: number[], ka: number, kb: number): number[][] {
  const t: number[][] = Array.from({ length: ka }, () => Array(kb).fill(0));
  a.forEach((c, i) => t[c][b[i]]++);
  return t;
}
type Fraction = readonly [number, number];
function ari(table: number[][]): Fraction {
  const c2 = (m: number) => (m * (m - 1)) / 2;
  const rows = table.map(sum);
  const cols = table[0].map((_, j) => sum(table.map((r) => r[j])));
  const s = sum(table.map((r) => sum(r.map(c2))));
  const a = sum(rows.map(c2));
  const b = sum(cols.map(c2));
  const z = c2(sum(rows));
  let n = 2 * (z * s - a * b);
  let d = z * (a + b) - 2 * a * b;
  if (d === 0) return [1, 1];
  if (d < 0) {
    n = -n;
    d = -d;
  }
  let x = Math.abs(n);
  let y = d;
  while (y) [x, y] = [y, x % y];
  return [n / x, d / x];
}
function fractionText(f: Fraction): string {
  return `${f[0]}/${f[1]} ${real(f[0] / f[1])}`;
}
function partitionMetrics(points: Point[], assignment: number[], k: number) {
  const groups = Array.from({ length: k }, (_, c) =>
    points.map((_, i) => i).filter((i) => assignment[i] === c),
  );
  const nonempty = groups.map((g, i) => i).filter((c) => groups[c].length > 0);
  const centers = groups.map((g) => ({
    x: g.length ? sum(g.map((i) => points[i].x)) / g.length : 0,
    y: g.length ? sum(g.map((i) => points[i].y)) / g.length : 0,
  }));
  const silhouettes: (number | null)[] = points.map(() => null);
  const clusterSilhouettes: (number | null)[] = groups.map(() => null);
  if (nonempty.length < 2) return { silhouette: null, ch: null, db: null, clusterSilhouettes };
  points.forEach((p, i) => {
    const own = groups[assignment[i]];
    if (own.length === 1) {
      silhouettes[i] = 0;
      return;
    }
    const a =
      sum(own.filter((j) => j !== i).map((j) => km.distance(p, points[j]))) / (own.length - 1);
    let b = Infinity;
    for (const c of nonempty) {
      if (c !== assignment[i]) {
        b = Math.min(b, sum(groups[c].map((j) => km.distance(p, points[j]))) / groups[c].length);
      }
    }
    silhouettes[i] = (b - a) / Math.max(a, b);
  });
  for (const c of nonempty) {
    clusterSilhouettes[c] = sum(groups[c].map((i) => silhouettes[i]!)) / groups[c].length;
  }
  const center = {
    x: sum(points.map((p) => p.x)) / points.length,
    y: sum(points.map((p) => p.y)) / points.length,
  };
  let between = 0;
  for (const c of nonempty) between += groups[c].length * km.squaredDistance(centers[c], center);
  const within = sum(points.map((p, i) => km.squaredDistance(p, centers[assignment[i]])));
  const scatter = groups.map((g, c) =>
    g.length ? sum(g.map((i) => km.distance(points[i], centers[c]))) / g.length : 0,
  );
  let ratios = 0;
  for (const c of nonempty) {
    let max = -Infinity;
    for (const d of nonempty) {
      if (c !== d) {
        max = Math.max(max, (scatter[c] + scatter[d]) / km.distance(centers[c], centers[d]));
      }
    }
    ratios += max;
  }
  return {
    silhouette: sum(silhouettes.map((v) => v!)) / points.length,
    ch: between / (nonempty.length - 1) / (within / (points.length - nonempty.length)),
    db: ratios / nonempty.length,
    clusterSilhouettes,
  };
}
function matching(table: number[][]) {
  let best: number[] = [];
  let agreement = -1;
  function visit(prefix: number[], remaining: number[]): void {
    if (!remaining.length) {
      let count = 0;
      for (let j = 0; j < prefix.length; j++) count += table[prefix[j]][j];
      if (count > agreement) {
        agreement = count;
        best = prefix;
      }
      return;
    }
    for (const c of remaining) {
      visit(
        [...prefix, c],
        remaining.filter((v) => v !== c),
      );
    }
  }
  visit(
    [],
    table.map((_, i) => i),
  );
  return { permutation: best, agreement };
}
function componentLines(points: Point[], model: Model, params: Params): string[] {
  const lines = ['selected components'];
  const metrics = partitionMetrics(points, model.assignment, model.k);
  model.components.forEach((s, k) => {
    const e = gaussian.eigen(s);
    const major = Math.sqrt(e.lambda1);
    const minor = Math.sqrt(e.lambda2);
    const assigned = points.map((_, i) => i).filter((i) => model.assignment[i] === k);
    const q = assigned.map((i) => gaussian.quadratic(points[i], s));
    const observed: number[] = Array(params.edges.length + 1).fill(0);
    for (const v of q) observed[params.edges.filter((edge) => Math.sqrt(v) >= edge).length]++;
    const bounds = [0, ...params.edges];
    const expected = bounds.map(
      (lower, i) =>
        assigned.length *
        (Math.exp((-lower * lower) / 2) -
          (i < params.edges.length ? Math.exp((-params.edges[i] * params.edges[i]) / 2) : 0)),
    );
    let chi2 = 0;
    observed.forEach((o, i) => {
      const d = o - expected[i];
      chi2 += (d * d) / expected[i];
    });
    lines.push(
      `component ${k + 1} weight ${real(s.w)} size ${assigned.length} soft_size ${real(sum(model.responsibilities.map((r) => r[k])))} mean ${reals([s.mx, s.my])}`,
      `  cov ${reals([s.a, s.b, s.c])} corr ${real(s.b / Math.sqrt(s.a * s.c))}`,
      `  eigen ${reals([e.lambda1, e.lambda2])} direction ${reals([e.ux, e.uy])} angle ${real(e.angle)}`,
      `  axes_1sigma ${reals([major, minor])} axes_2sigma ${reals([2 * major, 2 * minor])}`,
      `  inside_1sigma ${q.filter((v) => v <= 1).length} inside_2sigma ${q.filter((v) => v <= 4).length} area_1sigma ${real(Math.PI * Math.sqrt(e.lambda1 * e.lambda2))}`,
      `  silhouette ${real(metrics.clusterSilhouettes[k])}`,
      `  gof observed ${observed.join(' ')} expected ${reals(expected)} chi2 ${real(chi2)}`,
    );
  });
  return lines;
}
function mergeLines(model: Model): string[] {
  let clusters = model.components.map((_, k) => [k]);
  const responsibilities = (groups: number[][]) =>
    model.responsibilities.map((r) => groups.map((g) => sum(g.map((k) => r[k]))));
  const clusterEntropy = (groups: number[][]) => sum(responsibilities(groups).map(entropy));
  const name = (g: number[]) => g.map((k) => k + 1).join('+');
  const lines = ['merging', `start entropy ${real(clusterEntropy(clusters))}`];
  for (let step = 1; clusters.length > 1; step++) {
    let best: { a: number; b: number; groups: number[][]; entropy: number } | null = null;
    for (let a = 0; a < clusters.length - 1; a++) {
      for (let b = a + 1; b < clusters.length; b++) {
        const groups = clusters
          .filter((_, c) => c !== b)
          .map((g, c) => (c === a ? [...g, ...clusters[b]].sort((x, y) => x - y) : g));
        const value = clusterEntropy(groups);
        if (best === null || rounded(value) < rounded(best.entropy)) {
          best = { a, b, groups, entropy: value };
        }
      }
    }
    const chosen = best!;
    const a = name(clusters[chosen.a]);
    const b = name(clusters[chosen.b]);
    clusters = chosen.groups;
    const assignments = responsibilities(clusters).map(maximum);
    const sizes = clusters.map((_, c) => assignments.filter((k) => k === c).length);
    lines.push(
      `step ${step} merge ${a} ${b} entropy ${real(chosen.entropy)} sizes ${sizes.join(' ')}`,
    );
  }
  return lines;
}
function selectionReport(
  points: Point[],
  params: Params,
  initial: Map<number, Component[]>,
  models: Model[],
  kmeans: Map<number, ReturnType<typeof km.fit>>,
): string[] {
  const bic = rank(models, 'bic', params.types);
  const aic = rank(models, 'aic', params.types);
  const icl = rank(models, 'icl', params.types);
  const selected = bic[0];
  const ranking = [
    'ranking by bic',
    'rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank',
    ...bic.map(
      (m, i) =>
        `${i + 1} ${m.k} ${m.type} ${m.p} ${real(m.loglik)} ${real(m.bic)} ${real(rounded(m.bic) - rounded(selected.bic))} ${real(m.aic)} ${aic.indexOf(m) + 1} ${real(m.icl)} ${icl.indexOf(m) + 1}`,
    ),
    `selected K=${selected.k} type=${selected.type}`,
    `best_aic K=${aic[0].k} type=${aic[0].type}`,
    `best_icl K=${icl[0].k} type=${icl[0].type}`,
  ];
  const bestType = [
    'best K per type',
    ...params.types.map(
      (t) =>
        `${t} bic ${
          rank(
            models.filter((m) => m.type === t),
            'bic',
            params.types,
          )[0].k
        } aic ${
          rank(
            models.filter((m) => m.type === t),
            'aic',
            params.types,
          )[0].k
        } icl ${
          rank(
            models.filter((m) => m.type === t),
            'icl',
            params.types,
          )[0].k
        }`,
    ),
  ];
  const comparisons: string[][] = [];
  let previous: Model | null = null;
  for (const k of params.ks) {
    const m = rank(
      models.filter((m) => m.k === k),
      'bic',
      params.types,
    )[0];
    const kmfit = kmeans.get(k)!;
    const a = partitionMetrics(points, m.assignment, k);
    const b = partitionMetrics(points, kmfit.assignment, k);
    const lines = [
      `K=${k} type=${m.type} bic ${real(m.bic)}`,
      `  kmeans iterations ${kmfit.iterations} inertia ${real(kmfit.inertia)}`,
      `  ari ${fractionText(ari(contingency(m.assignment, kmfit.assignment, k, k)))}`,
      `  silhouette gmm ${real(a.silhouette)} kmeans ${real(b.silhouette)}`,
      `  calinski_harabasz gmm ${real(a.ch)} kmeans ${real(b.ch)}`,
      `  davies_bouldin gmm ${real(a.db)} kmeans ${real(b.db)}`,
    ];
    if (previous) {
      const table = contingency(previous.assignment, m.assignment, previous.k, k);
      const parents = m.components.map((_, j) => {
        const column = table.map((r) => r[j]);
        const a = maximum(column);
        return { parent: sum(column) ? a + 1 : '-', shared: column[a] };
      });
      lines.push(
        `  parents K=${previous.k} ${parents.map((p) => p.parent).join(' ')} shared ${parents.map((p) => p.shared).join(' ')}`,
      );
    }
    comparisons.push(lines);
    previous = m;
  }
  const violations = [
    'violations',
    ...models.flatMap((m) =>
      m.violations.map(
        (t) =>
          `K=${m.k} type=${m.type} iteration ${t} previous ${real(m.trace[t - 1])} current ${real(m.trace[t])}`,
      ),
    ),
  ];
  if (violations.length === 1) violations.push('none');
  const overlap = ['overlap'];
  for (let a = 0; a < selected.k - 1; a++) {
    for (let b = a + 1; b < selected.k; b++) {
      const d = gaussian.bhattacharyya(selected.components[a], selected.components[b]);
      overlap.push(
        `${a + 1}-${b + 1} bhattacharyya ${real(d)} coefficient ${real(Math.exp(-d))} shared ${real(sum(selected.responsibilities.map((r) => r[a] * r[b])))}`,
      );
    }
  }
  if (overlap.length === 1) overlap.push('none');
  const k = selected.k;
  const kmfit = kmeans.get(k)!;
  const table = contingency(selected.assignment, kmfit.assignment, k, k);
  const match = matching(table);
  const disagree = points
    .map((_, i) => i)
    .filter((i) => match.permutation[kmfit.assignment[i]] !== selected.assignment[i]);
  const comparison = [
    `kmeans K=${k}`,
    `iterations ${kmfit.iterations}`,
    `inertia ${real(kmfit.inertia)}`,
    `sizes ${kmfit.sizes.join(' ')}`,
    ...kmfit.centers.map((c, j) => `center ${j + 1} ${reals([c.x, c.y])}`),
    'contingency',
    ...table.map((r) => r.join(' ')),
    `ari ${fractionText(ari(table))}`,
    `matching ${match.permutation.map((c) => c + 1).join(' ')}`,
    `agreement ${match.agreement}/${points.length} ${real(match.agreement / points.length)}`,
    ...disagree.map(
      (i) =>
        `disagree ${points[i].id} gmm ${selected.assignment[i] + 1} kmeans ${kmfit.assignment[i] + 1} max ${real(Math.max(...selected.responsibilities[i]))}`,
    ),
    `disagreements ${disagree.length}`,
  ];
  const kmInitial = kmfit.centers.map((c, j) => {
    const group = points.filter((_, i) => kmfit.assignment[i] === j);
    let a = 0;
    let b = 0;
    let v = 0;
    for (const p of group) {
      const dx = p.x - c.x;
      const dy = p.y - c.y;
      a += dx * dx;
      b += dx * dy;
      v += dy * dy;
    }
    return {
      w: group.length / points.length,
      mx: c.x,
      my: c.y,
      a: a / group.length + params.eps,
      b: b / group.length,
      c: v / group.length + params.eps,
    };
  });
  const refit = summarize(
    em.fit(points, kmInitial, selected.type, params.iterations, params.eps),
    selected.type,
    params.tau,
    points.length,
  );
  const refitLines = [
    `refit_from_kmeans K=${k} type=${selected.type}`,
    `loglik ${real(refit.loglik)} bic ${real(refit.bic)} settled_at ${refit.settled}`,
    `sizes ${refit.sizes.join(' ')}`,
    `ari_vs_selected ${fractionText(ari(contingency(selected.assignment, refit.assignment, k, k)))}`,
  ];
  const cv = [`cross_validation K=${k} type=${selected.type} folds ${params.folds}`];
  const tests: number[] = [];
  for (let f = 0; f < params.folds; f++) {
    const train = points.filter((_, i) => i % params.folds !== f);
    const test = points.filter((_, i) => i % params.folds === f);
    const model = em.fit(train, initial.get(k)!, selected.type, params.iterations, params.eps);
    const testValue = em.expectation(test, model.components).loglik / test.length;
    tests.push(testValue);
    cv.push(
      `fold ${f + 1} train ${train.length} test ${test.length} train_loglik ${real(model.loglik / train.length)} test_loglik ${real(testValue)}`,
    );
  }
  cv.push(`mean_test_loglik ${real(sum(tests) / params.folds)}`);
  const indices = points.map((_, i) => i);
  const maxr = selected.responsibilities.map((r) => Math.max(...r));
  const uncertain = indices
    .filter((i) => maxr[i] < params.uncertain)
    .sort((a, b) => rounded(maxr[a]) - rounded(maxr[b]) || a - b);
  const outliers = indices
    .filter((i) => selected.logDensities[i] < params.lowDensity)
    .sort((a, b) => rounded(selected.logDensities[a]) - rounded(selected.logDensities[b]) || a - b);
  return sections([
    ranking,
    bestType,
    ...comparisons,
    violations,
    componentLines(points, selected, params),
    overlap,
    mergeLines(selected),
    comparison,
    refitLines,
    cv,
    [
      `uncertain threshold ${real(params.uncertain)}`,
      ...uncertain.map(
        (i) =>
          `${points[i].id} component ${selected.assignment[i] + 1} max ${real(maxr[i])} responsibilities ${reals(selected.responsibilities[i])}`,
      ),
      `count ${uncertain.length}`,
    ],
    [
      `outliers threshold ${real(params.lowDensity)}`,
      ...outliers.map(
        (i) =>
          `${points[i].id} component ${selected.assignment[i] + 1} log_density ${real(selected.logDensities[i])} q ${real(gaussian.quadratic(points[i], selected.components[selected.assignment[i]]))}`,
      ),
      `count ${outliers.length}`,
    ],
  ]);
}
function mapReport(points: Point[], model: Model, p: Params): string[] {
  const dx = (p.xmax - p.xmin) / p.width;
  const dy = (p.ymax - p.ymin) / p.height;
  const center = (r: number, c: number) => ({
    x: p.xmin + (c + 0.5) * dx,
    y: p.ymax - (r + 0.5) * dy,
  });
  const centers = Array.from({ length: p.height }, (_, r) =>
    Array.from({ length: p.width }, (_, c) => center(r, c)),
  );
  const logs = centers.map((row) =>
    row.map((c) => model.components.map((s) => gaussian.logWeighted(c, s))),
  );
  const densities = logs.map((row) => row.map((v) => sum(v.map(Math.exp))));
  const fmax = Math.max(...densities.flat());
  const levels = densities.map((row) => row.map((f) => Math.min(9, Math.floor((10 * f) / fmax))));
  const counts = Array.from({ length: 10 }, () => 0);
  const symbols = ' .:-=+*#%@';
  const density = levels.map((row) =>
    row.map((l) => {
      counts[l]++;
      return symbols[l];
    }),
  );
  const cell = (point: { x: number; y: number }) => ({
    c: Math.floor((point.x - p.xmin) / dx),
    r: Math.floor((p.ymax - point.y) / dy),
  });
  const inside = (r: number, c: number) => r >= 0 && r < p.height && c >= 0 && c < p.width;
  model.components.forEach((s, k) => {
    const { r, c } = cell({ x: s.mx, y: s.my });
    if (inside(r, c)) density[r][c] = String(k + 1);
  });
  const regions = logs.map((row) => row.map((v) => String(maximum(v) + 1)));
  const uncertainty = centers.map((row) =>
    row.map((c) => {
      if (model.k === 1) return ' ';
      const r = em.expectation([c], model.components).responsibilities[0];
      return symbols[Math.max(0, Math.min(9, Math.floor((10 * entropy(r)) / Math.log(model.k))))];
    }),
  );
  const pointMap: string[][] = centers.map((row, r) =>
    row.map((c, col) =>
      model.components.some(
        (s) =>
          gaussian.quadratic(c, s) <= 4 &&
          [
            [r - 1, col],
            [r + 1, col],
            [r, col - 1],
            [r, col + 1],
          ].some(([a, b]) => inside(a, b) && gaussian.quadratic(centers[a][b], s) > 4),
      )
        ? '.'
        : ' ',
    ),
  );
  const memberships = centers.map((row) => row.map(() => new Set<number>()));
  let outside = 0;
  points.forEach((point, i) => {
    const { r, c } = cell(point);
    if (!inside(r, c)) outside++;
    else memberships[r][c].add(model.assignment[i]);
  });
  memberships.forEach((row, r) =>
    row.forEach((set, c) => {
      if (set.size > 0) pointMap[r][c] = set.size > 1 ? '*' : String([...set][0] + 1);
    }),
  );
  return sections([
    [
      `density K=${model.k} type=${model.type}`,
      `x ${reals([p.xmin, p.xmax])} y ${reals([p.ymin, p.ymax])} grid ${p.width}x${p.height}`,
      `max_density ${real(fmax, 6)} mass_in_map ${real(sum(densities.flat()) * dx * dy)}`,
      ...frame(density),
      ...counts.map(
        (n, l) => `level ${l} "${symbols[l]}" from ${real((l * fmax) / 10, 6)} cells ${n}`,
      ),
    ],
    ['regions', ...frame(regions)],
    ['uncertainty', ...frame(uncertainty)],
    ['points', ...frame(pointMap), `outside ${outside}`],
  ]);
}
function main(): void {
  const { points, params, initial } = read();
  const models = params.ks.flatMap((k) =>
    params.types.map((type) =>
      summarize(
        em.fit(points, initial.get(k)!, type, params.iterations, params.eps),
        type,
        params.tau,
        points.length,
      ),
    ),
  );
  const kmeans = new Map(
    params.ks.map((k) => [k, km.fit(points, initial.get(k)!, params.kmeansMax)]),
  );
  const selected = rank(models, 'bic', params.types)[0];
  const modelLines = sections(
    models.map((m) => [
      `model K=${m.k} type=${m.type}`,
      `parameters ${m.p}`,
      `loglik ${real(m.loglik)}`,
      `bic ${real(m.bic)}`,
      `aic ${real(m.aic)}`,
      `icl ${real(m.icl)}`,
      `mean_entropy ${real(m.entropy / points.length)}`,
      `settled_at ${m.settled}`,
      `largest_increase iteration ${m.largest} value ${real(m.trace[m.largest] - m.trace[m.largest - 1])}`,
      `violations ${m.violations.length}`,
      `sizes ${m.sizes.join(' ')}`,
      ...m.components.map((s, k) => {
        const e = gaussian.eigen(s);
        return `component ${k + 1} weight ${real(s.w)} mean ${reals([s.mx, s.my])} cov ${reals([s.a, s.b, s.c])} axes ${reals([Math.sqrt(e.lambda1), Math.sqrt(e.lambda2)])} angle ${real(e.angle)}`;
      }),
    ]),
  );
  write('models.txt', modelLines);
  write('loglik_trace.csv', [
    'K,type,iteration,loglik',
    ...models.flatMap((m) => m.trace.map((l, t) => `${m.k},${m.type},${t},${real(l)}`)),
  ]);
  write('assignments.csv', [
    'id,component,max_responsibility,log_density,kmeans_cluster',
    ...points.map((p, i) =>
      [
        p.id,
        selected.assignment[i] + 1,
        real(Math.max(...selected.responsibilities[i])),
        real(selected.logDensities[i]),
        kmeans.get(selected.k)!.assignment[i] + 1,
      ].join(','),
    ),
  ]);
  write('selection.txt', selectionReport(points, params, initial, models, kmeans));
  write('density_map.txt', mapReport(points, selected, params));
}
main();
