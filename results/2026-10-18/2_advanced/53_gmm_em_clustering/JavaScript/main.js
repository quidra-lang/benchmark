'use strict';

const dataset = require('./dataset');
const gaussian = require('./gaussian');
const em = require('./em');
const kmeans = require('./kmeans');
const {real, frame, write} = require('./report');

const rounded = value => Number(real(value));
const reals = values => values.map(value => real(value)).join(' ');

function summarize(result, K, type, typeIndex, n, tau) {
    const p = {FULL: 6 * K - 1, TIED: 3 * K + 2,
        DIAG: 5 * K - 1, SPHERICAL: 4 * K - 1}[type];
    const assignment = [];
    const maximum = [];
    const sizes = Array(K).fill(0);
    let entropy = 0;
    for (const row of result.responsibilities) {
        let best = 0;
        let terms = 0;
        for (let k = 0; k < K; k++) {
            if (row[k] > row[best]) best = k;
            if (row[k] !== 0) terms += row[k] * Math.log(row[k]);
        }
        assignment.push(best);
        maximum.push(row[best]);
        sizes[best]++;
        entropy += -terms;
    }
    const bic = -2 * result.loglik + p * Math.log(n);
    const aic = -2 * result.loglik + 2 * p;
    const icl = bic + 2 * entropy;
    const N = result.trace.length - 1;
    let settledAt = N;
    for (let t = N - 1; t >= 0; t--) {
        if (Math.abs(result.trace[t] - result.loglik) > tau) break;
        settledAt = t;
    }
    const largestIncrease = {iteration: 1, value: result.trace[1] - result.trace[0]};
    const violations = [];
    for (let t = 1; t <= N; t++) {
        const increase = result.trace[t] - result.trace[t - 1];
        if (increase > largestIncrease.value) Object.assign(largestIncrease, {iteration: t, value: increase});
        if (result.trace[t] < result.trace[t - 1] - 0.000001 * Math.abs(result.trace[t - 1])) {
            violations.push(t);
        }
    }
    return {...result, K, type, typeIndex, p, assignment, maximum, sizes, entropy,
        meanEntropy: entropy / n, bic, aic, icl, settledAt, largestIncrease, violations};
}

function compareModels(first, second, criterion) {
    return rounded(first[criterion]) - rounded(second[criterion])
        || first.p - second.p || first.K - second.K || first.typeIndex - second.typeIndex;
}

function contingency(first, second, firstK, secondK) {
    const table = Array.from({length: firstK}, () => Array(secondK).fill(0));
    for (let i = 0; i < first.length; i++) table[first[i]][second[i]]++;
    return table;
}

function adjustedRand(table, n) {
    const choose2 = count => count * (count - 1) / 2;
    const columns = Array(table[0].length).fill(0);
    let S = 0;
    let A = 0;
    for (const row of table) {
        let total = 0;
        for (let b = 0; b < row.length; b++) {
            S += choose2(row[b]);
            total += row[b];
            columns[b] += row[b];
        }
        A += choose2(total);
    }
    let B = 0;
    for (const count of columns) B += choose2(count);
    const Z = choose2(n);
    let numerator = 2 * (Z * S - A * B);
    let denominator = Z * (A + B) - 2 * A * B;
    if (denominator === 0) return {numerator: 1, denominator: 1};
    if (denominator < 0) {
        numerator = -numerator;
        denominator = -denominator;
    }
    let a = Math.abs(numerator);
    let b = denominator;
    while (b !== 0) [a, b] = [b, a % b];
    return {numerator: numerator / a, denominator: denominator / a};
}

function fractionText({numerator, denominator}) {
    return `${numerator}/${denominator} ${real(numerator / denominator)}`;
}

