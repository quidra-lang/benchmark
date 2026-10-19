'use strict';

const fs = require('node:fs');
const { readDataset } = require('./dataset');
const { majority, statistics, compareFractions, impurityDecrease } = require('./impurity');
const { bestForAttribute, growTree } = require('./tree_builder');
const { reducedError, costComplexity } = require('./pruning');
const {
    isLeaf, preorder, route, predict, correctCount, formatReal, ratio,
    reducedFraction, classificationLines,
} = require('./evaluation');

function minstd(seed) {
    let state = seed;
    return () => {
        state = (48271 * state) % 2147483647;
        return state;
    };
}

function thresholdText(value) {
    return `${Math.floor(value / 2)}.${value % 2 === 0 ? '0' : '5'}`;
}

function splitText(split, left, attributes) {
    const attribute = attributes[split.attribute];
    if (split.kind === 'INT') {
        return `${attribute.name} ${left ? '<=' : '>'} ${thresholdText(split.threshold)}`;
    }
    return `${attribute.name} ${left ? '=' : '!='} ${attribute.values[split.value]}`;
}

function viewAtDepth(root, depth) {
    const original = { root, cuts: new Set() };
    const cuts = new Set();
    for (const node of preorder(original)) {
        if (node.depth === depth && node.split !== null) cuts.add(node.number);
    }
    return { root, cuts };
}

function treeSummary(view) {
    const summary = { nodes: 0, leaves: 0, depth: 0, errors: 0, levels: [] };
    for (const node of preorder(view)) {
        summary.nodes++;
        if (summary.levels[node.depth] === undefined) {
            summary.levels[node.depth] = { nodes: 0, leaves: 0, rows: 0, errors: 0 };
        }
        const level = summary.levels[node.depth];
        level.nodes++;
        if (isLeaf(node, view)) {
            summary.leaves++;
            summary.depth = Math.max(summary.depth, node.depth);
            summary.errors += node.error;
            level.leaves++;
            level.rows += node.n;
            level.errors += node.error;
        }
    }
    return summary;
}

function treeLines(view, data) {
    const lines = [];
    function visit(node, condition) {
        let line = `${' '.repeat(2 * node.depth)}${node.number} ${condition} n ${node.n} counts ${node.counts.join(' ')}`;
        if (isLeaf(node, view)) line += ` leaf ${data.classes[node.majority]}`;
        lines.push(line);
        if (!isLeaf(node, view)) {
            visit(node.left, splitText(node.split, true, data.attributes));
            visit(node.right, splitText(node.split, false, data.attributes));
        }
    }
    visit(view.root, 'root');
    const summary = treeSummary(view);
    lines.push('');
    lines.push(`nodes ${summary.nodes} leaves ${summary.leaves} depth ${summary.depth} errors ${ratio(summary.errors, data.train.length)}`);
    for (let depth = 0; depth <= summary.depth; depth++) {
        const level = summary.levels[depth];
        lines.push(`level ${depth} nodes ${level.nodes} leaves ${level.leaves} rows ${level.rows} errors ${level.errors}`);
    }
    return lines;
}

function rootCandidateLines(data, root) {
    const candidates = [];
    for (let index = 0; index < data.attributes.length; index++) {
        const best = bestForAttribute(
            data.train, data.attributes[index], index,
            data.settings.minSamplesLeaf, data.classes.length
        );
        if (best !== null) candidates.push(best);
    }
    candidates.sort((a, b) => -compareFractions(a.value, b.value) || a.split.attribute - b.split.attribute);
    const count = data.train.length;
    const lines = [`root candidates n ${count} counts ${root.counts.join(' ')}`];
    for (let index = 0; index < candidates.length; index++) {
        const candidate = candidates[index];
        const gain = (candidate.value.numerator / candidate.value.denominator) / count
            - root.sumSquares / (count * count);
        const condition = splitText(candidate.split, true, data.attributes);
        lines.push(`${index + 1} ${condition} left ${candidate.left.length} right ${candidate.right.length} gain ${formatReal(gain, 6)}`);
    }
    return lines;
}

