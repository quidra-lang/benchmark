'use strict';

const fs = require('node:fs');
const { readInputs, expandedFeatures, expand, statistics, standardizeOne, standardize } = require('./dataset');
const logistic = require('./logistic');
const { Minstd, shuffle, cholesky, solveFactor, gradientDescent, stochasticDescent, newton } = require('./optimizers');
const softmax = require('./softmax');
const { real, ratio, fraction, compareFractions, confusion, auc, rocPoints } = require('./metrics');

function sum(values, term = value => value) {
    let total = 0;
    for (let index = 0; index < values.length; index++) total += term(values[index], index);
    return total;
}

function length(vector) {
    return Math.sqrt(sum(vector, value => value * value));
}

function prepareData() {
    const data = readInputs();
    data.features = expandedFeatures(data.names, data.settings.degree);
    data.classes = Math.max(...data.train.labels) + 1;
    for (const rows of [data.train, data.test]) {
        rows.count = rows.ids.length;
        rows.expanded = rows.base.map(values => expand(values, data.features));
        rows.targets = rows.labels.map(label => Number(label === data.settings.positive));
        rows.positive = sum(rows.targets);
        rows.classCounts = Array(data.classes).fill(0);
        for (const label of rows.labels) rows.classCounts[label]++;
    }
    data.statistics = statistics(data.train.expanded);
    data.train.vectors = standardize(data.train.expanded, data.statistics);
    data.test.vectors = standardize(data.test.expanded, data.statistics);
    data.baseMean = data.statistics.means.slice(0, data.names.length);
    data.bounds = data.names.map((_, feature) => ({
        low: Math.min(...data.train.base.map(values => values[feature])),
        high: Math.max(...data.train.base.map(values => values[feature])),
    }));
    return data;
}

function inverse(matrix) {
    const factor = cholesky(matrix);
    const result = matrix.map(() => Array(matrix.length));
    for (let column = 0; column < matrix.length; column++) {
        const right = Array(matrix.length).fill(0);
        right[column] = 1;
        const solution = solveFactor(factor, right);
        for (let row = 0; row < matrix.length; row++) result[row][column] = solution[row];
    }
    return result;
}

function influence(weights, vectors, targets, lambda) {
    const evaluation = logistic.evaluate(weights, vectors, targets, lambda);
    const matrix = inverse(logistic.hessian(weights, vectors, lambda));
    const rows = vectors.map((vector, row) => {
        const probability = evaluation.probabilities[row];
        const variance = probability * (1 - probability);
        let quadratic = 0;
        for (let first = 0; first < weights.length; first++) {
            for (let second = 0; second < weights.length; second++) quadratic += vector[first] * matrix[first][second] * vector[second];
        }
        const leverage = variance * quadratic / vectors.length;
        const pearson = (targets[row] - probability) / Math.sqrt(variance);
        const residual = pearson / Math.sqrt(1 - leverage);
        const cook = pearson * pearson * leverage / (weights.length * ((1 - leverage) * (1 - leverage)));
        return { index: row, probability, leverage, residual, cook };
    });
    const edf = sum(rows, row => row.leverage);
    const deviance = 2 * vectors.length * evaluation.loss;
    return { matrix, rows, edf, deviance, loss: evaluation.loss,
        aic: deviance + 2 * edf, bic: deviance + Math.log(vectors.length) * edf };
}

function originalWeights(weights, stats) {
    const result = weights.map((value, component) => component === 0 ? value : value / stats.deviations[component - 1]);
    let shift = 0;
    for (let component = 1; component < result.length; component++) shift += result[component] * stats.means[component - 1];
    result[0] = weights[0] - shift;
    return result;
}

function featureCorrelations(data) {
    const matrix = data.features.map((_, first) => data.features.map((__, second) =>
        sum(data.train.vectors, vector => vector[first + 1] * vector[second + 1]) / (data.train.count - 1)));
    const inverted = inverse(matrix);
    return { matrix, vif: inverted.map((row, index) => row[index]) };
}

function crossValidate(data, width, lambda) {
    const losses = Array(data.train.count);
    const probabilities = Array(data.train.count);
    const foldLosses = [];
    let errors = 0;
    for (let fold = 0; fold < 5; fold++) {
        const training = [];
        const validation = [];
        for (let row = 0; row < data.train.count; row++) (row % 5 === fold ? validation : training).push(row);
        const stats = statistics(training.map(row => data.train.expanded[row]), width);
        const vectors = standardize(training.map(row => data.train.expanded[row]), stats);
        const targets = training.map(row => data.train.targets[row]);
        const fitted = newton(vectors, targets, lambda);
        let foldLoss = 0;
        for (const row of validation) {
            const vector = standardizeOne(data.train.expanded[row], stats);
            const score = logistic.score(fitted.weights, vector);
            losses[row] = logistic.loss(score, data.train.targets[row]);
            probabilities[row] = logistic.sigmoid(score);
            foldLoss += losses[row];
            if (Number(probabilities[row] >= data.settings.threshold) !== data.train.targets[row]) errors++;
        }
        foldLosses.push(foldLoss / validation.length);
    }
    return { lambda, foldLosses, loss: sum(losses) / data.train.count, errors, probabilities };
}