function evaluatePartition(points, assignment, K) {
    const members = Array.from({length: K}, () => []);
    for (let i = 0; i < points.length; i++) members[assignment[i]].push(i);
    const active = members.flatMap((indices, k) => indices.length ? [k] : []);
    const clusterSilhouettes = Array(K).fill(null);
    if (active.length < 2) return {silhouette: null, ch: null, db: null, clusterSilhouettes};
    const centers = members.map(indices => {
        if (indices.length === 0) return null;
        let x = 0;
        let y = 0;
        for (const i of indices) {
            x += points[i].x;
            y += points[i].y;
        }
        return {x: x / indices.length, y: y / indices.length};
    });
    let silhouetteSum = 0;
    const clusterSums = Array(K).fill(0);
    for (let i = 0; i < points.length; i++) {
        const own = assignment[i];
        let silhouette = 0;
        if (members[own].length > 1) {
            let inside = 0;
            for (const j of members[own]) {
                if (j !== i) inside += kmeans.distance(points[i], points[j]);
            }
            const a = inside / (members[own].length - 1);
            let b = Infinity;
            for (const other of active) {
                if (other === own) continue;
                let outside = 0;
                for (const j of members[other]) outside += kmeans.distance(points[i], points[j]);
                b = Math.min(b, outside / members[other].length);
            }
            silhouette = (b - a) / Math.max(a, b);
        }
        silhouetteSum += silhouette;
        clusterSums[own] += silhouette;
    }
    for (const k of active) clusterSilhouettes[k] = clusterSums[k] / members[k].length;
    let x = 0;
    let y = 0;
    for (const point of points) {
        x += point.x;
        y += point.y;
    }
    const grand = {x: x / points.length, y: y / points.length};
    let between = 0;
    for (const k of active) between += members[k].length * kmeans.squaredDistance(centers[k], grand);
    let within = 0;
    for (let i = 0; i < points.length; i++) within += kmeans.squaredDistance(points[i], centers[assignment[i]]);
    const ch = (between / (active.length - 1)) / (within / (points.length - active.length));
    const spreads = Array(K).fill(0);
    for (const k of active) {
        let total = 0;
        for (const i of members[k]) total += kmeans.distance(points[i], centers[k]);
        spreads[k] = total / members[k].length;
    }
    let dbSum = 0;
    for (const k of active) {
        let largest = -Infinity;
        for (const other of active) {
            if (other !== k) {
                const ratio = (spreads[k] + spreads[other]) / kmeans.distance(centers[k], centers[other]);
                largest = Math.max(largest, ratio);
            }
        }
        dbSum += largest;
    }
    return {silhouette: silhouetteSum / points.length, ch, db: dbSum / active.length, clusterSilhouettes};
}

function parents(table) {
    const values = [];
    const shared = [];
    for (let b = 0; b < table[0].length; b++) {
        let parent = 0;
        for (let a = 1; a < table.length; a++) {
            if (table[a][b] > table[parent][b]) parent = a;
        }
        values.push(table[parent][b] === 0 ? '-' : parent + 1);
        shared.push(table[parent][b]);
    }
    return {values, shared};
}

function matching(table) {
    const K = table.length;
    const used = Array(K).fill(false);
    const permutation = [];
    let agreement = -1;
    let best;
    function visit(column, score) {
        if (column === K) {
            if (score > agreement) {
                agreement = score;
                best = permutation.slice();
            }
            return;
        }
        for (let row = 0; row < K; row++) {
            if (used[row]) continue;
            used[row] = true;
            permutation.push(row);
            visit(column + 1, score + table[row][column]);
            permutation.pop();
            used[row] = false;
        }
    }
    visit(0, 0);
    return {permutation: best, agreement};
}

