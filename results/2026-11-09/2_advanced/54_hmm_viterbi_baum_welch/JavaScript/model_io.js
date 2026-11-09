'use strict';

const fs = require('node:fs');

function normalize(values) {
    let total = 0;
    for (const value of values) total += value;
    return values.map(value => value / total);
}

class Model {
    constructor(name, states, symbols, missing, initial, transition, emission) {
        this.name = name;
        this.states = states;
        this.symbols = symbols;
        this.missing = missing;
        this.initial = initial;
        this.transition = transition;
        this.emission = emission;
    }

    withProbabilities(name, initial, transition, emission) {
        return new Model(name, this.states, this.symbols, this.missing,
            initial, transition, emission);
    }
}

function readRows(filename) {
    return fs.readFileSync(`input/${filename}`, 'ascii').slice(0, -1)
        .split('\n').map(line => line.split(' '));
}

function readInputs() {
    const rows = readRows('model.txt');
    const states = rows[0].slice(1);
    const symbols = rows[1].slice(1);
    const count = states.length;
    const initial = normalize(rows[3].slice(1).map(Number));
    const transition = rows.slice(4, 4 + count)
        .map(row => normalize(row.slice(2).map(Number)));
    const emission = rows.slice(4 + count)
        .map(row => normalize(row.slice(2).map(Number)));
    return {
        model: new Model('INITIAL', states, symbols, rows[2][1], initial,
            transition, emission),
        sequences: readRows('sequences.txt'),
        labeled: readRows('labeled.txt'),
        parameters: readRows('params.txt'),
    };
}

function real(value, digits = 4) {
    if (value === null) return '-';
    if (Math.abs(value) >= 1e21) return `${BigInt(value)}.${'0'.repeat(digits)}`;
    const result = value.toFixed(digits);
    return Number(result) === 0 ? (0).toFixed(digits) : result;
}

function modelLines(model) {
    const lines = [`MODEL ${model.name}`, `STATES ${model.states.join(' ')}`,
        `SYMBOLS ${model.symbols.join(' ')}`, `MISSING ${model.missing}`,
        `INITIAL ${model.initial.map(value => real(value)).join(' ')}`];
    for (let i = 0; i < model.states.length; i++) {
        lines.push(`TRANSITION ${model.states[i]} ${model.transition[i]
            .map(value => real(value)).join(' ')}`);
    }
    for (let i = 0; i < model.states.length; i++) {
        lines.push(`EMISSION ${model.states[i]} ${model.emission[i]
            .map(value => real(value)).join(' ')}`);
    }
    return lines;
}

function writeLines(filename, lines) {
    fs.mkdirSync('output', { recursive: true });
    fs.writeFileSync(`output/${filename}`, `${lines.join('\n')}\n`, 'ascii');
}

module.exports = { Model, normalize, readInputs, real, modelLines, writeLines };
