'use strict';

const compareText = (a, b) => a < b ? -1 : a > b ? 1 : 0;

function buildVocabulary(documents, classCount, minimum, limit, kind) {
    const counts = new Map();
    const classCounts = Array(classCount).fill(0);
    for (const document of documents) {
        classCounts[document.label]++;
        for (const term of new Set(document.tokens[kind])) {
            if (!counts.has(term)) counts.set(term, { term, df: 0, perClass: Array(classCount).fill(0) });
            const entry = counts.get(term);
            entry.df++;
            entry.perClass[document.label]++;
        }
    }
    const candidates = [...counts.values()].filter(entry => entry.df >= minimum);
    const size = documents.length;
    for (const entry of candidates) {
        entry.chiSquare = 0;
        entry.bestClass = 0;
        for (let c = 0; c < classCount; c++) {
            const a = entry.perClass[c];
            const b = entry.df - a;
            const absent = classCounts[c] - a;
            const otherAbsent = size - classCounts[c] - b;
            const determinant = a * otherAbsent - b * absent;
            const numerator = size * (determinant * determinant);
            const denominator = entry.df * (size - entry.df) * classCounts[c] * (size - classCounts[c]);
            const value = denominator === 0 ? 0 : numerator / denominator;
            if (value > entry.chiSquare) { entry.chiSquare = value; entry.bestClass = c; }
        }
    }
    candidates.sort((a, b) => b.chiSquare - a.chiSquare || compareText(a.term, b.term));
    const ranking = limit > 0 ? candidates.slice(0, limit) : candidates;
    const terms = ranking.slice().sort((a, b) => compareText(a.term, b.term));
    const indices = new Map(terms.map((entry, index) => [entry.term, index]));
    return { kind, terms, indices, ranking, candidateCount: candidates.length, termCount: counts.size,
        classCounts, documentCount: documents.length };
}

function encode(document, vocabulary) {
    const sequence = [];
    const counts = new Map();
    for (const term of document.tokens[vocabulary.kind]) {
        const index = vocabulary.indices.get(term);
        if (index === undefined) continue;
        sequence.push(index);
        counts.set(index, (counts.get(index) ?? 0) + 1);
    }
    return { sequence, first: [...counts.keys()], counts };
}

module.exports = { compareText, buildVocabulary, encode };
