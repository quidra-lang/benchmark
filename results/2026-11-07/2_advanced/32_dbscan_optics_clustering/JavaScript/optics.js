'use strict';

function optics(neighborhoods, minimum, distances) {
    const count = neighborhoods.length;
    const core = neighborhoods.map((neighbors, p) => neighbors.length < minimum ? Infinity
        : neighbors.map(q => distances[p][q]).sort((a, b) => a - b)[minimum - 1]);
    const reach = Array(count).fill(Infinity);
    const predecessor = Array(count).fill(-1);
    const processed = Array(count).fill(false);
    const ordering = [];
    for (let start = 0; start < count; start++) {
        if (processed[start]) continue;
        const seeds = new Set([start]);
        while (seeds.size > 0) {
            let p = null;
            for (const candidate of seeds) if (p === null || reach[candidate] < reach[p]
                || (reach[candidate] === reach[p] && candidate < p)) p = candidate;
            seeds.delete(p);
            processed[p] = true;
            ordering.push(p);
            if (core[p] === Infinity) continue;
            for (const q of neighborhoods[p]) {
                if (processed[q]) continue;
                const value = Math.max(core[p], distances[p][q]);
                if (value < reach[q]) {
                    reach[q] = value;
                    predecessor[q] = p;
                    seeds.add(q);
                }
            }
        }
    }
    return { core, reach, predecessor, ordering };
}

module.exports = { optics };