function selectLambda(data) {
    const candidates = data.settings.lambdas.map(lambda => crossValidate(data, data.features.length, lambda));
    let selected = candidates[0];
    for (const candidate of candidates) if (candidate.loss <= selected.loss) selected = candidate;
    const mean = sum(selected.foldLosses) / 5;
    const se = Math.sqrt(sum(selected.foldLosses, value => (value - mean) * (value - mean)) / 4) / Math.sqrt(5);
    let oneSE = candidates[0].lambda;
    for (const candidate of candidates) if (candidate.loss <= selected.loss + se) oneSE = candidate.lambda;
    return { candidates, selected, se, oneSE,
        confusion: confusion(selected.probabilities, data.train.targets, data.settings.threshold),
        auc: auc(selected.probabilities, data.train.targets) };
}

function fitSummary(weights, training, targets, testing, testTargets, lambda, threshold) {
    const train = logistic.evaluate(weights, training, targets, lambda);
    const test = logistic.evaluate(weights, testing, testTargets);
    return { weights, train, test, norm: length(weights.slice(1)),
        trainCorrect: confusion(train.probabilities, targets, threshold).correct,
        testCorrect: confusion(test.probabilities, testTargets, threshold).correct,
        auc: auc(test.probabilities, testTargets) };
}

function lambdaPath(data) {
    return data.settings.lambdas.map(lambda => {
        const fitted = newton(data.train.vectors, data.train.targets, lambda);
        return { lambda, ...fitSummary(fitted.weights, data.train.vectors, data.train.targets,
            data.test.vectors, data.test.targets, lambda, data.settings.threshold) };
    });
}

function degreeComparison(data, lambda) {
    const results = [];
    for (let degree = 1; degree <= data.settings.degree; degree++) {
        const width = data.features.filter(feature => feature.degree <= degree).length;
        const training = data.train.vectors.map(vector => vector.slice(0, width + 1));
        const testing = data.test.vectors.map(vector => vector.slice(0, width + 1));
        const fitted = newton(training, data.train.targets, lambda);
        results.push({ degree, width, cv: crossValidate(data, width, lambda).loss,
            ...fitSummary(fitted.weights, training, data.train.targets, testing, data.test.targets, lambda, data.settings.threshold),
            influence: influence(fitted.weights, training, data.train.targets, lambda) });
    }
    return results;
}

function learningCurve(data, lambda) {
    const results = [];
    for (let step = 1; step <= 4; step++) {
        const size = Math.floor(step * data.train.count / 4);
        const expanded = data.train.expanded.slice(0, size);
        const stats = statistics(expanded);
        const training = standardize(expanded, stats);
        const testing = standardize(data.test.expanded, stats);
        const targets = data.train.targets.slice(0, size);
        const fitted = newton(training, targets, lambda);
        results.push({ size, ...fitSummary(fitted.weights, training, targets, testing, data.test.targets, lambda, data.settings.threshold) });
    }
    return results;
}

function trainModels(data, lambda) {
    const training = data.train.vectors;
    const targets = data.train.targets;
    return [
        { name: 'gd', ...gradientDescent(training, targets, lambda, ...data.settings.gd) },
        { name: 'sgd', ...stochasticDescent(training, targets, lambda, ...data.settings.sgd) },
        { name: 'newton', ...newton(training, targets, lambda) },
    ];
}

function calibration(probabilities, targets) {
    const bins = Array.from({ length: 10 }, () => ({ count: 0, total: 0, positives: 0 }));
    probabilities.forEach((probability, index) => {
        const bin = bins[Math.min(9, Math.floor(probability * 10))];
        bin.count++;
        bin.total += probability;
        bin.positives += targets[index];
    });
    let ece = 0;
    let mce = 0;
    let hl = 0;
    let groups = 0;
    for (const bin of bins) {
        if (bin.count === 0) continue;
        groups++;
        ece += Math.abs(bin.total - bin.positives);
        mce = Math.max(mce, Math.abs(bin.total / bin.count - bin.positives / bin.count));
        const difference = bin.positives - bin.total;
        hl += difference * difference / (bin.total * (1 - bin.total / bin.count));
    }
    return { bins, ece: ece / probabilities.length, mce, hl, groups };
}