function surrogateLines(data, grown) {
    const lines = ['surrogates'];
    for (const node of preorder(grown)) {
        if (isLeaf(node, grown)) continue;
        const surrogates = node.surrogates.map(item => {
            const condition = splitText(item.split, true, data.attributes);
            return `${condition} ${item.direction} ${item.score}/${node.n}`;
        }).join(' ; ') || 'none';
        const condition = splitText(node.split, true, data.attributes);
        lines.push(`node ${node.number} split ${condition} default ${node.defaultDirection} surrogates ${surrogates}`);
    }
    return lines;
}

function pruningLines(result, validationCount) {
    const lines = [`reduced_error_pruning validation ${validationCount}`];
    let pruned = 0;
    for (const decision of result.decisions) {
        const { node, rows, leafError, subtreeError } = decision;
        const action = decision.pruned ? 'pruned' : 'kept';
        if (decision.pruned) pruned++;
        lines.push(`node ${node.number} depth ${node.depth} rows ${rows} leaf ${leafError} subtree ${subtreeError} ${action}`);
    }
    lines.push(`examined ${result.decisions.length} pruned ${pruned} kept ${result.decisions.length - pruned}`);
    return lines;
}

function predictionLines(data, grownRoutes, prunedRoutes) {
    const lines = ['id,predicted,actual,grown,leaf,path,missing'];
    for (let index = 0; index < data.test.length; index++) {
        const row = data.test[index];
        const result = prunedRoutes[index];
        let missing = 0;
        for (const step of result.steps) if (step.method !== 'primary') missing++;
        lines.push([
            row.id, data.classes[result.prediction], data.classes[row.label],
            data.classes[grownRoutes[index].prediction], result.leaf.number,
            result.path.map(node => node.number).join('-'), missing,
        ].join(','));
    }
    return lines;
}

function simplifyConditions(steps, attributes) {
    const conditions = [];
    for (let index = 0; index < attributes.length; index++) {
        const selected = steps.filter(step => step.split.attribute === index);
        if (selected.length === 0) continue;
        if (attributes[index].kind === 'INT') {
            let lower = null;
            let upper = null;
            for (const step of selected) {
                if (step.left) {
                    upper = upper === null ? step.split.threshold : Math.min(upper, step.split.threshold);
                } else {
                    lower = lower === null ? step.split.threshold : Math.max(lower, step.split.threshold);
                }
            }
            conditions.push({ attribute: index, kind: 'INT', lower, upper });
        } else {
            let equal = null;
            const excluded = new Set();
            for (const step of selected) {
                if (step.left) equal = step.split.value;
                else excluded.add(step.split.value);
            }
            conditions.push({
                attribute: index, kind: 'CAT', equal,
                excluded: [...excluded].sort((a, b) => a - b),
            });
        }
    }
    return conditions;
}

function conditionText(condition, attributes) {
    const attribute = attributes[condition.attribute];
    if (condition.kind === 'INT') {
        if (condition.lower === null) return `${attribute.name} <= ${thresholdText(condition.upper)}`;
        if (condition.upper === null) return `${attribute.name} > ${thresholdText(condition.lower)}`;
        return `${thresholdText(condition.lower)} < ${attribute.name} <= ${thresholdText(condition.upper)}`;
    }
    if (condition.equal !== null) return `${attribute.name} = ${attribute.values[condition.equal]}`;
    const values = condition.excluded.map(value => attribute.values[value]);
    if (values.length === 1) return `${attribute.name} != ${values[0]}`;
    return `${attribute.name} not in {${values.join(',')}}`;
}

function conditionsText(conditions, attributes) {
    return conditions.map(condition => conditionText(condition, attributes)).join(' and ') || 'true';
}

function satisfies(row, conditions) {
    for (const condition of conditions) {
        const value = row.values[condition.attribute];
        if (value === null) return false;
        if (condition.kind === 'INT') {
            if (condition.lower !== null && 2 * value <= condition.lower) return false;
            if (condition.upper !== null && 2 * value > condition.upper) return false;
        } else if (condition.equal !== null) {
            if (value !== condition.equal) return false;
        } else if (condition.excluded.includes(value)) {
            return false;
        }
    }
    return true;
}

