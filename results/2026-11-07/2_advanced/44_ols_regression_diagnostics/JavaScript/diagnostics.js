'use strict';

const { fit } = require('./qr_solver');
const { chiP } = require('./inference');
const sum = values => values.reduce((total, value) => total + value, 0);

function diagnose(model, statistics, parameters) {
    const { n, rank, leverage, weightedResiduals: residuals } = model;
    const { df, sigma } = statistics;
    const rows = [];
    for (let i = 0; i < n; i++) {
        const h = leverage[i];
        const standardized = residuals[i] / (sigma * Math.sqrt(1 - h));
        const studentized = standardized * Math.sqrt((df - 1) / (df - standardized * standardized));
        const cooks = standardized * standardized * h / (rank * (1 - h));
        const dffits = studentized * Math.sqrt(h / (1 - h));
        let flags = '';
        if (h > parameters.LEVERAGE * rank / n) flags += 'H';
        if (Math.abs(studentized) > parameters.STUDENTIZED) flags += 'O';
        if (cooks > parameters.COOK / n) flags += 'C';
        if (Math.abs(dffits) > parameters.DFFITS * Math.sqrt(rank / n)) flags += 'F';
        const deletedSigma = sigma * Math.sqrt((df - standardized * standardized) / (df - 1));
        const dfbetas = model.g[i].map((value, k) => value * residuals[i] / (1 - h) / (deletedSigma * Math.sqrt(model.variance[k])));
        rows.push({ standardized, studentized, cooks, dffits, flags: flags || '-', dfbetas });
    }
    let differences = 0;
    for (let i = 1; i < n; i++) differences += (residuals[i] - residuals[i - 1]) * (residuals[i] - residuals[i - 1]);
    const dw = differences / model.rss;
    const squares = residuals.map(value => value * value);
    const auxiliary = fit(model.matrix.map(row => model.accepted.map(j => row[j])), squares, Array(n).fill(1), parameters.RANK_TOL);
    const meanSquare = sum(squares) / n;
    const squareTss = squares.reduce((total, value) => total + (value - meanSquare) * (value - meanSquare), 0);
    const bp = n * (1 - auxiliary.rss / squareTss);
    const mean = sum(residuals) / n;
    let second = 0;
    let third = 0;
    let fourth = 0;
    for (const residual of residuals) {
        const delta = residual - mean;
        second += delta * delta;
        third += delta * delta * delta;
        fourth += delta * delta * delta * delta;
    }
    second /= n;
    third /= n;
    fourth /= n;
    const skewness = third / (second * Math.sqrt(second));
    const kurtosis = fourth / (second * second);
    const jb = n / 6 * (skewness * skewness + (kurtosis - 3) * (kurtosis - 3) / 4);
    return { rows, dw, bp: { value: bp, df: auxiliary.rank - 1, p: chiP(bp, auxiliary.rank - 1) },
        jb: { value: jb, p: chiP(jb, 2), skewness, kurtosis } };
}

module.exports = { diagnose };
