'use strict';

function minimumMatching(costs) {
    const rows = costs.length, columns = rows === 0 ? 0 : costs[0].length;
    if (rows === 0 || columns === 0) return [];
    const transposed = rows > columns;
    const values = transposed
        ? Array.from({ length: columns }, (_, j) => costs.map(row => row[j])) : costs;
    const n = values.length, m = values[0].length;
    const u = new Array(n + 1).fill(0), v = new Array(m + 1).fill(0);
    const owner = new Array(m + 1).fill(0), way = new Array(m + 1).fill(0);
    for (let row = 1; row <= n; row++) {
        owner[0] = row;
        let column = 0;
        const slack = new Array(m + 1).fill(Infinity), used = new Array(m + 1).fill(false);
        do {
            used[column] = true;
            const current = owner[column];
            let delta = Infinity, next = 0;
            for (let j = 1; j <= m; j++) {
                if (used[j]) continue;
                const reduced = values[current - 1][j - 1] - u[current] - v[j];
                if (reduced < slack[j]) {
                    slack[j] = reduced;
                    way[j] = column;
                }
                if (slack[j] < delta) {
                    delta = slack[j];
                    next = j;
                }
            }
            for (let j = 0; j <= m; j++) {
                if (used[j]) {
                    u[owner[j]] += delta;
                    v[j] -= delta;
                } else slack[j] -= delta;
            }
            column = next;
        } while (owner[column] !== 0);
        do {
            const previous = way[column];
            owner[column] = owner[previous];
            column = previous;
        } while (column !== 0);
    }
    const pairs = [];
    for (let j = 1; j <= m; j++) {
        if (owner[j] === 0) continue;
        pairs.push(transposed ? [j - 1, owner[j] - 1] : [owner[j] - 1, j - 1]);
    }
    pairs.sort((a, b) => a[0] - b[0]);
    return pairs;
}

function optimal(costs) {
    if (costs.length === 0 || costs[0].length === 0) return [];
    let maximum = 0;
    for (const row of costs) for (const cost of row) if (cost !== null) maximum = Math.max(maximum, cost);
    const penalty = (maximum + 1) * (Math.min(costs.length, costs[0].length) + 1);
    const filled = costs.map(row => row.map(cost => cost === null ? penalty : cost));
    return minimumMatching(filled).filter(([i, j]) => costs[i][j] !== null);
}

module.exports = { minimumMatching, optimal };
