'use strict';

const fs = require('node:fs');
const { readInstance } = require('./instance');
const { Minstd } = require('./minstd');
const { dispatch } = require('./dispatch_rules');
const genetic = require('./genetic');
const { gantt } = require('./gantt');
const RULES = ['SPT', 'LPT', 'MWKR', 'FIFO'];
const copyOrder = order => order.map(sequence => sequence.slice());

function readParameters() {
    const rows = new Map(fs.readFileSync('input/ga_params.txt', 'ascii').split('\n').slice(0, -1).map(line => {
        const [name, ...values] = line.split(' ');
        return [name, values];
    }));
    const integer = name => Number(rows.get(name)[0]);
    const fraction = name => rows.get(name)[0].split('/').map(Number);
    return { seed: integer('seed'), population: integer('population'), generations: integer('generations'),
        tournament: integer('tournament'), crossover: fraction('crossover'), swap: fraction('swap_mutation'),
        insert: fraction('insert_mutation'), elitism: integer('elitism'), checkpoints: new Set(rows.get('checkpoints').map(Number)),
        tabuIterations: integer('tabu_iterations'), tenure: integer('tabu_tenure'), width: integer('gantt_width') };
}

function percentage(numerator, denominator) {
    const value = Math.floor((2000 * numerator + denominator) / (2 * denominator));
    return `${Math.floor(value / 10)}.${value % 10}%`;
}

function fraction(numerator, denominator) {
    let a = numerator;
    let b = denominator;
    while (b !== 0) [a, b] = [b, a % b];
    return `${numerator / a}/${denominator / a}`;
}

function jacksonBound(instance, machine) {
    const tasks = machine.operations.map(index => ({ ...instance.operations[index], remaining: instance.operations[index].duration }));
    let pending = tasks.length;
    let time = 0;
    let bound = 0;
    while (pending > 0) {
        let available = tasks.filter(task => task.head <= time && task.remaining > 0);
        if (available.length === 0) {
            time = Math.min(...tasks.filter(task => task.head > time).map(task => task.head));
            available = tasks.filter(task => task.head <= time && task.remaining > 0);
        }
        let chosen = available[0];
        for (const task of available) if (task.tail > chosen.tail || (task.tail === chosen.tail && task.job < chosen.job)) chosen = task;
        const future = tasks.filter(task => task.head > time);
        const elapsed = future.length === 0 ? chosen.remaining : Math.min(chosen.remaining, Math.min(...future.map(task => task.head)) - time);
        time += elapsed;
        chosen.remaining -= elapsed;
        if (chosen.remaining === 0) { bound = Math.max(bound, time + chosen.tail); pending--; }
    }
    return bound;
}

function lowerBounds(instance) {
    let job = instance.jobs[0];
    for (const candidate of instance.jobs) if (candidate.work > job.work) job = candidate;
    let machine = instance.machines[0];
    let jackson = instance.machines[0];
    for (const candidate of instance.machines) {
        candidate.jackson = jacksonBound(instance, candidate);
        if (candidate.bound > machine.bound) machine = candidate;
        if (candidate.jackson > jackson.jackson) jackson = candidate;
    }
    return { job, machine, jackson, lower: Math.max(job.work, machine.bound, jackson.jackson) };
}

function scheduleOrder(instance, order, durations = instance.operations.map(operation => operation.duration)) {
    const count = instance.operations.length;
    const machinePrevious = Array(count).fill(-1);
    const machineNext = Array(count).fill(-1);
    for (const sequence of order) {
        for (let i = 1; i < sequence.length; i++) {
            machinePrevious[sequence[i]] = sequence[i - 1];
            machineNext[sequence[i - 1]] = sequence[i];
        }
    }
    const remaining = instance.operations.map(operation => Number(operation.predecessor >= 0) + Number(machinePrevious[operation.index] >= 0));
    const ready = instance.operations.filter(operation => remaining[operation.index] === 0).map(operation => operation.index);
    const starts = Array(count);
    const ends = Array(count);
    let makespan = 0;
    for (let head = 0; head < ready.length; head++) {
        const index = ready[head];
        const operation = instance.operations[index];
        const jobEnd = operation.predecessor < 0 ? 0 : ends[operation.predecessor];
        const machineEnd = machinePrevious[index] < 0 ? 0 : ends[machinePrevious[index]];
        starts[index] = Math.max(jobEnd, machineEnd);
        ends[index] = starts[index] + durations[index];
        makespan = Math.max(makespan, ends[index]);
        for (const successor of [operation.successor, machineNext[index]]) {
            if (successor >= 0 && --remaining[successor] === 0) ready.push(successor);
        }
    }
    return { order, starts, ends, makespan, machinePrevious, machineNext, durations };
}

