'use strict';

function real(value) {
    if (value === null) return '-';
    let text = Math.abs(value).toFixed(4);
    if (text.includes('e')) text = BigInt(Math.abs(value)).toString() + '.0000';
    return value < 0 && /[1-9]/.test(text) ? '-' + text : text;
}

const rounded = value => Number(real(value));
const proportion = (numerator, denominator) => `${numerator}/${denominator} ${real(numerator / denominator)}`;

function metric(numerator, denominator) {
    if (denominator === 0) return '- -';
    let a = numerator;
    let b = denominator;
    while (b !== 0) [a, b] = [b, a % b];
    return `${numerator / a}/${denominator / a} ${real(numerator / denominator)}`;
}

function evaluate(actual, predicted, classCount) {
    const matrix = Array.from({ length: classCount }, () => Array(classCount).fill(0));
    for (let i = 0; i < actual.length; i++) matrix[actual[i]][predicted[i]]++;
    const details = [];
    let correct = 0;
    let macroTotal = 0;
    let defined = 0;
    for (let c = 0; c < classCount; c++) {
        const truePositive = matrix[c][c];
        let support = 0;
        let predictedCount = 0;
        for (let other = 0; other < classCount; other++) {
            support += matrix[c][other];
            predictedCount += matrix[other][c];
        }
        correct += truePositive;
        if (support + predictedCount > 0) {
            macroTotal += (2 * truePositive) / (predictedCount + support);
            defined++;
        }
        details.push({ truePositive, support, predictedCount });
    }
    return { matrix, details, correct, micro: correct / actual.length, macro: macroTotal / defined };
}

function evaluationLines(result, classes) {
    const lines = ['true\\predicted ' + classes.join(' ')];
    for (let c = 0; c < classes.length; c++) lines.push(classes[c] + ' ' + result.matrix[c].join(' '));
    for (let c = 0; c < classes.length; c++) {
        const { truePositive, support, predictedCount } = result.details[c];
        lines.push(`class ${classes[c]} precision ${metric(truePositive, predictedCount)} recall ${metric(truePositive, support)}` +
            ` f1 ${metric(2 * truePositive, predictedCount + support)} support ${support}`);
    }
    lines.push(`micro_f1 ${real(result.micro)} macro_f1 ${real(result.macro)}`);
    return lines;
}

module.exports = { real, rounded, proportion, metric, evaluate, evaluationLines };