function modelBlock(model) {
    const lines = [
        `model K=${model.K} type=${model.type}`, `parameters ${model.p}`,
        `loglik ${real(model.loglik)}`, `bic ${real(model.bic)}`, `aic ${real(model.aic)}`,
        `icl ${real(model.icl)}`, `mean_entropy ${real(model.meanEntropy)}`,
        `settled_at ${model.settledAt}`,
        `largest_increase iteration ${model.largestIncrease.iteration} value ${real(model.largestIncrease.value)}`,
        `violations ${model.violations.length}`, `sizes ${model.sizes.join(' ')}`
    ];
    model.components.forEach((component, k) => {
        const eigen = gaussian.eigen(component);
        const axes = [Math.sqrt(eigen.lambda1), Math.sqrt(eigen.lambda2)];
        lines.push(`component ${k + 1} weight ${real(component.w)} mean ${reals([component.mx, component.my])}`
            + ` cov ${reals([component.a, component.b, component.c])} axes ${reals(axes)} angle ${real(eigen.angle)}`);
    });
    return lines;
}

function comparisonPart(comparison, previous) {
    const {K, model, km, gmmMetrics, kmMetrics, ari} = comparison;
    const lines = [
        `K=${K} type=${model.type} bic ${real(model.bic)}`,
        `  kmeans iterations ${km.iterations} inertia ${real(km.inertia)}`,
        `  ari ${fractionText(ari)}`,
        `  silhouette gmm ${real(gmmMetrics.silhouette)} kmeans ${real(kmMetrics.silhouette)}`,
        `  calinski_harabasz gmm ${real(gmmMetrics.ch)} kmeans ${real(kmMetrics.ch)}`,
        `  davies_bouldin gmm ${real(gmmMetrics.db)} kmeans ${real(kmMetrics.db)}`
    ];
    if (previous) {
        const table = contingency(previous.model.assignment, model.assignment, previous.K, K);
        const lineage = parents(table);
        lines.push(`  parents K=${previous.K} ${lineage.values.join(' ')} shared ${lineage.shared.join(' ')}`);
    }
    return lines;
}

function componentDetails(points, model, metrics, edges, quadratics) {
    const lines = ['selected components'];
    model.components.forEach((component, k) => {
        const eigen = gaussian.eigen(component);
        const major = Math.sqrt(eigen.lambda1);
        const minor = Math.sqrt(eigen.lambda2);
        const area = Math.PI * Math.sqrt(eigen.lambda1 * eigen.lambda2);
        const correlation = component.b / Math.sqrt(component.a * component.c);
        let softSize = 0;
        let inside1 = 0;
        let inside2 = 0;
        const observed = Array(edges.length + 1).fill(0);
        for (let i = 0; i < points.length; i++) {
            softSize += model.responsibilities[i][k];
            if (model.assignment[i] !== k) continue;
            const q = quadratics[i][k];
            if (q <= 1) inside1++;
            if (q <= 4) inside2++;
            const rho = Math.sqrt(q);
            let bin = 0;
            while (bin < edges.length && rho >= edges[bin]) bin++;
            observed[bin]++;
        }
        const expected = [];
        let chi2 = 0;
        for (let bin = 0; bin <= edges.length; bin++) {
            const lower = bin === 0 ? 0 : edges[bin - 1];
            const tail = bin === edges.length ? 0 : Math.exp(-edges[bin] * edges[bin] / 2);
            const value = model.sizes[k] * (Math.exp(-lower * lower / 2) - tail);
            expected.push(value);
            const difference = observed[bin] - value;
            chi2 += difference * difference / value;
        }
        lines.push(`component ${k + 1} weight ${real(component.w)} size ${model.sizes[k]} soft_size ${real(softSize)}`
            + ` mean ${reals([component.mx, component.my])}`);
        lines.push(`  cov ${reals([component.a, component.b, component.c])} corr ${real(correlation)}`);
        lines.push(`  eigen ${reals([eigen.lambda1, eigen.lambda2])} direction ${reals([eigen.ux, eigen.uy])} angle ${real(eigen.angle)}`);
        lines.push(`  axes_1sigma ${reals([major, minor])} axes_2sigma ${reals([2 * major, 2 * minor])}`);
        lines.push(`  inside_1sigma ${inside1} inside_2sigma ${inside2} area_1sigma ${real(area)}`);
        lines.push(`  silhouette ${real(metrics.clusterSilhouettes[k])}`);
        lines.push(`  gof observed ${observed.join(' ')} expected ${reals(expected)} chi2 ${real(chi2)}`);
    });
    return lines;
}

