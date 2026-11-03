'use strict';

const fs = require('node:fs');

function readMaterials() {
    return fs.readFileSync('input/materials.txt', 'ascii').trimEnd().split('\n').map(line => {
        const [code, name, k, rho, cp] = line.split(' ');
        return { code, name, k: Number(k), rho: Number(rho), cp: Number(cp), cells: [] };
    });
}

function capacity(material, dx, depth) {
    return material.rho * material.cp * dx * dx * depth;
}

function interior(kp, kq, depth) {
    return 2 * kp * kq / (kp + kq) * depth;
}

function fixed(k, depth) {
    return 2 * k * depth;
}

function convective(k, h, dx, depth) {
    return 1 / (1 / (h * dx * depth) + 1 / (2 * k * depth));
}

module.exports = { readMaterials, capacity, interior, fixed, convective };
