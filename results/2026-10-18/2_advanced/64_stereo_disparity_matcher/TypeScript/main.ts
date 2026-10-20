import { readImage, readParameters, writeImage, writeLines, type CostKind } from './pgm_io.ts';
import { census, texture, matching } from './costs.ts';
import { aggregate, directions } from './aggregation.ts';
import { decimals, depthHundredths, refine } from './refinement.ts';
import { regions, evaluate, ratio } from './evaluation.ts';

const left = readImage('left.pgm');
const right = readImage('right.pgm');
const truth = readImage('ground_truth.pgm');
const p = readParameters();
const { width: w, height: h } = left;
const size = w * h;
const ground = truth.pixels;
const region = regions(truth);
const lc = census(left);
const rc = census(right);
const strength = texture(left, p.textureWindow);
const kinds: CostKind[] = ['sad', 'ssd', 'census'];
const regionNames = ['nonocc', 'all', 'disc'] as const;
const median = (values: number[]) =>
  values.slice().sort((a, b) => a - b)[Math.floor((values.length - 1) / 2)];
const validCount = (image: number[]) => image.filter((d) => d !== 0).length;
interface Selection {
  image: number[];
  reasons: number[];
  margins: number[];
  lr: number[];
  bounds: number;
  window: number;
}
function select(cost: number[][], window: number): Selection {
  const rightDisparity = Array<number>(size).fill(0);
  const image = Array<number>(size).fill(0);
  const reasons = Array<number>(size).fill(0);
  const margins = Array<number>(size).fill(0);
  const lr = [0, 0, 0, 0];
  let bounds = 0;
  for (let i = 0; i < size; i++) {
    const x = i % w;
    let best: number | undefined;
    for (let d = p.min; d <= p.max && x + d < w; d++) {
      const c = cost[i + d][d - p.min];
      if (best === undefined || c < best) {
        best = c;
        rightDisparity[i] = d;
      }
    }
  }
  for (let i = 0; i < size; i++) {
    const x = i % w;
    const row = cost[i];
    let index = 0;
    for (let d = 1; d < row.length; d++) if (row[d] < row[index]) index = d;
    const d1 = index + p.min;
    const c1 = row[index];
    let c2: number | undefined;
    for (let d = 0; d < row.length; d++) {
      if (Math.abs(d - index) >= 2 && (c2 === undefined || row[d] < c2)) c2 = row[d];
    }
    if (c2 === undefined) throw new Error('No uniqueness competitor');
    if (d1 === p.min || d1 === p.max) bounds++;
    const consistent = (d: number) => x - d >= 0 && Math.abs(d - rightDisparity[i - d]) <= p.lr;
    let reason = 0;
    if (strength[i] < p.textureThreshold) reason = 50;
    else if (100 * c2 <= (100 + p.uniqueness) * c1) reason = 100;
    else if (x - d1 < 0) reason = 150;
    else if (!consistent(d1)) {
      reason = 255;
      for (let d = p.min; d <= p.max; d++) {
        if (consistent(d)) {
          reason = 200;
          break;
        }
      }
    }
    reasons[i] = reason;
    if (reason === 0) {
      image[i] = d1;
      margins[i] = c2 - c1;
    }
    if (reason === 0 || reason === 200 || reason === 255) {
      lr[Math.min(3, Math.abs(d1 - rightDisparity[i - d1]))]++;
    }
  }
  return { image, reasons, margins, lr, bounds, window };
}
const sweep: string[] = [];
const selections = kinds.map((kind) => {
  let best: Selection | undefined;
  for (const window of p.windows[kind]) {
    const candidate = select(matching(left, right, lc, rc, kind, window, p), window);
    const score = evaluate(candidate.image, ground, region.nonocc);
    sweep.push(
      `sweep ${kind} window ${window} valid ${validCount(candidate.image)} bad1 ${ratio(score.bad1, score.pixels)} bad2 ${ratio(score.bad2, score.pixels)}`,
    );
    const old = best && evaluate(best.image, ground, region.nonocc);
    if (!old || score.bad1 < old.bad1 || (score.bad1 === old.bad1 && score.bad2 < old.bad2)) {
      best = candidate;
    }
  }
  if (!best) throw new Error('No matching windows');
  return best;
});
const base = matching(left, right, lc, rc, p.sgm, p.sgmWindow, p);
const pathLines: string[] = [];
let sgmCost = base;
let sgm = select(base, p.sgmWindow);
let pathNumber = 0;
for (const cost of aggregate(base, left, p)) {
  sgmCost = cost;
  sgm = select(cost, p.sgmWindow);
  pathNumber++;
  const score = evaluate(sgm.image, ground, region.nonocc);
  pathLines.push(
    `paths ${pathNumber} valid ${validCount(sgm.image)} bad1 ${ratio(score.bad1, score.pixels)} bad2 ${ratio(score.bad2, score.pixels)}`,
  );
}
selections.push(sgm);
function neighbours(i: number): number[] {
  const x = i % w;
  const y = Math.floor(i / w);
  const result: number[] = [];
  if (x + 1 < w) result.push(i + 1);
  if (x > 0) result.push(i - 1);
  if (y + 1 < h) result.push(i + w);
  if (y > 0) result.push(i - w);
  return result;
}
function components(image: number[], range: number): number[][] {
  const seen = Array<boolean>(size).fill(false);
  const result: number[][] = [];
  for (let i = 0; i < size; i++) {
    if (image[i] && !seen[i]) {
      const group = [i];
      seen[i] = true;
      for (let head = 0; head < group.length; head++) {
        for (const j of neighbours(group[head])) {
          if (image[j] && !seen[j] && Math.abs(image[j] - image[group[head]]) <= range) {
            seen[j] = true;
            group.push(j);
          }
        }
      }
      result.push(group);
    }
  }
  return result;
}
type Source = 'kept' | 'median' | 'background' | 'interpolated' | 'none';
interface Postprocess {
  image: number[];
  source: Source[];
  removed: number;
  removedPixels: number;
  median: number;
  background: number;
  interpolated: number;
  none: number;
}
function postprocess(selection: Selection): Postprocess {
  const a1 = selection.image.slice();
  let removed = 0;
  let removedPixels = 0;
  let changed = 0;
  for (const group of components(a1, p.speckleRange)) {
    if (group.length < p.speckleSize) {
      removed++;
      removedPixels += group.length;
      for (const i of group) a1[i] = 0;
    }
  }
  const a2 = a1.map((d, i) => {
    if (!d) return 0;
    const values: number[] = [];
    const x = i % w;
    const y = Math.floor(i / w);
    for (let dy = -1; dy <= 1; dy++) {
      for (let dx = -1; dx <= 1; dx++) {
        if (x + dx >= 0 && x + dx < w && y + dy >= 0 && y + dy < h) {
          const v = a1[(y + dy) * w + x + dx];
          if (v) values.push(v);
        }
      }
    }
    const value = median(values);
    if (value !== d) changed++;
    return value;
  });
  const image = a2.slice();
  const source: Source[] = Array<Source>(size).fill('none');
  for (let i = 0; i < size; i++) {
    if (a2[i]) {
      source[i] = a2[i] === selection.image[i] ? 'kept' : 'median';
      continue;
    }
    const background = selection.reasons[i] === 150 || selection.reasons[i] === 255;
    const values: number[] = [];
    const x = i % w;
    const y = Math.floor(i / w);
    for (const [dx, dy] of background ? directions.slice(0, 2) : directions) {
      let xx = x + dx;
      let yy = y + dy;
      while (xx >= 0 && xx < w && yy >= 0 && yy < h) {
        const d = a2[yy * w + xx];
        if (d) {
          values.push(d);
          break;
        }
        xx += dx;
        yy += dy;
      }
    }
    if (values.length) {
      image[i] = background ? Math.min(...values) : median(values);
      source[i] = background ? 'background' : 'interpolated';
    }
  }
  return {
    image,
    source,
    removed,
    removedPixels,
    median: changed,
    background: source.filter((s) => s === 'background').length,
    interpolated: source.filter((s) => s === 'interpolated').length,
    none: source.filter((s) => s === 'none').length,
  };
}
const wtaFinal = postprocess(selections[kinds.indexOf(p.wta)]);
const sgmFinal = postprocess(sgm);
const votes = [0, 0, 0, 0, 0];
const fusion = left.pixels.map((_, i) => {
  const values = selections.map((s) => s.image[i]).filter((d) => d !== 0);
  votes[values.length]++;
  if (!values.length) return 0;
  const center = median(values);
  return values.filter((d) => Math.abs(d - center) <= 1).length >= p.fusionVotes ? center : 0;
});
interface Method {
  name: string;
  image: number[];
  selection?: Selection;
  post?: Postprocess;
}
const methods: Method[] = [
  ...selections.map((selection, i) => ({
    name: [...kinds, 'sgm'][i],
    image: selection.image,
    selection,
  })),
  { name: 'fusion', image: fusion },
  { name: 'wta_final', image: wtaFinal.image, post: wtaFinal },
  { name: 'sgm_final', image: sgmFinal.image, post: sgmFinal },
];
const depthRows = ['x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth'];
for (const [x, y] of p.samples) {
  const i = y * w + x;
  const d = sgmFinal.image[i];
  const g = ground[i];
  const refined = d ? refine(sgmCost[i], d, p.min, p.max, p.focal, p.baseline) : undefined;
  depthRows.push(
    [
      x,
      y,
      ...selections.map((s) => s.image[i] || '-'),
      d || '-',
      sgmFinal.source[i],
      refined?.subpixel ?? '-',
      refined?.depth ?? '-',
      g || '-',
      g ? decimals(p.focal * p.baseline, g) : '-',
    ].join(','),
  );
}
let photometric = 0;
let photoAbs = 0;
for (const i of region.nonocc) {
  const diff = right.pixels[i - ground[i]] - left.pixels[i];
  photometric += diff;
  photoAbs += Math.abs(diff);
}
const bias = decimals(Math.abs(photometric), region.nonocc.length);
const report = [`image ${w} ${h}`, `disparities ${p.min} ${p.max}`];
for (const [name, image] of [
  ['left', left],
  ['right', right],
] as const) {
  report.push(
    `${name} mean ${decimals(
      image.pixels.reduce((a, b) => a + b, 0),
      size,
    )} min ${Math.min(...image.pixels)} max ${Math.max(...image.pixels)}`,
  );
}
report.push(
  `texture mean ${decimals(
    strength.reduce((a, b) => a + b, 0),
    size,
  )} textureless ${strength.filter((v) => v < p.textureThreshold).length}`,
  `ground_truth known ${region.all.length} nonocc ${region.nonocc.length} occluded ${region.occluded.length} disc ${region.disc.length} unknown ${size - region.all.length}`,
  `photometric pixels ${region.nonocc.length} mean_abs ${decimals(photoAbs, region.nonocc.length)} bias ${photometric < 0 && bias !== '0.00' ? '-' : ''}${bias}`,
  ...sweep,
  ...pathLines,
);
const scores = methods.map((method) =>
  regionNames.map((name) => evaluate(method.image, ground, region[name])),
);
for (let index = 0; index < methods.length; index++) {
  const method = methods[index];
  const values = method.image.filter((d) => d !== 0);
  let horizontal = 0;
  let vertical = 0;
  for (let i = 0; i < size; i++) {
    if (method.image[i]) {
      if (
        (i % w) + 1 < w &&
        method.image[i + 1] &&
        Math.abs(method.image[i] - method.image[i + 1]) >= 2
      ) {
        horizontal++;
      }
      if (
        i + w < size &&
        method.image[i + w] &&
        Math.abs(method.image[i] - method.image[i + w]) >= 2
      ) {
        vertical++;
      }
    }
  }
  report.push(
    `method ${method.name} valid ${values.length} invalid ${size - values.length}`,
    values.length
      ? `disparity min ${Math.min(...values)} max ${Math.max(...values)} median ${median(values)} distinct ${new Set(values).size}`
      : 'disparity min - max - median - distinct 0',
    `jumps horizontal ${horizontal} vertical ${vertical}`,
  );
  if (method.selection) {
    const s = method.selection;
    report.push(
      `window ${s.window} bounds ${s.bounds}`,
      'reasons ' +
        ['textureless', 'nonunique', 'outside', 'mismatch', 'occluded']
          .map(
            (name, i) =>
              `${name} ${s.reasons.filter((r) => r === [50, 100, 150, 200, 255][i]).length}`,
          )
          .join(' '),
      `lr 0 ${s.lr[0]} 1 ${s.lr[1]} 2 ${s.lr[2]} 3+ ${s.lr[3]}`,
    );
  } else if (method.post) {
    const post = method.post;
    report.push(
      `postprocess speckles ${post.removed} ${post.removedPixels} median ${post.median} background ${post.background} interpolated ${post.interpolated} unfilled ${post.none}`,
    );
    for (const source of ['kept', 'median', 'background', 'interpolated', 'none']) {
      const q = region.all.filter((i) => post.source[i] === source);
      const score = evaluate(method.image, ground, q);
      report.push(`source ${source} pixels ${q.length} bad1 ${ratio(score.bad1, q.length)}`);
    }
  } else report.push('votes ' + votes.map((count, i) => `${i} ${count}`).join(' '));
  scores[index].forEach((score, r) =>
    report.push(
      `region ${regionNames[r]} pixels ${score.pixels} valid ${score.valid} bad1 ${ratio(score.bad1, score.pixels)} bad2 ${ratio(score.bad2, score.pixels)} mae ${score.valid ? decimals(score.error, score.valid) : '-'} exact ${score.exact}`,
    ),
  );
  const depthErrors = region.nonocc
    .filter((i) => method.image[i])
    .map((i) =>
      Math.abs(
        depthHundredths(method.image[i], p.focal, p.baseline) -
          depthHundredths(ground[i], p.focal, p.baseline),
      ),
    );
  report.push(
    depthErrors.length
      ? `depth_error pixels ${depthErrors.length} mean ${decimals(
          depthErrors.reduce((a, b) => a + b, 0),
          100 * depthErrors.length,
        )} max ${decimals(Math.max(...depthErrors), 100)}`
      : 'depth_error pixels 0 mean - max -',
  );
  const errors = [0, 0, 0, 0, 0, 0];
  for (const i of region.all) {
    errors[method.image[i] ? Math.min(4, Math.abs(method.image[i] - ground[i])) : 5]++;
  }
  report.push(
    `errors 0 ${errors[0]} 1 ${errors[1]} 2 ${errors[2]} 3 ${errors[3]} 4+ ${errors[4]} invalid ${errors[5]}`,
  );
}
regionNames.forEach((name, r) => {
  const order = methods
    .map((_, i) => i)
    .sort((a, b) => {
      const x = scores[a][r];
      const y = scores[b][r];
      return (
        x.bad1 - y.bad1 ||
        x.bad2 - y.bad2 ||
        (x.valid === 0
          ? y.valid === 0
            ? 0
            : 1
          : y.valid === 0
            ? -1
            : x.error * y.valid - y.error * x.valid) ||
        a - b
      );
    });
  report.push(`ranking ${name} ` + order.map((i) => methods[i].name).join(' '));
});
selections.forEach((s, index) => {
  const detected = (i: number) => s.reasons[i] === 150 || s.reasons[i] === 255;
  const tp = region.occluded.filter(detected).length;
  const fp = region.nonocc.filter(detected).length;
  const fn = region.occluded.length - tp;
  report.push(
    `occlusion ${methods[index].name} tp ${tp} fp ${fp} fn ${fn} precision ${ratio(tp, tp + fp)} recall ${ratio(tp, tp + fn)}`,
  );
});
selections.forEach((s, index) => {
  const sorted = region.nonocc
    .filter((i) => s.image[i])
    .sort((a, b) => s.margins[b] - s.margins[a] || a - b);
  for (const percent of [25, 50, 75, 100]) {
    const n = Math.floor((sorted.length * percent + 99) / 100);
    const bad = sorted.slice(0, n).filter((i) => Math.abs(s.image[i] - ground[i]) > 1).length;
    report.push(
      `confidence ${methods[index].name} ${percent} pixels ${n} margin ${n ? s.margins[sorted[n - 1]] : '-'} bad1 ${ratio(bad, n)}`,
    );
  }
});
const layers = [...new Set(ground.filter((g) => g !== 0))].sort((a, b) => a - b);
for (const g of layers) {
  const known = region.all.filter((i) => ground[i] === g);
  const q = region.nonocc.filter((i) => ground[i] === g);
  report.push(
    `layer ${g} pixels ${known.length} nonocc ${q.length} bad1 ` +
      methods.map((method) => evaluate(method.image, ground, q).bad1).join(' '),
  );
}
for (let d = p.min; d <= p.max; d++) {
  report.push(`histogram ${d} ${sgmFinal.image.filter((v) => v === d).length}`);
}

