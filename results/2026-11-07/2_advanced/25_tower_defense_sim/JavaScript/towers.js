'use strict';

const { position, remainingDistance } = require('./enemies');
const { squaredDistance } = require('./combat');

const MODES = ['FIRST', 'LAST', 'STRONGEST', 'WEAKEST', 'CLOSEST'];
const PERFORMANCE = ['cost', 'range', 'power', 'interval', 'shotSpeed', 'splash', 'slowRate', 'slowTime', 'burnAmount', 'burnTime'];

function parseTowerType(header, rows) {
    const levels = rows.map(fields => Object.fromEntries(PERFORMANCE.map((name, index) => [name, Number(fields[index + 1])])));
    return { name: header[1], symbol: header[2], targets: header[3], levels };
}

function createTower(number, type, x, y, map, tick) {
    return {
        number, type, x, y, cell: map.cell(x, y), level: 1, mode: 'FIRST',
        ready: tick, investment: type.levels[0].cost, built: tick, sold: null,
        shots: 0, hits: 0, fizzles: 0, kills: 0, damage: 0,
    };
}

function canAim(targets, enemy) {
    return targets === 'both' || targets === enemy.type.movement;
}

function withinRange(tower, enemy, map) {
    const range = tower.type.levels[tower.level - 1].range;
    return squaredDistance(map.center(tower.cell), position(enemy, map)) <= range * range;
}

function chooseTarget(tower, enemies, map, distances) {
    let best = null;
    let bestValue = 0;
    for (const enemy of enemies) {
        if (!enemy.alive || !canAim(tower.type.targets, enemy) || !withinRange(tower, enemy, map)) continue;
        let value;
        switch (tower.mode) {
            case 'FIRST': value = remainingDistance(enemy, map, distances); break;
            case 'LAST': value = -remainingDistance(enemy, map, distances); break;
            case 'STRONGEST': value = -enemy.hp; break;
            case 'WEAKEST': value = enemy.hp; break;
            case 'CLOSEST': value = squaredDistance(map.center(tower.cell), position(enemy, map)); break;
        }
        if (best === null || value < bestValue || (value === bestValue && enemy.number < best.number)) {
            best = enemy;
            bestValue = value;
        }
    }
    return best;
}

module.exports = { MODES, parseTowerType, createTower, canAim, withinRange, chooseTarget };
