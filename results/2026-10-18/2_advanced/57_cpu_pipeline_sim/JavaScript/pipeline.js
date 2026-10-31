'use strict';

const hazards = require('./hazards');

function simulate(instructions, variant, mispredictions) {
    const times = [];
    const records = [];
    for (let i = 0; i < instructions.length; i++) {
        const instruction = instructions[i];
        let F = 1;
        let D = 2;
        let X = 3;
        if (i > 0) {
            const previous = times[i - 1];
            F = mispredictions[i - 1]
                ? previous.X + (hazards.idResolved(instructions[i - 1], variant) ? 0 : 1) : previous.D;
            D = Math.max(F + 1, previous.X);
            X = Math.max(D + 1, previous.M);
            const base = previous.X + 1;
            const bounds = [
                {cause: 'control', value: D + 1, producer: null},
                {cause: 'structural', value: previous.M, producer: null},
                {cause: 'load_use', value: base, producer: null},
                {cause: 'raw', value: base, producer: null}
            ];
            for (const source of instruction.sources) {
                if (source.producer === null) continue;
                const ready = hazards.readyCycle(source, instruction, variant, instructions, times);
                X = Math.max(X, ready);
                const bound = bounds[instructions[source.producer].className === 'LOAD' ? 2 : 3];
                if (ready > bound.value) Object.assign(bound, {value: ready, producer: source.producer});
            }
            let current = base;
            for (let cause = 0; cause < bounds.length; cause++) {
                const bound = bounds[cause];
                if (bound.value > current) {
                    records.push({cause: bound.cause, cycles: bound.value - current,
                        responsible: cause < 2 ? i - 1 : i, waiting: i, producer: bound.producer});
                    current = bound.value;
                }
            }
        }
        const M = X + (instruction.className === 'MUL' ? variant.latency : 1);
        times.push({F, D, X, M, W: M + 1});
    }
    const last = instructions.length - 1;
    if (instructions[last].className === 'MUL' && variant.latency >= 2) {
        records.push({cause: 'structural', cycles: variant.latency - 1,
            responsible: last, waiting: null, producer: null});
    }
    return {times, records, cycles: times[last].W};
}

module.exports = {simulate};
