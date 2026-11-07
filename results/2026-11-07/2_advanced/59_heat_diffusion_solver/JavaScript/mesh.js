'use strict';

const fs = require('node:fs');

function readPlate() {
    const lines = fs.readFileSync('input/plate.txt', 'ascii').trimEnd().split('\n');
    const [width, height, dx, depth] = lines[0].split(' ').map(Number);
    const codes = lines.slice(1).join('').split('');
    const neighbors = [];
    for (let r = 0; r < height; r++) {
        for (let c = 0; c < width; c++) {
            const p = r * width + c;
            neighbors.push([
                c > 0 ? p - 1 : -1,
                c + 1 < width ? p + 1 : -1,
                r > 0 ? p - width : -1,
                r + 1 < height ? p + width : -1,
            ]);
        }
    }
    return { width, height, dx, depth, count: width * height, codes, neighbors };
}

function segmentCells(mesh, edge, start, end) {
    const cells = [];
    for (let i = start; i <= end; i++) {
        if (edge === 'top') cells.push(i);
        else if (edge === 'bottom') cells.push((mesh.height - 1) * mesh.width + i);
        else if (edge === 'left') cells.push(i * mesh.width);
        else cells.push(i * mesh.width + mesh.width - 1);
    }
    return cells;
}

function sourceCells(mesh, r1, c1, r2, c2) {
    const cells = [];
    for (let r = r1; r <= r2; r++) {
        for (let c = c1; c <= c2; c++) cells.push(r * mesh.width + c);
    }
    return cells;
}

module.exports = { readPlate, segmentCells, sourceCells };
