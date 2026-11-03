'use strict';

const { readDataset } = require('./dataset');
const { Minstd } = require('./minstd');
const { sum, sorted, mean, Md, med, trim, moments, sd, mad, Qn, wins, mdiff, mratio,
    hl, sp, cd, corr, drawIndices, ordinaryIndices, balancedIndices, without, meanAndSe, Phi, PhiInv } = require('./resampling');
const { choices, contrast, doubledRanks, tieCounts, divide, anova, kruskal } = require('./tests');
const { real, pValue, numberList, binNumber, bar, writeLines } = require('./report');

const GROUP_NAMES = ['mean', 'median', 'trimmed_mean', 'sd'];
const GROUP_FUNCTIONS = [mean, med, trim, sd];
const PAIR_NAMES = ['mean_diff', 'median_ratio', 'hodges_lehmann', 'cohen_d'];
const PAIR_FUNCTIONS = [mdiff, mratio, hl, cd];
const TEST_NAMES = ['mean', 'median', 'ranksum', 'absdev'];
const sampleStatistics = sample => GROUP_FUNCTIONS.map(statistic => statistic(sample));
const pairStatistics = (x, y) => PAIR_FUNCTIONS.map(statistic => statistic(x, y));
const pairName = pair => pair.x.name + '-' + pair.y.name;

function describe(kind, name, sample, lo, hi, stems) {
    const order = sorted(sample);
    const count = sample.length;
    const center = mean(sample);
    const moment = moments(sample);
    const winsorized = wins(sample);
    const q1 = Qn(sample, 25);
    const q3 = Qn(sample, 75);
    const outliers = [];
    const inside = [];
    for (let index = 0; index < count; index++) {
        const value = sample[index];
        if (200 * value < 5 * q1 - 3 * q3 || 200 * value > 5 * q3 - 3 * q1) outliers.push(index + 1);
        else inside.push(value);
    }
    const w1 = Math.min(...inside);
    const w2 = Math.max(...inside);
    const delta = 100 * (hi - lo);
    const position = value => Math.floor((120 * (value - 100 * lo) + delta) / (2 * delta));
    const band = Array(61).fill('.');
    for (let index = position(100 * w1); index <= position(100 * w2); index++) band[index] = '-';
    for (let index = position(q1); index <= position(q3); index++) band[index] = '=';
    band[position(Qn(sample, 50))] = '|';
    for (const number of outliers) band[position(100 * sample[number - 1])] = 'o';
    const lines = [
        `${kind} ${name}`, `n ${count}`, `mean ${real(center)}`, `median ${real(med(sample))}`,
        `trimmed_mean ${real(trim(sample))} trim ${Math.floor(count / 10)}`,
        `winsorized_mean ${real(mean(winsorized))} winsorized_sd ${real(sd(winsorized))}`,
        `sd ${real(moment.sd)}`, `se_mean ${real(moment.sd / Math.sqrt(count))}`,
        `cv ${real(moment.sd / center)}`,
        `skewness ${real(moment.m3 / (moment.m2 * Math.sqrt(moment.m2)))}`,
        `kurtosis ${real(moment.m4 / (moment.m2 * moment.m2) - 3)}`,
        `mad ${real(mad(sample))}`, `min ${real(order[0] / 100)}`,
        `q1 ${real(q1 / 10000)}`, `q3 ${real(q3 / 10000)}`, `iqr ${real((q3 - q1) / 10000)}`,
        `max ${real(order.at(-1) / 100)}`,
        `percentiles p05 ${real(Qn(sample, 5) / 10000)} p10 ${real(Qn(sample, 10) / 10000)}`
            + ` p90 ${real(Qn(sample, 90) / 10000)} p95 ${real(Qn(sample, 95) / 10000)}`,
        `whiskers ${real(w1 / 100)} ${real(w2 / 100)}`,
        'outliers ' + numberList(outliers), 'box ' + band.join(''),
    ];
    if (stems) {
        for (let stem = Math.floor(order[0] / 100); stem <= Math.floor(order.at(-1) / 100); stem++) {
            const leaves = order.filter(value => Math.floor(value / 100) === stem)
                .map(value => Math.floor((value % 100) / 10)).join('');
            lines.push('stem ' + stem + (leaves === '' ? '' : ' ' + leaves));
        }
    }
    return lines;
}

