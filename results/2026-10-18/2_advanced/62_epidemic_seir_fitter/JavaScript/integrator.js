'use strict';

const STEP = 0.25;
const HALF_STEP = STEP / 2;
const SIXTH_STEP = STEP / 6;

function rk4(model, state, multiplier) {
    const k1 = model.rate(state, multiplier);
    const k2 = model.rate(state.map((value, i) => value + HALF_STEP * k1[i]), multiplier);
    const k3 = model.rate(state.map((value, i) => value + HALF_STEP * k2[i]), multiplier);
    const k4 = model.rate(state.map((value, i) => value + STEP * k3[i]), multiplier);
    return state.map((value, i) => value + SIXTH_STEP * (((k1[i] + 2 * k2[i]) + 2 * k3[i]) + k4[i]));
}

function simulate(model, multipliers, initial = model.initial) {
    let state = initial.slice();
    const days = [];
    for (const multiplier of multipliers) {
        state = state.slice();
        for (const index of model.inflows) state[index] = 0;
        for (let step = 0; step < 4; step++) state = rk4(model, state, multiplier);
        days.push(state);
    }
    return days;
}

module.exports = {rk4, simulate};
