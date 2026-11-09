'use strict';

const fs = require('node:fs');
const { readDataset } = require('./dataset');
const matrix = require('./matrix');
const eigen = require('./eigen');
const pca = require('./pca');
const plot = require('./plot');

const fields = (...values) => values.join(' ');
const componentNames = (prefix, count) => Array.from({ length: count }, (_, index) => prefix + (index + 1));

function real(value, digits = 4) {
  if (Math.abs(value) >= 1e21) return BigInt(value).toString() + '.' + '0'.repeat(digits);
  const text = value.toFixed(digits);
  return text === '-0.' + '0'.repeat(digits) ? text.slice(1) : text;
}

function reals(values) {
  return values.map(value => real(value)).join(' ');
}

function sum(values) {
  let total = 0;
  for (const value of values) total += value;
  return total;
}

function sections(parts) {
  const lines = [];
  parts.forEach((part, index) => {
    if (index > 0) lines.push('');
    lines.push(...part);
  });
  return lines;
}

function top(items, value, count) {
  return items.map((item, index) => ({ item, index, value: value(item) }))
    .sort((a, b) => b.value - a.value || a.index - b.index).slice(0, count).map(entry => entry.item);
}

function maximumIndex(values) {
  let index = 0;
  for (let next = 1; next < values.length; next++) if (values[next] > values[index]) index = next;
  return index;
}

function summarize(data) {
  return data.names.map((name, feature) => {
    const observed = data.rows.map(row => row.values[feature]).filter(value => value !== null);
    const mean = sum(observed) / observed.length;
    let square = 0;
    for (const value of observed) square += (value - mean) * (value - mean);
    return { name, observed: observed.length, missing: data.rows.length - observed.length, mean,
      deviation: Math.sqrt(square / (observed.length - 1)), minimum: Math.min(...observed), maximum: Math.max(...observed) };
  });
}

function analysis(data, summary, missing, scaling) {
  const rows = missing === 'listwise' ? data.rows.filter(row => !row.values.includes(null))
    : data.rows.map(row => ({ id: row.id, values: row.values.map((value, index) => value === null ? summary[index].mean : value) }));
  const prepared = pca.prepare(rows.map(row => row.values), scaling);
  return { rows, prepared, eigen: eigen.jacobi(prepared.matrix) };
}

function adequacy(correlation, count) {
  const dimension = correlation.length;
  const { inverse, determinant } = matrix.inverseDeterminant(correlation);
  const correlations = [];
  const partials = [];
  const msa = [];
  for (let first = 0; first < dimension; first++) {
    let squared = 0;
    let partialSquared = 0;
    for (let second = 0; second < dimension; second++) {
      if (first === second) continue;
      const partial = -inverse[first][second] / Math.sqrt(inverse[first][first] * inverse[second][second]);
      squared += correlation[first][second] * correlation[first][second];
      partialSquared += partial * partial;
    }
    correlations.push(squared);
    partials.push(partialSquared);
    msa.push(squared / (squared + partialSquared));
  }
  const numerator = sum(correlations);
  const kmo = numerator / (numerator + sum(partials));
  const bartlett = -(count - 1 - (2 * dimension + 5) / 6) * Math.log(determinant);
  return { msa, kmo, determinant, bartlett, degrees: dimension * (dimension - 1) / 2 };
}

function parallelAnalysis(count, dimension, settings) {
  let state = settings.seed;
  const totals = Array(dimension).fill(0);
  for (let iteration = 0; iteration < settings.parallel; iteration++) {
    const rows = matrix.zeros(count, dimension);
    for (let row = 0; row < count; row++) {
      for (let feature = 0; feature < dimension; feature++) {
        state = 48271 * state % 2147483647;
        rows[row][feature] = state / 2147483647;
      }
    }
    const values = eigen.jacobi(pca.prepare(rows, 'correlation').correlation).values;
    const total = sum(values);
    for (let component = 0; component < dimension; component++) totals[component] += values[component] / total;
  }
  return totals.map(total => total / settings.parallel);
}