function coverage(rows, conditions, label) {
    let covered = 0;
    let hits = 0;
    for (const row of rows) {
        if (!satisfies(row, conditions)) continue;
        covered++;
        if (row.label === label) hits++;
    }
    return { covered, hits };
}

function buildRules(view, attributes) {
    const rules = [];
    function visit(node, steps) {
        if (isLeaf(node, view)) {
            rules.push({
                number: rules.length + 1, node, label: node.majority,
                conditions: simplifyConditions(steps, attributes),
            });
            return;
        }
        visit(node.left, [...steps, { split: node.split, left: true }]);
        visit(node.right, [...steps, { split: node.split, left: false }]);
    }
    visit(view.root, []);
    return rules;
}

function generalize(rule, validation, classCount) {
    let current = rule.conditions;
    let counts = coverage(validation, current, rule.label);
    let estimate = { numerator: counts.hits + 1, denominator: counts.covered + classCount };
    const removed = [];
    while (current.length > 0) {
        let best = null;
        for (let index = 0; index < current.length; index++) {
            const conditions = current.filter((condition, position) => position !== index);
            const candidateCounts = coverage(validation, conditions, rule.label);
            const value = {
                numerator: candidateCounts.hits + 1,
                denominator: candidateCounts.covered + classCount,
            };
            if (best === null || compareFractions(value, best.value) > 0) {
                best = { index, conditions, counts: candidateCounts, value };
            }
        }
        if (compareFractions(best.value, estimate) < 0) break;
        removed.push(current[best.index].attribute);
        current = best.conditions;
        counts = best.counts;
        estimate = best.value;
    }
    return { conditions: current, removed, counts, estimate };
}

function ruleBlocks(data, pruned, routes) {
    const rules = buildRules(pruned, data.attributes);
    const leafRules = new Map(rules.map(rule => [rule.node.number, rule]));
    const routedCounts = new Map(rules.map(rule => [rule.node.number, { hits: 0, rows: 0 }]));
    for (let index = 0; index < routes.length; index++) {
        const result = routes[index];
        const counts = routedCounts.get(result.leaf.number);
        counts.rows++;
        if (result.prediction === data.test[index].label) counts.hits++;
    }
    const original = [`rules ${rules.length}`];
    const generalized = [`generalized ${rules.length}`];
    for (const rule of rules) {
        const label = data.classes[rule.label];
        const counts = routedCounts.get(rule.node.number);
        const conditions = conditionsText(rule.conditions, data.attributes);
        const trainRatio = ratio(rule.node.counts[rule.label], rule.node.n);
        original.push(`rule ${rule.number} node ${rule.node.number} if ${conditions} then ${label} train ${trainRatio} test ${ratio(counts.hits, counts.rows)}`);
        const general = generalize(rule, data.validation, data.classes.length);
        const test = coverage(data.test, general.conditions, rule.label);
        const text = conditionsText(general.conditions, data.attributes);
        const removed = general.removed.map(index => data.attributes[index].name).join(',') || 'none';
        const estimate = reducedFraction(general.estimate.numerator, general.estimate.denominator);
        generalized.push(`general ${rule.number} if ${text} then ${label} removed ${removed} laplace ${estimate} validation ${general.counts.hits}/${general.counts.covered} test ${test.hits}/${test.covered}`);
    }
    const mistakes = [];
    for (let index = 0; index < data.test.length; index++) {
        const row = data.test[index];
        const result = routes[index];
        if (result.prediction === row.label) continue;
        const explanation = result.steps.map(step => {
            const condition = splitText(step.node.split, step.left, data.attributes);
            return condition + (step.method === 'primary' ? '' : ` [${step.method}]`);
        }).join('; ') || 'root';
        const rule = leafRules.get(result.leaf.number);
        mistakes.push(`${row.id} actual ${data.classes[row.label]} predicted ${data.classes[result.prediction]} rule ${rule.number} path ${explanation}`);
    }
    return [original, generalized, [`misclassified ${mistakes.length}`, ...mistakes]];
}

