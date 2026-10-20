import { mkdirSync, writeFileSync } from 'node:fs';
import { readDataset } from './dataset.ts';
import type { Attribute, Dataset, Row } from './dataset.ts';
import { majority, statistics, compareFractions, impurityDecrease } from './impurity.ts';
import type { Fraction } from './impurity.ts';
import { bestForAttribute, growTree } from './tree_builder.ts';
import type { Split, SplitCandidate, TreeNode, TreeView } from './tree_builder.ts';
import { reducedError, costComplexity } from './pruning.ts';
import type { PruningResult, SequenceTree } from './pruning.ts';
import { isBranch, preorder, route, predict, correctCount, formatReal, ratio,
    reducedFraction, classificationLines } from './evaluation.ts';
import type { Route } from './evaluation.ts';

interface Level { nodes: number; leaves: number; rows: number; errors: number }
interface TreeSummary { nodes: number; leaves: number; depth: number; errors: number; levels: Level[] }
interface RuleStep { split: Split; left: boolean }
type Condition = { attribute: number; kind: 'INT'; lower: number | null; upper: number | null }
    | { attribute: number; kind: 'CAT'; equal: number | null; excluded: number[] };
interface Rule { number: number; node: TreeNode; label: number; conditions: Condition[] }
interface Coverage { covered: number; hits: number }
interface Fold { root: TreeNode; rows: Row[] }
type ModelName = 'grown' | 'pruned' | 'depth' | 'cost_complexity' | 'bagging';

