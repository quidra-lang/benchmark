'use strict';

const fs = require('node:fs');

function lines(filename) {
    return fs.readFileSync(`input/${filename}`, 'ascii').slice(0, -1).split('\n');
}

function images(filename) {
    return lines(filename).slice(1).map(line => {
        const [id, label, pixels] = line.split(',');
        return {id, label: Number(label), pixels, vector: Array.from(pixels, Number)};
    });
}

function readNetworks() {
    const source = lines('network.txt');
    const [, width, height] = source[0].split(' ').map(Number);
    const networks = [];
    for (const line of source.slice(2)) {
        if (line === '') continue;
        const [kind, first, second] = line.split(' ');
        if (kind === 'NETWORK') networks.push({name: first, layers: []});
        else networks.at(-1).layers.push({units: Number(first), activation: second});
    }
    return {width, height, networks};
}

function readWeights() {
    const weights = new Map();
    let current;
    for (const line of lines('weights.txt')) {
        if (line === '') continue;
        const [kind, ...values] = line.split(' ');
        if (kind === 'NETWORK') {
            current = [];
            weights.set(values[0], current);
        } else if (kind === 'W' || kind === 'B') {
            for (const value of values) current.push(Number(value));
        }
    }
    return weights;
}

function readSettings() {
    const settings = {runs: []};
    const single = {SEED: 'seed', BATCH_SIZE: 'batchSize', MAX_EPOCHS: 'maxEpochs',
        PATIENCE: 'patience', GRADIENT_CHECK_STRIDE: 'stride', CALIBRATION_BINS: 'bins'};
    for (const line of lines('params.txt')) {
        const [key, ...values] = line.split(' ');
        if (key in single) settings[single[key]] = Number(values[0]);
        else if (key === 'LR_STEP') [settings.step, settings.gamma] = values.map(Number);
        else if (key === 'PRUNE') settings.prune = values.map(Number);
        else if (key === 'NOISE') settings.noise = values.map(Number);
        else {
            const [name, network, optimizer, eta, decay, ...extra] = values;
            const run = {name, network, optimizer, eta: Number(eta), decay: Number(decay),
                order: settings.runs.length};
            if (optimizer === 'MOMENTUM') run.mu = Number(extra[0]);
            if (optimizer === 'ADAM') [run.beta1, run.beta2, run.epsilon] = extra.map(Number);
            settings.runs.push(run);
        }
    }
    return settings;
}

function readInputs() {
    return {...readNetworks(), weights: readWeights(), settings: readSettings(),
        train: images('train.csv'), test: images('test.csv')};
}

class Minstd {
    constructor(seed) {
        this.state = seed;
    }

    next() {
        this.state = (48271 * this.state) % 2147483647;
        return this.state;
    }

    shuffle(values) {
        for (let i = values.length - 1; i > 0; i--) {
            const j = this.next() % (i + 1);
            [values[i], values[j]] = [values[j], values[i]];
        }
        return values;
    }
}

module.exports = {readInputs, Minstd};
