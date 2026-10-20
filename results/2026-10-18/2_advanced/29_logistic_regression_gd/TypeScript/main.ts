import { mkdirSync, writeFileSync } from 'node:fs';
import { readInputs, expandedFeatures, expand, statistics, standardizeOne, standardize,
    type Table, type Feature, type Statistics } from './dataset.ts';
import * as logistic from './logistic.ts';
import { Minstd, shuffle, cholesky, solveFactor, gradientDescent, stochasticDescent, newton, type Fit, type NewtonFit } from './optimizers.ts';
import * as softmax from './softmax.ts';
import { real, ratio, fraction, compareFractions, confusion, auc, rocPoints, type Fraction, type ROCPoint } from './metrics.ts';

interface PreparedTable extends Table {
    count: number; expanded: number[][]; targets: number[]; positive: number; classCounts: number[]; vectors: number[][];
}
function sumBy<T>(values: readonly T[], term: (value: T, index: number) => number): number {
    let result = 0;
    for (let i = 0; i < values.length; i++) result += term(values[i], i);
    return result;
}
const sum = (values: readonly number[]): number => sumBy(values, value => value);
const length = (vector: number[]): number => Math.sqrt(sumBy(vector, value => value * value));

function prepareData() {
    const input = readInputs(), features = expandedFeatures(input.names, input.settings.degree);
    const classes = Math.max(...input.train.labels) + 1;
    const stats = statistics(input.train.base.map(base => expand(base, features)));
    function prepare(table: Table): PreparedTable {
        const expanded = table.base.map(base => expand(base, features));
        const targets = table.labels.map(label => Number(label === input.settings.positive));
        const classCounts: number[] = Array(classes).fill(0);
        for (const label of table.labels) classCounts[label]++;
        return { ...table, count: table.ids.length, expanded, targets, positive: sum(targets), classCounts,
            vectors: standardize(expanded, stats) };
    }
    return { names: input.names, settings: input.settings, features, classes, train: prepare(input.train), test: prepare(input.test),
        statistics: stats, baseMean: stats.means.slice(0, input.names.length), bounds: input.names.map((_, j) => ({
            low: Math.min(...input.train.base.map(row => row[j])), high: Math.max(...input.train.base.map(row => row[j])) })) };
}
type Data = ReturnType<typeof prepareData>;