function overlapPart(model) {
    const lines = ['overlap'];
    for (let a = 0; a < model.K; a++) {
        for (let b = a + 1; b < model.K; b++) {
            const D = gaussian.bhattacharyya(model.components[a], model.components[b]);
            let shared = 0;
            for (const row of model.responsibilities) shared += row[a] * row[b];
            lines.push(`${a + 1}-${b + 1} bhattacharyya ${real(D)} coefficient ${real(Math.exp(-D))} shared ${real(shared)}`);
        }
    }
    if (model.K === 1) lines.push('none');
    return lines;
}

function mergedState(responsibilities, clusters) {
    let entropy = 0;
    const sizes = clusters.map(() => 0);
    for (const row of responsibilities) {
        const masses = clusters.map(cluster => {
            let total = 0;
            for (const k of cluster) total += row[k];
            return total;
        });
        let terms = 0;
        let best = 0;
        for (let c = 0; c < clusters.length; c++) {
            if (masses[c] !== 0) terms += masses[c] * Math.log(masses[c]);
            if (masses[c] > masses[best]) best = c;
        }
        entropy += -terms;
        sizes[best]++;
    }
    return {entropy, sizes};
}

function mergingPart(model) {
    let clusters = Array.from({length: model.K}, (_, k) => [k]);
    const start = mergedState(model.responsibilities, clusters);
    const lines = ['merging', `start entropy ${real(start.entropy)}`];
    const name = cluster => cluster.map(k => k + 1).join('+');
    for (let step = 1; clusters.length > 1; step++) {
        let best = null;
        for (let a = 0; a < clusters.length; a++) {
            for (let b = a + 1; b < clusters.length; b++) {
                const next = clusters.flatMap((cluster, c) => {
                    if (c === b) return [];
                    return [c === a ? [...cluster, ...clusters[b]].sort((x, y) => x - y) : cluster];
                });
                const state = mergedState(model.responsibilities, next);
                if (best === null || rounded(state.entropy) < rounded(best.state.entropy)) {
                    best = {a, b, clusters: next, state};
                }
            }
        }
        lines.push(`step ${step} merge ${name(clusters[best.a])} ${name(clusters[best.b])}`
            + ` entropy ${real(best.state.entropy)} sizes ${best.state.sizes.join(' ')}`);
        clusters = best.clusters;
    }
    return lines;
}

function kmeansPart(points, model, comparison) {
    const {km, table, ari} = comparison;
    const match = matching(table);
    const lines = [`kmeans K=${model.K}`, `iterations ${km.iterations}`,
        `inertia ${real(km.inertia)}`, `sizes ${km.sizes.join(' ')}`];
    km.centers.forEach((center, k) => lines.push(`center ${k + 1} ${reals([center.x, center.y])}`));
    lines.push('contingency', ...table.map(row => row.join(' ')), `ari ${fractionText(ari)}`);
    lines.push(`matching ${match.permutation.map(k => k + 1).join(' ')}`);
    lines.push(`agreement ${match.agreement}/${points.length} ${real(match.agreement / points.length)}`);
    let disagreements = 0;
    for (let i = 0; i < points.length; i++) {
        if (match.permutation[km.assignment[i]] !== model.assignment[i]) {
            lines.push(`disagree ${points[i].id} gmm ${model.assignment[i] + 1}`
                + ` kmeans ${km.assignment[i] + 1} max ${real(model.maximum[i])}`);
            disagreements++;
        }
    }
    lines.push(`disagreements ${disagreements}`);
    return lines;
}