const groups = components(sgmFinal.image, p.objectRange);
const small = groups.filter((group) => group.length < p.objectSize).length;
const objects = groups
  .filter((group) => group.length >= p.objectSize)
  .map((group) => {
    const values = group.map((i) => sgmFinal.image[i]);
    const xs = group.map((i) => i % w);
    const ys = group.map((i) => Math.floor(i / w));
    const counts = layers.map((g) => group.filter((i) => ground[i] === g).length);
    let winner = -1;
    for (let i = 0; i < counts.length; i++) {
      if (counts[i] > 0 && (winner < 0 || counts[i] > counts[winner])) winner = i;
    }
    const t = winner < 0 ? 0 : layers[winner];
    const overlap = winner < 0 ? 0 : counts[winner];
    const union = t ? group.length + ground.filter((g) => g === t).length - overlap : 0;
    return {
      group,
      values,
      n: group.length,
      dm: median(values),
      sum: values.reduce((a, b) => a + b, 0),
      x0: Math.min(...xs),
      y0: Math.min(...ys),
      x1: Math.max(...xs),
      y1: Math.max(...ys),
      t,
      overlap,
      union,
    };
  })
  .sort((a, b) => b.dm - a.dm || b.n - a.n || a.group[0] - b.group[0]);
const objectLines = [
  `objects ${objects.length} small ${small} pixels ${objects.reduce((sum, object) => sum + object.n, 0)}`,
];
const detectedLayers = new Set<number>();
objects.forEach((object, i) => {
  const o = object;
  if (o.t && 2 * o.overlap > o.union) detectedLayers.add(o.t);
  objectLines.push(
    `object ${i + 1} pixels ${o.n} box ${o.x0} ${o.y0} ${o.x1} ${o.y1} disparity ${Math.min(...o.values)} ${Math.max(...o.values)} median ${o.dm} mean ${decimals(o.sum, o.n)} depth ${decimals(p.focal * p.baseline * o.n, o.sum)} size ${decimals((o.x1 - o.x0 + 1) * p.baseline, o.dm)} ${decimals((o.y1 - o.y0 + 1) * p.baseline, o.dm)} truth ${o.t || '-'} iou ${o.t ? ratio(o.overlap, o.union) : '-'}`,
  );
});
const missed = layers.filter((g) => !detectedLayers.has(g));
objectLines.push(
  `layers ${layers.length} detected ${detectedLayers.size} missed ${missed.length ? missed.join(' ') : '-'}`,
);
writeImage('disparity_wta.pgm', { ...left, pixels: wtaFinal.image.map((d) => 8 * d) });
writeImage('disparity_sgm.pgm', { ...left, pixels: sgmFinal.image.map((d) => 8 * d) });
writeImage('occlusion.pgm', { ...left, pixels: sgm.reasons });
writeImage('error_sgm.pgm', {
  ...left,
  pixels: ground.map((g, i) =>
    g === 0
      ? 0
      : sgmFinal.image[i] === 0
        ? 255
        : 50 * (Math.min(3, Math.abs(g - sgmFinal.image[i])) + 1),
  ),
});
writeLines('depth.csv', depthRows);
writeLines('evaluation.txt', report);
writeLines('objects.txt', objectLines);