function retention(values, count, parallel, settings) {
  const dimension = values.length;
  const total = sum(values);
  const average = total / dimension;
  const ratios = values.map(value => value / total);
  const cumulative = [];
  let accumulated = 0;
  for (const value of ratios) {
    accumulated += value;
    cumulative.push(accumulated);
  }
  const broken = [];
  for (let component = 1; component <= dimension; component++) {
    let value = 0;
    for (let index = component; index <= dimension; index++) value += 1 / index;
    broken.push(value / dimension);
  }
  const errors = values.map(value => value * Math.sqrt(2 / count));
  const separated = values.map((value, index) =>
    (index === 0 || Math.abs(value - values[index - 1]) > errors[index])
      && (index === dimension - 1 || Math.abs(value - values[index + 1]) > errors[index]));
  const leading = thresholds => {
    const failed = ratios.findIndex((value, index) => value <= thresholds[index]);
    return failed < 0 ? dimension : failed;
  };
  const criteria = { kaiser: values.filter(value => value > average).length, broken_stick: leading(broken),
    parallel: leading(parallel), cumulative: cumulative.findIndex(value => value >= settings.target) + 1 };
  const selected = /^[0-9]+$/.test(settings.components) ? Number(settings.components) : criteria[settings.components];
  return { total, average, ratios, cumulative, broken, parallel, errors, separated, criteria, retained: Math.max(1, selected) };
}

function criterion(values) {
  const variables = values.length;
  let total = 0;
  for (let component = 0; component < values[0].length; component++) {
    let fourth = 0;
    let second = 0;
    for (let feature = 0; feature < variables; feature++) {
      const value = values[feature][component];
      fourth += (value * value) * (value * value);
      second += value * value;
    }
    total += fourth / variables - (second / variables) * (second / variables);
  }
  return total;
}

function rotateVarimax(values, first, second) {
  let sa = 0;
  let sb = 0;
  let sc = 0;
  let sd = 0;
  for (const row of values) {
    const phi = row[first] * row[first] - row[second] * row[second];
    const psi = 2 * row[first] * row[second];
    sa += phi;
    sb += psi;
    sc += phi * phi - psi * psi;
    sd += 2 * phi * psi;
  }
  const numerator = sd - 2 * sa * sb / values.length;
  const denominator = sc - (sa * sa - sb * sb) / values.length;
  const omega = Math.sqrt(numerator * numerator + denominator * denominator);
  if (omega === 0) return;
  const cosine4 = denominator / omega;
  const sine4 = numerator / omega;
  const cosine2 = Math.sqrt((1 + cosine4) / 2);
  const sine2 = cosine2 === 0 ? 1 : sine4 / (2 * cosine2);
  const cosine1 = Math.sqrt((1 + cosine2) / 2);
  const sine1 = sine2 / (2 * cosine1);
  for (const row of values) {
    const x = row[first];
    const y = row[second];
    row[first] = cosine1 * x + sine1 * y;
    row[second] = -sine1 * x + cosine1 * y;
  }
}

function varimax(loadings, retained, cycles) {
  const eta = loadings.map(row => Math.sqrt(sum(row.slice(0, retained).map(value => value * value))));
  const normalized = loadings.map((row, index) => row.slice(0, retained).map(value => value / eta[index]));
  const criteria = [criterion(normalized)];
  for (let cycle = 0; cycle < cycles; cycle++) {
    for (let first = 0; first < retained - 1; first++) {
      for (let second = first + 1; second < retained; second++) rotateVarimax(normalized, first, second);
    }
    criteria.push(criterion(normalized));
  }
  const columns = Array.from({ length: retained }, (_, index) => {
    const vector = matrix.orient(normalized.map((row, feature) => row[index] * eta[feature]));
    return { index, vector, square: matrix.dot(vector, vector) };
  }).sort((a, b) => b.square - a.square || a.index - b.index);
  for (const column of columns) {
    let largest = -Infinity;
    let closest = 0;
    for (let component = 0; component < retained; component++) {
      const original = matrix.column(loadings, component);
      const congruence = Math.abs(matrix.dot(column.vector, original)
        / Math.sqrt(matrix.dot(column.vector, column.vector) * matrix.dot(original, original)));
      if (congruence > largest) {
        largest = congruence;
        closest = component;
      }
    }
    column.closest = closest;
    column.congruence = largest;
  }
  return { criteria, columns };
}

