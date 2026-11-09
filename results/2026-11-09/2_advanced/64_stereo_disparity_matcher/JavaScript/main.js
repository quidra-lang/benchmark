const fs = require('node:fs');
const { readPgm, readParameters, writePgm } = require('./pgm_io');
const { census, texture, costVolume } = require('./costs');
const { DIRECTIONS, cumulativeCosts } = require('./aggregation');
const { REGION_ORDER, truthRegions, evaluate, ratio } = require('./evaluation');
const { twoDecimals, depthHundredths, subpixel } = require('./refinement');

const METHODS = ['sad', 'ssd', 'census', 'sgm', 'fusion', 'wta_final', 'sgm_final'];
const SELECTION_METHODS = METHODS.slice(0, 4);
const REASONS = [['textureless', 50], ['nonunique', 100], ['outside', 150], ['mismatch', 200], ['occluded', 255]];
const SOURCES = ['kept', 'median', 'background', 'interpolated', 'none'];
const sum = values => values.reduce((a, b) => a + b, 0);
const lowerMedian = values => [...values].sort((a, b) => a - b)[Math.floor((values.length - 1) / 2)];
const validCount = image => image.filter(value => value !== 0).length;

function frequencies(values) {
  const counts = new Map();
  for (const value of values) counts.set(value, (counts.get(value) || 0) + 1);
  return counts;
}

function makeCosts(data, kind, window) {
  const { left, right, censusLeft, censusRight, width, height, params } = data;
  return costVolume(left, right, censusLeft, censusRight, width, height, kind, window,
    params.disparity_min, params.disparity_max);
}

function selectDisparities(volume, data) {
  const { width, height, strengths, params } = data;
  const minimum = params.disparity_min, maximum = params.disparity_max;
  const right = Array(volume.length).fill(null);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const p = y * width + x;
      for (let d = minimum; d <= maximum && x + d < width; d++) {
        const chosen = right[p];
        if (chosen === null || volume[p + d][d - minimum] < volume[p + chosen][chosen - minimum]) {
          right[p] = d;
        }
      }
    }
  }
  const image = Array(volume.length).fill(0);
  const reasons = Array(volume.length).fill(0);
  const margins = Array(volume.length).fill(0);
  const lr = [0, 0, 0, 0];
  let bounds = 0;
  for (let p = 0; p < volume.length; p++) {
    const x = p % width, costs = volume[p];
    let best = minimum;
    for (let d = minimum + 1; d <= maximum; d++) {
      if (costs[d - minimum] < costs[best - minimum]) best = d;
    }
    const first = costs[best - minimum];
    const separated = costs.filter((_, d) => Math.abs(d + minimum - best) >= 2);
    const second = Math.min(...separated);
    const consistent = d => x >= d && Math.abs(d - right[p - d]) <= params.lr_max_diff;
    if (best === minimum || best === maximum) bounds++;
    let reason = 0;
    if (strengths[p] < params.texture_threshold) reason = 50;
    else if (100 * second <= (100 + params.uniqueness) * first) reason = 100;
    else if (x < best) reason = 150;
    else if (!consistent(best)) {
      reason = 255;
      for (let d = minimum; d <= maximum; d++) {
        if (consistent(d)) { reason = 200; break; }
      }
    } else {
      image[p] = best;
      margins[p] = second - first;
    }
    reasons[p] = reason;
    if (reason === 0 || reason === 200 || reason === 255) {
      lr[Math.min(3, Math.abs(best - right[p - best]))]++;
    }
  }
  return { image, reasons, margins, lr, bounds };
}

function chooseWindows(data) {
  const methods = {}, sweeps = [];
  for (const kind of SELECTION_METHODS.slice(0, 3)) {
    let bestMetrics = null;
    for (const window of data.params[kind + '_windows']) {
      const selected = selectDisparities(makeCosts(data, kind, window), data);
      selected.window = window;
      const metrics = evaluate(selected.image, data.truth, data.regions.nonocc);
      sweeps.push({ kind, window, metrics, valid: validCount(selected.image) });
      if (bestMetrics === null || metrics.bad1 < bestMetrics.bad1
          || (metrics.bad1 === bestMetrics.bad1 && metrics.bad2 < bestMetrics.bad2)) {
        bestMetrics = metrics;
        methods[kind] = selected;
      }
    }
  }
  return { methods, sweeps };
}

