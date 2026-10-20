'use strict';

const fs = require('node:fs');
const readLines = name => fs.readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);

function readDataset() {
    const points = readLines('points.csv').slice(1).map(line => {
        const [id, x, y] = line.split(',').map(Number);
        return { id, x, y };
    }).sort((a, b) => a.id - b.id);
    const fields = new Map(readLines('params.txt').map(line => {
        const [name, ...values] = line.split(' ');
        return [name, values];
    }));
    const numbers = name => fields.get(name).map(Number);
    const first = name => Number(fields.get(name)[0]);
    return { points, parameters: { eps: numbers('EPS'), minimum: first('MIN_PTS'), maximum: first('OPTICS_MAX_EPS'),
        extracts: numbers('EXTRACT_EPS'), xi: fields.get('XI')[0].split('/').map(Number), xiText: fields.get('XI')[0],
        minimumSize: first('XI_MIN_SIZE'), mapSize: numbers('MAP_SIZE'), kdistSize: numbers('KDIST_PLOT'),
        reachWidth: first('PLOT_WIDTH') } };
}

module.exports = { readDataset };
