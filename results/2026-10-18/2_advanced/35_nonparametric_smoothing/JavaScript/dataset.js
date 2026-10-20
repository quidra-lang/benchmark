'use strict';

const fs = require('node:fs');
const hundredths = text => Number(text.replace('.', ''));
const lines = name => fs.readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);

function readInput() {
    const fields = new Map(lines('params.txt').map(line => {
        const [name, ...values] = line.split(' ');
        return [name, values];
    }));
    const decimalCandidates = name => fields.get(name).map(text => {
        const integer = hundredths(text);
        return { text, hundredths: integer, value: integer / 100 };
    });
    const settings = {
        windows: fields.get('WINDOWS').map(text => ({ text, value: Number(text) })),
        kernels: fields.get('KERNELS'), bandwidths: decimalCandidates('BANDWIDTHS'),
        degrees: fields.get('LOESS_DEGREES').map(Number), spans: decimalCandidates('SPANS'),
        robustIterations: Number(fields.get('ROBUST_ITERATIONS')[0]),
        lambdas: fields.get('LAMBDAS').map(text => ({ text, value: Number(text) })),
        folds: Number(fields.get('CV_FOLDS')[0]), directions: fields.get('ISOTONIC'),
        gridPoints: Number(fields.get('GRID_POINTS')[0]), bandZ: Number(fields.get('BAND_Z')[0]),
        bandMethods: fields.get('BAND_METHODS'), threshold: hundredths(fields.get('OUTLIER_THRESHOLD')[0]),
        bootstrap: Number(fields.get('BOOTSTRAP')[0]), trim: Number(fields.get('BOOTSTRAP')[1]),
        seed: Number(fields.get('BOOTSTRAP')[2]), plotSeries: fields.get('PLOT_SERIES'),
        plotMethods: fields.get('PLOT_METHODS'), width: Number(fields.get('PLOT_SIZE')[0]), height: Number(fields.get('PLOT_SIZE')[1])
    };
    const byName = new Map();
    for (const line of lines('series.csv').slice(1)) {
        const [name, rawX, rawY] = line.split(',');
        if (!byName.has(name)) byName.set(name, { name, points: [] });
        const X = hundredths(rawX);
        const Y = hundredths(rawY);
        byName.get(name).points.push({ X, Y, x: X / 100, y: Y / 100 });
    }
    const series = [...byName.values()];
    for (let i = 0; i < series.length; i++) {
        series[i].points.sort((a, b) => a.X - b.X);
        series[i].mode = settings.directions[i];
    }
    const tests = lines('test_points.csv').slice(1).map(line => {
        const [name, rawX] = line.split(',');
        return { name, X: hundredths(rawX) };
    });
    return { settings, series, tests };
}

module.exports = { hundredths, readInput };
