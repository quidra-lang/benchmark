'use strict';

const difference = (a, b) => a.map((value, i) => value - b[i]);
const add = (a, b) => a.map((value, i) => value + b[i]);
const dot = (a, b) => (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) || 0;
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]].map(value => value || 0);

function normal(face, vertices) {
    const [a, b, c] = face.vertices.map(vertex => vertices[vertex]);
    return cross(difference(b, a), difference(c, a));
}

function determinant(face, vertices) {
    const [a, b, c] = face.vertices.map(vertex => vertices[vertex]);
    return dot(a, cross(b, c));
}

function angle(face, vertices) {
    const [a, b, c] = face.vertices.map(vertex => vertices[vertex]);
    const minimum = Math.min(dot(difference(b, a), difference(c, a)),
        dot(difference(c, b), difference(a, b)), dot(difference(a, c), difference(b, c)));
    return minimum < 0 ? 'obtuse' : minimum === 0 ? 'right' : 'acute';
}

function faceGeometry(face, vertices) {
    const n = normal(face, vertices);
    return { normal: n, q: dot(n, n), determinant: determinant(face, vertices), angle: angle(face, vertices) };
}

function area(geometry) {
    let total = 0;
    for (const face of geometry) total += Math.sqrt(face.q);
    return total / 2;
}

function volume6(faces, vertices, indices) {
    let total = 0;
    for (const index of indices) total += determinant(faces[index], vertices);
    return total;
}

function fraction(numerator, denominator) {
    if (numerator === 0) return '0';
    if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
    let a = Math.abs(numerator);
    let b = denominator;
    while (b !== 0) [a, b] = [b, a % b];
    numerator /= a;
    denominator /= a;
    return denominator === 1 ? String(numerator) : numerator + '/' + denominator;
}

function centroid(faces, vertices, indices, geometry, volume) {
    const totals = [0, 0, 0];
    for (const index of indices) {
        const [a, b, c] = faces[index].vertices.map(vertex => vertices[vertex]);
        for (let k = 0; k < 3; k++) totals[k] += geometry[index].determinant * (a[k] + b[k] + c[k]);
    }
    return totals.map(total => fraction(total, 4 * volume));
}

function solidAngle(face, vertices, point) {
    const [a, b, c] = face.vertices.map(vertex => difference(vertices[vertex], point));
    const la = Math.sqrt(dot(a, a));
    const lb = Math.sqrt(dot(b, b));
    const lc = Math.sqrt(dot(c, c));
    const denominator = la * lb * lc + dot(a, b) * lc + dot(b, c) * la + dot(c, a) * lb;
    return 2 * Math.atan2(dot(a, cross(b, c)), denominator);
}

function winding(faces, vertices, indices, point) {
    let total = 0;
    for (const index of indices) total += solidAngle(faces[index], vertices, point);
    return Math.round(total / (4 * Math.PI)) || 0;
}

const real = value => value.toFixed(3);

module.exports = { difference, add, dot, cross, normal, determinant, angle, faceGeometry, area, volume6, fraction, centroid, solidAngle, winding, real };