function operationOrder(instance, schedule) {
    return instance.operations.map(operation => operation.index).sort((a, b) =>
        schedule.starts[a] - schedule.starts[b] || instance.operations[a].job - instance.operations[b].job);
}

function chromosomeOf(instance, schedule) {
    return operationOrder(instance, schedule).map(index => instance.operations[index].job);
}

function criticalAnalysis(instance, schedule) {
    const path = [];
    let current = instance.operations.find(operation => schedule.ends[operation.index] === schedule.makespan).index;
    for (;;) {
        path.push(current);
        if (schedule.starts[current] === 0) break;
        const previous = schedule.machinePrevious[current];
        current = previous >= 0 && schedule.ends[previous] === schedule.starts[current] ? previous : instance.operations[current].predecessor;
    }
    path.reverse();
    const blocks = [];
    const perMachine = instance.machines.map(() => 0);
    for (const index of path) {
        const machine = instance.operations[index].machine;
        if (blocks.length === 0 || blocks.at(-1).machine !== machine) blocks.push({ machine, operations: [] });
        blocks.at(-1).operations.push(index);
        perMachine[machine]++;
    }
    const counts = instance.operations.map(() => 0);
    let paths = 0;
    for (const index of operationOrder(instance, schedule)) {
        if (schedule.starts[index] === 0) counts[index] = 1;
        else {
            for (const previous of [instance.operations[index].predecessor, schedule.machinePrevious[index]]) {
                if (previous >= 0 && schedule.ends[previous] === schedule.starts[index]) counts[index] += counts[previous];
            }
        }
        if (schedule.ends[index] === schedule.makespan) paths += counts[index];
    }
    let bottleneck = 0;
    for (let machine = 1; machine < perMachine.length; machine++) if (perMachine[machine] > perMachine[bottleneck]) bottleneck = machine;
    return { path, blocks, paths, perMachine, bottleneck };
}

function neighbours(instance, schedule, analysis = criticalAnalysis(instance, schedule)) {
    const moves = [];
    for (const block of analysis.blocks) {
        for (let i = 1; i < block.operations.length; i++) {
            const u = block.operations[i - 1];
            const v = block.operations[i];
            const order = copyOrder(schedule.order);
            const position = order[block.machine].indexOf(u);
            [order[block.machine][position], order[block.machine][position + 1]] = [v, u];
            const changed = scheduleOrder(instance, order);
            moves.push({ u, v, machine: block.machine, schedule: changed, value: changed.makespan });
        }
    }
    return moves;
}

function tabuSearch(instance, startingOrder, parameters) {
    let current = scheduleOrder(instance, copyOrder(startingOrder));
    let best = current;
    let found = 0;
    let reason = 'limit';
    const expiries = new Map();
    const records = [];
    for (let iteration = 1; iteration <= parameters.tabuIterations; iteration++) {
        const moves = neighbours(instance, current);
        if (moves.length === 0) { reason = 'no_moves'; break; }
        let chosen = null;
        let tabu = 0;
        for (const move of moves) {
            move.tabu = (expiries.get(move.u + ',' + move.v) ?? 0) >= iteration;
            if (move.tabu) tabu++;
            if (move.tabu && move.value >= best.makespan) continue;
            if (chosen === null || move.value < chosen.value) chosen = move;
        }
        if (chosen === null) { reason = 'all_tabu'; break; }
        current = chosen.schedule;
        expiries.set(chosen.v + ',' + chosen.u, iteration + parameters.tenure);
        if (chosen.value < best.makespan) { best = current; found = iteration; }
        records.push({ iteration, moves: moves.length, tabu, chosen, best: best.makespan });
    }
    return { best, found, reason, records };
}