function diagnostics(row, standardized, result, retained, settings, includeQuality) {
  const scores = pca.scores(standardized, result.vectors);
  const residuals = pca.residuals(standardized, scores, result.vectors, retained);
  const t2 = pca.tSquared(scores, result.values, retained);
  const spe = matrix.dot(residuals, residuals);
  const flag = (t2 > settings.t2Limit ? 'T' : '') + (spe > settings.speLimit ? 'Q' : '');
  const item = { row, standardized, scores, residuals, t2, spe, flag: flag || '-' };
  if (includeQuality) {
    let explained = 0;
    for (let component = 0; component < retained; component++) explained += scores[component] * scores[component];
    item.quality = explained / matrix.dot(standardized, standardized);
    item.t2Contributions = standardized.map((value, feature) => {
      let weighted = 0;
      for (let component = 0; component < retained; component++) weighted += (scores[component] / result.values[component]) * result.vectors[component][feature];
      return value * weighted;
    });
    item.speContributions = residuals.map(value => value * value);
  }
  return item;
}

function supplementaryRows(data, main, retained, training) {
  return data.supplementary.map(row => {
    const standardized = pca.standardize(row.values, main.prepared.means, main.prepared.scales);
    const item = diagnostics(row, standardized, main.eigen, retained, data.settings, false);
    let nearest = 0;
    let distance = Infinity;
    training.forEach((other, index) => {
      let value = 0;
      for (let component = 0; component < retained; component++) {
        const difference = item.scores[component] - other.scores[component];
        value += difference * difference;
      }
      if (value < distance) {
        distance = value;
        nearest = index;
      }
    });
    item.nearest = training[nearest].row.id;
    item.distance = Math.sqrt(distance);
    return item;
  });
}

function scoreSummary(data, main, training, retained) {
  const lines = ['scores', 'component sd min min_id max max_id contributors'];
  for (let component = 0; component < retained; component++) {
    let squared = 0;
    let minimum = training[0];
    let maximum = training[0];
    for (const item of training) {
      squared += item.scores[component] * item.scores[component];
      if (item.scores[component] < minimum.scores[component]) minimum = item;
      if (item.scores[component] > maximum.scores[component]) maximum = item;
    }
    const contributions = training.map(item => ({ id: item.row.id,
      value: item.scores[component] * item.scores[component] / ((training.length - 1) * main.eigen.values[component]) }));
    const leaders = top(contributions, item => item.value, data.settings.top).map(item => item.id + ':' + real(item.value));
    lines.push(fields('pc' + (component + 1), real(Math.sqrt(squared / (training.length - 1))),
      real(minimum.scores[component]), minimum.row.id, real(maximum.scores[component]), maximum.row.id, ...leaders));
  }
  return lines;
}

function sensitivityReport(data, summary, main, retained) {
  const lines = ['sensitivity', 'missing scaling rows sweeps eigenvalues cumulative congruence'];
  for (const missing of ['listwise', 'mean']) {
    for (const scaling of ['covariance', 'correlation']) {
      const other = analysis(data, summary, missing, scaling);
      const total = sum(other.eigen.values);
      let cumulative = 0;
      const congruence = [];
      for (let component = 0; component < retained; component++) {
        cumulative += other.eigen.values[component] / total;
        congruence.push(Math.abs(matrix.dot(other.eigen.vectors[component], main.eigen.vectors[component])));
      }
      lines.push(fields(missing, scaling, other.rows.length, other.eigen.sweeps,
        reals(other.eigen.values.slice(0, retained)), real(cumulative), reals(congruence)));
    }
  }
  return lines;
}