function refitPart(points, params, model, km) {
    const initial = km.centers.map((center, k) => {
        let A = 0;
        let B = 0;
        let C = 0;
        for (let i = 0; i < points.length; i++) {
            if (km.assignment[i] !== k) continue;
            const dx = points[i].x - center.x;
            const dy = points[i].y - center.y;
            A += dx * dx;
            B += dx * dy;
            C += dy * dy;
        }
        return {w: km.sizes[k] / points.length, mx: center.x, my: center.y,
            a: A / km.sizes[k] + params.eps, b: B / km.sizes[k], c: C / km.sizes[k] + params.eps};
    });
    const result = em.fit(points, initial, model.type, params.iterations, params.eps);
    const refit = summarize(result, model.K, model.type, model.typeIndex, points.length, params.tau);
    const ari = adjustedRand(contingency(model.assignment, refit.assignment, model.K, model.K), points.length);
    return [`refit_from_kmeans K=${model.K} type=${model.type}`,
        `loglik ${real(refit.loglik)} bic ${real(refit.bic)} settled_at ${refit.settledAt}`,
        `sizes ${refit.sizes.join(' ')}`, `ari_vs_selected ${fractionText(ari)}`];
}

function crossValidationPart(points, params, model, initial) {
    const lines = [`cross_validation K=${model.K} type=${model.type} folds ${params.folds}`];
    let total = 0;
    for (let fold = 0; fold < params.folds; fold++) {
        const training = points.filter((_, i) => i % params.folds !== fold);
        const test = points.filter((_, i) => i % params.folds === fold);
        const fitted = em.fit(training, initial, model.type, params.iterations, params.eps);
        const trainLoglik = fitted.loglik / training.length;
        const testLoglik = em.expectation(test, fitted.components).loglik / test.length;
        total += testLoglik;
        lines.push(`fold ${fold + 1} train ${training.length} test ${test.length}`
            + ` train_loglik ${real(trainLoglik)} test_loglik ${real(testLoglik)}`);
    }
    lines.push(`mean_test_loglik ${real(total / params.folds)}`);
    return lines;
}

function exceptionalParts(points, params, model, quadratics) {
    const indices = points.map((_, i) => i);
    const uncertain = indices.filter(i => model.maximum[i] < params.uncertain)
        .sort((i, j) => rounded(model.maximum[i]) - rounded(model.maximum[j]) || i - j);
    const outliers = indices.filter(i => model.logDensities[i] < params.lowDensity)
        .sort((i, j) => rounded(model.logDensities[i]) - rounded(model.logDensities[j]) || i - j);
    const uncertainLines = [`uncertain threshold ${real(params.uncertain)}`];
    for (const i of uncertain) {
        uncertainLines.push(`${points[i].id} component ${model.assignment[i] + 1} max ${real(model.maximum[i])}`
            + ` responsibilities ${reals(model.responsibilities[i])}`);
    }
    uncertainLines.push(`count ${uncertain.length}`);
    const outlierLines = [`outliers threshold ${real(params.lowDensity)}`];
    for (const i of outliers) {
        outlierLines.push(`${points[i].id} component ${model.assignment[i] + 1} log_density ${real(model.logDensities[i])}`
            + ` q ${real(quadratics[i][model.assignment[i]])}`);
    }
    outlierLines.push(`count ${outliers.length}`);
    return [uncertainLines, outlierLines];
}

