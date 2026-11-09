'use strict';

function scale(values, season) {
    let total = 0;
    for (let t = season; t < values.length; t++) total += Math.abs(values[t] - values[t - season]);
    return total / (values.length - season);
}

function accuracy(actual, forecast, delta) {
    let errors = 0;
    let absolute = 0;
    let squares = 0;
    let percentage = 0;
    let symmetric = 0;
    for (let i = 0; i < actual.length; i++) {
        const error = actual[i] - forecast[i];
        const magnitude = Math.abs(error);
        errors += error;
        absolute += magnitude;
        squares += error * error;
        percentage += magnitude / actual[i];
        symmetric += 2 * magnitude / (Math.abs(actual[i]) + Math.abs(forecast[i]));
    }
    const count = actual.length;
    const mae = absolute / count;
    return { me: errors / count, mae, rmse: Math.sqrt(squares / count), mape: 100 * percentage / count,
        smape: 100 * symmetric / count, mase: mae / delta };
}

function winkler(actual, low, high, coefficient) {
    if (actual < low) return high - low + coefficient * (low - actual);
    if (actual > high) return high - low + coefficient * (actual - high);
    return high - low;
}

function rank(values) {
    return values.map((_, index) => index).sort((a, b) => values[a] - values[b] || a - b);
}

module.exports = { scale, accuracy, winkler, rank };