function descriptiveLines(data) {
    const all = data.groups.flatMap(group => group.sample);
    const lo = Math.min(...all);
    const hi = Math.max(...all);
    const lines = [`groups ${data.groups.length} observations ${all.length}`];
    for (const group of data.groups) lines.push(...describe('group', group.name, group.sample, lo, hi, true));
    lines.push('paired subjects ' + data.before.length);
    const together = [...data.before, ...data.after];
    const pairedLo = Math.min(...together);
    const pairedHi = Math.max(...together);
    lines.push(...describe('series', 'before', data.before, pairedLo, pairedHi, false));
    lines.push(...describe('series', 'after', data.after, pairedLo, pairedHi, false));
    lines.push(...describe('series', 'diff', data.differences, Math.min(...data.differences), Math.max(...data.differences), false));
    return lines;
}

function bootstrapSamples(sample, indices) {
    const samples = [];
    const values = GROUP_NAMES.map(() => []);
    for (const chosen of indices) {
        const replicate = chosen.map(index => sample[index]);
        samples.push(replicate);
        const statistics = sampleStatistics(replicate);
        for (let statistic = 0; statistic < values.length; statistic++) values[statistic].push(statistics[statistic]);
    }
    return { samples, values, indices };
}

function bootstrapSummary(estimate, values, confidence) {
    const { average, se } = meanAndSe(values);
    const order = sorted(values);
    const rankLo = Math.floor((values.length + 1) * (100 - confidence) / 200);
    const rankHi = values.length + 1 - rankLo;
    const lo = order[rankLo - 1];
    const hi = order[rankHi - 1];
    return { estimate, average, se, bias: average - estimate, lo, hi,
        basicLo: 2 * estimate - hi, basicHi: 2 * estimate - lo, order, rankLo, rankHi };
}

function bootstrapLines(data) {
    const lines = ['group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi'];
    function append(name, statistic, summary) {
        lines.push([name, statistic, ...[summary.estimate, summary.se, summary.bias, summary.lo,
            summary.hi, summary.basicLo, summary.basicHi].map(real)].join(','));
    }
    for (const group of data.groups) {
        for (let statistic = 0; statistic < 4; statistic++) append(group.name, GROUP_NAMES[statistic], group.summaries[statistic]);
        for (let statistic = 0; statistic < 4; statistic++) {
            append(group.name, 'balanced_' + GROUP_NAMES[statistic], group.balancedSummaries[statistic]);
        }
    }
    for (const pair of data.pairs) {
        for (let statistic = 0; statistic < 4; statistic++) append(pairName(pair), PAIR_NAMES[statistic], pair.summaries[statistic]);
    }
    return lines;
}

function histogram(name, statistic, values, summary, bins) {
    const lo = summary.order[0];
    const hi = summary.order.at(-1);
    const counts = Array(bins).fill(0);
    for (const value of values) counts[binNumber(value, lo, hi, bins) - 1]++;
    const top = Math.max(...counts);
    const estimateBin = summary.estimate < lo || summary.estimate > hi ? null : binNumber(summary.estimate, lo, hi, bins);
    const lowerBin = binNumber(summary.lo, lo, hi, bins);
    const upperBin = binNumber(summary.hi, lo, hi, bins);
    const lines = [`histogram ${name} ${statistic} min ${real(lo)} max ${real(hi)} width ${real((hi - lo) / bins)}`
        + ` top ${top} estimate_bin ${estimateBin === null ? 'none' : estimateBin}`];
    const convergence = [];
    for (let index = 1; index <= 4; index++) {
        const count = Math.floor(index * values.length / 4);
        convergence.push(`${count}:${real(meanAndSe(values.slice(0, count)).se)}`);
    }
    lines.push('convergence ' + convergence.join(' '));
    for (let index = 0; index < bins; index++) {
        let line = `bin ${index + 1} ${real(lo + (hi - lo) * index / bins)} ${counts[index]}`;
        if (counts[index] > 0) line += ' ' + bar(counts[index], top);
        if (index + 1 === lowerBin) line += ' L';
        if (index + 1 === estimateBin) line += ' E';
        if (index + 1 === upperBin) line += ' H';
        lines.push(line);
    }
    return lines;
}

