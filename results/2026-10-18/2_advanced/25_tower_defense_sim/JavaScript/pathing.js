'use strict';

const DIRECTIONS = [
    { x: 0, y: -1, symbol: '^' },
    { x: 1, y: 0, symbol: '>' },
    { x: 0, y: 1, symbol: 'v' },
    { x: -1, y: 0, symbol: '<' },
];

function distanceField(map, blocked) {
    const distances = Array(map.cells.length).fill(-1);
    const queue = [map.exit];
    distances[map.exit] = 0;
    for (let index = 0; index < queue.length; index++) {
        const cell = queue[index];
        const point = map.coordinates(cell);
        for (const direction of DIRECTIONS) {
            const x = point.x + direction.x;
            const y = point.y + direction.y;
            if (!map.inside(x, y)) continue;
            const next = map.cell(x, y);
            if (map.rock(next) || blocked.has(next) || distances[next] !== -1) continue;
            distances[next] = distances[cell] + 1;
            queue.push(next);
        }
    }
    return distances;
}

function nextCell(map, distances, cell) {
    const point = map.coordinates(cell);
    let best = null;
    for (const direction of DIRECTIONS) {
        const x = point.x + direction.x;
        const y = point.y + direction.y;
        if (!map.inside(x, y)) continue;
        const next = map.cell(x, y);
        if (distances[next] < 0) continue;
        if (best === null || distances[next] < distances[best]) best = next;
    }
    return best;
}

function spawnPath(map, distances, spawn) {
    const path = [spawn];
    while (path.at(-1) !== map.exit) path.push(nextCell(map, distances, path.at(-1)));
    return path;
}

module.exports = { DIRECTIONS, distanceField, nextCell, spawnPath };