function semiGlobal(data) {
  const { left, width, height, truth, regions, params } = data;
  const base = makeCosts(data, params.sgm_cost, params.sgm_window);
  const progress = [];
  let selected, summedCosts;
  for (const total of cumulativeCosts(base, left, width, height,
    params.sgm_paths, params.p1, params.p2, params.p2_gamma)) {
    selected = selectDisparities(total, data);
    progress.push({ number: progress.length + 1,
      metrics: evaluate(selected.image, truth, regions.nonocc),
      valid: validCount(selected.image) });
    summedCosts = total;
  }
  selected.window = params.sgm_window;
  return { selected, summedCosts, progress };
}

function neighbors4(p, data) {
  const { width, height } = data;
  const x = p % width, y = Math.floor(p / width);
  return [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]]
    .filter(([xx, yy]) => xx >= 0 && xx < width && yy >= 0 && yy < height)
    .map(([xx, yy]) => yy * width + xx);
}

function connectedRegions(image, data, maximumDifference) {
  const seen = new Set(), components = [];
  for (let start = 0; start < image.length; start++) {
    if (image[start] === 0 || seen.has(start)) continue;
    seen.add(start);
    const stack = [start], component = [];
    while (stack.length) {
      const p = stack.pop();
      component.push(p);
      for (const q of neighbors4(p, data)) {
        if (image[q] !== 0 && !seen.has(q) && Math.abs(image[q] - image[p]) <= maximumDifference) {
          seen.add(q);
          stack.push(q);
        }
      }
    }
    components.push(component);
  }
  return components;
}

function medianFilter(image, data) {
  const { width, height } = data;
  return image.map((value, p) => {
    if (value === 0) return 0;
    const x = p % width, y = Math.floor(p / width), values = [];
    for (let yy = Math.max(0, y - 1); yy < Math.min(height, y + 2); yy++) {
      for (let xx = Math.max(0, x - 1); xx < Math.min(width, x + 2); xx++) {
        if (image[yy * width + xx] !== 0) values.push(image[yy * width + xx]);
      }
    }
    return lowerMedian(values);
  });
}

function rayValues(image, data, p, directions) {
  const { width, height } = data, values = [];
  const x = p % width, y = Math.floor(p / width);
  for (const [dx, dy] of directions) {
    for (let xx = x + dx, yy = y + dy; xx >= 0 && xx < width && yy >= 0 && yy < height; xx += dx, yy += dy) {
      const value = image[yy * width + xx];
      if (value !== 0) { values.push(value); break; }
    }
  }
  return values;
}

function postprocess(selection, data) {
  const original = selection.image, params = data.params;
  const removed = connectedRegions(original, data, params.speckle_range)
    .filter(part => part.length < params.speckle_size);
  const filtered = [...original];
  for (const component of removed) for (const p of component) filtered[p] = 0;
  const medians = medianFilter(filtered, data);
  const image = [...medians], sources = Array(image.length).fill('none');
  for (let p = 0; p < image.length; p++) {
    if (medians[p] !== 0) {
      sources[p] = medians[p] === original[p] ? 'kept' : 'median';
    } else if (selection.reasons[p] === 150 || selection.reasons[p] === 255) {
      const values = rayValues(medians, data, p, [[-1, 0], [1, 0]]);
      if (values.length) { image[p] = Math.min(...values); sources[p] = 'background'; }
    } else {
      const values = rayValues(medians, data, p, DIRECTIONS);
      if (values.length) { image[p] = lowerMedian(values); sources[p] = 'interpolated'; }
    }
  }
  const counts = frequencies(sources);
  return { image, sources, speckles: removed.length,
    specklePixels: sum(removed.map(part => part.length)),
    medianChanged: filtered.filter((value, p) => value !== medians[p]).length,
    background: counts.get('background') || 0, interpolated: counts.get('interpolated') || 0,
    unfilled: counts.get('none') || 0 };
}

function fuse(methods, minimumVotes) {
  const votes = [0, 0, 0, 0, 0];
  const image = methods.sad.image.map((_, p) => {
    const values = SELECTION_METHODS.map(name => methods[name].image[p]).filter(d => d !== 0);
    votes[values.length]++;
    if (!values.length) return 0;
    const median = lowerMedian(values);
    return values.filter(d => Math.abs(d - median) <= 1).length >= minimumVotes ? median : 0;
  });
  return { image, votes };
}

