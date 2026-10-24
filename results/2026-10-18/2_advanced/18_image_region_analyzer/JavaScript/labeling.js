'use strict';

const DIRECTIONS = {
    4: [[1, 0], [0, -1], [-1, 0], [0, 1]],
    8: [[1, 0], [1, -1], [0, -1], [-1, -1], [-1, 0], [-1, 1], [0, 1], [1, 1]],
};

function label(mask, width, height, connectivity) {
    const provisional = new Int32Array(mask.length);
    const parents = [0];
    const preceding = connectivity === 4 ? [[-1, 0], [0, -1]]
        : [[-1, 0], [-1, -1], [0, -1], [1, -1]];
    function find(value) {
        let root = value;
        while (parents[root] !== root) root = parents[root];
        while (value !== root) {
            const next = parents[value];
            parents[value] = root;
            value = next;
        }
        return root;
    }
    function merge(first, second) {
        const a = find(first);
        const b = find(second);
        if (a < b) parents[b] = a;
        else parents[a] = b;
    }
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            const index = y * width + x;
            if (!mask[index]) continue;
            const neighbours = [];
            for (const [dx, dy] of preceding) {
                const nx = x + dx;
                const ny = y + dy;
                if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
                const value = provisional[ny * width + nx];
                if (value !== 0) neighbours.push(value);
            }
            if (neighbours.length === 0) {
                provisional[index] = parents.length;
                parents.push(parents.length);
            } else {
                const chosen = Math.min(...neighbours);
                provisional[index] = chosen;
                for (const other of neighbours) merge(chosen, other);
            }
        }
    }
    const labels = new Int32Array(mask.length);
    const components = [];
    const numbers = new Map();
    for (let index = 0; index < mask.length; index++) {
        if (provisional[index] === 0) continue;
        const root = find(provisional[index]);
        if (!numbers.has(root)) {
            numbers.set(root, components.length + 1);
            components.push([]);
        }
        const number = numbers.get(root);
        labels[index] = number;
        components[number - 1].push(index);
    }
    return { labels, components, provisional: parents.length - 1 };
}

function bitQuadEuler(mask, width, height, connectivity) {
    function at(x, y) {
        return x >= 0 && x < width && y >= 0 && y < height ? mask[y * width + x] : 0;
    }
    let one = 0;
    let three = 0;
    let diagonal = 0;
    for (let y = -1; y < height; y++) {
        for (let x = -1; x < width; x++) {
            const a = at(x, y);
            const b = at(x + 1, y);
            const c = at(x, y + 1);
            const d = at(x + 1, y + 1);
            const count = a + b + c + d;
            if (count === 1) one++;
            if (count === 3) three++;
            if (count === 2 && ((a && d) || (b && c))) diagonal++;
        }
    }
    return (one - three + (connectivity === 8 ? -2 : 2) * diagonal) / 4;
}

module.exports = { DIRECTIONS, label, bitQuadEuler };