function leftShifts(instance, schedule) {
    const shifts = [];
    for (let machine = 0; machine < schedule.order.length; machine++) {
        const sequence = schedule.order[machine];
        for (let i = 1; i < sequence.length; i++) {
            const index = sequence[i];
            const operation = instance.operations[index];
            const ready = operation.predecessor < 0 ? 0 : schedule.ends[operation.predecessor];
            for (let position = 0; position < i; position++) {
                const start = Math.max(position === 0 ? 0 : schedule.ends[sequence[position - 1]], ready);
                const end = schedule.starts[sequence[position]];
                if (start + operation.duration <= end) {
                    shifts.push({ index, machine, oldPosition: i, position, oldStart: schedule.starts[index], newStart: start });
                    break;
                }
            }
        }
    }
    return shifts;
}

function activate(instance, startingOrder) {
    let schedule = scheduleOrder(instance, copyOrder(startingOrder));
    const records = [];
    for (;;) {
        const choices = leftShifts(instance, schedule);
        if (choices.length === 0) break;
        choices.sort((a, b) => a.oldStart - b.oldStart || instance.operations[a.index].job - instance.operations[b.index].job);
        const chosen = choices[0];
        const order = copyOrder(schedule.order);
        order[chosen.machine].splice(chosen.oldPosition, 1);
        order[chosen.machine].splice(chosen.position, 0, chosen.index);
        records.push(chosen);
        schedule = scheduleOrder(instance, order);
    }
    return { schedule, records };
}

function slacks(instance, schedule) {
    const latest = Array(instance.operations.length);
    const slack = Array(instance.operations.length);
    const free = Array(instance.operations.length);
    for (const index of operationOrder(instance, schedule).reverse()) {
        const successors = [instance.operations[index].successor, schedule.machineNext[index]].filter(value => value >= 0);
        const limit = successors.length ? Math.min(...successors.map(value => latest[value])) : schedule.makespan;
        const nextStart = successors.length ? Math.min(...successors.map(value => schedule.starts[value])) : schedule.makespan;
        latest[index] = limit - instance.operations[index].duration;
        slack[index] = latest[index] - schedule.starts[index];
        free[index] = nextStart - schedule.ends[index];
    }
    return { slack, free, critical: slack.filter(value => value === 0).length };
}

function distance(first, second) {
    return first.order.map((sequence, machine) => {
        const positions = new Map(second.order[machine].map((index, position) => [index, position]));
        let inversions = 0;
        for (let i = 0; i < sequence.length; i++) {
            for (let j = i + 1; j < sequence.length; j++) if (positions.get(sequence[i]) > positions.get(sequence[j])) inversions++;
        }
        return inversions;
    });
}

function runGenetic(instance, baselines, parameters) {
    const rng = new Minstd(parameters.seed);
    const basic = instance.jobs.flatMap(job => job.operations.map(() => job.number));
    let population = baselines.map(baseline => chromosomeOf(instance, baseline.schedule));
    while (population.length < parameters.population) population.push(rng.shuffle(basic.slice()));
    const counts = { crossovers: 0, swaps: 0, inserts: 0 };
    const records = [];
    const progress = ['generation,best,mean,worst,distinct'];
    let previousBest = null;
    let decoded;
    let evaluations;
    let ranking;
    for (let generation = 0; generation <= parameters.generations; generation++) {
        decoded = population.map(chromosome => genetic.decode(instance, chromosome));
        evaluations = decoded.map(schedule => schedule.makespan);
        ranking = population.map((_, index) => index).sort((a, b) => evaluations[a] - evaluations[b] || a - b);
        const best = ranking[0];
        if (generation === 0 || evaluations[best] < previousBest) records.push({ generation, value: evaluations[best], individual: best + 1 });
        previousBest = evaluations[best];
        if (parameters.checkpoints.has(generation)) {
            const total = evaluations.reduce((sum, value) => sum + value, 0);
            const distinct = new Set(population.map(chromosome => chromosome.join(','))).size;
            progress.push(`${generation},${evaluations[best]},${fraction(total, parameters.population)},${evaluations[ranking.at(-1)]},${distinct}`);
        }
        if (generation === parameters.generations) break;
        const next = ranking.slice(0, parameters.elitism).map(index => population[index].slice());
        while (next.length < parameters.population) {
            const first = genetic.tournament(evaluations, parameters.tournament, rng);
            const second = genetic.tournament(evaluations, parameters.tournament, rng);
            let children;
            if (rng.chance(parameters.crossover)) {
                counts.crossovers++;
                children = genetic.crossover(population[first], population[second], instance.jobs, rng);
            } else children = [population[first].slice(), population[second].slice()];
            for (const child of children) {
                if (rng.chance(parameters.swap)) { counts.swaps++; genetic.swapMutation(child, rng); }
                if (rng.chance(parameters.insert)) { counts.inserts++; genetic.insertionMutation(child, rng); }
            }
            next.push(...children);
        }
        population = next;
    }
    const bestIndex = ranking[0];
    const best = scheduleOrder(instance, decoded[bestIndex].order);
    const top = [];
    const seen = new Set();
    for (const index of ranking) {
        const key = population[index].join(',');
        if (seen.has(key)) continue;
        seen.add(key);
        top.push({ individual: index + 1, value: evaluations[index], distance: distance(decoded[index], best).reduce((a, b) => a + b, 0) });
        if (top.length === 5) break;
    }
    return { best, chromosome: population[bestIndex], records, progress, top, counts };
}