function dataLines(data) {
    const train = statistics(data.train, data.classes.length).counts;
    const validation = statistics(data.validation, data.classes.length).counts;
    const test = statistics(data.test, data.classes.length).counts;
    const missingValidation = Array(data.attributes.length).fill(0);
    const missingTest = Array(data.attributes.length).fill(0);
    for (const row of data.validation) {
        row.values.forEach((value, index) => { if (value === null) missingValidation[index]++; });
    }
    for (const row of data.test) {
        row.values.forEach((value, index) => { if (value === null) missingTest[index]++; });
    }
    const lines = [`data train ${data.train.length} validation ${data.validation.length} test ${data.test.length} attributes ${data.attributes.length} classes ${data.classes.length} target ${data.target}`];
    for (let index = 0; index < data.classes.length; index++) {
        lines.push(`class ${data.classes[index]} train ${train[index]} validation ${validation[index]} test ${test[index]}`);
    }
    let validationTotal = 0;
    let testTotal = 0;
    for (let index = 0; index < data.attributes.length; index++) {
        validationTotal += missingValidation[index];
        testTotal += missingTest[index];
    }
    lines.push(`missing validation ${validationTotal} test ${testTotal}`);
    for (let index = 0; index < data.attributes.length; index++) {
        lines.push(`missing ${data.attributes[index].name} validation ${missingValidation[index]} test ${missingTest[index]}`);
    }
    return lines;
}

function treeComparisonLines(data, grown, pruned) {
    return [['grown', grown], ['pruned', pruned]].map(([name, view]) => {
        const summary = treeSummary(view);
        const train = ratio(correctCount(view, data.train), data.train.length);
        const validation = ratio(correctCount(view, data.validation), data.validation.length);
        const test = ratio(correctCount(view, data.test), data.test.length);
        return `${name} nodes ${summary.nodes} leaves ${summary.leaves} depth ${summary.depth} train ${train} validation ${validation} test ${test}`;
    });
}

function routingLines(data, pruned, routes) {
    const nodes = preorder(pruned).filter(node => !isLeaf(node, pruned));
    const tallies = new Map(nodes.map(node => [node.number, { rows: 0, primary: 0, surrogate: 0, default: 0 }]));
    const groups = [{ rows: 0, correct: 0 }, { rows: 0, correct: 0 }];
    for (let index = 0; index < routes.length; index++) {
        const result = routes[index];
        for (const step of result.steps) {
            const tally = tallies.get(step.node.number);
            tally.rows++;
            tally[step.method]++;
        }
        const group = groups[data.test[index].values.includes(null) ? 1 : 0];
        group.rows++;
        if (result.prediction === data.test[index].label) group.correct++;
    }
    const lines = ['routing pruned test'];
    for (const node of nodes) {
        const tally = tallies.get(node.number);
        lines.push(`node ${node.number} rows ${tally.rows} primary ${tally.primary} surrogate ${tally.surrogate} default ${tally.default}`);
    }
    for (let index = 0; index < groups.length; index++) {
        const group = groups[index];
        lines.push(`${index === 0 ? 'complete' : 'incomplete'} rows ${group.rows} correct ${ratio(group.correct, group.rows)}`);
    }
    return lines;
}

function crossValidation(data) {
    const folds = [];
    const lines = [`cross_validation folds ${data.settings.folds}`];
    let totalCorrect = 0;
    for (let fold = 0; fold < data.settings.folds; fold++) {
        const start = Number(BigInt(fold * data.train.length) / BigInt(data.settings.folds));
        const end = Number(BigInt((fold + 1) * data.train.length) / BigInt(data.settings.folds));
        const training = data.train.slice(0, start).concat(data.train.slice(end));
        const rows = data.train.slice(start, end);
        const root = growTree(training, data.attributes, data.classes.length, data.settings);
        const view = { root, cuts: new Set() };
        const correct = correctCount(view, rows);
        folds.push({ root, rows });
        totalCorrect += correct;
        lines.push(`fold ${fold + 1} rows ${start + 1}-${end} leaves ${treeSummary(view).leaves} correct ${ratio(correct, rows.length)}`);
    }
    lines.push(`cv accuracy ${ratio(totalCorrect, data.train.length)}`);
    return { folds, lines };
}