function histogramLines(data) {
    const lines = [];
    for (const group of data.groups) {
        for (let statistic = 0; statistic < 4; statistic++) {
            lines.push(...histogram(group.name, GROUP_NAMES[statistic], group.ordinary.values[statistic],
                group.summaries[statistic], data.settings.bins));
        }
    }
    for (const pair of data.pairs) {
        for (let statistic = 0; statistic < 4; statistic++) {
            lines.push(...histogram(pairName(pair), PAIR_NAMES[statistic], pair.values[statistic],
                pair.summaries[statistic], data.settings.bins));
        }
    }
    return lines;
}

function jackknifeSummary(values, estimate) {
    const average = sum(values) / values.length;
    let squared = 0;
    for (const value of values) {
        const difference = value - average;
        squared += difference * difference;
    }
    const variance = (values.length - 1) * squared / values.length;
    return { average, bias: (values.length - 1) * (average - estimate), variance, se: Math.sqrt(variance) };
}

function groupJackknife(group, zL) {
    const sample = group.sample;
    const n = sample.length;
    const deleted = sample.map((value, index) => sampleStatistics(without(sample, index)));
    const values = GROUP_NAMES.map((name, statistic) => deleted.map(row => row[statistic]));
    const summaries = values.map((column, statistic) => jackknifeSummary(column, group.estimates[statistic]));
    const lines = [`group ${group.name} n ${n}`];
    for (let statistic = 0; statistic < 4; statistic++) {
        const jack = summaries[statistic];
        lines.push(`jackknife ${GROUP_NAMES[statistic]} estimate ${real(group.estimates[statistic])}`
            + ` average ${real(jack.average)} bias ${real(jack.bias)} se ${real(jack.se)}`);
    }
    for (let statistic = 0; statistic < 4; statistic++) {
        const replicates = group.ordinary.values[statistic];
        const count = replicates.filter(value => value < group.estimates[statistic]).length;
        const z0 = PhiInv(count / replicates.length);
        let v2 = 0;
        let v3 = 0;
        for (const value of values[statistic]) {
            const difference = summaries[statistic].average - value;
            v2 += difference * difference;
            v3 += difference * difference * difference;
        }
        const acceleration = v3 / (6 * v2 * Math.sqrt(v2));
        const alpha = z => Phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z)));
        const b = replicates.length;
        const first = Math.max(1, Math.min(b, Math.floor((b + 1) * alpha(zL))));
        const second = Math.max(1, Math.min(b, b + 1 - Math.floor((b + 1) * (1 - alpha(-zL)))));
        const order = group.summaries[statistic].order;
        lines.push(`bca ${GROUP_NAMES[statistic]} below ${count} z0 ${real(z0)} acceleration ${real(acceleration)}`
            + ` ranks ${first} ${second} interval ${real(order[first - 1])} ${real(order[second - 1])}`);
    }
    const missing = sample.map(() => []);
    for (let replicate = 0; replicate < group.ordinary.indices.length; replicate++) {
        const chosen = new Set(group.ordinary.indices[replicate]);
        for (let observation = 0; observation < n; observation++) {
            if (!chosen.has(observation)) missing[observation].push(replicate);
        }
    }
    const errors = group.ordinary.values.map(column => missing.map(indices => meanAndSe(indices.map(index => column[index])).se));
    for (let statistic = 0; statistic < 4; statistic++) {
        const summary = jackknifeSummary(errors[statistic], 0);
        lines.push(`after_bootstrap ${GROUP_NAMES[statistic]} se ${real(group.summaries[statistic].se)}`
            + ` average ${real(summary.average)} se_of_se ${real(summary.se)}`);
    }
    const counts = missing.map(indices => indices.length);
    lines.push(`without min ${Math.min(...counts)} max ${Math.max(...counts)}`);
    const total = sum(sample);
    const influenceOrder = sample.map((value, index) => index).sort((first, second) =>
        Math.abs(n * sample[second] - total) - Math.abs(n * sample[first] - total) || first - second);
    for (let rank = 0; rank < 5; rank++) {
        const observation = influenceOrder[rank];
        const influence = (n - 1) * (summaries[0].average - values[0][observation]);
        const differences = sorted(missing[observation].map(index => group.ordinary.values[0][index] - group.estimates[0]));
        const quantile = percentile => differences[Math.floor((percentile * differences.length + 99) / 100) - 1];
        lines.push(`influence ${rank + 1} obs ${observation + 1} value ${real(sample[observation] / 100)}`
            + ` l ${real(influence)} without ${counts[observation]} se ${real(errors[0][observation])}`
            + ` q05 ${real(quantile(5))} q50 ${real(quantile(50))} q95 ${real(quantile(95))}`);
    }
    return lines;
}

