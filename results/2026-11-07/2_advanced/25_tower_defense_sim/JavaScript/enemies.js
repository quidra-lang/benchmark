'use strict';

const { nextCell } = require('./pathing');
const { newEffect, advanceEffect, isqrt, squaredDistance } = require('./combat');

function parseEnemyType(fields, known) {
    return {
        name: fields[1], symbol: fields[2], movement: fields[3],
        hp: Number(fields[4]), armor: Number(fields[5]), speed: Number(fields[6]),
        bounty: Number(fields[7]), lives: Number(fields[8]), regen: Number(fields[9]),
        splitInto: fields[10] === '-' ? null : known.get(fields[10]), splitCount: Number(fields[11]),
        spawned: 0, killed: 0, leaked: 0, damage: 0,
    };
}

function parseGroup(fields, known) {
    return {
        type: known.get(fields[1]), spawn: Number(fields[2]), count: Number(fields[3]),
        delay: Number(fields[4]), interval: Number(fields[5]), multiplier: Number(fields[6]),
    };
}

function newEnemy(number, type, multiplier) {
    const maximum = Math.floor(type.hp * multiplier / 100);
    return { number, type, multiplier, maximum, hp: maximum, alive: true, slow: newEffect(), burn: newEffect() };
}

function spawnEnemy(number, type, multiplier, spawn, map, distances) {
    const enemy = newEnemy(number, type, multiplier);
    if (type.movement === 'ground') {
        enemy.current = spawn;
        enemy.next = nextCell(map, distances, spawn);
        enemy.progress = 0;
    } else enemy.point = map.center(spawn);
    return enemy;
}

function splitEnemy(number, type, parent) {
    const enemy = newEnemy(number, type, parent.multiplier);
    if (type.movement === 'ground') {
        enemy.current = parent.current;
        enemy.next = parent.next;
        enemy.progress = parent.progress;
    } else enemy.point = { ...parent.point };
    return enemy;
}

function position(enemy, map) {
    if (enemy.type.movement === 'air') return enemy.point;
    const current = map.coordinates(enemy.current);
    const next = map.coordinates(enemy.next);
    return {
        x: 100 * current.x + (next.x - current.x) * enemy.progress,
        y: 100 * current.y + (next.y - current.y) * enemy.progress,
    };
}

function occupiedCell(enemy, map) {
    if (enemy.type.movement === 'ground') return enemy.progress < 50 ? enemy.current : enemy.next;
    return map.cell(Math.floor((enemy.point.x + 50) / 100), Math.floor((enemy.point.y + 50) / 100));
}

function remainingDistance(enemy, map, distances) {
    if (enemy.type.movement === 'ground') return 100 * distances[enemy.next] + 100 - enemy.progress;
    return isqrt(squaredDistance(enemy.point, map.center(map.exit)));
}

function slowedSpeed(enemy) {
    let speed = enemy.type.speed;
    if (enemy.slow.remaining > 0) {
        speed = Math.floor(speed * (100 - enemy.slow.strength) / 100);
        advanceEffect(enemy.slow);
    }
    return speed;
}

module.exports = { parseEnemyType, parseGroup, spawnEnemy, splitEnemy, position, occupiedCell, remainingDistance, slowedSpeed };
