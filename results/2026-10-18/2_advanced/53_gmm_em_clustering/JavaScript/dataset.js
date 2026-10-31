'use strict';

const fs = require('node:fs');

function lines(name) {
    return fs.readFileSync(`input/${name}`, 'ascii').slice(0, -1).split('\n');
}

function read() {
    const points = lines('points.csv').slice(1).map(line => {
        const [id, x, y] = line.split(',');
        return {id, x: Number(x), y: Number(y)};
    });
    const settings = new Map(lines('params.txt').map(line => {
        const [name, ...values] = line.split(' ');
        return [name, values];
    }));
    const values = name => settings.get(name).map(Number);
    const params = {
        ks: values('K'), types: settings.get('TYPES'),
        iterations: values('ITERATIONS')[0], eps: values('REGULARIZATION')[0],
        tau: values('SETTLE_TOLERANCE')[0],
        kmeansMax: values('KMEANS_MAX_ITERATIONS')[0],
        folds: values('CV_FOLDS')[0], uncertain: values('UNCERTAIN_THRESHOLD')[0],
        lowDensity: values('LOW_DENSITY_THRESHOLD')[0], edges: values('GOF_EDGES'),
        xmin: values('MAP_X')[0], xmax: values('MAP_X')[1],
        ymin: values('MAP_Y')[0], ymax: values('MAP_Y')[1],
        width: values('MAP_SIZE')[0], height: values('MAP_SIZE')[1]
    };
    const initial = new Map();
    for (const block of lines('init.txt').join('\n').split('\n\n')) {
        const rows = block.split('\n');
        const K = Number(rows[0].split(' ')[1]);
        const weights = rows[1].split(' ').slice(1).map(Number);
        const components = rows.slice(2).map((line, k) => {
            const [, , mx, my, a, b, c] = line.split(' ').map(Number);
            return {w: weights[k], mx, my, a, b, c};
        });
        initial.set(K, components);
    }
    return {points, params, initial};
}

module.exports = {read};