function pairJackknife(pair) {
    const x = pair.x.sample;
    const y = pair.y.sample;
    const deletedX = x.map((value, index) => pairStatistics(without(x, index), y));
    const deletedY = y.map((value, index) => pairStatistics(x, without(y, index)));
    const lines = [];
    for (let statistic = 0; statistic < 4; statistic++) {
        let bias = 0;
        let variance = 0;
        for (const deleted of [deletedX, deletedY]) {
            const summary = jackknifeSummary(deleted.map(row => row[statistic]), pair.estimates[statistic]);
            bias += summary.bias;
            variance += summary.variance;
        }
        lines.push(`pair ${pairName(pair)} ${PAIR_NAMES[statistic]} estimate ${real(pair.estimates[statistic])}`
            + ` bias ${real(bias)} se ${real(Math.sqrt(variance))}`);
    }
    return lines;
}

function rankedSample(sample) {
    const ranks = doubledRanks(sample);
    return sample.map((value, index) => ({ value, rank: ranks[index] }));
}

function permutationStatistics(items, firstSize) {
    const x = items.slice(0, firstSize).map(item => item.value);
    const y = items.slice(firstSize).map(item => item.value);
    const mx = Md(x);
    const my = Md(y);
    const ax = sum(x.map(value => Math.abs(2 * value - mx)));
    const ay = sum(y.map(value => Math.abs(2 * value - my)));
    const rankSum = sum(items.slice(0, firstSize).map(item => item.rank));
    return { values: [contrast(x, y), mx - my, rankSum - firstSize * (items.length + 1), y.length * ax - x.length * ay],
        w: rankSum / 2, u: (rankSum - firstSize * (firstSize + 1)) / 2 };
}

function countComparisons(observed, trial, counts) {
    for (let statistic = 0; statistic < observed.length; statistic++) {
        if (Math.abs(trial[statistic]) >= Math.abs(observed[statistic])) counts[statistic].extreme++;
        if (trial[statistic] >= observed[statistic]) counts[statistic].greater++;
    }
}

function resultText(count, trials, correction = 1) {
    return `extreme ${count.extreme} greater ${count.greater}`
        + ` p_two ${pValue(count.extreme + correction, trials + correction)}`
        + ` p_greater ${pValue(count.greater + correction, trials + correction)}`;
}

function twoGroupPermutation(pair, settings, rng) {
    const x = pair.x.sample;
    const y = pair.y.sample;
    const combined = rankedSample([...x, ...y]);
    const observed = permutationStatistics(combined, x.length);
    const counts = TEST_NAMES.map(() => ({ extreme: 0, greater: 0 }));
    for (let replicate = 0; replicate < settings.permutations; replicate++) {
        const shuffled = rng.shuffle(combined.slice());
        const trial = permutationStatistics(shuffled, x.length);
        countComparisons(observed.values, trial.values, counts);
    }
    const lines = [
        `mean diff ${real(mdiff(x, y))} ${resultText(counts[0], settings.permutations)}`,
        `median diff ${real(observed.values[1] / 200)} ${resultText(counts[1], settings.permutations)}`,
        `ranksum w ${real(observed.w)} u ${real(observed.u)} ${resultText(counts[2], settings.permutations)}`,
        `absdev diff ${real(observed.values[3] / (200 * x.length * y.length))} ${resultText(counts[3], settings.permutations)}`,
    ];
    return { counts, lines };
}

