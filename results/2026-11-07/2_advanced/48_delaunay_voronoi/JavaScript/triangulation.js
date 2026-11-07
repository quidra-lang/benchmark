'use strict';

const { orient, incircle } = require('./predicates');
const key = (a, b) => a + ',' + b;

function canonical(triangle) {
    const start = triangle.indexOf(Math.min(...triangle));
    return [triangle[start], triangle[(start + 1) % 3], triangle[(start + 2) % 3]];
}

class Triangulation {
    constructor(points) {
        this.points = points;
        this.directed = new Map();
        this.initial = orient(points[1], points[2], points[3]) > 0 ? [1, 2, 3] : [1, 3, 2];
        this.add(...this.initial);
    }

    add(a, b, c) {
        this.directed.set(key(a, b), c);
        this.directed.set(key(b, c), a);
        this.directed.set(key(c, a), b);
    }

    remove(a, b, c) {
        this.directed.delete(key(a, b));
        this.directed.delete(key(b, c));
        this.directed.delete(key(c, a));
    }

    triangles() {
        const result = [];
        for (const [edge, c] of this.directed) {
            const [a, b] = edge.split(',').map(Number);
            if (a < b && a < c) result.push([a, b, c]);
        }
        return result.sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2]);
    }

    hullEdges() {
        const result = [];
        for (const edge of this.directed.keys()) {
            const [a, b] = edge.split(',').map(Number);
            if (!this.directed.has(key(b, a))) result.push([a, b]);
        }
        return result.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    }

    insert(site) {
        const points = this.points;
        const containing = this.triangles().find(([a, b, c]) => orient(points[a], points[b], points[site]) > 0
            && orient(points[b], points[c], points[site]) > 0 && orient(points[c], points[a], points[site]) > 0);
        const pending = new Set();
        let visible = 0;
        if (containing) {
            const [a, b, c] = containing;
            this.remove(a, b, c);
            for (const [u, v] of [[a, b], [b, c], [c, a]]) { this.add(u, v, site); pending.add(key(u, v)); }
        } else {
            for (const [u, v] of this.hullEdges()) {
                if (orient(points[u], points[v], points[site]) >= 0) continue;
                visible++;
                this.add(v, u, site);
                pending.add(key(v, u));
            }
        }
        let flips = 0;
        while (pending.size > 0) {
            const edge = pending.values().next().value;
            pending.delete(edge);
            const [a, b] = edge.split(',').map(Number);
            if (this.directed.get(edge) !== site) continue;
            const q = this.directed.get(key(b, a));
            if (q === undefined || incircle(points[a], points[b], points[site], points[q]) <= 0) continue;
            this.remove(a, b, site);
            this.remove(b, a, q);
            this.add(a, q, site);
            this.add(q, b, site);
            pending.add(key(a, q));
            pending.add(key(q, b));
            flips++;
        }
        return { site, kind: containing ? 'inside' : 'outside', containing, visible, flips,
            triangles: this.directed.size / 3, hull: this.hullEdges().length };
    }

    walk(point, triangles, numbers) {
        let current = triangles[0].sites;
        const path = [1];
        while (true) {
            const [a, b, c] = current;
            const crossed = [[a, b], [b, c], [c, a]].find(([u, v]) => orient(this.points[u], this.points[v], point) < 0);
            if (!crossed) return { path, triangle: path[path.length - 1], outside: null };
            const [u, v] = crossed;
            const third = this.directed.get(key(v, u));
            if (third === undefined) return { path, triangle: null, outside: [Math.min(u, v), Math.max(u, v)] };
            current = canonical([v, u, third]);
            path.push(numbers.get(current.join(',')));
        }
    }
}

module.exports = { key, canonical, Triangulation };