function selectionReport(points, params, initial, models, ranks, comparisons) {
    const selected = ranks.bic[0];
    const aicRanks = new Map(ranks.aic.map((model, i) => [model, i + 1]));
    const iclRanks = new Map(ranks.icl.map((model, i) => [model, i + 1]));
    const ranking = ['ranking by bic', 'rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank'];
    ranks.bic.forEach((model, i) => {
        const delta = rounded(model.bic) - rounded(selected.bic);
        ranking.push(`${i + 1} ${model.K} ${model.type} ${model.p} ${real(model.loglik)} ${real(model.bic)}`
            + ` ${real(delta)} ${real(model.aic)} ${aicRanks.get(model)} ${real(model.icl)} ${iclRanks.get(model)}`);
    });
    ranking.push(`selected K=${selected.K} type=${selected.type}`);
    ranking.push(`best_aic K=${ranks.aic[0].K} type=${ranks.aic[0].type}`);
    ranking.push(`best_icl K=${ranks.icl[0].K} type=${ranks.icl[0].type}`);
    const byType = ['best K per type'];
    for (const type of params.types) {
        const best = criterion => ranks[criterion].find(model => model.type === type).K;
        byType.push(`${type} bic ${best('bic')} aic ${best('aic')} icl ${best('icl')}`);
    }
    const parts = [ranking, byType];
    comparisons.forEach((comparison, i) => parts.push(comparisonPart(comparison, comparisons[i - 1])));
    const violations = ['violations'];
    for (const model of models) {
        for (const t of model.violations) {
            violations.push(`K=${model.K} type=${model.type} iteration ${t}`
                + ` previous ${real(model.trace[t - 1])} current ${real(model.trace[t])}`);
        }
    }
    if (violations.length === 1) violations.push('none');
    parts.push(violations);
    const comparison = comparisons.find(item => item.K === selected.K);
    const quadratics = points.map(point => selected.components.map(component => gaussian.quadratic(point, component)));
    parts.push(componentDetails(points, selected, comparison.gmmMetrics, params.edges, quadratics));
    parts.push(overlapPart(selected), mergingPart(selected), kmeansPart(points, selected, comparison));
    parts.push(refitPart(points, params, selected, comparison.km));
    parts.push(crossValidationPart(points, params, selected, initial.get(selected.K)));
    parts.push(...exceptionalParts(points, params, selected, quadratics));
    return parts.flatMap((part, i) => i === 0 ? part : ['', ...part]);
}

function mapReport(points, params, model) {
    const {xmin, xmax, ymin, ymax, width, height} = params;
    const stepX = (xmax - xmin) / width;
    const stepY = (ymax - ymin) / height;
    const levels = ' .:-=+*#%@';
    const cells = [];
    let fmax = 0;
    let mass = 0;
    for (let r = 0; r < height; r++) {
        for (let c = 0; c < width; c++) {
            const point = {x: xmin + (c + 0.5) * stepX, y: ymax - (r + 0.5) * stepY};
            const logs = model.components.map(component => gaussian.logWeighted(point, component));
            let density = 0;
            let best = 0;
            for (let k = 0; k < model.K; k++) {
                density += Math.exp(logs[k]);
                if (logs[k] > logs[best]) best = k;
            }
            fmax = Math.max(fmax, density);
            mass += density;
            let uncertainty = ' ';
            if (model.K > 1) {
                const exponents = logs.map(value => Math.exp(value - logs[best]));
                let total = 0;
                for (const value of exponents) total += value;
                let terms = 0;
                for (const value of exponents) {
                    const responsibility = value / total;
                    if (responsibility !== 0) terms += responsibility * Math.log(responsibility);
                }
                const level = Math.max(0, Math.min(9, Math.floor(10 * -terms / Math.log(model.K))));
                uncertainty = levels[level];
            }
            cells.push({density, region: String(best + 1), uncertainty,
                q: model.components.map(component => gaussian.quadratic(point, component))});
        }
    }
    mass = mass * stepX * stepY;
    function cellIndex({x, y}) {
        const c = Math.floor((x - xmin) / stepX);
        const r = Math.floor((ymax - y) / stepY);
        return c >= 0 && c < width && r >= 0 && r < height ? r * width + c : -1;
    }
    const histogram = Array(10).fill(0);
    const densityChars = cells.map(cell => {
        const level = Math.min(9, Math.floor(10 * cell.density / fmax));
        histogram[level]++;
        return levels[level];
    });
    model.components.forEach((component, k) => {
        const index = cellIndex({x: component.mx, y: component.my});
        if (index !== -1) densityChars[index] = String(k + 1);
    });
    const occupants = cells.map(() => 0);
    let outside = 0;
    points.forEach((point, i) => {
        const index = cellIndex(point);
        if (index === -1) {
            outside++;
        } else {
            const component = model.assignment[i] + 1;
            if (occupants[index] === 0) occupants[index] = component;
            else if (occupants[index] !== component) occupants[index] = -1;
        }
    });
    const pointChars = cells.map((cell, index) => {
        if (occupants[index] === -1) return '*';
        if (occupants[index] > 0) return String(occupants[index]);
        const r = Math.floor(index / width);
        const c = index % width;
        const neighbors = [];
        if (r > 0) neighbors.push(index - width);
        if (r + 1 < height) neighbors.push(index + width);
        if (c > 0) neighbors.push(index - 1);
        if (c + 1 < width) neighbors.push(index + 1);
        for (let k = 0; k < model.K; k++) {
            if (cell.q[k] <= 4 && neighbors.some(other => cells[other].q[k] > 4)) return '.';
        }
        return ' ';
    });
    const rows = characters => Array.from({length: height}, (_, r) => characters.slice(r * width, (r + 1) * width));
    const lines = [`density K=${model.K} type=${model.type}`,
        `x ${real(xmin)} ${real(xmax)} y ${real(ymin)} ${real(ymax)} grid ${width}x${height}`,
        `max_density ${real(fmax, 6)} mass_in_map ${real(mass)}`, ...frame(rows(densityChars))];
    for (let level = 0; level < 10; level++) {
        lines.push(`level ${level} "${levels[level]}" from ${real(level * fmax / 10, 6)} cells ${histogram[level]}`);
    }
    lines.push('', 'regions', ...frame(rows(cells.map(cell => cell.region))));
    lines.push('', 'uncertainty', ...frame(rows(cells.map(cell => cell.uncertainty))));
    lines.push('', 'points', ...frame(rows(pointChars)), `outside ${outside}`);
    return lines;
}