function powerSimulation(pair, settings, rng) {
    const x = pair.x.sample;
    const y = pair.y.sample;
    let rejections = 0;
    for (let simulation = 0; simulation < settings.simulations; simulation++) {
        const first = drawIndices(x.length, rng).map(index => x[index]);
        const second = drawIndices(y.length, rng).map(index => y[index]);
        const combined = [...first, ...second];
        const observed = Math.abs(contrast(first, second));
        let extreme = 0;
        for (let permutation = 0; permutation < settings.innerPermutations; permutation++) {
            const shuffled = rng.shuffle(combined.slice());
            if (Math.abs(contrast(shuffled.slice(0, x.length), shuffled.slice(x.length))) >= observed) extreme++;
        }
        if (100 * (extreme + 1) <= (100 - settings.confidence) * (settings.innerPermutations + 1)) rejections++;
    }
    const power = rejections / settings.simulations;
    return `power sims ${settings.simulations} perms ${settings.innerPermutations} rejections ${rejections}`
        + ` power ${real(power)} se ${real(Math.sqrt(power * (1 - power) / settings.simulations))}`;
}

function exactPermutation(pair, settings) {
    const q = settings.pilot;
    const x = pair.x.sample.slice(0, q);
    const y = pair.y.sample.slice(0, q);
    const combined = rankedSample([...x, ...y]);
    const original = permutationStatistics(combined, q);
    const observed = [original.values[0], original.values[2]];
    const counts = observed.map(() => ({ extreme: 0, greater: 0 }));
    const total = sum(combined.map(item => item.value));
    const absoluteCounts = new Map();
    let splits = 0;
    for (const positions of choices(2 * q, q)) {
        let firstSum = 0;
        let firstRanks = 0;
        for (const position of positions) {
            firstSum += combined[position].value;
            firstRanks += combined[position].rank;
        }
        const statistic = q * firstSum - q * (total - firstSum);
        countComparisons(observed, [statistic, firstRanks - q * (2 * q + 1)], counts);
        const absolute = Math.abs(statistic);
        absoluteCounts.set(absolute, (absoluteCounts.get(absolute) ?? 0) + 1);
        splits++;
    }
    let attained = 0;
    let cumulative = 0;
    let critical = null;
    const order = [...absoluteCounts.keys()].sort((a, b) => b - a);
    for (const value of order) {
        cumulative += absoluteCounts.get(value);
        if (100 * cumulative > (100 - settings.confidence) * splits) break;
        critical = value / (100 * q * q);
        attained = cumulative;
    }
    return [
        `exact size ${q} splits ${splits}`,
        `mean diff ${real(mdiff(x, y))} ${resultText(counts[0], splits, 0)}`,
        `ranksum w ${real(original.w)} u ${real(original.u)} ${resultText(counts[1], splits, 0)}`,
        critical === null ? 'critical diff none attained none' : `critical diff ${real(critical)} attained ${pValue(attained, splits)}`,
    ];
}

function studentizedLines(pair, settings) {
    const x = pair.x.sample;
    const y = pair.y.sample;
    const k = x.length;
    const m = y.length;
    const sx = sd(x);
    const sy = sd(y);
    const vx = sx * sx / k;
    const vy = sy * sy / m;
    const se0 = Math.sqrt(vx + vy);
    const estimate = pair.estimates[0];
    const t = estimate / se0;
    const replicates = [];
    let extreme = 0;
    for (let index = 0; index < settings.bootstrap; index++) {
        const firstSd = pair.x.ordinary.values[3][index];
        const secondSd = pair.y.ordinary.values[3][index];
        const value = (pair.values[0][index] - estimate) / Math.sqrt(firstSd * firstSd / k + secondSd * secondSd / m);
        if (Math.abs(value) >= Math.abs(t)) extreme++;
        replicates.push(value);
    }
    const order = sorted(replicates);
    const lo = estimate - order[pair.summaries[0].rankHi - 1] * se0;
    const hi = estimate - order[pair.summaries[0].rankLo - 1] * se0;
    const df = (vx + vy) * (vx + vy) / (vx * vx / (k - 1) + vy * vy / (m - 1));
    const pooled = sp(x, y);
    const d = pair.estimates[3];
    const g = d * (1 - 3 / (4 * (k + m - 2) - 1));
    let greater = 0;
    let equal = 0;
    for (const first of x) {
        for (const second of y) {
            if (first > second) greater++;
            if (first === second) equal++;
        }
    }
    const cles = (2 * greater + equal) / (2 * k * m);
    return [
        `bootstrap_t t ${real(t)} df ${real(df)} extreme ${extreme} p ${pValue(extreme + 1, settings.bootstrap + 1)}`
            + ` interval ${real(lo)} ${real(hi)}`,
        `effect pooled_sd ${real(pooled)} cohen_d ${real(d)} hedges_g ${real(g)} cles ${real(cles)}`,
    ];
}