function inverse(matrix: number[][]): number[][] {
    const factor = cholesky(matrix), result: number[][] = matrix.map(() => []);
    for (let k = 0; k < matrix.length; k++) {
        const right: number[] = Array(matrix.length).fill(0); right[k] = 1;
        const solution = solveFactor(factor, right);
        for (let j = 0; j < matrix.length; j++) result[j][k] = solution[j];
    }
    return result;
}
function influence(weights: number[], vectors: number[][], targets: number[], lambda: number) {
    const evaluation = logistic.evaluate(weights, vectors, targets, lambda), matrix = inverse(logistic.hessian(weights, vectors, lambda));
    const rows = vectors.map((vector, i) => {
        const probability = evaluation.probabilities[i], variance = probability * (1 - probability);
        let quadratic = 0;
        for (let j = 0; j < weights.length; j++) for (let k = 0; k < weights.length; k++) quadratic += vector[j] * matrix[j][k] * vector[k];
        const leverage = variance * quadratic / vectors.length, pearson = (targets[i] - probability) / Math.sqrt(variance);
        const residual = pearson / Math.sqrt(1 - leverage);
        const cook = pearson * pearson * leverage / (weights.length * ((1 - leverage) * (1 - leverage)));
        return { index: i, probability, leverage, residual, cook };
    });
    const edf = sumBy(rows, row => row.leverage), deviance = 2 * vectors.length * evaluation.loss;
    return { matrix, rows, edf, deviance, loss: evaluation.loss, aic: deviance + 2 * edf, bic: deviance + Math.log(vectors.length) * edf };
}
type Influence = ReturnType<typeof influence>;
function originalWeights(weights: number[], stats: Statistics): number[] {
    const result = weights.map((value, j) => j === 0 ? value : value / stats.deviations[j - 1]);
    let shift = 0;
    for (let j = 1; j < result.length; j++) shift += result[j] * stats.means[j - 1];
    result[0] = weights[0] - shift; return result;
}
function featureCorrelations(data: Data) {
    const matrix = data.features.map((_, j) => data.features.map((__, k) =>
        sumBy(data.train.vectors, vector => vector[j + 1] * vector[k + 1]) / (data.train.count - 1)));
    return { matrix, vif: inverse(matrix).map((row, j) => row[j]) };
}
function crossValidate(data: Data, width: number, lambda: number) {
    const losses: number[] = [], probabilities: number[] = [], foldLosses: number[] = [];
    let errors = 0;
    for (let fold = 0; fold < 5; fold++) {
        const training: number[] = [], validation: number[] = [];
        for (let i = 0; i < data.train.count; i++) (i % 5 === fold ? validation : training).push(i);
        const stats = statistics(training.map(i => data.train.expanded[i]), width);
        const vectors = standardize(training.map(i => data.train.expanded[i]), stats), targets = training.map(i => data.train.targets[i]);
        const fitted = newton(vectors, targets, lambda);
        let foldLoss = 0;
        for (const i of validation) {
            const score = logistic.score(fitted.weights, standardizeOne(data.train.expanded[i], stats));
            losses[i] = logistic.loss(score, data.train.targets[i]); probabilities[i] = logistic.sigmoid(score); foldLoss += losses[i];
            if (Number(probabilities[i] >= data.settings.threshold) !== data.train.targets[i]) errors++;
        }
        foldLosses.push(foldLoss / validation.length);
    }
    return { lambda, foldLosses, loss: sum(losses) / data.train.count, errors, probabilities };
}
function selectLambda(data: Data) {
    const candidates = data.settings.lambdas.map(lambda => crossValidate(data, data.features.length, lambda));
    let selected = candidates[0];
    for (const candidate of candidates) if (candidate.loss <= selected.loss) selected = candidate;
    const mean = sum(selected.foldLosses) / 5;
    const se = Math.sqrt(sumBy(selected.foldLosses, value => (value - mean) * (value - mean)) / 4) / Math.sqrt(5);
    let oneSE = candidates[0].lambda;
    for (const candidate of candidates) if (candidate.loss <= selected.loss + se) oneSE = candidate.lambda;
    return { candidates, selected, se, oneSE, confusion: confusion(selected.probabilities, data.train.targets, data.settings.threshold),
        auc: auc(selected.probabilities, data.train.targets) };
}
function fitSummary(weights: number[], training: number[][], targets: number[], testing: number[][],
    testTargets: number[], lambda: number, threshold: number) {
    const train = logistic.evaluate(weights, training, targets, lambda), test = logistic.evaluate(weights, testing, testTargets);
    return { weights, train, test, norm: length(weights.slice(1)), trainCorrect: confusion(train.probabilities, targets, threshold).correct,
        testCorrect: confusion(test.probabilities, testTargets, threshold).correct, auc: auc(test.probabilities, testTargets) };
}
function lambdaPath(data: Data) {
    return data.settings.lambdas.map(lambda => ({ lambda, ...fitSummary(newton(data.train.vectors, data.train.targets, lambda).weights,
        data.train.vectors, data.train.targets, data.test.vectors, data.test.targets, lambda, data.settings.threshold) }));
}
function degreeComparison(data: Data, lambda: number) {
    const results = [];
    for (let degree = 1; degree <= data.settings.degree; degree++) {
        const width = data.features.filter(feature => feature.degree <= degree).length;
        const training = data.train.vectors.map(vector => vector.slice(0, width + 1)), testing = data.test.vectors.map(vector => vector.slice(0, width + 1));
        const fitted = newton(training, data.train.targets, lambda);
        results.push({ degree, width, cv: crossValidate(data, width, lambda).loss,
            ...fitSummary(fitted.weights, training, data.train.targets, testing, data.test.targets, lambda, data.settings.threshold),
            influence: influence(fitted.weights, training, data.train.targets, lambda) });
    }
    return results;
}
function learningCurve(data: Data, lambda: number) {
    const results = [];
    for (let k = 1; k <= 4; k++) {
        const size = Math.floor(k * data.train.count / 4), expanded = data.train.expanded.slice(0, size), stats = statistics(expanded);
        const training = standardize(expanded, stats), testing = standardize(data.test.expanded, stats), targets = data.train.targets.slice(0, size);
        const fitted = newton(training, targets, lambda);
        results.push({ size, ...fitSummary(fitted.weights, training, targets, testing, data.test.targets, lambda, data.settings.threshold) });
    }
    return results;
}
function calibration(probabilities: number[], targets: number[]) {
    const bins = Array.from({ length: 10 }, () => ({ count: 0, total: 0, positives: 0 }));
    probabilities.forEach((probability, i) => {
        const bin = bins[Math.min(9, Math.floor(probability * 10))]; bin.count++; bin.total += probability; bin.positives += targets[i];
    });
    let ece = 0, mce = 0, hl = 0, groups = 0;
    for (const bin of bins) {
        if (bin.count === 0) continue;
        groups++; ece += Math.abs(bin.total - bin.positives);
        mce = Math.max(mce, Math.abs(bin.total / bin.count - bin.positives / bin.count));
        const difference = bin.positives - bin.total;
        hl += difference * difference / (bin.total * (1 - bin.total / bin.count));
    }
    return { bins, ece: ece / probabilities.length, mce, hl, groups };
}
interface NamedFit extends Fit { name: string }
function binaryAnalysis(data: Data, fitted: NamedFit, lambda: number) {
    const result = fitSummary(fitted.weights, data.train.vectors, data.train.targets, data.test.vectors, data.test.targets, lambda, data.settings.threshold);
    const probabilities = result.test.probabilities, table = confusion(probabilities, data.test.targets, data.settings.threshold), points = rocPoints(probabilities, data.test.targets);
    const positive = data.test.positive, negative = data.test.count - positive, [fpCost, fnCost] = data.settings.cost;
    const cost = (p: ROCPoint) => fpCost * p.fp + fnCost * (positive - p.tp), youdenValue = (p: ROCPoint) => p.tp * negative - p.fp * positive;
    let youden = points[0], bestF1 = points[0], minCost = points[0], averagePrecision = 0, previousTP = 0;
    for (const point of points) {
        averagePrecision += (point.tp - previousTP) * point.tp / (point.tp + point.fp); previousTP = point.tp;
        if (youdenValue(point) > youdenValue(youden)) youden = point;
        if (compareFractions([2 * point.tp, positive + point.tp + point.fp], [2 * bestF1.tp, positive + bestF1.tp + bestF1.fp]) > 0) bestF1 = point;
        if (cost(point) < cost(minCost)) minCost = point;
    }
    const order = probabilities.map((_, i) => i).sort((a, b) => probabilities[b] - probabilities[a] || a - b), gains = [];
    for (let decile = 1; decile <= 10; decile++) {
        const size = Math.floor(decile * data.test.count / 10); gains.push({ decile, size, hits: sumBy(order.slice(0, size), i => data.test.targets[i]) });
    }
    return { ...fitted, ...result, confusion: table, points, youden, bestF1, minCost: { ...minCost, cost: cost(minCost) }, averagePrecision: averagePrecision / positive,
        brier: sumBy(probabilities, (p, i) => (p - data.test.targets[i]) * (p - data.test.targets[i])) / data.test.count,
        calibration: calibration(probabilities, data.test.targets), gains };
}
type BinaryModel = ReturnType<typeof binaryAnalysis>;
function multiclassAnalysis(data: Data, fitted: ReturnType<typeof softmax.train>, binary: BinaryModel) {
    const evaluation = softmax.evaluate(fitted.weights, data.test.vectors, data.test.labels);
    const table: number[][] = Array.from({ length: data.classes }, () => Array(data.classes).fill(0));
    const bins = Array.from({ length: 10 }, () => ({ count: 0, total: 0, hits: 0 }));
    let brier = 0, correct = 0;
    evaluation.rows.forEach((row, i) => {
        table[data.test.labels[i]][row.predicted]++;
        const hit = Number(row.predicted === data.test.labels[i]); correct += hit;
        let squared = 0;
        row.probabilities.forEach((p, k) => { const difference = p - Number(k === data.test.labels[i]); squared += difference * difference; });
        brier += squared;
        const confidence = row.probabilities[row.predicted], bin = bins[Math.min(9, Math.floor(confidence * 10))];
        bin.count++; bin.total += confidence; bin.hits += hit;
    });
    const rowTotals = table.map(row => sum(row)), columnTotals = table.map((_, k) => sumBy(table, row => row[k]));
    const expected = sumBy(rowTotals, (total, k) => total * columnTotals[k]);
    const classAUC = table.map((_, k) => auc(evaluation.rows.map(row => row.probabilities[k]), data.test.labels.map(label => Number(label === k))));
    const probabilities = evaluation.rows.map(row => row.probabilities[data.settings.positive]);
    const binaryConfusion = confusion(probabilities, data.test.targets, data.settings.threshold);
    const binaryLoss = sumBy(probabilities, (p, i) => -Math.log(data.test.targets[i] === 1 ? p : 1 - p)) / data.test.count;
    const agreement = sumBy(binaryConfusion.predictions, (p, i) => Number(p === binary.confusion.predictions[i]));
    const ece = sumBy(bins, bin => bin.count === 0 ? 0 : Math.abs(bin.total - bin.hits)) / data.test.count;
    const kappa: Fraction = [data.test.count * correct - expected, data.test.count * data.test.count - expected];
    return { ...fitted, ...evaluation, table, rowTotals, columnTotals, classAUC, correct, brier: brier / data.test.count, kappa,
        binaryAUC: auc(probabilities, data.test.targets), binaryConfusion, binaryLoss, agreement, bins, ece };
}
type MulticlassModel = ReturnType<typeof multiclassAnalysis>;