function binaryAnalysis(data, fitted, lambda) {
    const result = fitSummary(fitted.weights, data.train.vectors, data.train.targets,
        data.test.vectors, data.test.targets, lambda, data.settings.threshold);
    const probabilities = result.test.probabilities;
    const table = confusion(probabilities, data.test.targets, data.settings.threshold);
    const points = rocPoints(probabilities, data.test.targets);
    const positive = data.test.positive;
    const negative = data.test.count - positive;
    const [falsePositiveCost, falseNegativeCost] = data.settings.cost;
    const cost = point => falsePositiveCost * point.fp + falseNegativeCost * (positive - point.tp);
    const youdenValue = point => point.tp * negative - point.fp * positive;
    let youden = points[0];
    let bestF1 = points[0];
    let minCost = points[0];
    let averagePrecision = 0;
    let previousTP = 0;
    for (const point of points) {
        averagePrecision += (point.tp - previousTP) * point.tp / (point.tp + point.fp);
        previousTP = point.tp;
        if (youdenValue(point) > youdenValue(youden)) youden = point;
        if (compareFractions([2 * point.tp, positive + point.tp + point.fp],
            [2 * bestF1.tp, positive + bestF1.tp + bestF1.fp]) > 0) bestF1 = point;
        if (cost(point) < cost(minCost)) minCost = point;
    }
    const order = probabilities.map((_, index) => index).sort((a, b) => probabilities[b] - probabilities[a] || a - b);
    const gains = [];
    for (let decile = 1; decile <= 10; decile++) {
        const size = Math.floor(decile * data.test.count / 10);
        gains.push({ decile, size, hits: sum(order.slice(0, size), row => data.test.targets[row]) });
    }
    return { ...fitted, ...result, confusion: table, points, youden, bestF1, minCost: { ...minCost, cost: cost(minCost) },
        averagePrecision: averagePrecision / positive,
        brier: sum(probabilities, (probability, row) => (probability - data.test.targets[row]) * (probability - data.test.targets[row])) / data.test.count,
        calibration: calibration(probabilities, data.test.targets), gains };
}

function multiclassAnalysis(data, fitted, binary) {
    const evaluation = softmax.evaluate(fitted.weights, data.test.vectors, data.test.labels);
    const table = Array.from({ length: data.classes }, () => Array(data.classes).fill(0));
    const bins = Array.from({ length: 10 }, () => ({ count: 0, total: 0, hits: 0 }));
    let brier = 0;
    let correct = 0;
    evaluation.rows.forEach((row, index) => {
        table[data.test.labels[index]][row.predicted]++;
        const hit = Number(row.predicted === data.test.labels[index]);
        correct += hit;
        let squared = 0;
        row.probabilities.forEach((probability, label) => {
            const difference = probability - Number(label === data.test.labels[index]);
            squared += difference * difference;
        });
        brier += squared;
        const confidence = row.probabilities[row.predicted];
        const bin = bins[Math.min(9, Math.floor(confidence * 10))];
        bin.count++;
        bin.total += confidence;
        bin.hits += hit;
    });
    const rowTotals = table.map(row => sum(row));
    const columnTotals = table.map((_, column) => sum(table, row => row[column]));
    const expected = sum(rowTotals, (total, label) => total * columnTotals[label]);
    const classAUC = table.map((_, label) => auc(evaluation.rows.map(row => row.probabilities[label]), data.test.labels.map(value => Number(value === label))));
    const probabilities = evaluation.rows.map(row => row.probabilities[data.settings.positive]);
    const binaryConfusion = confusion(probabilities, data.test.targets, data.settings.threshold);
    const binaryLoss = sum(probabilities, (probability, index) => -Math.log(data.test.targets[index] === 1 ? probability : 1 - probability)) / data.test.count;
    const agreement = sum(binaryConfusion.predictions, (prediction, index) => Number(prediction === binary.confusion.predictions[index]));
    const ece = sum(bins, bin => bin.count === 0 ? 0 : Math.abs(bin.total - bin.hits)) / data.test.count;
    return { ...fitted, ...evaluation, table, rowTotals, columnTotals, classAUC, correct, brier: brier / data.test.count,
        kappa: [data.test.count * correct - expected, data.test.count * data.test.count - expected],
        binaryAUC: auc(probabilities, data.test.targets), binaryConfusion, binaryLoss, agreement, bins, ece };
}

function bootstrap(data, probabilities) {
    const [count, seed] = data.settings.bootstrap;
    const generator = new Minstd(seed);
    const results = [];
    for (let replicate = 0; replicate < count; replicate++) {
        const selected = [];
        for (let draw = 0; draw < data.test.count; draw++) selected.push(generator.draw() % data.test.count);
        const value = auc(selected.map(row => probabilities[row]), selected.map(row => data.test.targets[row]));
        results.push({ fraction: value, value: value[0] / value[1] });
    }
    const mean = sum(results, item => item.value) / count;
    const sd = Math.sqrt(sum(results, item => (item.value - mean) * (item.value - mean)) / (count - 1));
    const sorted = results.slice().sort((a, b) => a.value - b.value);
    return { mean, sd, lower: sorted[Math.floor(count / 40)].fraction, upper: sorted[count - Math.floor(count / 40) - 1].fraction };
}

function slope(data, weights, base, feature) {
    let total = 0;
    data.features.forEach((expanded, index) => {
        let count = 0;
        for (const component of expanded.tuple) if (component === feature) count++;
        if (count === 0) return;
        let product = 1;
        let removed = false;
        for (const component of expanded.tuple) {
            if (component === feature && !removed) removed = true;
            else product *= base[component];
        }
        total += weights[index + 1] * (count * product);
    });
    return total;
}

