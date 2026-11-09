'use strict';

function real(value, digits = 4) {
    if (value === null) return '-';
    if (Math.abs(value) >= 1e21) return `${BigInt(value)}.${'0'.repeat(digits)}`;
    const text = value.toFixed(digits);
    return Number(text) === 0 ? (0).toFixed(digits) : text;
}

function ratio(numerator, denominator) {
    if (denominator === 0) return '-';
    const a = BigInt(numerator);
    const b = BigInt(denominator);
    const rounded = (20000n * a + b) / (2n * b);
    return `${rounded / 10000n}.${String(rounded % 10000n).padStart(4, '0')}`;
}

function prediction(scores) {
    let best = 0;
    for (let k = 1; k < scores.length; k++) if (scores[k] > scores[best]) best = k;
    return best;
}

function secondClass(scores, first) {
    let best = first === 0 ? 1 : 0;
    for (let k = 0; k < scores.length; k++) {
        if (k !== first && scores[k] > scores[best]) best = k;
    }
    return best;
}

function confusion(images, results, classes) {
    const matrix = Array.from({length: classes}, () => Array(classes).fill(0));
    for (let i = 0; i < images.length; i++) matrix[images[i].label][results[i].predicted]++;
    return matrix;
}

function perClass(matrix) {
    const values = [];
    for (let k = 0; k < matrix.length; k++) {
        let support = 0;
        let predicted = 0;
        for (let i = 0; i < matrix.length; i++) {
            support += matrix[k][i];
            predicted += matrix[i][k];
        }
        values.push({support, predicted, precision: ratio(matrix[k][k], predicted),
            recall: ratio(matrix[k][k], support), f1: ratio(2 * matrix[k][k], support + predicted)});
    }
    return values;
}

function levelMaps(maps, width, height) {
    return Array.from({length: height}, (_, row) => maps.map(map =>
        map.slice(row * width, (row + 1) * width).join('')).join(' '));
}

function imageRows(image, width, height) {
    const pixels = image.pixels.replace(/[01]/g, pixel => pixel === '1' ? '#' : '.');
    return Array.from({length: height}, (_, row) => pixels.slice(row * width, (row + 1) * width));
}

module.exports = {real, ratio, prediction, secondClass, confusion, perClass, levelMaps, imageRows};
