'use strict';

function dbscan(neighborhoods, minimum) {
    const labels = Array(neighborhoods.length).fill(-2);
    const core = neighborhoods.map(neighbors => neighbors.length >= minimum);
    let cluster = 0;
    for (let p = 0; p < labels.length; p++) {
        if (labels[p] !== -2) continue;
        if (!core[p]) { labels[p] = -1; continue; }
        labels[p] = cluster;
        const queue = neighborhoods[p].slice();
        for (let head = 0; head < queue.length; head++) {
            const q = queue[head];
            if (labels[q] === -1) labels[q] = cluster;
            else if (labels[q] === -2) {
                labels[q] = cluster;
                if (core[q]) queue.push(...neighborhoods[q]);
            }
        }
        cluster++;
    }
    return { labels, core };
}

module.exports = { dbscan };