function newtonDiagnostics(data, model, lambda, measures) {
    const positiveRate = data.train.positive / data.train.count;
    const nullLoss = -(positiveRate * Math.log(positiveRate) + (1 - positiveRate) * Math.log(1 - positiveRate));
    const sorted = measures.rows.slice().sort((a, b) => a.probability - b.probability || a.index - b.index);
    const groups = [];
    let hl = 0;
    for (let group = 1; group <= 10; group++) {
        const rows = sorted.slice(Math.floor((group - 1) * data.train.count / 10), Math.floor(group * data.train.count / 10));
        const expected = sum(rows, row => row.probability);
        const observed = sum(rows, row => data.train.targets[row.index]);
        const difference = observed - expected;
        hl += difference * difference / (expected * (1 - expected / rows.length));
        groups.push({ group, size: rows.length, observed, expected });
    }
    const iterations = model.steps.map((step, index) => ({
        iteration: index + 1,
        objective: logistic.evaluate(model.checkpoints[index].weights, data.train.vectors, data.train.targets, lambda).objective,
        gradient: length(step.gradient), step: length(step.delta),
        decrease: sum(step.gradient, (value, component) => value * step.delta[component]) / 2,
    }));
    const original = originalWeights(model.weights, data.statistics);
    const meanVector = standardizeOne(expand(data.baseMean, data.features), data.statistics);
    const meanProbability = logistic.sigmoid(logistic.score(model.weights, meanVector));
    const marginals = data.names.map((name, feature) => ({ name,
        average: sum(measures.rows, row => row.probability * (1 - row.probability) * slope(data, original, data.train.base[row.index], feature)) / data.train.count,
        atMean: meanProbability * (1 - meanProbability) * slope(data, original, data.baseMean, feature) }));
    const thresholds = [];
    for (let digit = 1; digit <= 9; digit++) thresholds.push({ digit, ...confusion(model.test.probabilities, data.test.targets, digit / 10) });
    const errors = model.confusion.predictions.map((_, index) => index)
        .filter(index => model.confusion.predictions[index] !== data.test.targets[index])
        .sort((a, b) => Math.abs(model.test.probabilities[b] - data.settings.threshold) - Math.abs(model.test.probabilities[a] - data.settings.threshold) || a - b).slice(0, 5);
    const cooks = measures.rows.slice().sort((a, b) => b.cook - a.cook || a.index - b.index).slice(0, 5);
    return { nullLoss, mcfadden: 1 - measures.loss / nullLoss, groups, hl, iterations, marginals, thresholds, errors,
        bootstrap: bootstrap(data, model.test.probabilities), cooks, largeResiduals: measures.rows.filter(row => Math.abs(row.residual) > 2).length };
}

function permutationImportance(data, binary, multiclass) {
    const [repetitions, seed] = data.settings.permutation;
    const generator = new Minstd(seed);
    return data.names.map((name, feature) => {
        let losses = 0;
        let numerators = 0;
        let correct = 0;
        for (let repeat = 0; repeat < repetitions; repeat++) {
            const order = data.test.ids.map((_, index) => index);
            shuffle(order, generator);
            const base = data.test.base.map((row, index) => row.map((value, component) =>
                component === feature ? data.test.base[order[index]][feature] : value));
            const vectors = standardize(base.map(values => expand(values, data.features)), data.statistics);
            const evaluation = logistic.evaluate(binary.weights, vectors, data.test.targets);
            losses += evaluation.loss;
            numerators += auc(evaluation.probabilities, data.test.targets)[0];
            const classRows = softmax.evaluate(multiclass.weights, vectors, data.test.labels).rows;
            correct += sum(classRows, (row, index) => Number(row.predicted === data.test.labels[index]));
        }
        return { name, increase: losses / repetitions - binary.test.loss,
            auc: [numerators, repetitions * binary.auc[1]], correct, total: repetitions * data.test.count };
    });
}

function predictPoint(data, binary, multiclass, base) {
    const vector = standardizeOne(expand(base, data.features), data.statistics);
    return { probability: logistic.sigmoid(logistic.score(binary.weights, vector)),
        ...softmax.rowValues(multiclass.weights, vector) };
}

function profiles(data, binary, multiclass) {
    const results = [];
    data.names.forEach((name, feature) => {
        const { low, high } = data.bounds[feature];
        for (let point = 0; point <= 4; point++) {
            const base = data.baseMean.slice();
            base[feature] = low + (high - low) * point / 4;
            results.push({ name, value: base[feature], ...predictPoint(data, binary, multiclass, base) });
        }
    });
    return results;
}