function depthSelection(data, root, folds) {
    const lines = ['depth_selection'];
    let selected = null;
    for (let depth = 0; depth <= data.settings.maxDepth; depth++) {
        let crossCorrect = 0;
        for (const fold of folds) crossCorrect += correctCount(viewAtDepth(fold.root, depth), fold.rows);
        const view = viewAtDepth(root, depth);
        const leaves = treeSummary(view).leaves;
        const train = correctCount(view, data.train);
        const validation = correctCount(view, data.validation);
        const test = correctCount(view, data.test);
        const record = { depth, view, leaves, crossCorrect, test };
        if (selected === null || crossCorrect > selected.crossCorrect) selected = record;
        lines.push(`depth ${depth} leaves ${leaves} cv ${ratio(crossCorrect, data.train.length)} train ${ratio(train, data.train.length)} validation ${ratio(validation, data.validation.length)} test ${ratio(test, data.test.length)}`);
    }
    lines.push(`selected depth ${selected.depth} leaves ${selected.leaves} test ${ratio(selected.test, data.test.length)}`);
    return { view: selected.view, lines };
}

function sequenceSelection(data, sequence) {
    const lines = ['cost_complexity'];
    let selected = null;
    for (let index = 0; index < sequence.length; index++) {
        const { view, alpha } = sequence[index];
        const summary = treeSummary(view);
        const validationErrors = data.validation.length - correctCount(view, data.validation);
        const record = { index, view, summary, validationErrors };
        if (selected === null || validationErrors <= selected.validationErrors) selected = record;
        const value = reducedFraction(alpha.numerator, alpha.denominator * data.train.length, 6);
        lines.push(`subtree ${index} alpha ${value} leaves ${summary.leaves} train_errors ${summary.errors} validation_errors ${validationErrors}`);
    }
    const test = correctCount(selected.view, data.test);
    lines.push(`selected subtree ${selected.index} leaves ${selected.summary.leaves} test ${ratio(test, data.test.length)}`);
    return { view: selected.view, lines };
}

function bagging(data) {
    const random = minstd(data.settings.bagSeed);
    const classCount = data.classes.length;
    const oobVotes = data.train.map(() => Array(classCount).fill(0));
    const testVotes = data.test.map(() => Array(classCount).fill(0));
    const lines = [`bagging trees ${data.settings.bagTrees} seed ${data.settings.bagSeed}`];
    for (let bag = 0; bag < data.settings.bagTrees; bag++) {
        const sample = [];
        const selected = new Set();
        for (let draw = 0; draw < data.train.length; draw++) {
            const index = random() % data.train.length;
            sample.push(data.train[index]);
            selected.add(index);
        }
        const root = growTree(sample, data.attributes, classCount, data.settings);
        const view = { root, cuts: new Set() };
        let oobRows = 0;
        let oobCorrect = 0;
        for (let index = 0; index < data.train.length; index++) {
            if (selected.has(index)) continue;
            const prediction = predict(view, data.train[index]);
            oobVotes[index][prediction]++;
            oobRows++;
            if (prediction === data.train[index].label) oobCorrect++;
        }
        for (let index = 0; index < data.test.length; index++) {
            testVotes[index][predict(view, data.test[index])]++;
        }
        lines.push(`bag ${bag + 1} distinct ${selected.size} leaves ${treeSummary(view).leaves} oob ${ratio(oobCorrect, oobRows)}`);
    }
    let voted = 0;
    let correct = 0;
    for (let index = 0; index < data.train.length; index++) {
        const votes = oobVotes[index];
        if (!votes.some(count => count > 0)) continue;
        voted++;
        if (majority(votes) === data.train[index].label) correct++;
    }
    const predictions = testVotes.map(majority);
    lines.push(`oob accuracy ${ratio(correct, voted)} unvoted ${data.train.length - voted}`);
    lines.push(...classificationLines('bagging test', data.test, predictions, data.classes));
    return { predictions, votes: testVotes, lines };
}