function statistics(instance, schedule) {
    let flow = 0;
    for (const job of instance.jobs) flow += schedule.ends[job.operations.at(-1)];
    const machines = instance.machines.map((machine, index) => {
        const sequence = schedule.order[index];
        const intervals = [];
        let gaps = 0;
        let longest = 0;
        if (schedule.starts[sequence[0]] > 0) intervals.push([0, schedule.starts[sequence[0]]]);
        for (let i = 1; i < sequence.length; i++) {
            const start = schedule.ends[sequence[i - 1]];
            const end = schedule.starts[sequence[i]];
            if (end > start) { intervals.push([start, end]); gaps++; longest = Math.max(longest, end - start); }
        }
        const finish = schedule.ends[sequence.at(-1)];
        if (finish < schedule.makespan) intervals.push([finish, schedule.makespan]);
        return { idle: schedule.makespan - machine.load, intervals, gaps, longest };
    });
    return { flow, waiting: flow - instance.work, idle: instance.machineCount * schedule.makespan - instance.work, machines };
}

function baselineLines(instance, bounds, baselines) {
    const lines = [`INSTANCE jobs ${instance.jobs.length} machines ${instance.machineCount} operations ${instance.operations.length}`
        + ` work ${instance.work} errors ${instance.errors.length}`];
    for (const error of instance.errors) lines.push('ERROR ' + error);
    for (const job of instance.jobs) {
        lines.push(`JOB J${job.number} operations ${job.operations.length} work ${job.work} route `
            + job.operations.map(index => 'M' + (instance.operations[index].machine + 1)).join(' '));
    }
    for (const machine of instance.machines) {
        lines.push(`MACHINE M${machine.number} operations ${machine.operations.length} load ${machine.load} head ${machine.head}`
            + ` tail ${machine.tail} bound ${machine.bound} jackson ${machine.jackson}`);
    }
    lines.push(`BOUND job ${bounds.job.work} J${bounds.job.number}`, `BOUND machine ${bounds.machine.bound} M${bounds.machine.number}`,
        `BOUND jackson ${bounds.jackson.jackson} M${bounds.jackson.number}`, `BOUND lower ${bounds.lower}`);
    let best = baselines[0];
    for (const baseline of baselines) {
        const { rule, schedule, analysis, search, dispatched } = baseline;
        const stats = statistics(instance, schedule);
        lines.push(`RULE ${rule} makespan ${schedule.makespan} gap ${percentage(schedule.makespan - bounds.lower, bounds.lower)}`
            + ` flow ${stats.flow} idle ${stats.idle} decisions ${dispatched.decisions} ties ${dispatched.ties}`,
        `PATH ${rule} operations ${analysis.path.length} blocks ${analysis.blocks.length} critical_paths ${analysis.paths} bottleneck M${analysis.bottleneck + 1}`,
        `TABU ${rule} makespan ${schedule.makespan} -> ${search.best.makespan} found ${search.found} iterations ${search.records.length} stop ${search.reason}`);
        if (schedule.makespan < best.schedule.makespan) best = baseline;
    }
    lines.push(`BEST ${best.rule} makespan ${best.schedule.makespan}`);
    for (const machine of instance.machines) {
        lines.push(`UTILIZATION M${machine.number} ` + baselines.map(baseline =>
            baseline.rule + ' ' + percentage(machine.load, baseline.schedule.makespan)).join(' '));
    }
    return lines;
}