function holmLines(pairs, settings) {
    const lines = [];
    for (let statistic = 0; statistic < TEST_NAMES.length; statistic++) {
        const order = pairs.map((pair, index) => ({ pair, index, extreme: pair.permutation.counts[statistic].extreme }))
            .sort((a, b) => a.extreme - b.extreme || a.index - b.index);
        let adjusted = 0;
        for (let index = 0; index < order.length; index++) {
            const { pair, extreme } = order[index];
            adjusted = Math.max(adjusted, Math.min(settings.permutations + 1, (order.length - index) * (extreme + 1)));
            const decision = 100 * adjusted <= (100 - settings.confidence) * (settings.permutations + 1) ? 'reject' : 'retain';
            lines.push(`holm ${TEST_NAMES[statistic]} rank ${index + 1} ${pair.x.name} ${pair.y.name}`
                + ` p ${pValue(extreme + 1, settings.permutations + 1)} adjusted ${pValue(adjusted, settings.permutations + 1)} ${decision}`);
        }
    }
    return lines;
}

function intervalText(summary) {
    return `se ${real(summary.se)} bias ${real(summary.bias)} percentile ${real(summary.lo)} ${real(summary.hi)}`
        + ` basic ${real(summary.basicLo)} ${real(summary.basicHi)}`;
}

function pairedLines(data, paired, zL, rng) {
    const d = data.differences;
    const m = d.length;
    const differenceMean = mean(d);
    const differenceSd = sd(d);
    let positive = 0;
    let negative = 0;
    let zero = 0;
    for (const value of d) {
        if (value > 0) positive++;
        else if (value < 0) negative++;
        else zero++;
    }
    const correlation = paired.correlation.estimate;
    const z = 0.5 * Math.log((1 + correlation) / (1 - correlation));
    const halfWidth = -zL / Math.sqrt(m - 3);
    const tanh = value => {
        const exponential = Math.exp(2 * value);
        return (exponential - 1) / (exponential + 1);
    };
    const lines = [
        `paired subjects ${m} positive ${positive} negative ${negative} zero ${zero}`,
        `paired before ${real(mean(data.before))} after ${real(mean(data.after))} diff ${real(differenceMean)}`
            + ` sd_diff ${real(differenceSd)} t ${real(differenceMean / (differenceSd / Math.sqrt(m)))}`
            + ` dz ${real(differenceMean / differenceSd)}`,
        'paired_bootstrap ' + intervalText(paired.difference),
        `correlation r ${real(correlation)} ${intervalText(paired.correlation)}`
            + ` fisher ${real(tanh(z - halfWidth))} ${real(tanh(z + halfWidth))}`,
    ];
    const nonzero = d.filter(value => value !== 0).map(Math.abs);
    const ranks = doubledRanks(nonzero);
    let position = 0;
    let positiveRanks = 0;
    const signedRanks = d.map(value => {
        if (value === 0) return 0;
        const rank = ranks[position++];
        if (value > 0) positiveRanks += rank;
        return value > 0 ? rank : -rank;
    });
    const observed = [sum(d), sum(signedRanks)];
    const counts = observed.map(() => ({ extreme: 0, greater: 0 }));
    for (let replicate = 0; replicate < data.settings.permutations; replicate++) {
        let total = 0;
        let rankTotal = 0;
        for (let index = 0; index < m; index++) {
            const sign = rng.draw() % 2 === 1 ? -1 : 1;
            total += sign * d[index];
            rankTotal += sign * signedRanks[index];
        }
        countComparisons(observed, [total, rankTotal], counts);
    }
    lines.push(`signflip flips ${data.settings.permutations}`,
        `mean diff ${real(differenceMean)} ${resultText(counts[0], data.settings.permutations)}`,
        `signedrank w_plus ${real(positiveRanks / 2)} ${resultText(counts[1], data.settings.permutations)}`);
    return lines;
}