function oneVersusRest(data, multiclass) {
    const lambda = data.settings.softmax[2];
    const classes = [];
    for (let label = 0; label < data.classes; label++) {
        const targets = data.train.labels.map(value => Number(value === label));
        const testTargets = data.test.labels.map(value => Number(value === label));
        const fitted = newton(data.train.vectors, targets, lambda);
        const evaluation = logistic.evaluate(fitted.weights, data.test.vectors, testTargets);
        classes.push({ label, objective: logistic.evaluate(fitted.weights, data.train.vectors, targets, lambda).objective,
            probabilities: evaluation.probabilities, auc: auc(evaluation.probabilities, testTargets) });
    }
    let correct = 0;
    let agreement = 0;
    for (let row = 0; row < data.test.count; row++) {
        let predicted = 0;
        for (let label = 1; label < data.classes; label++) {
            if (classes[label].probabilities[row] > classes[predicted].probabilities[row]) predicted = label;
        }
        if (predicted === data.test.labels[row]) correct++;
        if (predicted === multiclass.rows[row].predicted) agreement++;
    }
    return { classes, correct, agreement };
}

function predictionMaps(data, binary, multiclass) {
    const [width, height] = data.settings.map;
    const first = data.bounds[0];
    const second = data.bounds[1];
    const classes = [];
    const probabilities = [];
    const counts = Array(data.classes).fill(0);
    for (let row = 0; row < height; row++) {
        let classLine = '';
        let probabilityLine = '';
        for (let column = 0; column < width; column++) {
            const base = data.baseMean.slice();
            base[0] = first.low + (column + 0.5) * (first.high - first.low) / width;
            base[1] = second.high - (row + 0.5) * (second.high - second.low) / height;
            const prediction = predictPoint(data, binary, multiclass, base);
            classLine += prediction.predicted;
            probabilityLine += Math.min(9, Math.floor(prediction.probability * 10));
            counts[prediction.predicted]++;
        }
        classes.push(classLine);
        probabilities.push(probabilityLine);
    }
    return { classes, probabilities, counts };
}

function sections(parts) {
    return parts.flatMap((part, index) => index === 0 ? part : ['', ...part]);
}

function termLines(data, weights) {
    const original = originalWeights(weights, data.statistics);
    const names = ['intercept', ...data.features.map(feature => feature.name)];
    return names.map((name, component) => `term ${name} standardized ${real(weights[component])} original ${real(original[component])}`);
}

function weightsReport(data, state) {
    const parts = [];
    const features = [`features ${data.names.length} degree ${data.settings.degree} expanded ${data.features.length}`, 'standardization'];
    data.features.forEach((feature, index) => features.push(`${feature.name} mean ${real(data.statistics.means[index], 6)} sd ${real(data.statistics.deviations[index], 6)} vif ${real(state.correlations.vif[index])}`));
    features.push('correlation', ...state.correlations.matrix.map(row => row.map(value => real(value)).join(' ')));
    parts.push(features);
    const binary = state.models[2];
    for (const model of state.models) {
        const lines = [`model ${model.name} lambda ${real(state.lambda)}`, ...termLines(data, model.weights), `norm ${real(model.norm)}`];
        if (model.name !== 'newton') lines.push(`distance_to_newton ${real(length(model.weights.map((weight, index) => weight - binary.weights[index])), 6)}`);
        parts.push(lines);
    }
    const coefficients = [`coefficients newton lambda ${real(state.lambda)}`];
    const names = ['intercept', ...data.features.map(feature => feature.name)];
    binary.weights.forEach((weight, component) => {
        const se = Math.sqrt(state.influence.matrix[component][component] / data.train.count);
        coefficients.push(`${names[component]} weight ${real(weight)} se ${real(se)} z ${real(weight / se)} lower ${real(weight - 1.96 * se)} upper ${real(weight + 1.96 * se)} odds_ratio ${real(Math.exp(weight))}`);
    });
    parts.push(coefficients);
    const multiclass = [`model softmax lambda ${real(data.settings.softmax[2])}`];
    state.softmax.weights.forEach((weights, label) => multiclass.push(`class ${label}`, ...termLines(data, weights)));
    parts.push(multiclass);
    return sections(parts);
}

function lossTrace(data, state) {
    const lines = ['optimizer,iteration,loss,gradient_norm,test_loss'];
    for (const model of state.models) {
        for (const checkpoint of model.checkpoints) {
            const training = logistic.evaluate(checkpoint.weights, data.train.vectors, data.train.targets, state.lambda);
            const direction = logistic.gradient(checkpoint.weights, data.train.vectors, data.train.targets, state.lambda);
            const testing = logistic.evaluate(checkpoint.weights, data.test.vectors, data.test.targets);
            lines.push([model.name, checkpoint.iteration, real(training.objective, 6), real(length(direction), 6), real(testing.loss, 6)].join(','));
        }
    }
    for (const checkpoint of state.softmax.checkpoints) {
        const training = softmax.evaluate(checkpoint.weights, data.train.vectors, data.train.labels, data.settings.softmax[2]);
        const direction = softmax.gradient(checkpoint.weights, data.train.vectors, data.train.labels, data.settings.softmax[2]);
        const testing = softmax.evaluate(checkpoint.weights, data.test.vectors, data.test.labels);
        lines.push(['softmax', checkpoint.iteration, real(training.objective, 6), real(length(direction.flat()), 6), real(testing.loss, 6)].join(','));
    }
    return lines;
}

