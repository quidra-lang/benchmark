'use strict';

const fs = require('node:fs');
const readLines = name => fs.readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);

function readInput() {
    const ecg = readLines('ecg.csv').slice(1).map(line => Number(line.split(',')[1]));
    const annotations = readLines('annotations.csv').slice(1).map(line => {
        const [sample, label] = line.split(',');
        return { sample: Number(sample), label, beat: null };
    });
    const parameters = Object.fromEntries(readLines('params.txt').map(line => {
        const [name, value] = line.split(' ');
        return [name, Number(value)];
    }));
    return { ecg, annotations, parameters };
}

function writeLines(name, lines) {
    fs.mkdirSync('output', { recursive: true });
    fs.writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

module.exports = { readInput, writeLines };
