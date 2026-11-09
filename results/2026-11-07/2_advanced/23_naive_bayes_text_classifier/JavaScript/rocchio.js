'use strict';

function vector(document, idf) {
    const entries = [...document.counts].sort((a, b) => a[0] - b[0])
        .map(([term, count]) => [term, count * idf[term]]);
    let squared = 0;
    for (const [, value] of entries) squared += value * value;
    return { entries, length: Math.sqrt(squared) };
}

function train(documents, encoded, vocabulary, classCount) {
    const idf = vocabulary.terms.map(entry => Math.log(documents.length / entry.df));
    const centroids = Array.from({ length: classCount }, () => Array(idf.length).fill(0));
    for (let i = 0; i < documents.length; i++) {
        const current = vector(encoded[i], idf);
        if (current.length === 0) continue;
        const center = centroids[documents[i].label];
        for (const [term, value] of current.entries) center[term] += value / current.length;
    }
    const lengths = [];
    for (let c = 0; c < classCount; c++) {
        let squared = 0;
        for (let t = 0; t < idf.length; t++) {
            centroids[c][t] /= vocabulary.classCounts[c];
            squared += centroids[c][t] * centroids[c][t];
        }
        lengths.push(Math.sqrt(squared));
    }
    return { idf, centroids, lengths };
}

function predict(model, document) {
    const current = vector(document, model.idf);
    const scores = [];
    for (let c = 0; c < model.centroids.length; c++) {
        let similarity = 0;
        if (current.length > 0 && model.lengths[c] > 0) {
            for (const [term, value] of current.entries) similarity += value * model.centroids[c][term];
            similarity /= current.length * model.lengths[c];
        }
        scores.push(similarity);
    }
    const ranking = scores.map((_, c) => c).sort((a, b) => scores[b] - scores[a] || a - b);
    return { label: ranking[0], ranking, scores, score: scores[ranking[0]] };
}

module.exports = { vector, train, predict };
