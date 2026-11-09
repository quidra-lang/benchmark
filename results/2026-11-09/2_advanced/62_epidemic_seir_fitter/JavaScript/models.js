'use strict';

function seird(data, beta, gamma, sigma = data.params.sigma) {
    const {N, fatality, params} = data;
    return {
        initial: [N - params.exposed - params.infectious, params.exposed, params.infectious, 0, 0, 0],
        inflows: [5],
        rate(state, multiplier) {
            const [S, E, I] = state;
            const flow = beta * multiplier * S * I / N;
            return [-flow, flow - sigma * E, sigma * E - gamma * I,
                (1 - fatality) * gamma * I, fatality * gamma * I, sigma * E];
        }
    };
}

function sir(data, beta, gamma) {
    const {N, params} = data;
    return {
        initial: [N - params.exposed - params.infectious, params.exposed + params.infectious, 0, 0],
        inflows: [3],
        rate(state, multiplier) {
            const [S, I] = state;
            const flow = beta * multiplier * S * I / N;
            return [-flow, flow - gamma * I, gamma * I, flow];
        }
    };
}

function ageSeird(data, beta, gamma, matrix) {
    const {groups, N, params} = data;
    const initial = [];
    const inflows = [];
    for (let g = 0; g < groups.length; g++) {
        const exposed = params.exposed * groups[g].population / N;
        const infectious = params.infectious * groups[g].population / N;
        initial.push(groups[g].population - exposed - infectious, exposed, infectious, 0, 0, 0);
        inflows.push(6 * g + 5);
    }
    return {
        initial, inflows,
        rate(state, multiplier) {
            const rates = [];
            for (let g = 0; g < groups.length; g++) {
                let contacts = 0;
                for (let h = 0; h < groups.length; h++) {
                    contacts += matrix[g][h] * state[6 * h + 2] / groups[h].population;
                }
                const lambda = beta * multiplier * contacts;
                const flow = lambda * state[6 * g];
                const E = state[6 * g + 1];
                const I = state[6 * g + 2];
                const fatality = groups[g].fatality;
                rates.push(-flow, flow - params.sigma * E, params.sigma * E - gamma * I,
                    (1 - fatality) * gamma * I, fatality * gamma * I, params.sigma * E);
            }
            return rates;
        }
    };
}

function generation(sigma, gamma) {
    return {
        initial: [1, 0, 0], inflows: [2],
        rate(state) {
            const [E, I] = state;
            return [-sigma * E, sigma * E - gamma * I, gamma * I];
        }
    };
}

module.exports = {seird, sir, ageSeird, generation};