function extractObjects(image, data) {
  const { width, truth, params } = data;
  const counts = frequencies(truth.filter(value => value !== 0));
  const objects = [];
  let small = 0;
  for (const component of connectedRegions(image, data, params.object_range)) {
    if (component.length < params.object_min_size) { small++; continue; }
    const n = component.length;
    const xs = component.map(p => p % width), ys = component.map(p => Math.floor(p / width));
    const box = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
    const values = component.map(p => image[p]), median = lowerMedian(values), total = sum(values);
    const layerCounts = frequencies(component.filter(p => truth[p] !== 0).map(p => truth[p]));
    const candidates = [...layerCounts.keys()].sort((a, b) => layerCounts.get(b) - layerCounts.get(a) || a - b);
    const layer = candidates.length ? candidates[0] : null;
    const hits = layer === null ? 0 : layerCounts.get(layer);
    objects.push({ pixels: n, box, minimum: Math.min(...values), maximum: Math.max(...values), median,
      mean: twoDecimals(total, n), depth: twoDecimals(params.focal_length * params.baseline * n, total),
      width: twoDecimals((box[2] - box[0] + 1) * params.baseline, median),
      height: twoDecimals((box[3] - box[1] + 1) * params.baseline, median),
      truth: layer, hits, union: layer === null ? 0 : n + counts.get(layer) - hits,
      first: Math.min(...component) });
  }
  objects.sort((a, b) => b.median - a.median || b.pixels - a.pixels || a.first - b.first);
  const detected = new Set(objects.filter(item => item.truth !== null && 2 * item.hits > item.union)
    .map(item => item.truth));
  return { objects, small, layers: [...counts.keys()].sort((a, b) => a - b), detected };
}

function objectLines(result) {
  const { objects, small, layers, detected } = result;
  const lines = [`objects ${objects.length} small ${small} pixels ${sum(objects.map(o => o.pixels))}`];
  objects.forEach((item, index) => {
    const truth = item.truth === null ? 'truth - iou -' : `truth ${item.truth} iou ${ratio(item.hits, item.union)}`;
    lines.push(`object ${index + 1} pixels ${item.pixels} box ${item.box.join(' ')} `
      + `disparity ${item.minimum} ${item.maximum} median ${item.median} mean ${item.mean} `
      + `depth ${item.depth} size ${item.width} ${item.height} ${truth}`);
  });
  const missed = layers.filter(g => !detected.has(g)).join(' ') || '-';
  lines.push(`layers ${layers.length} detected ${detected.size} missed ${missed}`);
  return lines;
}

function sampleLines(methods, summedCosts, data) {
  const { width, truth, params } = data;
  const focal = params.focal_length, baseline = params.baseline;
  const lines = ['x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth'];
  for (const [x, y] of params.samplePixels) {
    const p = y * width + x, values = [x, y];
    values.push(...SELECTION_METHODS.map(name => methods[name].image[p] || '-'));
    const disparity = methods.sgm_final.image[p];
    if (disparity !== 0) {
      const [refined, depth] = subpixel(disparity, summedCosts[p], params.disparity_min,
        params.disparity_max, focal, baseline);
      values.push(disparity, methods.sgm_final.sources[p], refined, depth);
    } else values.push('-', 'none', '-', '-');
    if (truth[p] !== 0) values.push(truth[p], twoDecimals(focal * baseline, truth[p]));
    else values.push('-', '-');
    lines.push(values.join(','));
  }
  return lines;
}

function inputSummary(data) {
  const { left, right, truth, width, height, regions, strengths, params } = data;
  const size = width * height;
  const imageLine = (name, image) => `${name} mean ${twoDecimals(sum(image), size)} `
    + `min ${Math.min(...image)} max ${Math.max(...image)}`;
  const delta = regions.nonocc.map(p => right[p - truth[p]] - left[p]);
  const biasSum = sum(delta);
  let bias = twoDecimals(Math.abs(biasSum), delta.length);
  if (biasSum < 0 && bias !== '0.00') bias = '-' + bias;
  return [`image ${width} ${height}`, `disparities ${params.disparity_min} ${params.disparity_max}`,
    imageLine('left', left), imageLine('right', right),
    `texture mean ${twoDecimals(sum(strengths), size)} textureless ${strengths.filter(v => v < params.texture_threshold).length}`,
    `ground_truth known ${regions.all.length} nonocc ${regions.nonocc.length} occluded ${regions.occluded.length} `
      + `disc ${regions.disc.length} unknown ${size - regions.all.length}`,
    `photometric pixels ${delta.length} mean_abs ${twoDecimals(sum(delta.map(Math.abs)), delta.length)} bias ${bias}`];
}

function sweepLines(sweeps, progress) {
  const line = (prefix, item) => `${prefix} valid ${item.valid} `
    + `bad1 ${ratio(item.metrics.bad1, item.metrics.pixels)} bad2 ${ratio(item.metrics.bad2, item.metrics.pixels)}`;
  return [...sweeps.map(item => line(`sweep ${item.kind} window ${item.window}`, item)),
    ...progress.map(item => line(`paths ${item.number}`, item))];
}

