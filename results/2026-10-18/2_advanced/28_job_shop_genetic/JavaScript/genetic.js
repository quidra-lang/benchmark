'use strict';

function decode(instance, chromosome) {
    const next = instance.jobs.map(() => 0);
    const ready = instance.jobs.map(() => 0);
    const free = instance.machines.map(() => 0);
    const starts = Array(instance.operations.length);
    const ends = Array(instance.operations.length);
    const order = instance.machines.map(() => []);
    let makespan = 0;
    for (const number of chromosome) {
        const job = instance.byNumber.get(number);
        const operation = instance.operations[job.operations[next[job.index]++]];
        const start = Math.max(ready[job.index], free[operation.machine]);
        const end = start + operation.duration;
        starts[operation.index] = start;
        ends[operation.index] = end;
        order[operation.machine].push(operation.index);
        ready[job.index] = end;
        free[operation.machine] = end;
        makespan = Math.max(makespan, end);
    }
    return { starts, ends, order, makespan };
}

function tournament(evaluations, size, rng) {
    let best = null;
    for (let i = 0; i < size; i++) {
        const candidate = rng.below(evaluations.length);
        if (best === null || evaluations[candidate] < evaluations[best]
            || (evaluations[candidate] === evaluations[best] && candidate < best)) best = candidate;
    }
    return best;
}

function crossover(first, second, jobs, rng) {
    const selected = new Set();
    for (const job of jobs) if (rng.below(2) === 0) selected.add(job.number);
    function child(fixed, filling) {
        const remaining = filling.filter(gene => !selected.has(gene));
        let position = 0;
        return fixed.map(gene => selected.has(gene) ? gene : remaining[position++]);
    }
    return [child(first, second), child(second, first)];
}

function swapMutation(chromosome, rng) {
    const first = rng.below(chromosome.length);
    const second = rng.below(chromosome.length);
    [chromosome[first], chromosome[second]] = [chromosome[second], chromosome[first]];
}

function insertionMutation(chromosome, rng) {
    const first = rng.below(chromosome.length);
    const second = rng.below(chromosome.length);
    const [gene] = chromosome.splice(first, 1);
    chromosome.splice(second, 0, gene);
}

module.exports = { decode, tournament, crossover, swapMutation, insertionMutation };