function predictionsReport(data, state) {
    const lines = ['id,model,probability,predicted,actual'];
    for (const model of state.models) {
        data.test.ids.forEach((id, index) => lines.push([id, model.name, real(model.test.probabilities[index], 6), model.confusion.predictions[index], data.test.targets[index]].join(',')));
    }
    state.softmax.rows.forEach((row, index) => lines.push([data.test.ids[index], 'softmax', real(row.probabilities[row.predicted], 6), row.predicted, data.test.labels[index]].join(',')));
    return lines;
}

function rocReport(data, models) {
    const lines = ['model,threshold,tpr,fpr,precision'];
    for (const model of models) {
        lines.push(`${model.name},inf,0.0000,0.0000,-`);
        for (const point of model.points) {
            lines.push([model.name, real(point.threshold, 6), ratio(point.tp, data.test.positive),
                ratio(point.fp, data.test.count - data.test.positive), ratio(point.tp, point.tp + point.fp)].join(','));
        }
    }
    return lines;
}

function dataLines(data) {
    return [
        `data train ${data.train.count} test ${data.test.count} base_features ${data.names.length} degree ${data.settings.degree} features ${data.features.length}`,
        `binary positive_class ${data.settings.positive} train ${data.train.positive}/${data.train.count} test ${data.test.positive}/${data.test.count}`,
        `classes ${data.classes} train ${data.train.classCounts.join(' ')} test ${data.test.classCounts.join(' ')}`,
    ];
}

function crossValidationLines(data, validation) {
    const lines = ['cross_validation folds 5 newton_iterations 10'];
    for (const candidate of validation.candidates) {
        lines.push(`lambda ${real(candidate.lambda)} fold_loss ${candidate.foldLosses.map(value => real(value, 6)).join(' ')} cv_loss ${real(candidate.loss, 6)} errors ${candidate.errors}/${data.train.count}`);
    }
    lines.push(`selected lambda ${real(validation.selected.lambda)} cv_loss ${real(validation.selected.loss, 6)} se ${real(validation.se, 6)} lambda_1se ${real(validation.oneSE)}`);
    const { tp, fp, tn, fn } = validation.confusion;
    lines.push(`out_of_fold tp ${tp} fp ${fp} tn ${tn} fn ${fn} accuracy ${ratio(tp + tn, data.train.count)} auc ${fraction(validation.auc)}`);
    return lines;
}

function pathLines(data, path) {
    const lines = ['lambda_path'];
    for (const model of path) {
        lines.push(`lambda ${real(model.lambda)} objective ${real(model.train.objective, 6)} train_loss ${real(model.train.loss, 6)} test_loss ${real(model.test.loss, 6)} train_accuracy ${ratio(model.trainCorrect, data.train.count)} test_accuracy ${ratio(model.testCorrect, data.test.count)} norm ${real(model.norm)}`);
    }
    return lines;
}

function degreeLines(data, state) {
    const lines = [`degrees lambda ${real(state.lambda)}`];
    for (const degree of state.degrees) {
        lines.push(`degree ${degree.degree} features ${degree.width} cv_loss ${real(degree.cv, 6)} train_loss ${real(degree.train.loss, 6)} test_loss ${real(degree.test.loss, 6)} test_accuracy ${ratio(degree.testCorrect, data.test.count)} auc ${fraction(degree.auc)} edf ${real(degree.influence.edf)} aic ${real(degree.influence.aic)} bic ${real(degree.influence.bic)}`);
    }
    return lines;
}

function learningLines(data, state) {
    const lines = [`learning_curve lambda ${real(state.lambda)}`];
    for (const model of state.learning) {
        lines.push(`size ${model.size} train_loss ${real(model.train.loss, 6)} test_loss ${real(model.test.loss, 6)} test_accuracy ${ratio(model.testCorrect, data.test.count)} auc ${fraction(model.auc)}`);
    }
    return lines;
}

function binRange(index) {
    return `0.${index}-${index === 9 ? '1.0' : `0.${index + 1}`}`;
}

