'use strict';

class DungeonLevel {
    constructor(width, height, depth) {
        this.width = width;
        this.height = height;
        this.depth = depth;
        this.terrain = Array(width * height).fill(' ');
        this.memory = Array(width * height).fill(' ');
        this.rooms = [];
        this.monsters = [];
        this.items = new Map();
        this.killed = 0;
        this.picked = 0;
    }

    key(x, y) { return y * this.width + x; }

    roomCell(rng, number = null) {
        if (number === null) number = rng.rnd(this.rooms.length);
        const room = this.rooms[number];
        const x = room.x + 1 + rng.rnd(room.width - 2);
        const y = room.y + 1 + rng.rnd(room.height - 2);
        return { x, y, room: number };
    }
}

function generateDungeon(config, depth, rng) {
    const level = new DungeonLevel(config.width, config.height, depth);
    const leaves = [];
    const minimum = config.regionSize;
    function split(x, y, width, height, splitDepth) {
        const vertical = width >= 2 * minimum;
        const horizontal = height >= 2 * minimum;
        if (splitDepth === config.splitDepth || (!vertical && !horizontal)) {
            const node = { x, y, width, height, roomNumbers: [leaves.length] };
            leaves.push(node);
            return node;
        }
        let cutVertically = vertical;
        if (vertical && horizontal) {
            if (4 * width >= 5 * height) cutVertically = true;
            else if (4 * height >= 5 * width) cutVertically = false;
            else cutVertically = rng.rnd(2) === 0;
        }
        let first;
        let second;
        if (cutVertically) {
            const cut = minimum + rng.rnd(width - 2 * minimum + 1);
            first = split(x, y, cut, height, splitDepth + 1);
            second = split(x + cut, y, width - cut, height, splitDepth + 1);
        } else {
            const cut = minimum + rng.rnd(height - 2 * minimum + 1);
            first = split(x, y, width, cut, splitDepth + 1);
            second = split(x, y + cut, width, height - cut, splitDepth + 1);
        }
        return { first, second, roomNumbers: [...first.roomNumbers, ...second.roomNumbers] };
    }
    const tree = split(0, 0, config.width, config.height, 0);
    for (const leaf of leaves) {
        const width = config.roomMin + rng.rnd(Math.min(config.roomMax, leaf.width - 1) - config.roomMin + 1);
        const height = config.roomMin + rng.rnd(Math.min(config.roomMax, leaf.height - 1) - config.roomMin + 1);
        const x = leaf.x + rng.rnd(leaf.width - width);
        const y = leaf.y + rng.rnd(leaf.height - height);
        const room = { x, y, width, height, cx: x + Math.floor(width / 2), cy: y + Math.floor(height / 2) };
        level.rooms.push(room);
        for (let row = y; row < y + height; row++) {
            for (let column = x; column < x + width; column++) {
                level.terrain[level.key(column, row)] = row === y || row === y + height - 1 ? '-'
                    : column === x || column === x + width - 1 ? '|' : '.';
            }
        }
    }
    function carve(x, y, endX, endY) {
        const dx = Math.sign(endX - x);
        const dy = Math.sign(endY - y);
        for (;;) {
            const key = level.key(x, y);
            if (level.terrain[key] === ' ') level.terrain[key] = '#';
            else if (level.terrain[key] === '-' || level.terrain[key] === '|') level.terrain[key] = '+';
            if (x === endX && y === endY) return;
            x += dx;
            y += dy;
        }
    }
    function connect(node) {
        if (!node.first) return;
        connect(node.first);
        connect(node.second);
        let chosen = null;
        for (const a of node.first.roomNumbers) {
            for (const b of node.second.roomNumbers) {
                const first = level.rooms[a];
                const second = level.rooms[b];
                const distance = Math.abs(first.cx - second.cx) + Math.abs(first.cy - second.cy);
                if (chosen === null || distance < chosen.distance) chosen = { first, second, distance };
            }
        }
        const { first, second } = chosen;
        if (rng.rnd(2) === 0) {
            carve(first.cx, first.cy, second.cx, first.cy);
            carve(second.cx, first.cy, second.cx, second.cy);
        } else {
            carve(first.cx, first.cy, first.cx, second.cy);
            carve(first.cx, second.cy, second.cx, second.cy);
        }
    }
    connect(tree);
    level.arrival = level.roomCell(rng);
    level.terrain[level.key(level.arrival.x, level.arrival.y)] = '<';
    let targetRoom = rng.rnd(level.rooms.length - 1);
    if (targetRoom >= level.arrival.room) targetRoom++;
    level.target = level.roomCell(rng, targetRoom);
    return level;
}

module.exports = { DungeonLevel, generateDungeon };