function eigenReport(data, summary, main, measures, retained, power, rotation, training) {
  const settings = data.settings;
  const dimension = data.names.length;
  const incomplete = data.rows.filter(row => row.values.includes(null));
  const parts = [[fields('pca rows', data.rows.length, 'used', main.rows.length, 'variables', dimension,
    'missing', settings.missing, 'scaling', settings.scaling),
  fields('incomplete', incomplete.length, incomplete.length ? incomplete.map(row => row.id).join(' ') : '-')]];
  const variables = ['variable observed missing mean sd min max msa'];
  summary.forEach((item, feature) => variables.push(fields(item.name, item.observed, item.missing, real(item.mean),
    real(item.deviation), real(item.minimum), real(item.maximum), real(measures.msa[feature]))));
  variables.push(fields('adequacy kmo', real(measures.kmo), 'determinant', real(measures.determinant, 6),
    'bartlett', real(measures.bartlett), 'df', measures.degrees));
  parts.push(variables);
  const correlations = [];
  for (let first = 0; first < dimension; first++) {
    for (let second = first + 1; second < dimension; second++) correlations.push({ first, second, value: main.prepared.correlation[first][second] });
  }
  const strongest = top(correlations, item => Math.abs(item.value), settings.top)
    .map(item => data.names[item.first] + ':' + data.names[item.second] + ':' + real(item.value));
  parts.push([fields('matrix', settings.scaling),
    ...main.prepared.matrix.map((row, index) => fields(data.names[index], reals(row))), fields('strongest', ...strongest)]);
  const spectrum = [fields('jacobi sweeps', main.eigen.sweeps),
    fields('eigenvalues total', real(retained.total), 'average', real(retained.average)),
    'k eigenvalue ratio cumulative broken_stick parallel se separated'];
  main.eigen.values.forEach((value, index) => spectrum.push(fields(index + 1, real(value), real(retained.ratios[index]),
    real(retained.cumulative[index]), real(retained.broken[index]), real(retained.parallel[index]),
    real(retained.errors[index]), retained.separated[index] ? 'yes' : 'no')));
  spectrum.push(fields('retention kaiser', retained.criteria.kaiser, 'broken_stick', retained.criteria.broken_stick,
    'parallel', retained.criteria.parallel, 'cumulative', retained.criteria.cumulative, 'target', real(settings.target)),
  fields('components', retained.retained, 'rule', settings.components));
  parts.push(spectrum);
  parts.push(['eigenvectors', fields('variable', ...componentNames('pc', dimension)),
    ...data.names.map((name, feature) => fields(name, reals(main.eigen.vectors.map(vector => vector[feature]))))]);
  parts.push(['power_iteration iterations 1000', 'k jacobi power agree_at match',
    ...power.map((item, index) => fields(index + 1, real(main.eigen.values[index]), real(item.value), item.agreement ?? '-', item.match ? 'yes' : 'no')),
    fields('cross_check', power.filter(item => item.match).length + '/' + dimension)]);
  parts.push(scoreSummary(data, main, training, retained.retained));
  const rotated = [fields('varimax components', retained.retained, 'cycles', settings.cycles)];
  rotation.criteria.forEach((value, cycle) => rotated.push(fields('cycle', cycle, 'criterion', real(value, 6))));
  rotation.columns.forEach((column, index) => rotated.push(fields('rc' + (index + 1), 'ss', real(column.square),
    'ratio', real(column.square / retained.total), 'closest', 'pc' + (column.closest + 1), 'congruence', real(column.congruence))));
  parts.push(rotated, sensitivityReport(data, summary, main, retained.retained));
  return sections(parts);
}

function loadingReport(data, main, loadings, retained, rotation) {
  const lines = [['variable', ...componentNames('pc', retained), 'communality', ...componentNames('rc', retained)].join(',')];
  data.names.forEach((name, feature) => {
    let squared = 0;
    for (let component = 0; component < retained; component++) squared += loadings[feature][component] * loadings[feature][component];
    const values = [...loadings[feature].slice(0, retained), squared / main.prepared.matrix[feature][feature],
      ...rotation.columns.map(column => column.vector[feature])];
    lines.push([name, ...values.map(value => real(value))].join(','));
  });
  return lines;
}

function scoresReport(training, supplementary, retained) {
  const lines = [['id', 'set', ...componentNames('pc', retained)].join(',')];
  for (const [name, items] of [['data', training], ['supplementary', supplementary]]) {
    for (const item of items) lines.push([item.row.id, name, ...item.scores.slice(0, retained).map(value => real(value))].join(','));
  }
  return lines;
}

