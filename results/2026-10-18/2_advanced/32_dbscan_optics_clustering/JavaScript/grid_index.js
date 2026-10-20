'use strict';

function squaredDistance(first, second) {
    const x = first.x - second.x;
    const y = first.y - second.y;
    return x * x + y * y;
}

function buildGrid(points, radius, distances) {
    const cells = new Map();
    const locations = points.map(point => [Math.floor(point.x / radius), Math.floor(point.y / radius)]);
    for (let p = 0; p < points.length; p++) {
        const [gx, gy] = locations[p];
        const key = gx + ',' + gy;
        if (!cells.has(key)) cells.set(key, { gx, gy, points: [] });
        cells.get(key).points.push(p);
    }
    let busiest = null;
    const occupancy = new Map();
    for (const cell of cells.values()) {
        const count = cell.points.length;
        occupancy.set(count, (occupancy.get(count) ?? 0) + 1);
        if (busiest === null || count > busiest.points.length || (count === busiest.points.length
            && (cell.gy < busiest.gy || (cell.gy === busiest.gy && cell.gx < busiest.gx)))) busiest = cell;
    }
    let candidates = 0;
    let neighborTotal = 0;
    let bruteTotal = 0;
    let matches = true;
    const neighborhoods = [];
    const candidateCounts = [];
    for (let p = 0; p < points.length; p++) {
        const [gx, gy] = locations[p];
        const neighbors = [];
        let count = 0;
        for (let row = gy - 1; row <= gy + 1; row++) {
            for (let column = gx - 1; column <= gx + 1; column++) {
                const cell = cells.get(column + ',' + row);
                if (!cell) continue;
                for (const q of cell.points) {
                    count++;
                    if (distances[p][q] <= radius * radius) neighbors.push(q);
                }
            }
        }
        let brute = 0;
        for (let q = 0; q < points.length; q++) if (distances[p][q] <= radius * radius) brute++;
        if (brute !== neighbors.length) matches = false;
        neighborhoods.push(neighbors);
        candidateCounts.push(count);
        candidates += count;
        neighborTotal += neighbors.length;
        bruteTotal += brute;
    }
    return { radius, neighborhoods, candidateCounts, cells: cells.size, busiest, occupancy, candidates,
        pairs: (neighborTotal - points.length) / 2, brutePairs: (bruteTotal - points.length) / 2, matches };
}

module.exports = { squaredDistance, buildGrid };