function bestScheduleLines(instance, bounds, baselines, ga, activeDecode, activated, final, analysis, parameters) {
    const lines = [`GA best ${ga.best.makespan} generation ${ga.records.at(-1).generation} crossovers ${ga.counts.crossovers}`
        + ` swaps ${ga.counts.swaps} inserts ${ga.counts.inserts}`];
    for (const record of ga.records) lines.push(`RECORD generation ${record.generation} makespan ${record.value} individual ${record.individual}`);
    for (let i = 0; i < ga.top.length; i++) {
        const individual = ga.top[i];
        lines.push(`TOP ${i + 1} individual ${individual.individual} makespan ${individual.value} distance ${individual.distance}`);
    }
    lines.push('GA_CHROMOSOME ' + ga.chromosome.join(' '), `ACTIVE_DECODE makespan ${activeDecode.makespan} decisions ${activeDecode.decisions}`);
    for (let i = 0; i < activated.records.length; i++) {
        const shift = activated.records[i];
        lines.push(`SHIFT ${i + 1} ${instance.operations[shift.index].notation} M${shift.machine + 1} start ${shift.oldStart} -> ${shift.newStart}`);
    }
    lines.push(`ACTIVATED makespan ${ga.best.makespan} -> ${activated.schedule.makespan} shifts ${activated.records.length}`,
        `SCHEDULE makespan ${final.makespan} lower_bound ${bounds.lower} gap ${percentage(final.makespan - bounds.lower, bounds.lower)}`
            + ` improvement ${ga.best.makespan - final.makespan} shiftable ${leftShifts(instance, final).length}`,
        'CHROMOSOME ' + chromosomeOf(instance, final).join(' '), 'LEGEND ' + instance.jobs.map(job => `${job.letter}=J${job.number}`).join(' '));
    const chart = gantt(instance, final, analysis.path, parameters.width);
    lines.push(`GANTT scale ${chart.scale} columns ${chart.columns}`, ...chart.lines);
    const sequenceLetters = sequence => sequence.map(index => instance.byNumber.get(instance.operations[index].job).letter).join('');
    for (let machine = 0; machine < instance.machineCount; machine++) {
        lines.push(`ORDER M${machine + 1} FINAL ${sequenceLetters(final.order[machine])} ` + baselines.map(baseline =>
            baseline.rule + ' ' + sequenceLetters(baseline.schedule.order[machine])).join(' '));
    }
    const stats = statistics(instance, final);
    for (let machine = 0; machine < instance.machineCount; machine++) {
        const values = stats.machines[machine];
        const load = instance.machines[machine].load;
        const sequence = final.order[machine].map(index => `J${instance.operations[index].job}:${final.starts[index]}-${final.ends[index]}`).join(' ');
        lines.push(`MACHINE M${machine + 1} load ${load} idle ${values.idle} utilization ${percentage(load, final.makespan)}`
            + ` gaps ${values.gaps} longest_gap ${values.longest} sequence ${sequence}`,
        `IDLE M${machine + 1} ` + (values.intervals.length ? values.intervals.map(([start, end]) => `${start}-${end}`).join(' ') : 'none'));
    }
    for (const job of instance.jobs) {
        const completion = final.ends[job.operations.at(-1)];
        lines.push(`JOB J${job.number} operations ${job.operations.length} work ${job.work} start ${final.starts[job.operations[0]]}`
            + ` completion ${completion} waiting ${completion - job.work}`);
    }
    lines.push(`TOTAL flow ${stats.flow} waiting ${stats.waiting} idle ${stats.idle}`);
    const distances = [...baselines.map(baseline => ({ name: baseline.rule, values: distance(final, baseline.schedule) })),
        { name: 'GA', values: distance(final, ga.best) }];
    let pairs = 0;
    for (let machine = 0; machine < instance.machineCount; machine++) {
        const count = final.order[machine].length;
        const machinePairs = count * (count - 1) / 2;
        pairs += machinePairs;
        lines.push(`DISTANCE M${machine + 1} pairs ${machinePairs} ` + distances.map(item => `${item.name} ${item.values[machine]}`).join(' '));
    }
    lines.push(`DISTANCE total pairs ${pairs} ` + distances.map(item => `${item.name} ${item.values.reduce((sum, value) => sum + value, 0)}`).join(' '));
    return lines;
}

