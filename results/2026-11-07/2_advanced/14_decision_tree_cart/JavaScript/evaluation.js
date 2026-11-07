'use strict';

const { goesLeft } = require('./tree_builder');

function isLeaf(node, view) {
    return node.split === null || view.cuts.has(node.number);
}

function preorder(view) {
    const nodes = [];
    function visit(node) {
        nodes.push(node);
        if (!isLeaf(node, view)) {
            visit(node.left);
            visit(node.right);
        }
    }
    visit(view.root);
    return nodes;
}

function route(view, row) {
    const path = [];
    const steps = [];
    let node = view.root;
    while (true) {
        path.push(node);
        if (isLeaf(node, view)) return { leaf: node, prediction: node.majority, path, steps };
        let left;
        let method;
        if (row.values[node.split.attribute] !== null) {
            left = goesLeft(node.split, row);
            method = 'primary';
        } else {
            const surrogate = node.surrogates.find(item => row.values[item.split.attribute] !== null);
            if (surrogate !== undefined) {
                left = goesLeft(surrogate.split, row) === (surrogate.direction === 'left');
                method = 'surrogate';
            } else {
                left = node.defaultDirection === 'left';
                method = 'default';
            }
        }
        steps.push({ node, left, method });
        node = left ? node.left : node.right;
    }
}

function predict(view, row) {
    return route(view, row).prediction;
}

function correctCount(view, rows) {
    let correct = 0;
    for (const row of rows) if (predict(view, row) === row.label) correct++;
    return correct;
}

function formatReal(value, digits = 4) {
    const text = value.toFixed(digits);
    return Number(text) === 0 ? (0).toFixed(digits) : text;
}

function ratio(numerator, denominator) {
    if (denominator === 0) return '0/0 -';
    return `${numerator}/${denominator} ${formatReal(numerator / denominator)}`;
}

function reducedFraction(numerator, denominator, digits = 4) {
    if (denominator === 0) return '- -';
    const value = numerator / denominator;
    let a = Math.abs(numerator);
    let b = denominator;
    while (b !== 0) [a, b] = [b, a % b];
    return `${numerator / a}/${denominator / a} ${formatReal(value, digits)}`;
}

function classificationLines(title, rows, predictions, classes) {
    const count = classes.length;
    const matrix = Array.from({ length: count }, () => Array(count).fill(0));
    let correct = 0;
    for (let index = 0; index < rows.length; index++) {
        matrix[rows[index].label][predictions[index]]++;
        if (rows[index].label === predictions[index]) correct++;
    }
    const lines = [
        `confusion ${title} correct ${correct}/${rows.length} accuracy ${reducedFraction(correct, rows.length)}`,
        `actual\\predicted ${classes.join(' ')}`,
    ];
    for (let index = 0; index < count; index++) lines.push(`${classes[index]} ${matrix[index].join(' ')}`);
    let macro = 0;
    let defined = 0;
    for (let index = 0; index < count; index++) {
        const truePositive = matrix[index][index];
        let predicted = 0;
        let actual = 0;
        for (let other = 0; other < count; other++) {
            predicted += matrix[other][index];
            actual += matrix[index][other];
        }
        const precision = reducedFraction(truePositive, predicted);
        const recall = reducedFraction(truePositive, actual);
        const f1 = reducedFraction(2 * truePositive, predicted + actual);
        lines.push(`class ${classes[index]} precision ${precision} recall ${recall} f1 ${f1} support ${actual}`);
        if (predicted + actual > 0) {
            macro += (2 * truePositive) / (predicted + actual);
            defined++;
        }
    }
    lines.push(`macro_f1 ${defined === 0 ? '-' : formatReal(macro / defined)}`);
    return lines;
}

module.exports = {
    isLeaf, preorder, route, predict, correctCount, formatReal, ratio,
    reducedFraction, classificationLines,
};