function binaryLines(data, model, lambda) {
    const { tp, fp, tn, fn } = model.confusion;
    const positive = data.test.positive;
    const negative = data.test.count - positive;
    const youden = model.youden;
    const best = model.bestF1;
    const cost = model.minCost;
    const lines = [
        `model ${model.name} lambda ${real(lambda)}`,
        `train correct ${model.trainCorrect}/${data.train.count} accuracy ${ratio(model.trainCorrect, data.train.count)}`,
        `test tp ${tp} fp ${fp} tn ${tn} fn ${fn}`,
        `test accuracy ${ratio(tp + tn, data.test.count)} precision ${ratio(tp, tp + fp)} recall ${ratio(tp, tp + fn)} specificity ${ratio(tn, tn + fp)} f1 ${ratio(2 * tp, 2 * tp + fp + fn)}`,
        `log_loss ${real(model.test.loss, 6)} brier ${real(model.brier, 6)}`,
        `auc ${fraction(model.auc)} average_precision ${real(model.averagePrecision)}`,
        `youden threshold ${real(youden.threshold, 6)} tpr ${ratio(youden.tp, positive)} fpr ${ratio(youden.fp, negative)} j ${ratio(youden.tp * negative - youden.fp * positive, positive * negative)}`,
        `best_f1 threshold ${real(best.threshold, 6)} precision ${ratio(best.tp, best.tp + best.fp)} recall ${ratio(best.tp, positive)} f1 ${ratio(2 * best.tp, positive + best.tp + best.fp)}`,
        `min_cost threshold ${real(cost.threshold, 6)} cost ${cost.cost} fp ${cost.fp} fn ${positive - cost.tp}`,
        'calibration',
    ];
    model.calibration.bins.forEach((bin, index) => lines.push(`bin ${binRange(index)} count ${bin.count} mean_probability ${real(bin.count === 0 ? null : bin.total / bin.count)} positive_rate ${ratio(bin.positives, bin.count)}`));
    const calibration = model.calibration;
    lines.push(`ece ${real(calibration.ece)} mce ${real(calibration.mce)} hosmer_lemeshow ${real(calibration.hl)} groups ${calibration.groups}`, 'gains');
    for (const gain of model.gains) {
        lines.push(`decile ${gain.decile} rows ${gain.size} positives ${gain.hits} gain ${ratio(gain.hits, positive)} lift ${ratio(gain.hits * data.test.count, gain.size * positive)}`);
    }
    return lines;
}

function agreementLines(data, models) {
    const lines = [];
    for (const [first, second] of [[0, 1], [0, 2], [1, 2]]) {
        const a = models[first];
        const b = models[second];
        let same = 0;
        let onlyFirst = 0;
        let onlySecond = 0;
        for (let row = 0; row < data.test.count; row++) {
            const predictionA = a.confusion.predictions[row];
            const predictionB = b.confusion.predictions[row];
            if (predictionA === predictionB) same++;
            else if (predictionA === data.test.targets[row]) onlyFirst++;
            else onlySecond++;
        }
        const corrected = Math.abs(onlyFirst - onlySecond) - 1;
        lines.push(`agreement ${a.name} ${b.name} same ${same}/${data.test.count} only_first ${onlyFirst} only_second ${onlySecond} mcnemar ${ratio(corrected * corrected, onlyFirst + onlySecond)}`);
    }
    return lines;
}

function diagnosticLines(data, state) {
    const diagnostic = state.diagnostics;
    const measures = state.influence;
    const model = state.models[2];
    const lines = [
        `diagnostics newton lambda ${real(state.lambda)}`,
        `fit null_loss ${real(diagnostic.nullLoss, 6)} train_loss ${real(measures.loss, 6)} mcfadden_r2 ${real(diagnostic.mcfadden)} deviance ${real(measures.deviance)} edf ${real(measures.edf)} aic ${real(measures.aic)} bic ${real(measures.bic)}`,
        `hosmer_lemeshow_train groups 10 statistic ${real(diagnostic.hl)}`,
    ];
    for (const group of diagnostic.groups) lines.push(`group ${group.group} rows ${group.size} observed ${group.observed} expected ${real(group.expected)}`);
    lines.push('newton_iterations');
    for (const iteration of diagnostic.iterations) {
        lines.push(`iteration ${iteration.iteration} objective ${real(iteration.objective, 6)} gradient_norm ${real(iteration.gradient, 6)} step_norm ${real(iteration.step, 6)} predicted_decrease ${real(iteration.decrease, 6)}`);
    }
    for (const marginal of diagnostic.marginals) lines.push(`marginal ${marginal.name} average ${real(marginal.average)} at_mean ${real(marginal.atMean)}`);
    for (const cut of diagnostic.thresholds) {
        lines.push(`cut 0.${cut.digit} positive ${cut.tp + cut.fp} tp ${cut.tp} fp ${cut.fp} precision ${ratio(cut.tp, cut.tp + cut.fp)} recall ${ratio(cut.tp, cut.tp + cut.fn)} accuracy ${ratio(cut.tp + cut.tn, data.test.count)}`);
    }
    for (const row of diagnostic.errors) lines.push(`error ${data.test.ids[row]} actual ${data.test.targets[row]} probability ${real(model.test.probabilities[row], 6)}`);
    const resampling = diagnostic.bootstrap;
    lines.push(`bootstrap resamples ${data.settings.bootstrap[0]} seed ${data.settings.bootstrap[1]} auc_mean ${real(resampling.mean)} auc_sd ${real(resampling.sd)} lower ${fraction(resampling.lower)} upper ${fraction(resampling.upper)}`,
        `influence effective_parameters ${real(measures.edf)} large_residuals ${diagnostic.largeResiduals}`);
    for (const row of diagnostic.cooks) {
        lines.push(`cook ${data.train.ids[row.index]} actual ${data.train.targets[row.index]} probability ${real(row.probability)} leverage ${real(row.leverage)} residual ${real(row.residual)} distance ${real(row.cook)}`);
    }
    return lines;
}

