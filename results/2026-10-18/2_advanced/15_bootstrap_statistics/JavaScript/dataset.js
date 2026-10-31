'use strict';

const fs = require('node:fs');

function readLines(name) {
    return fs.readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);
}

function hundredths(text) {
    const [whole, fraction = ''] = text.split('.');
    return Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
}

function readDataset() {
    const groups = [];
    const byName = new Map();
    for (const line of readLines('samples.csv').slice(1)) {
        const [name, value] = line.split(',');
        if (!byName.has(name)) {
            const group = { name, sample: [] };
            byName.set(name, group);
            groups.push(group);
        }
        byName.get(name).sample.push(hundredths(value));
    }
    const before = [];
    const after = [];
    const differences = [];
    for (const line of readLines('paired.csv').slice(1)) {
        const fields = line.split(',');
        const b = hundredths(fields[1]);
        const a = hundredths(fields[2]);
        before.push(b);
        after.push(a);
        differences.push(a - b);
    }
    const settings = {};
    const pairs = [];
    for (const line of readLines('params.txt')) {
        const [name, ...values] = line.split(' ');
        if (name === 'compare') pairs.push({ x: byName.get(values[0]), y: byName.get(values[1]) });
        else if (name === 'power') [settings.simulations, settings.innerPermutations] = values.map(Number);
        else settings[name] = Number(values[0]);
    }
    return { groups, pairs, before, after, differences, settings };
}

module.exports = { readDataset };
