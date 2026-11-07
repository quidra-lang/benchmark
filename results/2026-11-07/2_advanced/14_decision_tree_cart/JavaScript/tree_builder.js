'use strict';

const { statistics, evaluationValue, compareFractions, improves } = require('./impurity');

function candidates(rows, attribute, index) {
    const values = [...new Set(rows.map(row => row.values[index]))].sort((a, b) => a - b);
    if (values.length < 2) return [];
    if (attribute.kind === 'CAT') {
        return values.map(value => ({ attribute: index, kind: 'CAT', value }));
    }
    const result = [];
    for (let position = 0; position + 1 < values.length; position++) {
        result.push({
            attribute: index,
            kind: 'INT',
            threshold: values[position] + values[position + 1],
        });
    }
    return result;
}

function goesLeft(split, row) {
    const value = row.values[split.attribute];
    return split.kind === 'INT' ? 2 * value <= split.threshold : value === split.value;
}

function partition(rows, split) {
    const left = [];
    const right = [];
    for (const row of rows) (goesLeft(split, row) ? left : right).push(row);
    return { left, right };
}

function bestForAttribute(rows, attribute, index, minLeaf, classCount) {
    let best = null;
    for (const split of candidates(rows, attribute, index)) {
        const divided = partition(rows, split);
        if (divided.left.length < minLeaf || divided.right.length < minLeaf) continue;
        const leftStats = statistics(divided.left, classCount);
        const rightStats = statistics(divided.right, classCount);
        const value = evaluationValue(leftStats, rightStats);
        if (best === null || compareFractions(value, best.value) > 0) {
            best = { split, left: divided.left, right: divided.right, value };
        }
    }
    return best;
}

function bestSplit(rows, attributes, minLeaf, classCount) {
    let best = null;
    for (let index = 0; index < attributes.length; index++) {
        const candidate = bestForAttribute(rows, attributes[index], index, minLeaf, classCount);
        if (candidate !== null && (best === null || compareFractions(candidate.value, best.value) > 0)) {
            best = candidate;
        }
    }
    return best;
}

function findSurrogates(rows, primary, attributes, limit, leftCount, rightCount) {
    const retained = [];
    const primaryLeft = rows.map(row => goesLeft(primary, row));
    for (let index = 0; index < attributes.length; index++) {
        if (index === primary.attribute) continue;
        let best = null;
        for (const split of candidates(rows, attributes[index], index)) {
            let agreement = 0;
            for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
                if (goesLeft(split, rows[rowIndex]) === primaryLeft[rowIndex]) agreement++;
            }
            const reversed = rows.length - agreement;
            const direction = agreement >= reversed ? 'left' : 'right';
            const score = Math.max(agreement, reversed);
            if (best === null || score > best.score) best = { split, direction, score };
        }
        if (best !== null && best.score > Math.max(leftCount, rightCount)) retained.push(best);
    }
    retained.sort((a, b) => b.score - a.score || a.split.attribute - b.split.attribute);
    return retained.slice(0, limit);
}

function growTree(rows, attributes, classCount, settings) {
    function grow(sequence, number, depth) {
        const stats = statistics(sequence, classCount);
        const node = {
            ...stats,
            rows: sequence,
            number,
            depth,
            split: null,
            left: null,
            right: null,
            surrogates: [],
            defaultDirection: 'left',
        };
        if (stats.error === 0 || depth === settings.maxDepth || sequence.length < settings.minSamplesSplit) {
            return node;
        }
        const best = bestSplit(sequence, attributes, settings.minSamplesLeaf, classCount);
        if (best === null || !improves(best.value, stats)) return node;
        node.split = best.split;
        node.defaultDirection = best.left.length >= best.right.length ? 'left' : 'right';
        node.surrogates = findSurrogates(
            sequence, best.split, attributes, settings.maxSurrogates,
            best.left.length, best.right.length
        );
        node.left = grow(best.left, 2 * number, depth + 1);
        node.right = grow(best.right, 2 * number + 1, depth + 1);
        return node;
    }
    return grow(rows, 1, 0);
}

module.exports = { candidates, goesLeft, bestForAttribute, bestSplit, growTree };
