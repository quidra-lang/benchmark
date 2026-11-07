'use strict';

const fs = require('node:fs');

function readLines(name) {
    return fs.readFileSync(`input/${name}`, 'ascii').slice(0, -1).split('\n');
}

function parseHex(text) {
    return /^[0-9a-f]{8}$/.test(text) ? Number.parseInt(text, 16) : null;
}

function parseRegister(text) {
    if (text === '-') return null;
    return /^r(?:[0-9]|[12][0-9]|3[01])$/.test(text) ? Number(text.slice(1)) : undefined;
}

function read() {
    const config = {predictors: [], variants: []};
    for (const line of readLines('config.txt')) {
        const [keyword, ...words] = line.split(' ');
        if (keyword === 'BTB') config.btb = Number(words[0]);
        else if (keyword === 'RAS') config.ras = Number(words[0]);
        else if (keyword === 'PREDICTOR') {
            config.predictors.push({name: words[0], scheme: words[1], parameters: words.slice(2).map(Number)});
        } else if (keyword === 'VARIANT') {
            config.variants.push({name: words[0], forwarding: words[1] === 'ON',
                resolution: words[2], latency: Number(words[3])});
        } else if (keyword === 'PRIMARY') {
            [config.primaryVariant, config.primaryPredictor] = words;
        } else if (keyword === 'WINDOW') {
            [config.start, config.end] = words.map(Number);
        } else if (keyword === 'TOP') config.top = Number(words[0]);
        else if (keyword === 'INTERVAL') config.interval = Number(words[0]);
    }
    return {lines: readLines('trace.txt'), config};
}

module.exports = {read, parseHex, parseRegister};