function disparitySummary(name, image, data) {
  const values = image.filter(d => d !== 0);
  let horizontal = 0, vertical = 0;
  image.forEach((value, p) => {
    if (value === 0) return;
    if (p % data.width + 1 < data.width && image[p + 1] !== 0 && Math.abs(value - image[p + 1]) >= 2) horizontal++;
    if (p + data.width < image.length && image[p + data.width] !== 0 && Math.abs(value - image[p + data.width]) >= 2) vertical++;
  });
  const distribution = values.length ? `disparity min ${Math.min(...values)} max ${Math.max(...values)} `
    + `median ${lowerMedian(values)} distinct ${new Set(values).size}` : 'disparity min - max - median - distinct 0';
  return [`method ${name} valid ${values.length} invalid ${image.length - values.length}`, distribution,
    `jumps horizontal ${horizontal} vertical ${vertical}`];
}

function selectionDetails(method) {
  const counts = frequencies(method.reasons);
  return [`window ${method.window} bounds ${method.bounds}`,
    'reasons ' + REASONS.map(([name, code]) => `${name} ${counts.get(code) || 0}`).join(' '),
    `lr 0 ${method.lr[0]} 1 ${method.lr[1]} 2 ${method.lr[2]} 3+ ${method.lr[3]}`];
}

function postprocessDetails(method, data) {
  const lines = [`postprocess speckles ${method.speckles} ${method.specklePixels} median ${method.medianChanged} `
    + `background ${method.background} interpolated ${method.interpolated} unfilled ${method.unfilled}`];
  for (const source of SOURCES) {
    const region = data.regions.all.filter(p => method.sources[p] === source);
    const result = evaluate(method.image, data.truth, region);
    lines.push(`source ${source} pixels ${result.pixels} bad1 ${ratio(result.bad1, result.pixels)}`);
  }
  return lines;
}

function regionLine(region, metrics) {
  return `region ${region} pixels ${metrics.pixels} valid ${metrics.valid} `
    + `bad1 ${ratio(metrics.bad1, metrics.pixels)} bad2 ${ratio(metrics.bad2, metrics.pixels)} `
    + `mae ${metrics.mae} exact ${metrics.exact}`;
}

function depthErrorLine(image, data) {
  const { truth, params, regions } = data;
  const errors = regions.nonocc.filter(p => image[p] !== 0).map(p =>
    Math.abs(depthHundredths(image[p], params.focal_length, params.baseline)
      - depthHundredths(truth[p], params.focal_length, params.baseline)));
  return errors.length ? `depth_error pixels ${errors.length} mean ${twoDecimals(sum(errors), 100 * errors.length)} `
    + `max ${twoDecimals(Math.max(...errors), 100)}` : 'depth_error pixels 0 mean - max -';
}

function errorCountsLine(image, data) {
  const errors = frequencies(data.regions.all.filter(p => image[p] !== 0)
    .map(p => Math.min(4, Math.abs(image[p] - data.truth[p]))));
  return `errors 0 ${errors.get(0) || 0} 1 ${errors.get(1) || 0} 2 ${errors.get(2) || 0} `
    + `3 ${errors.get(3) || 0} 4+ ${errors.get(4) || 0} invalid ${data.regions.all.filter(p => image[p] === 0).length}`;
}

function methodLines(name, method, metrics, data) {
  const lines = disparitySummary(name, method.image, data);
  if (SELECTION_METHODS.includes(name)) lines.push(...selectionDetails(method));
  else if (name === 'fusion') lines.push('votes ' + method.votes.map((count, n) => `${n} ${count}`).join(' '));
  else lines.push(...postprocessDetails(method, data));
  for (const region of REGION_ORDER) lines.push(regionLine(region, metrics[name][region]));
  lines.push(depthErrorLine(method.image, data), errorCountsLine(method.image, data));
  return lines;
}

function rankingLines(metrics) {
  return REGION_ORDER.map(region => {
    const names = [...METHODS].sort((a, b) => {
      const x = metrics[a][region], y = metrics[b][region];
      let comparison = x.bad1 - y.bad1 || x.bad2 - y.bad2;
      if (comparison) return comparison;
      if (x.valid === 0 || y.valid === 0) comparison = Number(x.valid === 0) - Number(y.valid === 0);
      else comparison = x.errorSum * y.valid - y.errorSum * x.valid;
      return comparison || METHODS.indexOf(a) - METHODS.indexOf(b);
    });
    return `ranking ${region} ${names.join(' ')}`;
  });
}