function outlierReport(data, main, training, supplementary, retained) {
  const lines = [fields('diagnostics components', retained, 't2_limit', real(data.settings.t2Limit), 'spe_limit', real(data.settings.speLimit)),
    'id t2 spe quality flag', ...training.map(item => fields(item.row.id, real(item.t2), real(item.spe), real(item.quality), item.flag)),
    fields('flagged t2', training.filter(item => item.flag.includes('T')).length,
      'spe', training.filter(item => item.flag.includes('Q')).length, 'both', training.filter(item => item.flag === 'TQ').length,
      'any', training.filter(item => item.flag !== '-').length)];
  const parts = [lines];
  for (const statistic of ['t2', 'spe']) {
    const header = [fields('top', statistic), fields('rank id', statistic, 'variable contribution')];
    top(training, item => item[statistic], data.settings.top).forEach((item, rank) => {
      const contributions = statistic === 't2' ? item.t2Contributions : item.speContributions;
      const feature = maximumIndex(contributions);
      header.push(fields(rank + 1, item.row.id, real(item[statistic]), data.names[feature], real(contributions[feature])));
    });
    parts.push(header);
  }
  const reconstruction = ['reconstruction', 'k mean_spe max_spe max_id'];
  for (let components = 1; components < data.names.length; components++) {
    let total = 0;
    let maximum = -Infinity;
    let id = null;
    for (const item of training) {
      const residuals = pca.residuals(item.standardized, item.scores, main.eigen.vectors, components);
      const spe = matrix.dot(residuals, residuals);
      total += spe;
      if (spe > maximum) {
        maximum = spe;
        id = item.row.id;
      }
    }
    reconstruction.push(fields(components, real(total / training.length), real(maximum), id));
  }
  parts.push(reconstruction);
  parts.push(['supplementary', fields('id', ...componentNames('pc', retained), 't2 spe flag nearest distance'),
    ...supplementary.map(item => fields(item.row.id, reals(item.scores.slice(0, retained)),
      real(item.t2), real(item.spe), item.flag, item.nearest, real(item.distance)))]);
  return sections(parts);
}

function axes(grid, position) {
  grid[position.row].fill('-');
  for (const row of grid) row[position.column] = '|';
  grid[position.row][position.column] = '+';
}

function density(grid, positions) {
  const counts = matrix.zeros(grid.length, grid[0].length);
  for (const position of positions) counts[position.row][position.column]++;
  for (let row = 0; row < grid.length; row++) {
    for (let column = 0; column < grid[0].length; column++) {
      const count = counts[row][column];
      if (count > 0) grid[row][column] = count === 1 ? '.' : count <= 3 ? 'o' : '@';
    }
  }
}

function biplotReport(data, training, supplementary, loadings) {
  const width = data.settings.biplotWidth;
  const height = data.settings.biplotHeight;
  const all = [...training, ...supplementary];
  const maximumX = Math.max(...all.map(item => Math.abs(item.scores[0])));
  const maximumY = Math.max(...all.map(item => Math.abs(item.scores[1])));
  const loadingX = Math.max(...loadings.map(row => Math.abs(row[0])));
  const loadingY = Math.max(...loadings.map(row => Math.abs(row[1])));
  const scale = 0.9 * Math.min(maximumX / loadingX, maximumY / loadingY);
  const position = (x, y) => plot.biplotCell(x, y, maximumX, maximumY, width, height);
  const origin = position(0, 0);
  const grid = plot.grid(width, height);
  axes(grid, origin);
  const tips = loadings.map(row => position(scale * row[0], scale * row[1]));
  for (const tip of tips) for (const point of plot.shaft(origin, tip)) grid[point.row][point.column] = point.character;
  const points = training.map(item => position(item.scores[0], item.scores[1]));
  density(grid, points);
  training.forEach((item, index) => {
    if (item.flag !== '-') grid[points[index].row][points[index].column] = 'X';
  });
  for (const item of supplementary) {
    const point = position(item.scores[0], item.scores[1]);
    grid[point.row][point.column] = '*';
  }
  tips.forEach((tip, index) => { grid[tip.row][tip.column] = String.fromCharCode(65 + index); });
  return [fields('biplot pc1 pc2 width', width, 'height', height),
    fields('x', real(-maximumX), real(maximumX), 'y', real(-maximumY), real(maximumY), 'arrow_scale', real(scale)),
    ...plot.frame(grid), ...data.names.map((name, index) => fields(String.fromCharCode(65 + index), name, real(loadings[index][0]), real(loadings[index][1])))];
}

function circleReport(data, main, loadings) {
  const radius = data.settings.radius;
  const centerRow = radius / 2 + 1;
  const centerColumn = radius + 1;
  const grid = plot.grid(2 * radius + 3, radius + 3);
  axes(grid, { row: centerRow, column: centerColumn });
  const inside = (row, column) => (column - centerColumn) * (column - centerColumn)
    + (2 * (row - centerRow)) * (2 * (row - centerRow)) <= radius * radius;
  for (let row = 0; row < grid.length; row++) {
    for (let column = 0; column < grid[0].length; column++) {
      if (inside(row, column) && (!inside(row - 1, column) || !inside(row + 1, column) || !inside(row, column - 1) || !inside(row, column + 1))) {
        grid[row][column] = '.';
      }
    }
  }
  const correlations = loadings.map((row, feature) => row.slice(0, 2).map(value => value / Math.sqrt(main.prepared.matrix[feature][feature])));
  correlations.forEach((point, index) => {
    const row = centerRow - Math.floor(point[1] * (radius / 2) + 0.5);
    const column = centerColumn + Math.floor(point[0] * radius + 0.5);
    grid[row][column] = String.fromCharCode(65 + index);
  });
  return [fields('circle radius', radius), ...plot.frame(grid),
    ...correlations.map((point, index) => fields(String.fromCharCode(65 + index), data.names[index],
      real(point[0]), real(point[1]), real(point[0] * point[0] + point[1] * point[1])))];
}

