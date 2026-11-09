'use strict';

const fs = require('node:fs');
const integerWord = text => /^-?[0-9]+$/.test(text);

function readModel() {
    const lines = fs.readFileSync('input/model.obj', 'ascii').split('\n').slice(0, -1);
    const vertices = [null];
    const polygons = [];
    const errors = [];
    const groups = [];
    const seenGroups = new Set();
    const ignoredKeywords = new Set(['vt', 'vn', 's', 'o', 'usemtl', 'mtllib']);
    let group = 'default';
    let ignored = 0;
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line === '' || line.startsWith('#')) continue;
        const [keyword, ...args] = line.split(' ');
        let error = null;
        if (keyword === 'v') {
            if (args.length !== 3 || !args.every(integerWord)) error = 'bad_vertex';
            else vertices.push(args.map(Number));
        } else if (keyword === 'f') {
            const references = [];
            if (args.length < 3) error = 'short_face';
            else {
                for (const reference of args) {
                    const part = reference.split('/')[0];
                    const value = Number(part);
                    if (!integerWord(part) || value === 0) { error = 'bad_index'; break; }
                    const index = value > 0 ? value : vertices.length + value;
                    if (index < 1 || index >= vertices.length) { error = 'out_of_range'; break; }
                    references.push(index);
                }
            }
            if (error === null) {
                polygons.push({ number: polygons.length + 1, line: i + 1, group, vertices: references });
                if (!seenGroups.has(group)) { seenGroups.add(group); groups.push(group); }
            }
        } else if (keyword === 'g') group = args.length ? args[0] : 'default';
        else if (ignoredKeywords.has(keyword)) ignored++;
        else error = 'unknown_keyword';
        if (error !== null) errors.push({ line: i + 1, kind: error });
    }
    return { vertices, polygons, groups, errors, ignored, lines: lines.length };
}

function writeModel(vertices, faces) {
    const lines = [`# vertices ${vertices.length - 1} faces ${faces.length}`];
    for (let v = 1; v < vertices.length; v++) lines.push('v ' + vertices[v].join(' '));
    let group = null;
    for (const face of faces) {
        if (face.group !== group) { group = face.group; lines.push('g ' + group); }
        lines.push('f ' + face.vertices.join(' '));
    }
    fs.writeFileSync('output/repaired.obj', lines.join('\n') + '\n', 'ascii');
}

module.exports = { integerWord, readModel, writeModel };
