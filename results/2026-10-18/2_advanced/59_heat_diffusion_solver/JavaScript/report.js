'use strict';

const fs = require('node:fs');

function fixed(value, places) {
    let result;
    if (Math.abs(value) < 1e21) result = value.toFixed(places);
    else {
        result = (value < 0 ? '-' : '') + BigInt(Math.abs(value)).toString();
        if (places > 0) result += '.' + '0'.repeat(places);
    }
    return /^-0(?:\.0+)?$/.test(result) ? result.slice(1) : result;
}

function time(milliseconds) {
    return Math.floor(milliseconds / 1000) + '.' + String(milliseconds % 1000).padStart(3, '0');
}

function temperatureRows(mesh, field) {
    const lines = [];
    for (let r = 0; r < mesh.height; r++) {
        lines.push(field.slice(r * mesh.width, (r + 1) * mesh.width).map(t => fixed(t, 2)).join(' '));
    }
    return lines;
}

function isothermRows(mesh, field, bands) {
    let hottest = 0;
    for (let p = 1; p < mesh.count; p++) if (field[p] > field[hottest]) hottest = p;
    const counts = new Array(bands.length + 1).fill(0);
    const characters = field.map((value, p) => {
        let digit = 0;
        for (const boundary of bands) if (boundary <= value) digit++;
        counts[digit]++;
        return p === hottest ? '*' : String(digit);
    });
    const lines = [];
    for (let r = 0; r < mesh.height; r++) {
        lines.push(characters.slice(r * mesh.width, (r + 1) * mesh.width).join(''));
    }
    return { counts, lines };
}

function writeFiles(files) {
    fs.mkdirSync('output', { recursive: true });
    for (const [name, lines] of Object.entries(files)) {
        fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
    }
}

module.exports = { fixed, time, temperatureRows, isothermRows, writeFiles };
