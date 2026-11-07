'use strict';

const { normal } = require('./measure');

function triangulate(polygons) {
    const triangles = [];
    for (const polygon of polygons) {
        for (let i = 1; i < polygon.vertices.length - 1; i++) triangles.push({ number: triangles.length + 1,
            vertices: [polygon.vertices[0], polygon.vertices[i], polygon.vertices[i + 1]], polygon });
    }
    return triangles;
}

function snap(vertices, spacing) {
    const positions = [null];
    const changed = [];
    for (let original = 1; original < vertices.length; original++) {
        const position = vertices[original].map(value => spacing * Math.floor((2 * value + spacing) / (2 * spacing)));
        positions.push(position);
        if (position.some((value, i) => value !== vertices[original][i])) changed.push({ original, before: vertices[original], after: position });
    }
    return { positions, changed };
}

function representatives(vertices, merge) {
    const numbers = [null];
    const first = new Map();
    const groups = new Map();
    let merged = 0;
    for (let original = 1; original < vertices.length; original++) {
        const key = vertices[original].join(',');
        if (!first.has(key)) first.set(key, original);
        const representative = merge ? first.get(key) : original;
        numbers.push(representative);
        if (!groups.has(representative)) groups.set(representative, []);
        groups.get(representative).push(original);
        if (representative !== original) merged++;
    }
    return { numbers, groups, merged };
}

function removeTriangles(triangles, representatives, positions, settings) {
    const faces = [];
    const removed = [];
    const seen = new Set();
    for (const triangle of triangles) {
        const vertices = triangle.vertices.map(vertex => representatives[vertex]);
        const key = vertices.slice().sort((a, b) => a - b).join(',');
        let reason = null;
        if (new Set(vertices).size < 3) reason = 'repeated';
        else if (settings.degenerate && normal({ vertices }, positions).every(value => value === 0)) reason = 'zero_area';
        else if (settings.duplicates && seen.has(key)) reason = 'duplicate';
        if (reason !== null) removed.push({ triangle, reason });
        else {
            seen.add(key);
            faces.push({ vertices, group: triangle.polygon.group, polygon: triangle.polygon, triangle: triangle.number });
        }
    }
    return { faces, removed };
}

function fillTriangles(loop) {
    const faces = [];
    for (let i = 1; i < loop.vertices.length - 1; i++) faces.push({
        vertices: [loop.vertices[0], loop.vertices[i + 1], loop.vertices[i]], group: 'fill', polygon: null });
    return faces;
}

module.exports = { triangulate, snap, representatives, removeTriangles, fillTriangles };