function criticalLines(instance, activated, search, analysis, parameters) {
    const final = search.best;
    const lines = [`SEARCH start ${activated.schedule.makespan} iterations ${parameters.tabuIterations} tenure ${parameters.tenure}`];
    for (const record of search.records) {
        const move = record.chosen;
        lines.push(`ITER ${record.iteration} moves ${record.moves} tabu ${record.tabu} swap M${move.machine + 1}`
            + ` ${instance.operations[move.u].notation} ${instance.operations[move.v].notation} ${move.tabu ? 'aspiration' : 'free'}`
            + ` makespan ${move.value} best ${record.best}`);
    }
    lines.push(`STOP iterations ${search.records.length} reason ${search.reason} best ${final.makespan} found ${search.found}`,
        `PATH operations ${analysis.path.length} blocks ${analysis.blocks.length} makespan ${final.makespan} critical_paths ${analysis.paths}`);
    for (let i = 0; i < analysis.path.length; i++) {
        const index = analysis.path[i];
        const operation = instance.operations[index];
        const link = i === 0 ? 'start' : analysis.path[i - 1] === final.machinePrevious[index] ? 'machine' : 'job';
        lines.push(`NODE ${i + 1} ${operation.notation} M${operation.machine + 1} ${final.starts[index]}-${final.ends[index]} ${link}`);
    }
    for (let i = 0; i < analysis.blocks.length; i++) {
        const block = analysis.blocks[i];
        lines.push(`BLOCK ${i + 1} M${block.machine + 1} ${final.starts[block.operations[0]]}-${final.ends[block.operations.at(-1)]} `
            + block.operations.map(index => instance.operations[index].notation).join(' '));
    }
    const moves = neighbours(instance, final, analysis);
    for (let i = 0; i < moves.length; i++) {
        const move = moves[i];
        lines.push(`NEIGHBOUR ${i + 1} M${move.machine + 1} ${instance.operations[move.u].notation} ${instance.operations[move.v].notation} makespan ${move.value}`);
    }
    const values = slacks(instance, final);
    lines.push(`CRITICAL operations ${values.critical} total ${instance.operations.length}`);
    for (const job of instance.jobs) lines.push(`SLACK J${job.number} ` + job.operations.map(index => values.slack[index]).join(' '));
    for (const job of instance.jobs) lines.push(`FREE J${job.number} ` + job.operations.map(index => values.free[index]).join(' '));
    for (let machine = 0; machine < instance.machineCount; machine++) {
        const critical = instance.machines[machine].operations.filter(index => values.slack[index] === 0).length;
        const durations = instance.operations.map(operation => operation.duration
            + (operation.machine === machine ? Math.floor((operation.duration + 9) / 10) : 0));
        const sensitivity = scheduleOrder(instance, final.order, durations).makespan;
        lines.push(`MACHINE M${machine + 1} critical ${critical} path ${analysis.perMachine[machine]} sensitivity ${sensitivity} delta ${sensitivity - final.makespan}`);
    }
    lines.push(`BOTTLENECK M${analysis.bottleneck + 1} path ${analysis.perMachine[analysis.bottleneck]}`);
    return lines;
}

function main() {
    const instance = readInstance();
    const parameters = readParameters();
    const bounds = lowerBounds(instance);
    const baselines = RULES.map(rule => {
        const dispatched = dispatch(instance, rule);
        const schedule = scheduleOrder(instance, dispatched.order);
        return { rule, dispatched, schedule, analysis: criticalAnalysis(instance, schedule), search: tabuSearch(instance, schedule.order, parameters) };
    });
    const ga = runGenetic(instance, baselines, parameters);
    const genePositions = Array(instance.operations.length);
    const next = instance.jobs.map(() => 0);
    for (let position = 0; position < ga.chromosome.length; position++) {
        const job = instance.byNumber.get(ga.chromosome[position]);
        genePositions[job.operations[next[job.index]++]] = position + 1;
    }
    const activeDecode = dispatch(instance, 'GENES', genePositions);
    const activated = activate(instance, ga.best.order);
    const search = tabuSearch(instance, activated.schedule.order, parameters);
    const analysis = criticalAnalysis(instance, search.best);
    const outputs = [
        ['baselines.txt', baselineLines(instance, bounds, baselines)], ['ga_progress.csv', ga.progress],
        ['best_schedule.txt', bestScheduleLines(instance, bounds, baselines, ga, activeDecode, activated, search.best, analysis, parameters)],
        ['critical_path.txt', criticalLines(instance, activated, search, analysis, parameters)],
    ];
    fs.mkdirSync('output', { recursive: true });
    for (const [name, lines] of outputs) fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

if (require.main === module) main();