function bootstrap(data: Data, probabilities: number[]) {
    const [count, seed] = data.settings.bootstrap, generator = new Minstd(seed), results: { fraction: Fraction; value: number }[] = [];
    for (let b = 0; b < count; b++) {
        const selected: number[] = [];
        for (let i = 0; i < data.test.count; i++) selected.push(generator.draw() % data.test.count);
        const value = auc(selected.map(i => probabilities[i]), selected.map(i => data.test.targets[i]));
        results.push({ fraction: value, value: value[0] / value[1] });
    }
    const mean = sumBy(results, result => result.value) / count;
    const sd = Math.sqrt(sumBy(results, result => (result.value - mean) * (result.value - mean)) / (count - 1));
    const sorted = results.slice().sort((a, b) => compareFractions(a.fraction, b.fraction));
    return { mean, sd, lower: sorted[Math.floor(count / 40)].fraction, upper: sorted[count - Math.floor(count / 40) - 1].fraction };
}
function slope(features: Feature[], weights: number[], base: number[], feature: number): number {
    let total = 0;
    features.forEach((expanded, j) => {
        let count = 0;
        for (const k of expanded.tuple) if (k === feature) count++;
        if (count === 0) return;
        let product = 1, removed = false;
        for (const k of expanded.tuple) { if (k === feature && !removed) removed = true; else product *= base[k]; }
        total += weights[j + 1] * (count * product);
    });
    return total;
}
function newtonDiagnostics(data: Data, model: BinaryModel, fit: NewtonFit, lambda: number, measures: Influence) {
    const rate = data.train.positive / data.train.count, nullLoss = -(rate * Math.log(rate) + (1 - rate) * Math.log(1 - rate));
    const sorted = measures.rows.slice().sort((a, b) => a.probability - b.probability || a.index - b.index), groups = [];
    let hl = 0;
    for (let g = 1; g <= 10; g++) {
        const rows = sorted.slice(Math.floor((g - 1) * data.train.count / 10), Math.floor(g * data.train.count / 10));
        const expected = sumBy(rows, row => row.probability), observed = sumBy(rows, row => data.train.targets[row.index]), difference = observed - expected;
        hl += difference * difference / (expected * (1 - expected / rows.length)); groups.push({ group: g, size: rows.length, observed, expected });
    }
    const iterations = fit.steps.map((step, i) => ({ iteration: i + 1,
        objective: logistic.evaluate(fit.checkpoints[i].weights, data.train.vectors, data.train.targets, lambda).objective,
        gradient: length(step.gradient), step: length(step.delta), decrease: sumBy(step.gradient, (g, j) => g * step.delta[j]) / 2 }));
    const original = originalWeights(model.weights, data.statistics), meanVector = standardizeOne(expand(data.baseMean, data.features), data.statistics);
    const meanProbability = logistic.sigmoid(logistic.score(model.weights, meanVector));
    const marginals = data.names.map((name, k) => ({ name, average: sumBy(measures.rows, row => row.probability * (1 - row.probability)
        * slope(data.features, original, data.train.base[row.index], k)) / data.train.count,
        atMean: meanProbability * (1 - meanProbability) * slope(data.features, original, data.baseMean, k) }));
    const thresholds = [];
    for (let digit = 1; digit <= 9; digit++) thresholds.push({ digit, ...confusion(model.test.probabilities, data.test.targets, digit / 10) });
    const errors = model.confusion.predictions.map((_, i) => i).filter(i => model.confusion.predictions[i] !== data.test.targets[i])
        .sort((a, b) => Math.abs(model.test.probabilities[b] - data.settings.threshold) - Math.abs(model.test.probabilities[a] - data.settings.threshold) || a - b).slice(0, 5);
    const cooks = measures.rows.slice().sort((a, b) => b.cook - a.cook || a.index - b.index).slice(0, 5);
    return { nullLoss, mcfadden: 1 - measures.loss / nullLoss, groups, hl, iterations, marginals, thresholds, errors,
        bootstrap: bootstrap(data, model.test.probabilities), cooks, largeResiduals: measures.rows.filter(row => Math.abs(row.residual) > 2).length };
}
function permutationImportance(data: Data, binary: BinaryModel, multiclass: MulticlassModel) {
    const [repetitions, seed] = data.settings.permutation, generator = new Minstd(seed);
    return data.names.map((name, feature) => {
        let losses = 0, numerators = 0, correct = 0;
        for (let t = 0; t < repetitions; t++) {
            const order = data.test.ids.map((_, i) => i); shuffle(order, generator);
            const base = data.test.base.map((row, i) => row.map((value, k) => k === feature ? data.test.base[order[i]][feature] : value));
            const vectors = standardize(base.map(values => expand(values, data.features)), data.statistics);
            const evaluation = logistic.evaluate(binary.weights, vectors, data.test.targets);
            losses += evaluation.loss; numerators += auc(evaluation.probabilities, data.test.targets)[0];
            correct += sumBy(softmax.evaluate(multiclass.weights, vectors, data.test.labels).rows, (row, i) => Number(row.predicted === data.test.labels[i]));
        }
        const value: Fraction = [numerators, repetitions * binary.auc[1]];
        return { name, increase: losses / repetitions - binary.test.loss, auc: value, correct, total: repetitions * data.test.count };
    });
}
function predictPoint(data: Data, binary: BinaryModel, multiclass: MulticlassModel, base: number[]) {
    const vector = standardizeOne(expand(base, data.features), data.statistics);
    return { probability: logistic.sigmoid(logistic.score(binary.weights, vector)), ...softmax.rowValues(multiclass.weights, vector) };
}
function profiles(data: Data, binary: BinaryModel, multiclass: MulticlassModel) {
    const results = [];
    for (let k = 0; k < data.names.length; k++) for (let g = 0; g <= 4; g++) {
        const base = data.baseMean.slice(), { low, high } = data.bounds[k]; base[k] = low + (high - low) * g / 4;
        results.push({ name: data.names[k], value: base[k], ...predictPoint(data, binary, multiclass, base) });
    }
    return results;
}
function oneVersusRest(data: Data, multiclass: MulticlassModel) {
    const lambda = data.settings.softmax[2], classes = [];
    for (let k = 0; k < data.classes; k++) {
        const targets = data.train.labels.map(label => Number(label === k)), testTargets = data.test.labels.map(label => Number(label === k));
        const fit = newton(data.train.vectors, targets, lambda), evaluation = logistic.evaluate(fit.weights, data.test.vectors, testTargets);
        classes.push({ label: k, objective: logistic.evaluate(fit.weights, data.train.vectors, targets, lambda).objective,
            probabilities: evaluation.probabilities, auc: auc(evaluation.probabilities, testTargets) });
    }
    let correct = 0, agreement = 0;
    for (let i = 0; i < data.test.count; i++) {
        let predicted = 0;
        for (let k = 1; k < data.classes; k++) if (classes[k].probabilities[i] > classes[predicted].probabilities[i]) predicted = k;
        if (predicted === data.test.labels[i]) correct++;
        if (predicted === multiclass.rows[i].predicted) agreement++;
    }
    return { classes, correct, agreement };
}
function predictionMaps(data: Data, binary: BinaryModel, multiclass: MulticlassModel) {
    const [width, height] = data.settings.map, first = data.bounds[0], second = data.bounds[1], classes: string[] = [], probabilities: string[] = [];
    const counts: number[] = Array(data.classes).fill(0);
    for (let r = 0; r < height; r++) {
        let classLine = '', probabilityLine = '';
        for (let c = 0; c < width; c++) {
            const base = data.baseMean.slice(); base[0] = first.low + (c + 0.5) * (first.high - first.low) / width;
            base[1] = second.high - (r + 0.5) * (second.high - second.low) / height;
            const prediction = predictPoint(data, binary, multiclass, base);
            classLine += prediction.predicted; probabilityLine += Math.min(9, Math.floor(prediction.probability * 10)); counts[prediction.predicted]++;
        }
        classes.push(classLine); probabilities.push(probabilityLine);
    }
    return { classes, probabilities, counts };
}
function buildState(data: Data) {
    const validation = selectLambda(data), lambda = validation.selected.lambda;
    const fit = newton(data.train.vectors, data.train.targets, lambda);
    const fitted: NamedFit[] = [ { name: 'gd', ...gradientDescent(data.train.vectors, data.train.targets, lambda, ...data.settings.gd) },
        { name: 'sgd', ...stochasticDescent(data.train.vectors, data.train.targets, lambda, ...data.settings.sgd) }, { name: 'newton', ...fit } ];
    const models = fitted.map(model => binaryAnalysis(data, model, lambda));
    const [rate, iterations, softLambda] = data.settings.softmax;
    const multiclass = multiclassAnalysis(data, softmax.train(data.train.vectors, data.train.labels, data.classes, softLambda, rate, iterations), models[2]);
    const measures = influence(models[2].weights, data.train.vectors, data.train.targets, lambda);
    return { validation, lambda, models, softmax: multiclass, influence: measures, correlations: featureCorrelations(data), path: lambdaPath(data),
        degrees: degreeComparison(data, lambda), learning: learningCurve(data, lambda), diagnostics: newtonDiagnostics(data, models[2], fit, lambda, measures),
        importance: permutationImportance(data, models[2], multiclass), profiles: profiles(data, models[2], multiclass),
        oneVersusRest: oneVersusRest(data, multiclass), maps: predictionMaps(data, models[2], multiclass) };
}
type State = ReturnType<typeof buildState>;