function diagnosticReport(data, training, supplementary) {
  const settings = data.settings;
  const width = settings.diagnosticWidth;
  const height = settings.diagnosticHeight;
  const maximumX = 2 * settings.t2Limit;
  const maximumY = 2 * settings.speLimit;
  const position = (t2, spe) => plot.diagnosticCell(t2, spe, maximumX, maximumY, width, height);
  const grid = plot.grid(width, height);
  axes(grid, position(settings.t2Limit, settings.speLimit));
  density(grid, training.map(item => position(item.t2, item.spe)));
  for (const item of supplementary) {
    const point = position(item.t2, item.spe);
    grid[point.row][point.column] = '*';
  }
  return [fields('diagnostic width', width, 'height', height, 't2_max', real(maximumX), 'spe_max', real(maximumY)), ...plot.frame(grid)];
}

function plotsReport(data, main, retained, training, supplementary, loadings) {
  const width = data.settings.screeWidth;
  const largest = main.eigen.values[0];
  const kaiser = Math.floor(retained.average / largest * width + 0.5);
  const scree = [fields('scree width', width, 'kaiser_column', kaiser)];
  main.eigen.values.forEach((value, index) => {
    const bar = Math.floor(value / largest * width + 0.5);
    const broken = Math.floor(retained.broken[index] * retained.total / largest * width + 0.5);
    scree.push(fields('|' + plot.scree(width, bar, broken, kaiser) + '|', 'pc' + (index + 1), real(value)));
  });
  return sections([scree, biplotReport(data, training, supplementary, loadings),
    circleReport(data, main, loadings), diagnosticReport(data, training, supplementary)]);
}

function writeLines(filename, lines) {
  fs.writeFileSync('output/' + filename, lines.join('\n') + '\n', 'ascii');
}

function main() {
  const data = readDataset();
  const summary = summarize(data);
  const mainAnalysis = analysis(data, summary, data.settings.missing, data.settings.scaling);
  const measures = adequacy(mainAnalysis.prepared.correlation, mainAnalysis.rows.length);
  const parallel = parallelAnalysis(mainAnalysis.rows.length, data.names.length, data.settings);
  const retained = retention(mainAnalysis.eigen.values, mainAnalysis.rows.length, parallel, data.settings);
  const count = retained.retained;
  const loadings = data.names.map((name, feature) => mainAnalysis.eigen.values.map((value, component) =>
    mainAnalysis.eigen.vectors[component][feature] * Math.sqrt(value)));
  const rotation = varimax(loadings, count, data.settings.cycles);
  const training = mainAnalysis.rows.map((row, index) => diagnostics(row, mainAnalysis.prepared.standardized[index],
    mainAnalysis.eigen, count, data.settings, true));
  const supplementary = supplementaryRows(data, mainAnalysis, count, training);
  const power = eigen.power(mainAnalysis.prepared.matrix, mainAnalysis.eigen);
  const eigenLines = eigenReport(data, summary, mainAnalysis, measures, retained, power, rotation, training);
  const loadingLines = loadingReport(data, mainAnalysis, loadings, count, rotation);
  const scoreLines = scoresReport(training, supplementary, count);
  const outlierLines = outlierReport(data, mainAnalysis, training, supplementary, count);
  const plotLines = plotsReport(data, mainAnalysis, retained, training, supplementary, loadings);
  fs.mkdirSync('output', { recursive: true });
  writeLines('eigen.txt', eigenLines);
  writeLines('loadings.csv', loadingLines);
  writeLines('scores.csv', scoreLines);
  writeLines('outliers.txt', outlierLines);
  writeLines('plots.txt', plotLines);
}

if (require.main === module) main();
