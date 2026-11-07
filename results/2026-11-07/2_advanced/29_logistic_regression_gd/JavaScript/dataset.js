'use strict';

const fs = require('node:fs');

function lines(path) {
    return fs.readFileSync(path, 'ascii').slice(0, -1).split('\n');
}

function readTable(path) {
    const records = lines(path).map(line => line.split(','));
    const names = records[0].slice(1, -1);
    const rows = records.slice(1);
    return {
        names, ids: rows.map(row => row[0]),
        base: rows.map(row => row.slice(1, -1).map(Number)),
        labels: rows.map(row => Number(row.at(-1))),
    };
}

function readInputs() {
    const train = readTable('input/train.csv');
    const test = readTable('input/test.csv');
    const parameters = new Map(lines('input/params.txt').map(line => {
        const [name, ...values] = line.split(' ');
        return [name, values.map(Number)];
    }));
    const settings = {
        positive: parameters.get('POSITIVE')[0], degree: parameters.get('DEGREE')[0],
        threshold: parameters.get('THRESHOLD')[0], lambdas: parameters.get('LAMBDAS'),
        gd: parameters.get('GD'), sgd: parameters.get('SGD'), softmax: parameters.get('SOFTMAX'),
        bootstrap: parameters.get('BOOTSTRAP'), permutation: parameters.get('PERMUTATION'),
        map: parameters.get('MAP'), cost: parameters.get('COST'),
    };
    return { names: train.names, train, test, settings };
}

function expandedFeatures(names, maximumDegree) {
    const features = [];
    function visit(tuple, start, remaining) {
        if (remaining === 0) {
            features.push({ tuple: tuple.slice(), degree: tuple.length, name: tuple.map(index => names[index]).join('*') });
            return;
        }
        for (let index = start; index < names.length; index++) {
            tuple.push(index);
            visit(tuple, index, remaining - 1);
            tuple.pop();
        }
    }
    for (let degree = 1; degree <= maximumDegree; degree++) visit([], 0, degree);
    return features;
}

function expand(base, features) {
    return features.map(feature => {
        let value = base[feature.tuple[0]];
        for (let index = 1; index < feature.tuple.length; index++) value *= base[feature.tuple[index]];
        return value;
    });
}

function statistics(values, width = values[0].length) {
    const means = Array(width);
    const deviations = Array(width);
    for (let feature = 0; feature < width; feature++) {
        let total = 0;
        for (const row of values) total += row[feature];
        const mean = total / values.length;
        let squared = 0;
        for (const row of values) squared += (row[feature] - mean) * (row[feature] - mean);
        means[feature] = mean;
        deviations[feature] = Math.sqrt(squared / (values.length - 1));
    }
    return { means, deviations };
}

function standardizeOne(values, stats) {
    return [1, ...stats.means.map((mean, index) => (values[index] - mean) / stats.deviations[index])];
}

function standardize(values, stats) {
    return values.map(row => standardizeOne(row, stats));
}

module.exports = { readInputs, expandedFeatures, expand, statistics, standardizeOne, standardize };