function sections(parts: string[][]): string[] { return parts.flatMap((part, i) => i === 0 ? part : ['', ...part]); }
function termLines(data: Data, weights: number[]): string[] {
    const original = originalWeights(weights, data.statistics), names = ['intercept', ...data.features.map(feature => feature.name)];
    return names.map((name, j) => `term ${name} standardized ${real(weights[j])} original ${real(original[j])}`);
}
function weightsReport(data: Data, state: State): string[] {
    const features = [`features ${data.names.length} degree ${data.settings.degree} expanded ${data.features.length}`, 'standardization'];
    data.features.forEach((f, j) => features.push(`${f.name} mean ${real(data.statistics.means[j], 6)} sd ${real(data.statistics.deviations[j], 6)} vif ${real(state.correlations.vif[j])}`));
    features.push('correlation', ...state.correlations.matrix.map(row => row.map(value => real(value)).join(' ')));
    const parts = [features], binary = state.models[2];
    for (const model of state.models) {
        const lines = [`model ${model.name} lambda ${real(state.lambda)}`, ...termLines(data, model.weights), `norm ${real(model.norm)}`];
        if (model.name !== 'newton') lines.push(`distance_to_newton ${real(length(model.weights.map((w, j) => w - binary.weights[j])), 6)}`);
        parts.push(lines);
    }
    const coefficients = [`coefficients newton lambda ${real(state.lambda)}`], names = ['intercept', ...data.features.map(f => f.name)];
    binary.weights.forEach((weight, j) => {
        const se = Math.sqrt(state.influence.matrix[j][j] / data.train.count);
        coefficients.push(`${names[j]} weight ${real(weight)} se ${real(se)} z ${real(weight / se)} lower ${real(weight - 1.96 * se)} upper ${real(weight + 1.96 * se)} odds_ratio ${real(Math.exp(weight))}`);
    });
    parts.push(coefficients);
    const multiclass = [`model softmax lambda ${real(data.settings.softmax[2])}`];
    state.softmax.weights.forEach((weights, k) => multiclass.push(`class ${k}`, ...termLines(data, weights)));
    parts.push(multiclass); return sections(parts);
}
function lossTrace(data: Data, state: State): string[] {
    const lines = ['optimizer,iteration,loss,gradient_norm,test_loss'];
    for (const model of state.models) for (const checkpoint of model.checkpoints) {
        const train = logistic.evaluate(checkpoint.weights, data.train.vectors, data.train.targets, state.lambda);
        const direction = logistic.gradient(checkpoint.weights, data.train.vectors, data.train.targets, state.lambda);
        const test = logistic.evaluate(checkpoint.weights, data.test.vectors, data.test.targets);
        lines.push([model.name, checkpoint.iteration, real(train.objective, 6), real(length(direction), 6), real(test.loss, 6)].join(','));
    }
    for (const checkpoint of state.softmax.checkpoints) {
        const train = softmax.evaluate(checkpoint.weights, data.train.vectors, data.train.labels, data.settings.softmax[2]);
        const direction = softmax.gradient(checkpoint.weights, data.train.vectors, data.train.labels, data.settings.softmax[2]);
        const test = softmax.evaluate(checkpoint.weights, data.test.vectors, data.test.labels);
        lines.push(['softmax', checkpoint.iteration, real(train.objective, 6), real(length(direction.flat()), 6), real(test.loss, 6)].join(','));
    }
    return lines;
}
function predictionsReport(data: Data, state: State): string[] {
    const lines = ['id,model,probability,predicted,actual'];
    for (const model of state.models) data.test.ids.forEach((id, i) => lines.push([id, model.name, real(model.test.probabilities[i], 6), model.confusion.predictions[i], data.test.targets[i]].join(',')));
    state.softmax.rows.forEach((row, i) => lines.push([data.test.ids[i], 'softmax', real(row.probabilities[row.predicted], 6), row.predicted, data.test.labels[i]].join(',')));
    return lines;
}
function rocReport(data: Data, models: BinaryModel[]): string[] {
    const lines = ['model,threshold,tpr,fpr,precision'];
    for (const model of models) {
        lines.push(`${model.name},inf,0.0000,0.0000,-`);
        for (const point of model.points) lines.push([model.name, real(point.threshold, 6), ratio(point.tp, data.test.positive),
            ratio(point.fp, data.test.count - data.test.positive), ratio(point.tp, point.tp + point.fp)].join(','));
    }
    return lines;
}
const binRange = (index: number): string => `0.${index}-${index === 9 ? '1.0' : `0.${index + 1}`}`;
function binaryLines(data: Data, model: BinaryModel, lambda: number): string[] {
    const { tp, fp, tn, fn } = model.confusion, positive = data.test.positive, negative = data.test.count - positive;
    const y = model.youden, best = model.bestF1, cost = model.minCost;
    const lines = [ `model ${model.name} lambda ${real(lambda)}`,
        `train correct ${model.trainCorrect}/${data.train.count} accuracy ${ratio(model.trainCorrect, data.train.count)}`,
        `test tp ${tp} fp ${fp} tn ${tn} fn ${fn}`,
        `test accuracy ${ratio(tp + tn, data.test.count)} precision ${ratio(tp, tp + fp)} recall ${ratio(tp, tp + fn)} specificity ${ratio(tn, tn + fp)} f1 ${ratio(2 * tp, 2 * tp + fp + fn)}`,
        `log_loss ${real(model.test.loss, 6)} brier ${real(model.brier, 6)}`, `auc ${fraction(model.auc)} average_precision ${real(model.averagePrecision)}`,
        `youden threshold ${real(y.threshold, 6)} tpr ${ratio(y.tp, positive)} fpr ${ratio(y.fp, negative)} j ${ratio(y.tp * negative - y.fp * positive, positive * negative)}`,
        `best_f1 threshold ${real(best.threshold, 6)} precision ${ratio(best.tp, best.tp + best.fp)} recall ${ratio(best.tp, positive)} f1 ${ratio(2 * best.tp, positive + best.tp + best.fp)}`,
        `min_cost threshold ${real(cost.threshold, 6)} cost ${cost.cost} fp ${cost.fp} fn ${positive - cost.tp}`, 'calibration' ];
    model.calibration.bins.forEach((bin, i) => lines.push(`bin ${binRange(i)} count ${bin.count} mean_probability ${real(bin.count === 0 ? null : bin.total / bin.count)} positive_rate ${ratio(bin.positives, bin.count)}`));
    const c = model.calibration;
    lines.push(`ece ${real(c.ece)} mce ${real(c.mce)} hosmer_lemeshow ${real(c.hl)} groups ${c.groups}`, 'gains');
    for (const g of model.gains) lines.push(`decile ${g.decile} rows ${g.size} positives ${g.hits} gain ${ratio(g.hits, positive)} lift ${ratio(g.hits * data.test.count, g.size * positive)}`);
    return lines;
}
function agreementLines(data: Data, models: BinaryModel[]): string[] {
    const lines: string[] = [];
    for (const [first, second] of [[0, 1], [0, 2], [1, 2]]) {
        const a = models[first], b = models[second];
        let same = 0, onlyFirst = 0, onlySecond = 0;
        for (let i = 0; i < data.test.count; i++) {
            const pa = a.confusion.predictions[i], pb = b.confusion.predictions[i];
            if (pa === pb) same++; else if (pa === data.test.targets[i]) onlyFirst++; else onlySecond++;
        }
        const corrected = Math.abs(onlyFirst - onlySecond) - 1;
        lines.push(`agreement ${a.name} ${b.name} same ${same}/${data.test.count} only_first ${onlyFirst} only_second ${onlySecond} mcnemar ${ratio(corrected * corrected, onlyFirst + onlySecond)}`);
    }
    return lines;
}
function diagnosticLines(data: Data, state: State): string[] {
    const d = state.diagnostics, measures = state.influence, model = state.models[2];
    const lines = [`diagnostics newton lambda ${real(state.lambda)}`,
        `fit null_loss ${real(d.nullLoss, 6)} train_loss ${real(measures.loss, 6)} mcfadden_r2 ${real(d.mcfadden)} deviance ${real(measures.deviance)} edf ${real(measures.edf)} aic ${real(measures.aic)} bic ${real(measures.bic)}`,
        `hosmer_lemeshow_train groups 10 statistic ${real(d.hl)}`];
    for (const g of d.groups) lines.push(`group ${g.group} rows ${g.size} observed ${g.observed} expected ${real(g.expected)}`);
    lines.push('newton_iterations');
    for (const t of d.iterations) lines.push(`iteration ${t.iteration} objective ${real(t.objective, 6)} gradient_norm ${real(t.gradient, 6)} step_norm ${real(t.step, 6)} predicted_decrease ${real(t.decrease, 6)}`);
    for (const marginal of d.marginals) lines.push(`marginal ${marginal.name} average ${real(marginal.average)} at_mean ${real(marginal.atMean)}`);
    for (const c of d.thresholds) lines.push(`cut 0.${c.digit} positive ${c.tp + c.fp} tp ${c.tp} fp ${c.fp} precision ${ratio(c.tp, c.tp + c.fp)} recall ${ratio(c.tp, c.tp + c.fn)} accuracy ${ratio(c.tp + c.tn, data.test.count)}`);
    for (const i of d.errors) lines.push(`error ${data.test.ids[i]} actual ${data.test.targets[i]} probability ${real(model.test.probabilities[i], 6)}`);
    const b = d.bootstrap;
    lines.push(`bootstrap resamples ${data.settings.bootstrap[0]} seed ${data.settings.bootstrap[1]} auc_mean ${real(b.mean)} auc_sd ${real(b.sd)} lower ${fraction(b.lower)} upper ${fraction(b.upper)}`,
        `influence effective_parameters ${real(measures.edf)} large_residuals ${d.largeResiduals}`);
    for (const row of d.cooks) lines.push(`cook ${data.train.ids[row.index]} actual ${data.train.targets[row.index]} probability ${real(row.probability)} leverage ${real(row.leverage)} residual ${real(row.residual)} distance ${real(row.cook)}`);
    return lines;
}
function softmaxLines(data: Data, model: MulticlassModel): string[] {
    const lines = [`softmax classes ${data.classes} lambda ${real(data.settings.softmax[2])} iterations ${data.settings.softmax[1]}`, 'confusion'];
    for (const row of model.table) lines.push(row.join(' '));
    for (let k = 0; k < data.classes; k++) {
        const diagonal = model.table[k][k];
        lines.push(`class ${k} precision ${ratio(diagonal, model.columnTotals[k])} recall ${ratio(diagonal, model.rowTotals[k])} f1 ${ratio(2 * diagonal, model.columnTotals[k] + model.rowTotals[k])} auc ${fraction(model.classAUC[k])}`);
    }
    lines.push(`accuracy ${ratio(model.correct, data.test.count)} kappa ${ratio(model.kappa[0], model.kappa[1])}`,
        `log_loss ${real(model.loss, 6)} brier ${real(model.brier, 6)}`,
        `binary_view positive_class ${data.settings.positive} auc ${fraction(model.binaryAUC)} log_loss ${real(model.binaryLoss, 6)} accuracy ${ratio(model.binaryConfusion.correct, data.test.count)} agreement_with_newton ${model.agreement}/${data.test.count}`, 'confidence');
    model.bins.forEach((bin, i) => lines.push(`bin ${binRange(i)} count ${bin.count} mean_confidence ${real(bin.count === 0 ? null : bin.total / bin.count)} accuracy ${ratio(bin.hits, bin.count)}`));
    lines.push(`ece ${real(model.ece)}`); return lines;
}
function evaluationReport(data: Data, state: State): string[] {
    const n = data.train.count, m = data.test.count, lambda = state.lambda, validation = state.validation;
    const parts: string[][] = [[
        `data train ${n} test ${m} base_features ${data.names.length} degree ${data.settings.degree} features ${data.features.length}`,
        `binary positive_class ${data.settings.positive} train ${data.train.positive}/${n} test ${data.test.positive}/${m}`,
        `classes ${data.classes} train ${data.train.classCounts.join(' ')} test ${data.test.classCounts.join(' ')}` ]];
    const cv = ['cross_validation folds 5 newton_iterations 10'];
    for (const c of validation.candidates) cv.push(`lambda ${real(c.lambda)} fold_loss ${c.foldLosses.map(v => real(v, 6)).join(' ')} cv_loss ${real(c.loss, 6)} errors ${c.errors}/${n}`);
    cv.push(`selected lambda ${real(lambda)} cv_loss ${real(validation.selected.loss, 6)} se ${real(validation.se, 6)} lambda_1se ${real(validation.oneSE)}`);
    const { tp, fp, tn, fn } = validation.confusion;
    cv.push(`out_of_fold tp ${tp} fp ${fp} tn ${tn} fn ${fn} accuracy ${ratio(tp + tn, n)} auc ${fraction(validation.auc)}`); parts.push(cv);
    const path = ['lambda_path'];
    for (const p of state.path) path.push(`lambda ${real(p.lambda)} objective ${real(p.train.objective, 6)} train_loss ${real(p.train.loss, 6)} test_loss ${real(p.test.loss, 6)} train_accuracy ${ratio(p.trainCorrect, n)} test_accuracy ${ratio(p.testCorrect, m)} norm ${real(p.norm)}`);
    parts.push(path);
    const degrees = [`degrees lambda ${real(lambda)}`];
    for (const d of state.degrees) degrees.push(`degree ${d.degree} features ${d.width} cv_loss ${real(d.cv, 6)} train_loss ${real(d.train.loss, 6)} test_loss ${real(d.test.loss, 6)} test_accuracy ${ratio(d.testCorrect, m)} auc ${fraction(d.auc)} edf ${real(d.influence.edf)} aic ${real(d.influence.aic)} bic ${real(d.influence.bic)}`);
    parts.push(degrees);
    const learning = [`learning_curve lambda ${real(lambda)}`];
    for (const p of state.learning) learning.push(`size ${p.size} train_loss ${real(p.train.loss, 6)} test_loss ${real(p.test.loss, 6)} test_accuracy ${ratio(p.testCorrect, m)} auc ${fraction(p.auc)}`);
    parts.push(learning, ...state.models.map(model => binaryLines(data, model, lambda)), agreementLines(data, state.models), diagnosticLines(data, state));
    const binary = state.models[2], importance = [`importance repeats ${data.settings.permutation[0]} seed ${data.settings.permutation[1]}`,
        `baseline log_loss ${real(binary.test.loss, 6)} auc ${fraction(binary.auc)} softmax_accuracy ${ratio(state.softmax.correct, m)}`];
    for (const f of state.importance) importance.push(`feature ${f.name} log_loss_increase ${real(f.increase, 6)} auc ${fraction(f.auc)} softmax_accuracy ${ratio(f.correct, f.total)}`);
    parts.push(importance, ['profiles', ...state.profiles.map(p => `profile ${p.name} value ${real(p.value)} newton ${real(p.probability)} softmax ${p.probabilities.map(v => real(v)).join(' ')}`)], softmaxLines(data, state.softmax));
    const ovr = [`one_vs_rest lambda ${real(data.settings.softmax[2])} newton_iterations 10`];
    for (const c of state.oneVersusRest.classes) ovr.push(`class ${c.label} objective ${real(c.objective, 6)} auc ${fraction(c.auc)}`);
    ovr.push(`accuracy ${ratio(state.oneVersusRest.correct, m)} agreement_with_softmax ${state.oneVersusRest.agreement}/${m}`); parts.push(ovr);
    parts.push([`map ${data.names[0]} ${data.names[1]} width ${data.settings.map[0]} height ${data.settings.map[1]}`, 'softmax_classes',
        ...state.maps.classes, `cells ${state.maps.counts.join(' ')}`, 'newton_probability', ...state.maps.probabilities]);
    return sections(parts);
}
function main(): void {
    const data = prepareData(), state = buildState(data);
    const reports: [string, string[]][] = [ ['weights.txt', weightsReport(data, state)], ['loss_trace.csv', lossTrace(data, state)],
        ['predictions.csv', predictionsReport(data, state)], ['evaluation.txt', evaluationReport(data, state)], ['roc.csv', rocReport(data, state.models)] ];
    mkdirSync('output', { recursive: true });
    for (const [name, lines] of reports) writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}

main();