function importanceLines(data, state) {
    const binary = state.models[2];
    const lines = [`importance repeats ${data.settings.permutation[0]} seed ${data.settings.permutation[1]}`,
        `baseline log_loss ${real(binary.test.loss, 6)} auc ${fraction(binary.auc)} softmax_accuracy ${ratio(state.softmax.correct, data.test.count)}`];
    for (const feature of state.importance) {
        lines.push(`feature ${feature.name} log_loss_increase ${real(feature.increase, 6)} auc ${fraction(feature.auc)} softmax_accuracy ${ratio(feature.correct, feature.total)}`);
    }
    return lines;
}

function profileLines(profiles) {
    return ['profiles', ...profiles.map(point => `profile ${point.name} value ${real(point.value)} newton ${real(point.probability)} softmax ${point.probabilities.map(value => real(value)).join(' ')}`)];
}

function softmaxLines(data, model) {
    const lines = [`softmax classes ${data.classes} lambda ${real(data.settings.softmax[2])} iterations ${data.settings.softmax[1]}`, 'confusion'];
    for (const row of model.table) lines.push(row.join(' '));
    for (let label = 0; label < data.classes; label++) {
        const diagonal = model.table[label][label];
        lines.push(`class ${label} precision ${ratio(diagonal, model.columnTotals[label])} recall ${ratio(diagonal, model.rowTotals[label])} f1 ${ratio(2 * diagonal, model.columnTotals[label] + model.rowTotals[label])} auc ${fraction(model.classAUC[label])}`);
    }
    lines.push(`accuracy ${ratio(model.correct, data.test.count)} kappa ${ratio(model.kappa[0], model.kappa[1])}`,
        `log_loss ${real(model.loss, 6)} brier ${real(model.brier, 6)}`,
        `binary_view positive_class ${data.settings.positive} auc ${fraction(model.binaryAUC)} log_loss ${real(model.binaryLoss, 6)} accuracy ${ratio(model.binaryConfusion.correct, data.test.count)} agreement_with_newton ${model.agreement}/${data.test.count}`,
        'confidence');
    model.bins.forEach((bin, index) => lines.push(`bin ${binRange(index)} count ${bin.count} mean_confidence ${real(bin.count === 0 ? null : bin.total / bin.count)} accuracy ${ratio(bin.hits, bin.count)}`));
    lines.push(`ece ${real(model.ece)}`);
    return lines;
}

function oneVersusRestLines(data, result) {
    const lines = [`one_vs_rest lambda ${real(data.settings.softmax[2])} newton_iterations 10`];
    for (const model of result.classes) lines.push(`class ${model.label} objective ${real(model.objective, 6)} auc ${fraction(model.auc)}`);
    lines.push(`accuracy ${ratio(result.correct, data.test.count)} agreement_with_softmax ${result.agreement}/${data.test.count}`);
    return lines;
}

function mapLines(data, maps) {
    return [`map ${data.names[0]} ${data.names[1]} width ${data.settings.map[0]} height ${data.settings.map[1]}`,
        'softmax_classes', ...maps.classes, `cells ${maps.counts.join(' ')}`, 'newton_probability', ...maps.probabilities];
}

function evaluationReport(data, state) {
    return sections([
        dataLines(data), crossValidationLines(data, state.validation), pathLines(data, state.path),
        degreeLines(data, state), learningLines(data, state),
        ...state.models.map(model => binaryLines(data, model, state.lambda)),
        agreementLines(data, state.models), diagnosticLines(data, state), importanceLines(data, state),
        profileLines(state.profiles), softmaxLines(data, state.softmax), oneVersusRestLines(data, state.oneVersusRest),
        mapLines(data, state.maps),
    ]);
}

function main() {
    const data = prepareData();
    const validation = selectLambda(data);
    const lambda = validation.selected.lambda;
    const models = trainModels(data, lambda).map(fitted => binaryAnalysis(data, fitted, lambda));
    const [rate, iterations, softmaxLambda] = data.settings.softmax;
    const multiclass = multiclassAnalysis(data, softmax.train(data.train.vectors, data.train.labels, data.classes, softmaxLambda, rate, iterations), models[2]);
    const measures = influence(models[2].weights, data.train.vectors, data.train.targets, lambda);
    const state = {
        validation, lambda, models, softmax: multiclass, influence: measures, correlations: featureCorrelations(data),
        path: lambdaPath(data), degrees: degreeComparison(data, lambda), learning: learningCurve(data, lambda),
        diagnostics: newtonDiagnostics(data, models[2], lambda, measures), importance: permutationImportance(data, models[2], multiclass),
        profiles: profiles(data, models[2], multiclass), oneVersusRest: oneVersusRest(data, multiclass), maps: predictionMaps(data, models[2], multiclass),
    };
    const reports = {
        'weights.txt': weightsReport(data, state), 'loss_trace.csv': lossTrace(data, state),
        'predictions.csv': predictionsReport(data, state), 'evaluation.txt': evaluationReport(data, state), 'roc.csv': rocReport(data, models),
    };
    fs.mkdirSync('output', { recursive: true });
    for (const [name, lines] of Object.entries(reports)) fs.writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}

if (require.main === module) main();
