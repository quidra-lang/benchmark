'use strict';

const fs = require('node:fs');
const lines = name => fs.readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);

function readTable(name, knownColumns = null) {
    const text = lines(name).map(line => line.split(','));
    const header = text[0];
    const raw = text.slice(1);
    const columns = header.map((name, index) => ({ name, categorical: knownColumns === null
        ? raw.some(row => row[index] !== 'NA' && /^[A-Z]/.test(row[index])) : knownColumns.find(column => column.name === name).categorical }));
    const rows = raw.map((row, index) => ({ number: index + 1, values: Object.fromEntries(columns.map((column, j) =>
        [column.name, row[j] === 'NA' ? null : column.categorical ? row[j] : Number(row[j])])) }));
    return { columns, rows };
}

function readInput() {
    const data = readTable('data.csv');
    const predictions = readTable('predict.csv', data.columns);
    const models = lines('model.txt');
    const parameters = Object.fromEntries(lines('params.txt').map(line => {
        const [name, ...values] = line.split(' ');
        return [name, name === 'PLOT' ? values.map(Number) : Number(values[0])];
    }));
    return { data, predictions, models, parameters };
}

module.exports = { readTable, readInput };