function occlusionLines(methods, regions) {
  return SELECTION_METHODS.map(name => {
    const detected = p => methods[name].reasons[p] === 150 || methods[name].reasons[p] === 255;
    const tp = regions.occluded.filter(detected).length;
    const fp = regions.nonocc.filter(detected).length;
    const fn = regions.occluded.length - tp;
    return `occlusion ${name} tp ${tp} fp ${fp} fn ${fn} precision ${ratio(tp, tp + fp)} recall ${ratio(tp, tp + fn)}`;
  });
}

function confidenceLines(methods, data) {
  const lines = [];
  for (const name of SELECTION_METHODS) {
    const method = methods[name];
    const pixels = data.regions.nonocc.filter(p => method.image[p] !== 0)
      .sort((a, b) => method.margins[b] - method.margins[a] || a - b);
    for (const percentage of [25, 50, 75, 100]) {
      const count = Math.floor((pixels.length * percentage + 99) / 100);
      const bad = pixels.slice(0, count).filter(p => Math.abs(method.image[p] - data.truth[p]) > 1).length;
      const margin = count === 0 ? '-' : method.margins[pixels[count - 1]];
      lines.push(`confidence ${name} ${percentage} pixels ${count} margin ${margin} bad1 ${ratio(bad, count)}`);
    }
  }
  return lines;
}

function layerLines(methods, data) {
  const counts = frequencies(data.truth.filter(value => value !== 0));
  return [...counts.keys()].sort((a, b) => a - b).map(layer => {
    const nonocc = data.regions.nonocc.filter(p => data.truth[p] === layer);
    const errors = METHODS.map(name => evaluate(methods[name].image, data.truth, nonocc).bad1);
    return `layer ${layer} pixels ${counts.get(layer)} nonocc ${nonocc.length} bad1 ${errors.join(' ')}`;
  });
}

function evaluationLines(methods, sweeps, progress, data) {
  const metrics = Object.fromEntries(METHODS.map(name => [name,
    Object.fromEntries(REGION_ORDER.map(region => [region, evaluate(methods[name].image, data.truth, data.regions[region])]))]));
  const lines = [...inputSummary(data), ...sweepLines(sweeps, progress)];
  for (const name of METHODS) lines.push(...methodLines(name, methods[name], metrics, data));
  lines.push(...rankingLines(metrics), ...occlusionLines(methods, data.regions),
    ...confidenceLines(methods, data), ...layerLines(methods, data));
  const counts = frequencies(methods.sgm_final.image);
  for (let d = data.params.disparity_min; d <= data.params.disparity_max; d++) {
    lines.push(`histogram ${d} ${counts.get(d) || 0}`);
  }
  return lines;
}

function errorImage(image, truth) {
  return image.map((actual, p) => truth[p] === 0 ? 0 : actual === 0 ? 255
    : 50 * (Math.min(Math.abs(actual - truth[p]), 3) + 1));
}

function saveText(name, lines) {
  fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

function main() {
  const { width, height, pixels: left } = readPgm('input/left.pgm');
  const right = readPgm('input/right.pgm').pixels;
  const truth = readPgm('input/ground_truth.pgm').pixels;
  const params = readParameters();
  const data = { width, height, left, right, truth, params,
    regions: truthRegions(truth, width, height),
    strengths: texture(left, width, height, params.texture_window),
    censusLeft: census(left, width, height), censusRight: census(right, width, height) };
  const { methods, sweeps } = chooseWindows(data);
  const { selected, summedCosts, progress } = semiGlobal(data);
  methods.sgm = selected;
  methods.fusion = fuse(methods, params.fusion_min_votes);
  methods.wta_final = postprocess(methods[params.wta_cost], data);
  methods.sgm_final = postprocess(selected, data);
  const objects = extractObjects(methods.sgm_final.image, data);

  fs.mkdirSync('output', { recursive: true });
  writePgm('output/disparity_wta.pgm', width, height, methods.wta_final.image.map(d => 8 * d));
  writePgm('output/disparity_sgm.pgm', width, height, methods.sgm_final.image.map(d => 8 * d));
  writePgm('output/occlusion.pgm', width, height, selected.reasons);
  writePgm('output/error_sgm.pgm', width, height, errorImage(methods.sgm_final.image, truth));
  saveText('depth.csv', sampleLines(methods, summedCosts, data));
  saveText('evaluation.txt', evaluationLines(methods, sweeps, progress, data));
  saveText('objects.txt', objectLines(objects));
}

main();