function mcnemarLines(data, predictions) {
    const lines = ['mcnemar pruned test'];
    for (const name of ['grown', 'depth', 'cost_complexity', 'bagging']) {
        let b = 0;
        let c = 0;
        for (let index = 0; index < data.test.length; index++) {
            const prunedCorrect = predictions.pruned[index] === data.test[index].label;
            const otherCorrect = predictions[name][index] === data.test[index].label;
            if (prunedCorrect && !otherCorrect) b++;
            if (otherCorrect && !prunedCorrect) c++;
        }
        const difference = Math.max(0, Math.abs(b - c) - 1);
        const numerator = difference * difference;
        const statistic = b + c === 0 ? reducedFraction(0, 1) : reducedFraction(numerator, b + c);
        const significant = 1000 * numerator > 3841 * (b + c) ? 'yes' : 'no';
        lines.push(`versus ${name} b ${b} c ${c} statistic ${statistic} significant ${significant}`);
    }
    return lines;
}

function aucLines(data, grownRoutes, prunedRoutes, bagVotes) {
    const treeScores = routes => routes.map(result => ({ counts: result.leaf.counts, total: result.leaf.n }));
    const models = [
        ['grown', treeScores(grownRoutes)],
        ['pruned', treeScores(prunedRoutes)],
        ['bagging', bagVotes.map(counts => ({ counts, total: data.settings.bagTrees }))],
    ];
    const lines = [];
    for (const [name, scores] of models) {
        const parts = [`auc ${name}`];
        let macro = 0;
        let defined = 0;
        for (let label = 0; label < data.classes.length; label++) {
            const positives = [];
            const negatives = [];
            for (let index = 0; index < data.test.length; index++) {
                (data.test[index].label === label ? positives : negatives).push(index);
            }
            let numerator = 0;
            for (const positive of positives) {
                for (const negative of negatives) {
                    const left = { numerator: scores[positive].counts[label], denominator: scores[positive].total };
                    const right = { numerator: scores[negative].counts[label], denominator: scores[negative].total };
                    const comparison = compareFractions(left, right);
                    if (comparison > 0) numerator += 2;
                    else if (comparison === 0) numerator++;
                }
            }
            const denominator = 2 * positives.length * negatives.length;
            parts.push(data.classes[label], reducedFraction(numerator, denominator));
            if (denominator > 0) {
                macro += numerator / denominator;
                defined++;
            }
        }
        parts.push('macro', defined === 0 ? '-' : formatReal(macro / defined));
        lines.push(parts.join(' '));
    }
    return lines;
}

function learningCurveLines(data) {
    const lines = ['learning_curve'];
    for (const size of data.settings.curve) {
        const root = growTree(data.train.slice(0, size), data.attributes, data.classes.length, data.settings);
        const grown = { root, cuts: new Set() };
        const pruned = reducedError(root, data.validation).view;
        const grownCorrect = correctCount(grown, data.test);
        const prunedCorrect = correctCount(pruned, data.test);
        lines.push(`size ${size} grown leaves ${treeSummary(grown).leaves} test ${ratio(grownCorrect, data.test.length)} pruned leaves ${treeSummary(pruned).leaves} test ${ratio(prunedCorrect, data.test.length)}`);
    }
    return lines;
}

function impurityImportance(data, view, name) {
    const importance = Array(data.attributes.length).fill(0);
    const splits = Array(data.attributes.length).fill(0);
    for (const node of preorder(view)) {
        if (isLeaf(node, view)) continue;
        importance[node.split.attribute] += impurityDecrease(node);
        splits[node.split.attribute]++;
    }
    let total = 0;
    for (const value of importance) total += value;
    const records = data.attributes.map((attribute, index) => {
        const share = formatReal(total === 0 ? 0 : importance[index] / total);
        return {
            index, name: attribute.name, share, rounded: Number(share),
            decrease: formatReal(importance[index] / data.train.length), splits: splits[index],
        };
    });
    records.sort((a, b) => b.rounded - a.rounded || a.index - b.index);
    const lines = [`impurity ${name}`];
    records.forEach((record, index) => {
        lines.push(`${index + 1} ${record.name} decrease ${record.decrease} share ${record.share} splits ${record.splits}`);
    });
    return lines;
}

