'use strict';

const fs = require('node:fs');

class GridMap {
    constructor(width, height, rows) {
        this.width = width;
        this.height = height;
        this.cells = rows.join('').split('');
        this.spawns = [];
        this.exit = -1;
        this.cells.forEach((terrain, cell) => {
            if (terrain === 'E') this.exit = cell;
            else if (/^[1-9]$/.test(terrain)) this.spawns.push({ number: Number(terrain), cell });
        });
        this.spawns.sort((a, b) => a.number - b.number);
    }

    inside(x, y) {
        return x >= 0 && x < this.width && y >= 0 && y < this.height;
    }

    cell(x, y) {
        return y * this.width + x;
    }

    coordinates(cell) {
        return { x: cell % this.width, y: Math.floor(cell / this.width) };
    }

    center(cell) {
        const { x, y } = this.coordinates(cell);
        return { x: 100 * x, y: 100 * y };
    }

    rock(cell) {
        return this.cells[cell] === '#';
    }

    water(cell) {
        return this.cells[cell] === '~';
    }

    buildable(cell) {
        return this.cells[cell] === '.';
    }
}

function readMap() {
    const lines = fs.readFileSync('input/map.txt', 'ascii').slice(0, -1).split('\n');
    const [width, height] = lines[0].split(' ').map(Number);
    return new GridMap(width, height, lines.slice(1));
}

module.exports = { GridMap, readMap };
