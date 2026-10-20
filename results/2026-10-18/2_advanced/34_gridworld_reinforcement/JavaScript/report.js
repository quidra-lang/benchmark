'use strict';

const fs = require('node:fs');
const { ACTIONS } = require('./environment');
const { floorDivide } = require('./dynamic_programming');

const POLICY_CHARACTERS = '^>v<';

function fixed(value) {
    if (value === null) return '-';
    const magnitude = Math.abs(value);
    return `${value < 0 ? '-' : ''}${floorDivide(magnitude, 10000)}.${String(magnitude % 10000).padStart(4, '0')}`;
}

function average(total, count) {
    return fixed(floorDivide(10000 * total, count));
}

function cell(world, position) {
    return `${Math.floor(position / world.width)},${position % world.width}`;
}

function grid(world, content, separated = false) {
    const lines = [];
    for (let row = 0; row < world.height; row++) {
        const fields = [];
        for (let column = 0; column < world.width; column++) {
            const position = row * world.width + column;
            const state = world.index[position];
            fields.push(state < 0 ? world.cells[position] : String(content(state, position)));
        }
        lines.push(fields.join(separated ? ' ' : ''));
    }
    return lines;
}

function policyGrid(world, policy) {
    return grid(world, state => POLICY_CHARACTERS[policy[state]]);
}

function qRows(name, world, table, visits = null) {
    const lines = [];
    world.states.forEach((position, state) => {
        for (let action = 0; action < 4; action++) {
            lines.push(`${name},${cell(world, position)},${ACTIONS[action]},${fixed(table[state][action])},${visits === null ? '-' : visits[state][action]}`);
        }
    });
    return lines;
}

function writeReports(reports) {
    fs.mkdirSync('output', { recursive: true });
    for (const [name, lines] of Object.entries(reports)) {
        fs.writeFileSync(`output/${name}`, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
    }
}

module.exports = { fixed, average, cell, grid, policyGrid, qRows, writeReports };