function permutationImportance(data, pruned, base) {
    const repeats = data.settings.permutationRepeats;
    const random = minstd(data.settings.permutationSeed);
    const records = [];
    for (let attribute = 0; attribute < data.attributes.length; attribute++) {
        const correctCounts = [];
        let totalCorrect = 0;
        for (let repeat = 0; repeat < repeats; repeat++) {
            const values = data.test.map(row => row.values[attribute]);
            for (let index = values.length - 1; index > 0; index--) {
                const other = random() % (index + 1);
                [values[index], values[other]] = [values[other], values[index]];
            }
            let correct = 0;
            for (let index = 0; index < data.test.length; index++) {
                const row = data.test[index];
                const changed = { ...row, values: row.values.slice() };
                changed.values[attribute] = values[index];
                if (predict(pruned, changed) === row.label) correct++;
            }
            correctCounts.push(correct);
            totalCorrect += correct;
        }
        records.push({ attribute, correctCounts, drop: repeats * base - totalCorrect });
    }
    records.sort((a, b) => b.drop - a.drop || a.attribute - b.attribute);
    const lines = [`permutation pruned test repeats ${repeats} seed ${data.settings.permutationSeed} base ${ratio(base, data.test.length)}`];
    records.forEach((record, index) => {
        const drop = reducedFraction(record.drop, repeats * data.test.length);
        lines.push(`${index + 1} ${data.attributes[record.attribute].name} correct ${record.correctCounts.join(' ')} drop ${drop}`);
    });
    return lines;
}

function writeBlocks(name, blocks) {
    const text = blocks.map(lines => lines.join('\n')).join('\n\n') + '\n';
    fs.writeFileSync(`output/${name}`, text, 'ascii');
}

function main() {
    const data = readDataset();
    const root = growTree(data.train, data.attributes, data.classes.length, data.settings);
    const grown = { root, cuts: new Set() };
    const pruning = reducedError(root, data.validation);
    const pruned = pruning.view;
    const grownRoutes = data.test.map(row => route(grown, row));
    const prunedRoutes = data.test.map(row => route(pruned, row));
    const cross = crossValidation(data);
    const depth = depthSelection(data, root, cross.folds);
    const sequence = sequenceSelection(data, costComplexity(root));
    const bag = bagging(data);
    const predictions = {
        grown: grownRoutes.map(result => result.prediction),
        pruned: prunedRoutes.map(result => result.prediction),
        depth: data.test.map(row => predict(depth.view, row)),
        cost_complexity: data.test.map(row => predict(sequence.view, row)),
        bagging: bag.predictions,
    };
    const evaluation = [
        dataLines(data),
        treeComparisonLines(data, grown, pruned),
        classificationLines('grown test', data.test, predictions.grown, data.classes),
        classificationLines('pruned test', data.test, predictions.pruned, data.classes),
        routingLines(data, pruned, prunedRoutes),
        cross.lines,
        depth.lines,
        sequence.lines,
        bag.lines,
        mcnemarLines(data, predictions),
        aucLines(data, grownRoutes, prunedRoutes, bag.votes),
        learningCurveLines(data),
    ];
    const importance = [
        impurityImportance(data, grown, 'grown'),
        impurityImportance(data, pruned, 'pruned'),
        permutationImportance(data, pruned, correctCount(pruned, data.test)),
    ];
    fs.mkdirSync('output', { recursive: true });
    writeBlocks('tree.txt', [rootCandidateLines(data, root), treeLines(grown, data), surrogateLines(data, grown)]);
    writeBlocks('pruned_tree.txt', [pruningLines(pruning, data.validation.length), treeLines(pruned, data)]);
    writeBlocks('predictions.csv', [predictionLines(data, grownRoutes, prunedRoutes)]);
    writeBlocks('rules.txt', ruleBlocks(data, pruned, prunedRoutes));
    writeBlocks('evaluation.txt', evaluation);
    writeBlocks('importance.txt', importance);
}

main();
