'use strict';

const { mean } = require('./decomposition');

function difference(values, kind, season) {
    const offset = { none: 0, first: 1, seasonal: season, both: season + 1 }[kind];
    const result = [];
    for (let t = offset; t < values.length; t++) {
        if (kind === 'none') result.push(values[t]);
        else if (kind === 'first') result.push(values[t] - values[t - 1]);
        else if (kind === 'seasonal') result.push(values[t] - values[t - season]);
        else result.push((values[t] - values[t - 1]) - (values[t - season] - values[t - season - 1]));
    }
    return { values: result, offset };
}

function autocorrelation(values, maximumLag) {
    const average = mean(values);
    const differences = values.map(value => value - average);
    let squares = 0;
    for (const value of differences) squares += value * value;
    const variance = squares / values.length;
    const correlations = [1];
    for (let lag = 1; lag <= maximumLag; lag++) {
        let total = 0;
        for (let i = 0; i < values.length - lag; i++) total += differences[i] * differences[i + lag];
        correlations.push(total / values.length / variance);
    }
    return { mean: average, variance, correlations };
}

function durbinLevinson(correlations) {
    const rows = [[]];
    const variances = [1];
    const partial = [0];
    for (let k = 1; k < correlations.length; k++) {
        const previous = rows[k - 1];
        let total = 0;
        for (let j = 1; j < k; j++) total += previous[j - 1] * correlations[k - j];
        const theta = (correlations[k] - total) / variances[k - 1];
        const row = [];
        for (let j = 1; j < k; j++) row.push(previous[j - 1] - theta * previous[k - j - 1]);
        row.push(theta);
        rows.push(row);
        variances.push(variances[k - 1] * (1 - theta * theta));
        partial.push(theta);
    }
    return { rows, variances, partial };
}

function residuals(values, average, coefficients) {
    const result = [];
    for (let i = coefficients.length; i < values.length; i++) {
        let total = 0;
        for (let j = 1; j <= coefficients.length; j++) total += coefficients[j - 1] * (values[i - j] - average);
        result.push(values[i] - average - total);
    }
    return result;
}

function forecast(model, origin, steps, season) {
    const differenced = model.differenced.slice(0, origin - model.offset);
    const appended = [];
    for (let k = 0; k < steps; k++) {
        let total = 0;
        for (let j = 1; j <= model.coefficients.length; j++) total += model.coefficients[j - 1] * (differenced.at(-j) - model.average);
        const value = model.average + total;
        differenced.push(value);
        appended.push(value);
    }
    const original = model.values.slice(0, origin);
    const result = [];
    for (const value of appended) {
        let next = value;
        if (model.difference === 'first') next = value + original.at(-1);
        else if (model.difference === 'seasonal') next = value + original.at(-season);
        else if (model.difference === 'both') next = value + original.at(-1) + original.at(-season) - original.at(-season - 1);
        original.push(next);
        result.push(next);
    }
    return result;
}

function ljungBox(values, lags) {
    const { correlations } = autocorrelation(values, Math.max(...lags));
    return lags.map(lag => {
        let total = 0;
        for (let k = 1; k <= lag; k++) total += correlations[k] * correlations[k] / (values.length - k);
        const q = values.length * (values.length + 2) * total;
        const x = q / 2;
        let term = 1;
        let terms = term;
        for (let i = 1; i <= lag / 2 - 1; i++) { term = term * x / i; terms += term; }
        return { lag, q, p: Math.exp(-x) * terms };
    });
}

module.exports = { difference, autocorrelation, durbinLevinson, residuals, forecast, ljungBox };
