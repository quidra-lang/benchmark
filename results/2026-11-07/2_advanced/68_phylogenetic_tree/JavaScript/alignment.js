'use strict';

const fs = require('node:fs');

const BASES = { A: 1, C: 2, G: 4, T: 8, R: 5, Y: 10, S: 6, W: 9,
    K: 12, M: 3, B: 14, D: 13, H: 11, V: 7, N: 15, '-': 15 };
const LETTERS = 'ACGT';

function readFasta(path) {
    const records = [];
    const lines = fs.readFileSync(path, 'ascii').slice(0, -1).split('\n');
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.startsWith('>')) {
            records.push({ name: line.slice(1).split(' ')[0], line: i + 1, sequence: '' });
        } else {
            records[records.length - 1].sequence += line.toUpperCase();
        }
    }
    return records;
}

function encode(taxa) {
    return taxa.map(taxon => Array.from(taxon.sequence, character => BASES[character]));
}

function patterns(taxa, length) {
    const columns = [];
    const distinct = new Map();
    for (let c = 0; c < length; c++) {
        const pattern = taxa.map(taxon => taxon.sequence[c]).join('');
        columns.push(pattern);
        if (!distinct.has(pattern)) distinct.set(pattern, []);
        distinct.get(pattern).push(c);
    }
    return { columns, distinct };
}

function classifyColumns(taxa, length) {
    const columns = [];
    for (let c = 0; c < length; c++) {
        const counts = [0, 0, 0, 0];
        let gapped = false;
        for (const taxon of taxa) {
            const character = taxon.sequence[c];
            const base = LETTERS.indexOf(character);
            if (base >= 0) counts[base]++;
            if (character === '-') gapped = true;
        }
        const kinds = counts.filter(count => count > 0).length;
        columns.push({ counts, kinds, gapped,
            informative: counts.filter(count => count >= 2).length >= 2 });
    }
    return columns;
}

module.exports = { BASES, LETTERS, readFasta, encode, patterns, classifyColumns };
