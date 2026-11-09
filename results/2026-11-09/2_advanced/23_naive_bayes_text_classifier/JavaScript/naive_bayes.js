'use strict';

function trainingCounts(documents, encoded, classCount, vocabularySize) {
    const classes = Array(classCount).fill(0);
    const occurrences = Array.from({ length: classCount }, () => Array(vocabularySize).fill(0));
    const documentTerms = occurrences.map(row => row.slice());
    const totals = classes.slice();
    for (let i = 0; i < documents.length; i++) {
        const c = documents[i].label;
        classes[c]++;
        for (const term of encoded[i].sequence) { occurrences[c][term]++; totals[c]++; }
        for (const term of encoded[i].first) documentTerms[c][term]++;
    }
    const termTotals = Array(vocabularySize).fill(0);
    const documentTotals = termTotals.slice();
    let total = 0;
    for (let c = 0; c < classCount; c++) {
        total += totals[c];
        for (let t = 0; t < vocabularySize; t++) {
            termTotals[t] += occurrences[c][t];
            documentTotals[t] += documentTerms[c][t];
        }
    }
    return { classes, occurrences, documentTerms, totals, termTotals, documentTotals, total,
        documents: documents.length, vocabularySize };
}

function multinomialModel(occurrences, totals, classCounts, documents, alpha) {
    const size = occurrences[0].length;
    const weights = occurrences.map((row, c) => row.map(count => Math.log((100 * count + alpha) / (100 * totals[c] + alpha * size))));
    const prior = classCounts.map(count => Math.log(count / documents));
    return { kind: 'multinomial', weights, prior };
}

function train(kind, counts, alpha) {
    if (kind === 'multinomial') {
        return multinomialModel(counts.occurrences, counts.totals, counts.classes, counts.documents, alpha);
    }
    const weights = [];
    const baseline = [];
    for (let c = 0; c < counts.classes.length; c++) {
        const row = [];
        let base = 0;
        for (let t = 0; t < counts.vocabularySize; t++) {
            if (kind === 'bernoulli') {
                const p = Math.log((100 * counts.documentTerms[c][t] + alpha) / (100 * counts.classes[c] + 2 * alpha));
                const q = Math.log((100 * (counts.classes[c] - counts.documentTerms[c][t]) + alpha) / (100 * counts.classes[c] + 2 * alpha));
                row.push(p - q);
                base += q;
            } else {
                row.push(Math.log((100 * (counts.termTotals[t] - counts.occurrences[c][t]) + alpha) /
                    (100 * (counts.total - counts.totals[c]) + alpha * counts.vocabularySize)));
            }
        }
        weights.push(row);
        baseline.push(base);
    }
    return { kind, weights, baseline, prior: counts.classes.map(count => Math.log(count / counts.documents)) };
}

function posterior(scores) {
    const ranking = scores.map((_, c) => c).sort((a, b) => scores[b] - scores[a] || a - b);
    const label = ranking[0];
    const exponentials = [];
    let normalizer = 0;
    for (const value of scores) {
        const exponential = Math.exp(value - scores[label]);
        exponentials.push(exponential);
        normalizer += exponential;
    }
    const probabilities = exponentials.map(value => value / normalizer);
    return { label, ranking, scores, probabilities, normalizer, score: probabilities[label],
        margin: scores[label] - scores[ranking[1]] };
}

function predict(model, document) {
    const scores = [];
    for (let c = 0; c < model.prior.length; c++) {
        let score = model.kind === 'bernoulli' ? model.baseline[c] : 0;
        const terms = model.kind === 'bernoulli' ? document.first : document.sequence;
        for (const term of terms) {
            if (model.kind === 'complement') score -= model.weights[c][term];
            else score += model.weights[c][term];
        }
        score += model.prior[c];
        scores.push(score);
    }
    return posterior(scores);
}

module.exports = { trainingCounts, multinomialModel, train, predict, posterior };