function anovaLines(data, rng) {
    const { groups, settings } = data;
    const samples = groups.map(group => group.sample);
    const sizes = samples.map(sample => sample.length);
    const original = anova(samples);
    const n = original.count;
    const g = groups.length;
    const msw = original.ssw / (n - g);
    const eta = original.ssb / (original.ssb + original.ssw);
    const omega = (original.ssb - (g - 1) * msw) / (original.ssb + original.ssw + msw);
    const etaReplicates = [];
    for (let replicate = 0; replicate < settings.bootstrap; replicate++) {
        const result = anova(groups.map(group => group.ordinary.samples[replicate]));
        etaReplicates.push(result.ssb / (result.ssb + result.ssw));
    }
    const etaSummary = bootstrapSummary(eta, etaReplicates, settings.confidence);
    const weights = samples.map(sample => {
        const deviation = sd(sample);
        return sample.length / (deviation * deviation);
    });
    const weightTotal = sum(weights);
    let weightedMean = 0;
    for (let index = 0; index < g; index++) weightedMean += weights[index] * original.means[index];
    weightedMean /= weightTotal;
    let aw = 0;
    let lambda = 0;
    for (let index = 0; index < g; index++) {
        const difference = original.means[index] - weightedMean;
        aw += weights[index] * (difference * difference);
        const part = 1 - weights[index] / weightTotal;
        lambda += (part * part) / (sizes[index] - 1);
    }
    aw /= g - 1;
    const welch = aw / (1 + 2 * (g - 2) * lambda / (g * g - 1));
    const df2 = (g * g - 1) / (3 * lambda);
    const combinedValues = samples.flat();
    const combined = rankedSample(combinedValues);
    const ties = tieCounts(combinedValues);
    const correction = 1 - ties.correction / (n * n * n - n);
    const h = kruskal(divide(combined.map(item => item.rank), sizes), correction);
    const lines = [
        `anova groups ${g} observations ${n} ssb ${real(original.ssb)} ssw ${real(original.ssw)} df ${g - 1} ${n - g}`
            + ` f ${real(original.f)} eta_squared ${real(eta)} omega_squared ${real(omega)}`,
        'eta_bootstrap ' + intervalText(etaSummary),
        `welch f ${real(welch)} df ${g - 1} ${real(df2)}`,
        `kruskal h ${real(h)} tie_groups ${ties.groups}`,
    ];
    const totals = samples.map(sum);
    const pairs = [];
    for (let first = 0; first < g; first++) {
        for (let second = first + 1; second < g; second++) {
            pairs.push({ first, second, numerator: Math.abs(sizes[second] * totals[first] - sizes[first] * totals[second]),
                denominator: sizes[first] * sizes[second], extreme: 0, maximum: 0 });
        }
    }
    let fExtreme = 0;
    let hExtreme = 0;
    for (let permutation = 0; permutation < settings.permutations; permutation++) {
        const divided = divide(rng.shuffle(combined.slice()), sizes);
        const trialSamples = divided.map(items => items.map(item => item.value));
        const trial = anova(trialSamples);
        const trialH = kruskal(divided.map(items => items.map(item => item.rank)), correction);
        if (trial.f >= original.f - 0.000000001 * original.f) fExtreme++;
        if (trialH >= h - 0.000000001 * h) hExtreme++;
        const trialTotals = trialSamples.map(sum);
        const deltas = pairs.map(pair => ({
            numerator: Math.abs(sizes[pair.second] * trialTotals[pair.first] - sizes[pair.first] * trialTotals[pair.second]),
            denominator: pair.denominator,
        }));
        let maximum = deltas[0];
        for (const delta of deltas) {
            if (delta.numerator * maximum.denominator > maximum.numerator * delta.denominator) maximum = delta;
        }
        for (let index = 0; index < pairs.length; index++) {
            const pair = pairs[index];
            const delta = deltas[index];
            if (delta.numerator * pair.denominator >= pair.numerator * delta.denominator) pair.extreme++;
            if (maximum.numerator * pair.denominator >= pair.numerator * maximum.denominator) pair.maximum++;
        }
    }
    lines.push(`anova_permutation perms ${settings.permutations} f_extreme ${fExtreme} f_p ${pValue(fExtreme + 1, settings.permutations + 1)}`
        + ` h_extreme ${hExtreme} h_p ${pValue(hExtreme + 1, settings.permutations + 1)}`);
    for (const pair of pairs) {
        lines.push(`pairwise ${groups[pair.first].name} ${groups[pair.second].name} diff ${real(mdiff(samples[pair.first], samples[pair.second]))}`
            + ` extreme ${pair.extreme} p ${pValue(pair.extreme + 1, settings.permutations + 1)}`
            + ` maxt ${pair.maximum} adjusted ${pValue(pair.maximum + 1, settings.permutations + 1)}`);
    }
    return lines;
}

