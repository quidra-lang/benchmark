'use strict';

function squaredDistance(first, second) {
    const dx = first.x - second.x;
    const dy = first.y - second.y;
    return dx * dx + dy * dy;
}

function distance(first, second) {
    return Math.sqrt(squaredDistance(first, second));
}

function assign(points, centers) {
    return points.map(point => {
        let cluster = 0;
        let best = squaredDistance(point, centers[0]);
        for (let k = 1; k < centers.length; k++) {
            const value = squaredDistance(point, centers[k]);
            if (value < best) {
                cluster = k;
                best = value;
            }
        }
        return cluster;
    });
}

function update(points, assignment, centers) {
    const sums = centers.map(() => ({x: 0, y: 0, count: 0}));
    for (let i = 0; i < points.length; i++) {
        const sum = sums[assignment[i]];
        sum.x += points[i].x;
        sum.y += points[i].y;
        sum.count++;
    }
    return sums.map((sum, k) => sum.count
        ? {x: sum.x / sum.count, y: sum.y / sum.count} : centers[k]);
}

function fit(points, initial, maximumIterations) {
    let centers = initial.map(component => ({x: component.mx, y: component.my}));
    let assignment = assign(points, centers);
    let iterations = 0;
    for (let t = 1; t <= maximumIterations; t++) {
        centers = update(points, assignment, centers);
        const next = assign(points, centers);
        const stable = next.every((cluster, i) => cluster === assignment[i]);
        assignment = next;
        iterations = t;
        if (stable) break;
    }
    let inertia = 0;
    const sizes = centers.map(() => 0);
    for (let i = 0; i < points.length; i++) {
        sizes[assignment[i]]++;
        inertia += squaredDistance(points[i], centers[assignment[i]]);
    }
    return {centers, assignment, iterations, inertia, sizes};
}

module.exports = {squaredDistance, distance, assign, update, fit};
