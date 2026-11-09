'use strict';

function goldenSearch(objective, lower, upper, iterations) {
    const phi = 0.6180339887498949;
    let a = lower;
    let b = upper;
    let c = b - phi * (b - a);
    let d = a + phi * (b - a);
    let fc = objective(c);
    let fd = objective(d);
    const records = [{a, b, c, d, fc, fd}];
    for (let i = 0; i < iterations; i++) {
        if (fc < fd) {
            b = d;
            d = c;
            fd = fc;
            c = b - phi * (b - a);
            fc = objective(c);
        } else {
            a = c;
            c = d;
            fc = fd;
            d = a + phi * (b - a);
            fd = objective(d);
        }
        records.push({a, b, c, d, fc, fd});
    }
    return fc < fd ? {point: c, value: fc, records} : {point: d, value: fd, records};
}

const vertexOrder = (left, right) => left.value - right.value || left.number - right.number;

function nelderMead(objective, beta, gamma, settings) {
    let nextNumber = 0;
    const evaluate = point => ({point, value: objective(point[0], point[1])});
    const number = candidate => ({...candidate, number: nextNumber++});
    const move = (origin, target, factor) => origin.map((value, i) => value + factor * (target[i] - value));
    const initial = [[beta, gamma], [beta + settings.deltaBeta, gamma], [beta, gamma + settings.deltaGamma]]
        .map(point => number(evaluate(point)));
    let vertices = initial.slice();
    const records = [];
    for (let iteration = 1; iteration <= settings.iterations; iteration++) {
        vertices.sort(vertexOrder);
        const [first, second, third] = vertices;
        const center = first.point.map((value, i) => (value + second.point[i]) / 2);
        const reflected = evaluate(center.map((value, i) => value + settings.alpha * (value - third.point[i])));
        let accepted = null;
        let operation = 'shrink';
        if (reflected.value < first.value) {
            const expanded = evaluate(move(center, reflected.point, settings.chi));
            accepted = expanded.value < reflected.value ? expanded : reflected;
            operation = expanded.value < reflected.value ? 'expand' : 'reflect';
        } else if (reflected.value < second.value) {
            accepted = reflected;
            operation = 'reflect';
        } else if (reflected.value < third.value) {
            const contracted = evaluate(move(center, reflected.point, settings.psi));
            if (contracted.value <= reflected.value) {
                accepted = contracted;
                operation = 'contract_out';
            }
        } else {
            const contracted = evaluate(move(center, third.point, settings.psi));
            if (contracted.value < third.value) {
                accepted = contracted;
                operation = 'contract_in';
            }
        }
        if (accepted !== null) vertices = [first, second, number(accepted)];
        else {
            const smallerSecond = number(evaluate(move(first.point, second.point, settings.omega)));
            const smallerThird = number(evaluate(move(first.point, third.point, settings.omega)));
            vertices = [first, smallerSecond, smallerThird];
        }
        vertices.sort(vertexOrder);
        records.push({iteration, operation, best: vertices[0]});
    }
    return {initial, records, vertices};
}

module.exports = {goldenSearch, nelderMead};
