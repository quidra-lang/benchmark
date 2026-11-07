'use strict';

const { mean } = require('./decomposition');

function smooth(name, values, season, parameters) {
    const { alpha, beta, gamma, phi = 1 } = parameters;
    const winters = name === 'hw_add' || name === 'hw_mult';
    let level = winters ? mean(values.slice(0, season)) : values[0];
    let slope = name === 'ses' ? 0 : winters ? (mean(values.slice(season, 2 * season)) - level) / season
        : (values[season] - values[0]) / season;
    const seasonal = winters ? values.slice(0, season).map(value => name === 'hw_add' ? value - level : value / level) : [];
    const snapshot = () => ({ level, slope, seasonal: seasonal.slice() });
    const states = [snapshot()];
    const residuals = [];
    for (let t = 0; t < values.length; t++) {
        const value = values[t];
        let nextLevel;
        let nextSlope = slope;
        if (name === 'ses') {
            residuals.push(value - level);
            nextLevel = alpha * value + (1 - alpha) * level;
        } else if (!winters) {
            const forecast = level + phi * slope;
            residuals.push(value - forecast);
            nextLevel = alpha * value + (1 - alpha) * forecast;
            nextSlope = beta * (nextLevel - level) + (1 - beta) * phi * slope;
        } else {
            const j = t % season;
            const u = level + slope;
            const q = seasonal[j];
            if (name === 'hw_add') {
                residuals.push(value - (u + q));
                nextLevel = alpha * (value - q) + (1 - alpha) * u;
                seasonal[j] = gamma * (value - u) + (1 - gamma) * q;
            } else {
                residuals.push(value - u * q);
                nextLevel = alpha * (value / q) + (1 - alpha) * u;
                seasonal[j] = gamma * (value / u) + (1 - gamma) * q;
            }
            nextSlope = beta * (nextLevel - level) + (1 - beta) * slope;
        }
        level = nextLevel;
        slope = nextSlope;
        states.push(snapshot());
    }
    return { states, residuals };
}

function forecast(name, state, origin, steps, season, parameters) {
    const values = [];
    const phi = parameters.phi ?? 1;
    let power = phi;
    let cumulative = power;
    for (let k = 1; k <= steps; k++) {
        if (name === 'ses') values.push(state.level);
        else if (name === 'holt' || name === 'damped') {
            if (k > 1) { power *= phi; cumulative += power; }
            values.push(state.level + cumulative * state.slope);
        } else {
            const seasonal = state.seasonal[(origin + k - 1) % season];
            values.push(name === 'hw_add' ? state.level + k * state.slope + seasonal
                : (state.level + k * state.slope) * seasonal);
        }
    }
    return values;
}

module.exports = { smooth, forecast };