function main() {
    const {points, params, initial} = dataset.read();
    const models = [];
    const kmeansModels = new Map();
    for (const K of params.ks) {
        params.types.forEach((type, typeIndex) => {
            const result = em.fit(points, initial.get(K), type, params.iterations, params.eps);
            models.push(summarize(result, K, type, typeIndex, points.length, params.tau));
        });
        kmeansModels.set(K, kmeans.fit(points, initial.get(K), params.kmeansMax));
    }
    const ranks = {};
    for (const criterion of ['bic', 'aic', 'icl']) {
        ranks[criterion] = models.toSorted((a, b) => compareModels(a, b, criterion));
    }
    const selected = ranks.bic[0];
    const comparisons = params.ks.map(K => {
        const model = ranks.bic.find(item => item.K === K);
        const km = kmeansModels.get(K);
        const table = contingency(model.assignment, km.assignment, K, K);
        return {K, model, km, table, ari: adjustedRand(table, points.length),
            gmmMetrics: evaluatePartition(points, model.assignment, K),
            kmMetrics: evaluatePartition(points, km.assignment, K)};
    });
    const modelLines = models.flatMap((model, i) => i === 0 ? modelBlock(model) : ['', ...modelBlock(model)]);
    const traceLines = ['K,type,iteration,loglik'];
    for (const model of models) {
        model.trace.forEach((value, t) => traceLines.push(`${model.K},${model.type},${t},${real(value)}`));
    }
    const assignmentLines = ['id,component,max_responsibility,log_density,kmeans_cluster'];
    const selectedKmeans = kmeansModels.get(selected.K);
    points.forEach((point, i) => {
        assignmentLines.push(`${point.id},${selected.assignment[i] + 1},${real(selected.maximum[i])},`
            + `${real(selected.logDensities[i])},${selectedKmeans.assignment[i] + 1}`);
    });
    const selectionLines = selectionReport(points, params, initial, models, ranks, comparisons);
    const mapLines = mapReport(points, params, selected);
    write('models.txt', modelLines);
    write('loglik_trace.csv', traceLines);
    write('assignments.csv', assignmentLines);
    write('selection.txt', selectionLines);
    write('density_map.txt', mapLines);
}

main();
