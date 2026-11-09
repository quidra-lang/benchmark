'use strict';

const { d2, dot } = require('./predicates');
const { key } = require('./triangulation');

class DisjointSet {
    constructor(size) {
        this.parent = Array.from({ length: size + 1 }, (_, i) => i);
        this.sizes = Array(size + 1).fill(1);
        this.count = size;
    }

    find(site) {
        if (this.parent[site] !== site) this.parent[site] = this.find(this.parent[site]);
        return this.parent[site];
    }

    union(a, b) {
        let first = this.find(a), second = this.find(b);
        if (first === second) return false;
        if (this.sizes[first] < this.sizes[second]) [first, second] = [second, first];
        this.parent[second] = first;
        this.sizes[first] += this.sizes[second];
        this.count--;
        return true;
    }
}

function nearestNeighbors(points, neighbors) {
    return neighbors.map((adjacent, site) => {
        if (site === 0) return null;
        let nearest = adjacent[0];
        for (const other of adjacent) {
            const distance = d2(points[site], points[other]);
            const bestDistance = d2(points[site], points[nearest]);
            if (distance < bestDistance || distance === bestDistance && other < nearest) nearest = other;
        }
        return nearest;
    });
}

function nearestComponents(nearest) {
    const sets = new DisjointSet(nearest.length - 1);
    for (let site = 1; site < nearest.length; site++) sets.union(site, nearest[site]);
    const groups = new Map();
    for (let site = 1; site < nearest.length; site++) {
        const root = sets.find(site);
        if (!groups.has(root)) groups.set(root, []);
        groups.get(root).push(site);
    }
    return [...groups.values()].sort((a, b) => a[0] - b[0]);
}

function minimumTree(edges, size) {
    const sorted = edges.slice().sort((a, b) => a.length2 - b.length2 || a.i - b.i || a.j - b.j);
    const sets = new DisjointSet(size);
    const adopted = [];
    for (const edge of sorted) if (sets.union(edge.i, edge.j)) adopted.push(edge);
    return adopted;
}

function gabriel(edge, mesh, points) {
    const opposites = [mesh.directed.get(key(edge.i, edge.j)), mesh.directed.get(key(edge.j, edge.i))];
    return opposites.every(site => site === undefined || dot(points[site], points[edge.i], points[edge.j]) > 0);
}

function relativeNeighborhood(edge, points) {
    for (let site = 1; site < points.length; site++)
        if (d2(points[edge.i], points[site]) < edge.length2 && d2(points[edge.j], points[site]) < edge.length2) return false;
    return true;
}

function greedyRoute(start, end, neighbors, points) {
    const path = [start];
    let current = start, length = 0;
    while (current !== end) {
        let next = neighbors[current][0];
        for (const other of neighbors[current]) {
            const distance = d2(points[other], points[end]);
            const best = d2(points[next], points[end]);
            if (distance < best || distance === best && other < next) next = other;
        }
        length += Math.sqrt(d2(points[current], points[next]));
        current = next;
        path.push(current);
    }
    return { path, length };
}

function dijkstra(start, neighbors, points) {
    const distances = Array(points.length).fill(Infinity);
    const previous = Array(points.length).fill(null);
    const visited = Array(points.length).fill(false);
    distances[start] = 0;
    for (let step = 1; step < points.length; step++) {
        let current = null;
        for (let site = 1; site < points.length; site++)
            if (!visited[site] && (current === null || distances[site] < distances[current])) current = site;
        visited[current] = true;
        for (const other of neighbors[current]) {
            if (visited[other]) continue;
            const length = distances[current] + Math.sqrt(d2(points[current], points[other]));
            if (length < distances[other]) { distances[other] = length; previous[other] = current; }
        }
    }
    return { distances, previous };
}

module.exports = { DisjointSet, nearestNeighbors, nearestComponents, minimumTree, gabriel, relativeNeighborhood, greedyRoute, dijkstra };