function main() {
    const data = readDataset();
    const { groups, pairs, settings } = data;
    const rng = new Minstd(settings.seed);
    const b = settings.bootstrap;
    const zL = PhiInv((100 - settings.confidence) / 200);
    // The single random stream visits ordinary groups, balanced groups, then subjects.
    for (const group of groups) {
        group.estimates = sampleStatistics(group.sample);
        group.ordinary = bootstrapSamples(group.sample, ordinaryIndices(group.sample.length, b, rng));
        group.summaries = group.ordinary.values.map((values, index) => bootstrapSummary(group.estimates[index], values, settings.confidence));
    }
    for (const pair of pairs) {
        pair.estimates = pairStatistics(pair.x.sample, pair.y.sample);
        pair.values = PAIR_NAMES.map(() => []);
        for (let replicate = 0; replicate < b; replicate++) {
            const values = pairStatistics(pair.x.ordinary.samples[replicate], pair.y.ordinary.samples[replicate]);
            for (let statistic = 0; statistic < 4; statistic++) pair.values[statistic].push(values[statistic]);
        }
        pair.summaries = pair.values.map((values, index) => bootstrapSummary(pair.estimates[index], values, settings.confidence));
    }
    for (const group of groups) {
        const balanced = bootstrapSamples(group.sample, balancedIndices(group.sample.length, b, rng));
        group.balancedSummaries = balanced.values.map((values, index) => bootstrapSummary(group.estimates[index], values, settings.confidence));
    }
    const differences = [];
    const correlations = [];
    for (let replicate = 0; replicate < b; replicate++) {
        const indices = drawIndices(data.before.length, rng);
        differences.push(mean(indices.map(index => data.differences[index])));
        correlations.push(corr(indices.map(index => data.before[index]), indices.map(index => data.after[index])));
    }
    const paired = {
        difference: bootstrapSummary(mean(data.differences), differences, settings.confidence),
        correlation: bootstrapSummary(corr(data.before, data.after), correlations, settings.confidence),
    };
    const descriptives = descriptiveLines(data);
    const bootstrap = bootstrapLines(data);
    const histograms = histogramLines(data);
    const jackknife = [];
    for (const group of groups) jackknife.push(...groupJackknife(group, zL));
    for (const pair of pairs) jackknife.push(...pairJackknife(pair));
    const tests = [];
    for (const pair of pairs) {
        pair.permutation = twoGroupPermutation(pair, settings, rng);
        const power = powerSimulation(pair, settings, rng);
        tests.push(`compare ${pair.x.name} ${pair.y.name}`,
            `permutation n ${pair.x.sample.length} ${pair.y.sample.length} perms ${settings.permutations}`,
            ...pair.permutation.lines, power, ...exactPermutation(pair, settings), ...studentizedLines(pair, settings));
    }
    tests.push(...holmLines(pairs, settings));
    tests.push(...pairedLines(data, paired, zL, rng));
    tests.push(...anovaLines(data, rng));
    writeLines('descriptives.txt', descriptives);
    writeLines('bootstrap.csv', bootstrap);
    writeLines('jackknife.txt', jackknife);
    writeLines('tests.txt', tests);
    writeLines('histograms.txt', histograms);
}

if (require.main === module) main();