function minstd(seed: number): () => number {
    let state = seed;
    return () => { state = (48271 * state) % 2147483647; return state; };
}
function thresholdText(value: number): string {
    return `${Math.floor(value / 2)}.${value % 2 === 0 ? '0' : '5'}`;
}
function splitText(split: Split, left: boolean, attributes: Attribute[]): string {
    const attribute = attributes[split.attribute];
    return split.kind === 'INT'
        ? `${attribute.name} ${left ? '<=' : '>'} ${thresholdText(split.threshold)}`
        : `${attribute.name} ${left ? '=' : '!='} ${attribute.values[split.value]}`;
}
function viewAtDepth(root: TreeNode, depth: number): TreeView {
    const original: TreeView = { root, cuts: new Set() };
    return { root, cuts: new Set(preorder(original).filter(node => node.depth === depth && node.kind === 'branch')
        .map(node => node.number)) };
}
function treeSummary(view: TreeView): TreeSummary {
    const summary: TreeSummary = { nodes: 0, leaves: 0, depth: 0, errors: 0, levels: [] };
    for (const node of preorder(view)) {
        summary.nodes++;
        const level = summary.levels[node.depth] ??= { nodes: 0, leaves: 0, rows: 0, errors: 0 };
        level.nodes++;
        if (!isBranch(node, view)) {
            summary.leaves++; summary.depth = Math.max(summary.depth, node.depth); summary.errors += node.error;
            level.leaves++; level.rows += node.n; level.errors += node.error;
        }
    }
    return summary;
}
function treeLines(view: TreeView, data: Dataset): string[] {
    const lines: string[] = [];
    function visit(node: TreeNode, condition: string): void {
        let line = `${' '.repeat(2 * node.depth)}${node.number} ${condition} n ${node.n} counts ${node.counts.join(' ')}`;
        if (!isBranch(node, view)) line += ` leaf ${data.classes[node.majority]}`;
        lines.push(line);
        if (isBranch(node, view)) {
            visit(node.left, splitText(node.split, true, data.attributes));
            visit(node.right, splitText(node.split, false, data.attributes));
        }
    }
    visit(view.root, 'root');
    const summary = treeSummary(view);
    lines.push('', `nodes ${summary.nodes} leaves ${summary.leaves} depth ${summary.depth} errors ${ratio(summary.errors, data.train.length)}`);
    summary.levels.forEach((level, depth) => lines.push(`level ${depth} nodes ${level.nodes} leaves ${level.leaves} rows ${level.rows} errors ${level.errors}`));
    return lines;
}
function rootCandidateLines(data: Dataset, root: TreeNode): string[] {
    const candidates: SplitCandidate[] = [];
    data.attributes.forEach((attribute, i) => {
        const best = bestForAttribute(data.train, attribute, i, data.settings.minSamplesLeaf, data.classes.length);
        if (best) candidates.push(best);
    });
    candidates.sort((a, b) => -compareFractions(a.value, b.value) || a.split.attribute - b.split.attribute);
    const n = data.train.length;
    return [`root candidates n ${n} counts ${root.counts.join(' ')}`, ...candidates.map((candidate, i) => {
        const gain = (candidate.value.numerator / candidate.value.denominator) / n - root.sumSquares / (n * n);
        return `${i + 1} ${splitText(candidate.split, true, data.attributes)} left ${candidate.left.length} right ${candidate.right.length} gain ${formatReal(gain, 6)}`;
    })];
}
function surrogateLines(data: Dataset, grown: TreeView): string[] {
    const lines = ['surrogates'];
    for (const node of preorder(grown)) if (isBranch(node, grown)) {
        const items = node.surrogates.map(item => `${splitText(item.split, true, data.attributes)} ${item.direction} ${item.score}/${node.n}`).join(' ; ') || 'none';
        lines.push(`node ${node.number} split ${splitText(node.split, true, data.attributes)} default ${node.defaultDirection} surrogates ${items}`);
    }
    return lines;
}
function pruningLines(result: PruningResult, validation: number): string[] {
    const lines = [`reduced_error_pruning validation ${validation}`];
    let pruned = 0;
    for (const decision of result.decisions) {
        const { node, rows, leafError, subtreeError } = decision;
        if (decision.pruned) pruned++;
        lines.push(`node ${node.number} depth ${node.depth} rows ${rows} leaf ${leafError} subtree ${subtreeError} ${decision.pruned ? 'pruned' : 'kept'}`);
    }
    lines.push(`examined ${result.decisions.length} pruned ${pruned} kept ${result.decisions.length - pruned}`);
    return lines;
}
function predictionLines(data: Dataset, grown: Route[], pruned: Route[]): string[] {
    return ['id,predicted,actual,grown,leaf,path,missing', ...data.test.map((row, i) => {
        const result = pruned[i];
        return [row.id, data.classes[result.prediction], data.classes[row.label], data.classes[grown[i].prediction],
            result.leaf.number, result.path.map(node => node.number).join('-'),
            result.steps.filter(step => step.method !== 'primary').length].join(',');
    })];
}
function simplifyConditions(steps: RuleStep[], attributes: Attribute[]): Condition[] {
    const conditions: Condition[] = [];
    for (let a = 0; a < attributes.length; a++) {
        const selected = steps.filter(step => step.split.attribute === a);
        if (!selected.length) continue;
        if (attributes[a].kind === 'INT') {
            let lower: number | null = null, upper: number | null = null;
            for (const { split, left } of selected) if (split.kind === 'INT') {
                if (left) upper = upper === null ? split.threshold : Math.min(upper, split.threshold);
                else lower = lower === null ? split.threshold : Math.max(lower, split.threshold);
            }
            conditions.push({ attribute: a, kind: 'INT', lower, upper });
        } else {
            let equal: number | null = null;
            const excluded = new Set<number>();
            for (const { split, left } of selected) if (split.kind === 'CAT') {
                if (left) equal = split.value; else excluded.add(split.value);
            }
            conditions.push({ attribute: a, kind: 'CAT', equal, excluded: [...excluded].sort((x, y) => x - y) });
        }
    }
    return conditions;
}
function conditionText(condition: Condition, attributes: Attribute[]): string {
    const attribute = attributes[condition.attribute];
    if (condition.kind === 'INT') {
        if (condition.lower === null) return `${attribute.name} <= ${thresholdText(condition.upper!)}`;
        if (condition.upper === null) return `${attribute.name} > ${thresholdText(condition.lower)}`;
        return `${thresholdText(condition.lower)} < ${attribute.name} <= ${thresholdText(condition.upper)}`;
    }
    if (condition.equal !== null) return `${attribute.name} = ${attribute.values[condition.equal]}`;
    const values = condition.excluded.map(value => attribute.values[value]);
    return values.length === 1 ? `${attribute.name} != ${values[0]}` : `${attribute.name} not in {${values.join(',')}}`;
}
function conditionsText(conditions: Condition[], attributes: Attribute[]): string {
    return conditions.map(condition => conditionText(condition, attributes)).join(' and ') || 'true';
}
function coverage(rows: Row[], conditions: Condition[], label: number): Coverage {
    let covered = 0, hits = 0;
    for (const row of rows) {
        const satisfies = conditions.every(condition => {
            const value = row.values[condition.attribute];
            if (value === null) return false;
            if (condition.kind === 'INT') return (condition.lower === null || 2 * value > condition.lower)
                && (condition.upper === null || 2 * value <= condition.upper);
            return condition.equal !== null ? value === condition.equal : !condition.excluded.includes(value);
        });
        if (satisfies) { covered++; if (row.label === label) hits++; }
    }
    return { covered, hits };
}
function buildRules(view: TreeView, attributes: Attribute[]): Rule[] {
    const rules: Rule[] = [];
    function visit(node: TreeNode, steps: RuleStep[]): void {
        if (!isBranch(node, view)) {
            rules.push({ number: rules.length + 1, node, label: node.majority, conditions: simplifyConditions(steps, attributes) });
        } else {
            visit(node.left, [...steps, { split: node.split, left: true }]);
            visit(node.right, [...steps, { split: node.split, left: false }]);
        }
    }
    visit(view.root, []);
    return rules;
}
function generalize(rule: Rule, validation: Row[], classes: number) {
    let current = rule.conditions;
    let counts = coverage(validation, current, rule.label);
    let estimate: Fraction = { numerator: counts.hits + 1, denominator: counts.covered + classes };
    const removed: number[] = [];
    while (current.length > 0) {
        let best: { index: number; conditions: Condition[]; counts: Coverage; value: Fraction } | null = null;
        for (let i = 0; i < current.length; i++) {
            const conditions = current.filter((_, j) => j !== i);
            const counts = coverage(validation, conditions, rule.label);
            const value = { numerator: counts.hits + 1, denominator: counts.covered + classes };
            if (best === null || compareFractions(value, best.value) > 0) best = { index: i, conditions, counts, value };
        }
        if (best === null || compareFractions(best.value, estimate) < 0) break;
        removed.push(current[best.index].attribute);
        current = best.conditions; counts = best.counts; estimate = best.value;
    }
    return { conditions: current, removed, counts, estimate };
}
function ruleBlocks(data: Dataset, pruned: TreeView, routes: Route[]): string[][] {
    const rules = buildRules(pruned, data.attributes);
    const leafRules = new Map(rules.map(rule => [rule.node.number, rule]));
    const tallies = new Map(rules.map(rule => [rule.node.number, { rows: 0, hits: 0 }]));
    routes.forEach((result, i) => {
        const tally = tallies.get(result.leaf.number)!;
        tally.rows++; if (result.prediction === data.test[i].label) tally.hits++;
    });
    const original = [`rules ${rules.length}`], generalized = [`generalized ${rules.length}`];
    for (const rule of rules) {
        const tally = tallies.get(rule.node.number)!;
        const label = data.classes[rule.label];
        original.push(`rule ${rule.number} node ${rule.node.number} if ${conditionsText(rule.conditions, data.attributes)} then ${label} train ${ratio(rule.node.counts[rule.label], rule.node.n)} test ${ratio(tally.hits, tally.rows)}`);
        const general = generalize(rule, data.validation, data.classes.length);
        const test = coverage(data.test, general.conditions, rule.label);
        const removed = general.removed.map(a => data.attributes[a].name).join(',') || 'none';
        generalized.push(`general ${rule.number} if ${conditionsText(general.conditions, data.attributes)} then ${label} removed ${removed} laplace ${reducedFraction(general.estimate.numerator, general.estimate.denominator)} validation ${general.counts.hits}/${general.counts.covered} test ${test.hits}/${test.covered}`);
    }
    const mistakes: string[] = [];
    data.test.forEach((row, i) => {
        const result = routes[i];
        if (result.prediction === row.label) return;
        const explanation = result.steps.map(step => splitText(step.node.split, step.left, data.attributes)
            + (step.method === 'primary' ? '' : ` [${step.method}]`)).join('; ') || 'root';
        mistakes.push(`${row.id} actual ${data.classes[row.label]} predicted ${data.classes[result.prediction]} rule ${leafRules.get(result.leaf.number)!.number} path ${explanation}`);
    });
    return [original, generalized, [`misclassified ${mistakes.length}`, ...mistakes]];
}
function dataLines(data: Dataset): string[] {
    const counts = [data.train, data.validation, data.test].map(rows => statistics(rows, data.classes.length).counts);
    const missing = [data.validation, data.test].map(rows => data.attributes.map((_, a) => rows.filter(row => row.values[a] === null).length));
    const lines = [`data train ${data.train.length} validation ${data.validation.length} test ${data.test.length} attributes ${data.attributes.length} classes ${data.classes.length} target ${data.target}`];
    data.classes.forEach((name, k) => lines.push(`class ${name} train ${counts[0][k]} validation ${counts[1][k]} test ${counts[2][k]}`));
    lines.push(`missing validation ${missing[0].reduce((a, b) => a + b, 0)} test ${missing[1].reduce((a, b) => a + b, 0)}`);
    data.attributes.forEach((attribute, a) => lines.push(`missing ${attribute.name} validation ${missing[0][a]} test ${missing[1][a]}`));
    return lines;
}
function treeComparisonLines(data: Dataset, grown: TreeView, pruned: TreeView): string[] {
    const models: [string, TreeView][] = [['grown', grown], ['pruned', pruned]];
    return models.map(([name, view]) => {
        const s = treeSummary(view);
        return `${name} nodes ${s.nodes} leaves ${s.leaves} depth ${s.depth} train ${ratio(correctCount(view, data.train), data.train.length)} validation ${ratio(correctCount(view, data.validation), data.validation.length)} test ${ratio(correctCount(view, data.test), data.test.length)}`;
    });
}
function routingLines(data: Dataset, pruned: TreeView, routes: Route[]): string[] {
    const nodes = preorder(pruned).filter(node => isBranch(node, pruned));
    const tallies = new Map(nodes.map(node => [node.number, { rows: 0, primary: 0, surrogate: 0, default: 0 }]));
    const groups = [{ rows: 0, correct: 0 }, { rows: 0, correct: 0 }];
    routes.forEach((result, i) => {
        for (const step of result.steps) { const tally = tallies.get(step.node.number)!; tally.rows++; tally[step.method]++; }
        const group = groups[data.test[i].values.includes(null) ? 1 : 0];
        group.rows++; if (result.prediction === data.test[i].label) group.correct++;
    });
    const lines = ['routing pruned test'];
    for (const node of nodes) {
        const tally = tallies.get(node.number)!;
        lines.push(`node ${node.number} rows ${tally.rows} primary ${tally.primary} surrogate ${tally.surrogate} default ${tally.default}`);
    }
    groups.forEach((group, i) => lines.push(`${i === 0 ? 'complete' : 'incomplete'} rows ${group.rows} correct ${ratio(group.correct, group.rows)}`));
    return lines;
}
function crossValidation(data: Dataset): { folds: Fold[]; lines: string[] } {
    const folds: Fold[] = [], lines = [`cross_validation folds ${data.settings.folds}`];
    let total = 0;
    for (let f = 0; f < data.settings.folds; f++) {
        const start = Math.floor(f * data.train.length / data.settings.folds);
        const end = Math.floor((f + 1) * data.train.length / data.settings.folds);
        const root = growTree(data.train.slice(0, start).concat(data.train.slice(end)), data.attributes, data.classes.length, data.settings);
        const rows = data.train.slice(start, end), view: TreeView = { root, cuts: new Set() };
        const correct = correctCount(view, rows);
        folds.push({ root, rows }); total += correct;
        lines.push(`fold ${f + 1} rows ${start + 1}-${end} leaves ${treeSummary(view).leaves} correct ${ratio(correct, rows.length)}`);
    }
    lines.push(`cv accuracy ${ratio(total, data.train.length)}`);
    return { folds, lines };
}
function depthSelection(data: Dataset, root: TreeNode, folds: Fold[]) {
    const lines = ['depth_selection'];
    let selected = { depth: 0, view: viewAtDepth(root, 0), leaves: 1, crossCorrect: -1, test: 0 };
    for (let depth = 0; depth <= data.settings.maxDepth; depth++) {
        let crossCorrect = 0;
        for (const fold of folds) crossCorrect += correctCount(viewAtDepth(fold.root, depth), fold.rows);
        const view = viewAtDepth(root, depth), leaves = treeSummary(view).leaves;
        const train = correctCount(view, data.train), validation = correctCount(view, data.validation), test = correctCount(view, data.test);
        if (crossCorrect > selected.crossCorrect) selected = { depth, view, leaves, crossCorrect, test };
        lines.push(`depth ${depth} leaves ${leaves} cv ${ratio(crossCorrect, data.train.length)} train ${ratio(train, data.train.length)} validation ${ratio(validation, data.validation.length)} test ${ratio(test, data.test.length)}`);
    }
    lines.push(`selected depth ${selected.depth} leaves ${selected.leaves} test ${ratio(selected.test, data.test.length)}`);
    return { view: selected.view, lines };
}
function sequenceSelection(data: Dataset, sequence: SequenceTree[]) {
    const lines = ['cost_complexity'];
    let selected = 0, minimumErrors = data.validation.length + 1;
    sequence.forEach(({ view, alpha }, i) => {
        const summary = treeSummary(view), errors = data.validation.length - correctCount(view, data.validation);
        if (errors <= minimumErrors) { selected = i; minimumErrors = errors; }
        lines.push(`subtree ${i} alpha ${reducedFraction(alpha.numerator, alpha.denominator * data.train.length, 6)} leaves ${summary.leaves} train_errors ${summary.errors} validation_errors ${errors}`);
    });
    const view = sequence[selected].view;
    lines.push(`selected subtree ${selected} leaves ${treeSummary(view).leaves} test ${ratio(correctCount(view, data.test), data.test.length)}`);
    return { view, lines };
}
function bagging(data: Dataset) {
    const random = minstd(data.settings.bagSeed), classes = data.classes.length;
    const oobVotes: number[][] = data.train.map(() => Array(classes).fill(0));
    const testVotes: number[][] = data.test.map(() => Array(classes).fill(0));
    const lines = [`bagging trees ${data.settings.bagTrees} seed ${data.settings.bagSeed}`];
    for (let bag = 0; bag < data.settings.bagTrees; bag++) {
        const sample: Row[] = [], selected = new Set<number>();
        for (let draw = 0; draw < data.train.length; draw++) {
            const i = random() % data.train.length; sample.push(data.train[i]); selected.add(i);
        }
        const root = growTree(sample, data.attributes, classes, data.settings), view: TreeView = { root, cuts: new Set() };
        let oobRows = 0, oobCorrect = 0;
        data.train.forEach((row, i) => {
            if (selected.has(i)) return;
            const prediction = predict(view, row); oobVotes[i][prediction]++; oobRows++;
            if (prediction === row.label) oobCorrect++;
        });
        data.test.forEach((row, i) => testVotes[i][predict(view, row)]++);
        lines.push(`bag ${bag + 1} distinct ${selected.size} leaves ${treeSummary(view).leaves} oob ${ratio(oobCorrect, oobRows)}`);
    }
    let voted = 0, correct = 0;
    oobVotes.forEach((votes, i) => {
        if (!votes.some(count => count > 0)) return;
        voted++; if (majority(votes) === data.train[i].label) correct++;
    });
    const predictions = testVotes.map(majority);
    lines.push(`oob accuracy ${ratio(correct, voted)} unvoted ${data.train.length - voted}`,
        ...classificationLines('bagging test', data.test, predictions, data.classes));
    return { predictions, votes: testVotes, lines };
}
function mcnemarLines(data: Dataset, predictions: Record<ModelName, number[]>): string[] {
    const lines = ['mcnemar pruned test'];
    const models: ModelName[] = ['grown', 'depth', 'cost_complexity', 'bagging'];
    for (const name of models) {
        let b = 0, c = 0;
        data.test.forEach((row, i) => {
            const p = predictions.pruned[i] === row.label, other = predictions[name][i] === row.label;
            if (p && !other) b++; if (other && !p) c++;
        });
        const difference = Math.max(0, Math.abs(b - c) - 1), u = difference * difference;
        lines.push(`versus ${name} b ${b} c ${c} statistic ${reducedFraction(u, b + c || 1)} significant ${1000 * u > 3841 * (b + c) ? 'yes' : 'no'}`);
    }
    return lines;
}
function aucLines(data: Dataset, grown: Route[], pruned: Route[], bagVotes: number[][]): string[] {
    interface Scores { counts: number[]; total: number }
    const treeScores = (routes: Route[]): Scores[] => routes.map(result => ({ counts: result.leaf.counts, total: result.leaf.n }));
    const models: [string, Scores[]][] = [['grown', treeScores(grown)], ['pruned', treeScores(pruned)],
        ['bagging', bagVotes.map(counts => ({ counts, total: data.settings.bagTrees }))]];
    return models.map(([name, scores]) => {
        const parts = [`auc ${name}`];
        let macro = 0, defined = 0;
        for (let k = 0; k < data.classes.length; k++) {
            const positives: number[] = [], negatives: number[] = [];
            data.test.forEach((row, i) => (row.label === k ? positives : negatives).push(i));
            let numerator = 0;
            for (const p of positives) for (const n of negatives) {
                const comparison = compareFractions({ numerator: scores[p].counts[k], denominator: scores[p].total },
                    { numerator: scores[n].counts[k], denominator: scores[n].total });
                if (comparison > 0) numerator += 2; else if (comparison === 0) numerator++;
            }
            const denominator = 2 * positives.length * negatives.length;
            parts.push(data.classes[k], reducedFraction(numerator, denominator));
            if (denominator > 0) { macro += numerator / denominator; defined++; }
        }
        parts.push('macro', defined === 0 ? '-' : formatReal(macro / defined));
        return parts.join(' ');
    });
}
function learningCurveLines(data: Dataset): string[] {
    return ['learning_curve', ...data.settings.curve.map(size => {
        const root = growTree(data.train.slice(0, size), data.attributes, data.classes.length, data.settings);
        const grown: TreeView = { root, cuts: new Set() }, pruned = reducedError(root, data.validation).view;
        return `size ${size} grown leaves ${treeSummary(grown).leaves} test ${ratio(correctCount(grown, data.test), data.test.length)} pruned leaves ${treeSummary(pruned).leaves} test ${ratio(correctCount(pruned, data.test), data.test.length)}`;
    })];
}
function impurityImportance(data: Dataset, view: TreeView, name: string): string[] {
    const importance: number[] = Array(data.attributes.length).fill(0), splits: number[] = Array(data.attributes.length).fill(0);
    for (const node of preorder(view)) if (isBranch(node, view)) {
        importance[node.split.attribute] += impurityDecrease(node, node.left, node.right); splits[node.split.attribute]++;
    }
    let total = 0;
    for (const value of importance) total += value;
    const records = data.attributes.map((attribute, a) => {
        const share = formatReal(total === 0 ? 0 : importance[a] / total);
        return { a, name: attribute.name, share, rounded: Number(share), decrease: formatReal(importance[a] / data.train.length), splits: splits[a] };
    });
    records.sort((a, b) => b.rounded - a.rounded || a.a - b.a);
    return [`impurity ${name}`, ...records.map((record, i) => `${i + 1} ${record.name} decrease ${record.decrease} share ${record.share} splits ${record.splits}`)];
}
function permutationImportance(data: Dataset, pruned: TreeView, base: number): string[] {
    const repeats = data.settings.permutationRepeats, random = minstd(data.settings.permutationSeed);
    const records: { attribute: number; correct: number[]; drop: number }[] = [];
    for (let a = 0; a < data.attributes.length; a++) {
        const correct: number[] = [];
        for (let r = 0; r < repeats; r++) {
            const values = data.test.map(row => row.values[a]);
            for (let i = values.length - 1; i > 0; i--) {
                const j = random() % (i + 1); [values[i], values[j]] = [values[j], values[i]];
            }
            const rows = data.test.map((row, i) => {
                const changed = { ...row, values: row.values.slice() }; changed.values[a] = values[i]; return changed;
            });
            correct.push(correctCount(pruned, rows));
        }
        records.push({ attribute: a, correct, drop: repeats * base - correct.reduce((sum, n) => sum + n, 0) });
    }
    records.sort((a, b) => b.drop - a.drop || a.attribute - b.attribute);
    return [`permutation pruned test repeats ${repeats} seed ${data.settings.permutationSeed} base ${ratio(base, data.test.length)}`,
        ...records.map((record, i) => `${i + 1} ${data.attributes[record.attribute].name} correct ${record.correct.join(' ')} drop ${reducedFraction(record.drop, repeats * data.test.length)}`)];
}
function writeBlocks(name: string, blocks: string[][]): void {
    writeFileSync(`output/${name}`, blocks.map(lines => lines.join('\n')).join('\n\n') + '\n', 'ascii');
}
function main(): void {
    const data = readDataset();
    const root = growTree(data.train, data.attributes, data.classes.length, data.settings);
    const grown: TreeView = { root, cuts: new Set() }, pruning = reducedError(root, data.validation), pruned = pruning.view;
    const grownRoutes = data.test.map(row => route(grown, row)), prunedRoutes = data.test.map(row => route(pruned, row));
    const cross = crossValidation(data), depth = depthSelection(data, root, cross.folds);
    const sequence = sequenceSelection(data, costComplexity(root)), bag = bagging(data);
    const predictions: Record<ModelName, number[]> = {
        grown: grownRoutes.map(result => result.prediction), pruned: prunedRoutes.map(result => result.prediction),
        depth: data.test.map(row => predict(depth.view, row)), cost_complexity: data.test.map(row => predict(sequence.view, row)), bagging: bag.predictions,
    };
    mkdirSync('output', { recursive: true });
    writeBlocks('tree.txt', [rootCandidateLines(data, root), treeLines(grown, data), surrogateLines(data, grown)]);
    writeBlocks('pruned_tree.txt', [pruningLines(pruning, data.validation.length), treeLines(pruned, data)]);
    writeBlocks('predictions.csv', [predictionLines(data, grownRoutes, prunedRoutes)]);
    writeBlocks('rules.txt', ruleBlocks(data, pruned, prunedRoutes));
    writeBlocks('evaluation.txt', [dataLines(data), treeComparisonLines(data, grown, pruned),
        classificationLines('grown test', data.test, predictions.grown, data.classes),
        classificationLines('pruned test', data.test, predictions.pruned, data.classes), routingLines(data, pruned, prunedRoutes),
        cross.lines, depth.lines, sequence.lines, bag.lines, mcnemarLines(data, predictions),
        aucLines(data, grownRoutes, prunedRoutes, bag.votes), learningCurveLines(data)]);
    writeBlocks('importance.txt', [impurityImportance(data, grown, 'grown'), impurityImportance(data, pruned, 'pruned'),
        permutationImportance(data, pruned, correctCount(pruned, data.test))]);
}
main();
