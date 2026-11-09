'use strict';

const DIRECTIONS = [
    { name: 'N', dx: 0, dy: -1 }, { name: 'NE', dx: 1, dy: -1 },
    { name: 'E', dx: 1, dy: 0 }, { name: 'SE', dx: 1, dy: 1 },
    { name: 'S', dx: 0, dy: 1 }, { name: 'SW', dx: -1, dy: 1 },
    { name: 'W', dx: -1, dy: 0 }, { name: 'NW', dx: -1, dy: -1 },
];

function passable(level, x, y) {
    return x >= 0 && x < level.width && y >= 0 && y < level.height
        && '.#+<>'.includes(level.terrain[level.key(x, y)]);
}

function canMove(level, x, y, dx, dy) {
    if (!passable(level, x + dx, y + dy)) return false;
    return dx === 0 || dy === 0 || (level.terrain[level.key(x, y)] !== '+'
        && level.terrain[level.key(x + dx, y + dy)] !== '+');
}

function line(x, y, endX, endY) {
    const dx = Math.abs(endX - x);
    const dy = Math.abs(endY - y);
    const sx = endX > x ? 1 : -1;
    const sy = endY > y ? 1 : -1;
    let error = dx - dy;
    const cells = [];
    while (x !== endX || y !== endY) {
        const twice = 2 * error;
        if (twice > -dy) { error -= dy; x += sx; }
        if (twice < dx) { error += dx; y += sy; }
        cells.push({ x, y });
    }
    return cells;
}

function fieldOfView(level, px, py, radius) {
    const visible = new Set();
    for (let y = 0; y < level.height; y++) {
        for (let x = 0; x < level.width; x++) {
            if ((x - px) * (x - px) + (y - py) * (y - py) > radius * radius) continue;
            const cells = line(px, py, x, y);
            let clear = true;
            for (let i = 0; i + 1 < cells.length; i++) {
                if (!passable(level, cells[i].x, cells[i].y)) { clear = false; break; }
            }
            if (clear) visible.add(level.key(x, y));
        }
    }
    return visible;
}

function distances(level, px, py) {
    const result = Array(level.width * level.height).fill(-1);
    const queue = [{ x: px, y: py }];
    result[level.key(px, py)] = 0;
    for (let head = 0; head < queue.length; head++) {
        const { x, y } = queue[head];
        const nextDistance = result[level.key(x, y)] + 1;
        for (const { dx, dy } of DIRECTIONS) {
            if (!canMove(level, x, y, dx, dy)) continue;
            const key = level.key(x + dx, y + dy);
            if (result[key] !== -1) continue;
            result[key] = nextDistance;
            queue.push({ x: x + dx, y: y + dy });
        }
    }
    return result;
}

module.exports = { DIRECTIONS, passable, canMove, line, fieldOfView, distances };
