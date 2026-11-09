'use strict';

function flow(model, field, p, start, end) {
    let total = 0;
    let first = true;
    for (let direction = start; direction < end; direction++) {
        const face = model.faces[p][direction];
        if (face.q < 0 && face.theta === null) continue;
        const outside = face.q >= 0 ? field[face.q] : face.theta;
        const term = face.g * (outside - field[p]);
        total = first ? term : total + term;
        first = false;
    }
    return total;
}

function hx(model, field, p) {
    return flow(model, field, p, 0, 2);
}

function hy(model, field, p) {
    return flow(model, field, p, 2, 4);
}

function totalFlow(model, field, p) {
    return flow(model, field, p, 0, 4);
}

function thomas(lower, diagonal, upper, rhs) {
    const size = diagonal.length;
    const upperPrime = [upper[0] / diagonal[0]];
    const rhsPrime = [rhs[0] / diagonal[0]];
    for (let i = 1; i < size; i++) {
        const divisor = diagonal[i] - lower[i] * upperPrime[i - 1];
        upperPrime.push(upper[i] / divisor);
        rhsPrime.push((rhs[i] - lower[i] * rhsPrime[i - 1]) / divisor);
    }
    const answer = new Array(size);
    answer[size - 1] = rhsPrime[size - 1];
    for (let i = size - 2; i >= 0; i--) {
        answer[i] = rhsPrime[i] - upperPrime[i] * answer[i + 1];
    }
    return answer;
}

function sweep(model, tau, rhs, horizontal) {
    const lines = horizontal ? model.height : model.width;
    const size = horizontal ? model.width : model.height;
    const direction = horizontal ? 0 : 2;
    const field = new Array(model.count);
    for (let line = 0; line < lines; line++) {
        const cells = [];
        const lower = [], diagonal = [], upper = [], adjusted = [];
        for (let i = 0; i < size; i++) {
            const p = horizontal ? line * model.width + i : i * model.width + line;
            cells.push(p);
            const before = model.faces[p][direction];
            const after = model.faces[p][direction + 1];
            lower.push(before.q >= 0 ? -before.g : 0);
            diagonal.push(model.capacities[p] / tau + before.g + after.g);
            upper.push(after.q >= 0 ? -after.g : 0);
            let value = rhs[p];
            if (before.theta !== null) value += before.g * before.theta;
            if (after.theta !== null) value += after.g * after.theta;
            adjusted.push(value);
        }
        const answer = thomas(lower, diagonal, upper, adjusted);
        for (let i = 0; i < size; i++) field[cells[i]] = answer[i];
    }
    return field;
}

function horizontalSweep(model, tau, rhs) {
    return sweep(model, tau, rhs, true);
}

function verticalSweep(model, tau, rhs) {
    return sweep(model, tau, rhs, false);
}

function ftcs(model, old, source, dt) {
    const field = new Array(model.count);
    for (let p = 0; p < model.count; p++) {
        field[p] = old[p] + dt * (totalFlow(model, old, p) + source[p]) / model.capacities[p];
    }
    return { field, intermediate: null };
}

function backwardEuler(model, old, source, dt) {
    const oldVertical = new Array(model.count);
    const rhs = new Array(model.count);
    for (let p = 0; p < model.count; p++) {
        oldVertical[p] = hy(model, old, p);
        rhs[p] = model.capacities[p] / dt * old[p] + oldVertical[p] + source[p];
    }
    const intermediate = horizontalSweep(model, dt, rhs);
    for (let p = 0; p < model.count; p++) {
        rhs[p] = model.capacities[p] / dt * intermediate[p] - oldVertical[p];
    }
    return { field: verticalSweep(model, dt, rhs), intermediate };
}

function crankNicolson(model, old, source, dt) {
    const tau = dt / 2;
    const rhs = new Array(model.count);
    for (let p = 0; p < model.count; p++) {
        rhs[p] = model.capacities[p] / tau * old[p] + hy(model, old, p) + source[p];
    }
    const intermediate = horizontalSweep(model, tau, rhs);
    for (let p = 0; p < model.count; p++) {
        rhs[p] = model.capacities[p] / tau * intermediate[p]
            + hx(model, intermediate, p) + source[p];
    }
    return { field: verticalSweep(model, tau, rhs), intermediate };
}

module.exports = {
    hx, hy, totalFlow, thomas, horizontalSweep, verticalSweep,
    ftcs, backwardEuler, crankNicolson,
};
