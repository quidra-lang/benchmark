'use strict';

const fs = require('node:fs');
const { ACTIONS, readWorld, Minstd, TransitionModel } = require('./environment');
const { floorDivide, firstMaximum, rowValues, actionValues, greedyPolicy,
    valueIteration, inPlaceValueIteration, evaluatePolicy, policyIteration } = require('./dynamic_programming');
const { choose, nextValue, update, DynaModel } = require('./td_learning');
const { FirstVisit, discountedReturn } = require('./monte_carlo');
const { fixed, average, cell, grid, policyGrid, qRows, writeReports } = require('./report');

const METHODS = ['mc', 'sarsa', 'q_learning', 'expected_sarsa', 'dyna_q'];
const ABSORPTION_SCALE = 100000000;

function sum(values, valueOf = value => value) {
    let total = 0;
    for (const value of values) total += valueOf(value);
    return total;
}

function maximum(values) {
    return values[firstMaximum(values)];
}

function pairs(values) {
    const result = [];
    for (let index = 0; index < values.length; index += 2) result.push([values[index], values[index + 1]]);
    return result;
}

function scheduleValue(schedule, episode) {
    let value = schedule[0][1];
    for (const [start, numerator] of schedule) {
        if (start > episode) break;
        value = numerator;
    }
    return value;
}

function readSettings() {
    const text = fs.readFileSync('input/params.txt', 'ascii');
    const parameters = new Map(text.slice(0, -1).split('\n').map(line => {
        const [name, ...values] = line.split(' ');
        return [name, values.map(Number)];
    }));
    const single = name => parameters.get(name)[0];
    const [denominator, floorSlip, iceSlip] = parameters.get('SLIP');
    const settings = {
        gamma: single('GAMMA'), stepReward: single('STEP_REWARD'), denominator, floorSlip, iceSlip,
        theta: single('THETA'), gammaSweep: parameters.get('GAMMA_SWEEP'), slipSweep: pairs(parameters.get('SLIP_SWEEP')),
        episodes: single('EPISODES'), limit: single('STEP_LIMIT'), blockSize: single('BLOCK_SIZE'),
        alpha: pairs(parameters.get('ALPHA')), epsilon: pairs(parameters.get('EPSILON')),
        planning: single('PLANNING_STEPS'), seed: single('SEED'), rollouts: single('ROLLOUTS'), rolloutSeed: single('ROLLOUT_SEED'),
    };
    const starts = [...new Set([...settings.alpha, ...settings.epsilon].map(pair => pair[0]))].sort((a, b) => a - b);
    settings.phases = starts.map((first, index) => ({ first, last: index + 1 < starts.length ? starts[index + 1] - 1 : settings.episodes }));
    settings.finalEpsilon = scheduleValue(settings.epsilon, settings.episodes);
    return settings;
}

function agreement(first, second) {
    let count = 0;
    for (let state = 0; state < first.length; state++) if (first[state] === second[state]) count++;
    return count;
}

function largestEntry(values) {
    let at = 0;
    for (let index = 1; index < values.length; index++) if (values[index] > values[at]) at = index;
    return { at, value: values[at] };
}

function distanceAnalysis(world, model) {
    const distances = Array(world.cells.length).fill(-1);
    distances[world.start] = 0;
    let frontier = [world.start];
    let distance = 0;
    while (frontier.length > 0) {
        const next = [];
        for (const position of frontier) {
            for (const transitions of model.transitions[world.index[position]]) {
                for (const transition of transitions) {
                    if (distances[transition.cell] >= 0) continue;
                    distances[transition.cell] = distance + 1;
                    if (transition.next >= 0) next.push(transition.cell);
                }
            }
        }
        frontier = next.sort((a, b) => a - b);
        distance++;
    }
    return { distances, reachable: world.states.filter(position => distances[position] >= 0).length };
}

function symmetry(world, optimal) {
    const mirrorActions = [0, 3, 2, 1];
    let pairs = 0;
    let values = 0;
    let actions = 0;
    world.states.forEach((position, state) => {
        const column = position % world.width;
        if (column >= world.width - 1 - column) return;
        const mirror = world.index[position + world.width - 1 - 2 * column];
        if (mirror < 0) return;
        pairs++;
        if (optimal.values[state] === optimal.values[mirror]) values++;
        if (optimal.policy[mirror] === mirrorActions[optimal.policy[state]]) actions++;
    });
    return { pairs, values, actions };
}

function prepareData() {
    const world = readWorld();
    const settings = readSettings();
    const model = new TransitionModel(world, settings.denominator, settings.floorSlip, settings.iceSlip, settings.stepReward);
    const optimal = valueIteration(model, settings.gamma, settings.theta);
    optimal.table = actionValues(model, optimal.values, settings.gamma);
    optimal.policy = greedyPolicy(optimal.table);
    optimal.actions = optimal.table.map(row => [0, 1, 2, 3].filter(action => row[action] === maximum(row)));
    return { world, settings, model, optimal,
        inPlace: inPlaceValueIteration(model, settings.gamma, settings.theta),
        iteration: policyIteration(model, settings.gamma, settings.theta),
        distance: distanceAnalysis(world, model), symmetry: symmetry(world, optimal) };
}

function episodeStatistics(episodes) {
    const result = { count: episodes.length, totalReturn: 0, totalSteps: 0, goals: 0, pits: 0, timeouts: 0 };
    for (const episode of episodes) {
        result.totalReturn += episode.totalReturn;
        result.totalSteps += episode.steps;
        if (episode.ending === 'goal') result.goals++;
        else if (episode.ending === 'pit') result.pits++;
        else result.timeouts++;
    }
    return result;
}

function blockRecord(data, table, visits, episodes, number) {
    const statistics = episodeStatistics(episodes.slice(-data.settings.blockSize));
    const policy = greedyPolicy(table);
    let error = 0;
    let coverage = 0;
    table.forEach((row, state) => {
        error += Math.abs(maximum(row) - data.optimal.values[state]);
        if (sum(visits[state]) > 0) coverage++;
    });
    return { number, ...statistics, agree: agreement(policy, data.optimal.policy),
        valueError: floorDivide(error, table.length), coverage };
}

function learn(data, name) {
    const { world, settings, model } = data;
    const table = world.states.map(() => Array(4).fill(0));
    const visits = world.states.map(() => Array(4).fill(0));
    const generator = new Minstd(settings.seed);
    const monteCarlo = name === 'mc' ? new FirstVisit(table.length) : null;
    const dyna = name === 'dyna_q' ? new DynaModel() : null;
    const episodes = [];
    const blocks = [];
    for (let episode = 1; episode <= settings.episodes; episode++) {
        const alpha = scheduleValue(settings.alpha, episode);
        const epsilon = scheduleValue(settings.epsilon, episode);
        const trajectory = [];
        const path = episode === settings.episodes ? [world.start] : null;
        let state = world.startIndex;
        let action = name === 'sarsa' ? choose(table, state, epsilon, generator) : 0;
        let totalReturn = 0;
        let steps = 0;
        let ending = 'timeout';
        for (let step = 1; step <= settings.limit; step++) {
            if (name !== 'sarsa') action = choose(table, state, epsilon, generator);
            const result = model.step(state, action, generator);
            visits[state][action]++;
            if (monteCarlo !== null) trajectory.push({ state, action, reward: result.reward });
            else {
                let future = 0;
                let nextAction = action;
                if (name === 'sarsa') {
                    if (result.next >= 0) {
                        nextAction = choose(table, result.next, epsilon, generator);
                        future = table[result.next][nextAction];
                    }
                } else future = nextValue(table, result.next, name === 'expected_sarsa' ? epsilon : null);
                update(table, state, action, result.reward, result.next, future, settings.gamma, alpha);
                if (dyna !== null) {
                    dyna.record(state, action, result.reward, result.next);
                    dyna.plan(table, settings.planning, settings.gamma, alpha, generator);
                }
                if (name === 'sarsa') action = nextAction;
            }
            totalReturn += result.reward;
            steps++;
            if (path !== null) path.push(result.cell);
            if (result.next < 0) {
                ending = world.terminalAt[result.cell].ending;
                break;
            }
            state = result.next;
        }
        if (monteCarlo !== null) monteCarlo.update(table, trajectory, settings.gamma);
        episodes.push({ totalReturn, steps, ending, path });
        if (episode % settings.blockSize === 0) blocks.push(blockRecord(data, table, visits, episodes, floorDivide(episode, settings.blockSize)));
    }
    return { name, table, visits, episodes, blocks, policy: greedyPolicy(table), visitTotals: visits.map(row => sum(row)) };
}

function nominalPath(world, policy, origin, limit) {
    const path = [world.states[origin]];
    const seen = new Set(path);
    let state = origin;
    for (let steps = 1; steps <= limit; steps++) {
        const reached = world.moves[state][policy[state]];
        const repeated = seen.has(reached);
        path.push(reached);
        const terminal = world.terminalAt[reached];
        if (terminal !== null) return { path, steps, ending: terminal.ending, last: reached };
        if (repeated) return { path, steps, ending: 'loop', last: reached };
        if (steps === limit) return { path, steps, ending: 'limit', last: reached };
        seen.add(reached);
        state = world.index[reached];
    }
}

function describePolicy(data, policy) {
    const { world, model, settings } = data;
    const actions = [0, 0, 0, 0];
    let risk = 0;
    const basins = world.states.map((_, state) => {
        actions[policy[state]]++;
        if (model.transitions[state][policy[state]].some(transition => world.cells[transition.cell] === 'P')) risk++;
        const path = nominalPath(world, policy, state, settings.limit);
        return path.ending === 'goal' || path.ending === 'pit' ? world.terminalAt[path.last].symbol : '*';
    });
    return { actions, risk, basins, path: nominalPath(world, policy, world.startIndex, settings.limit) };
}

function absorption(data, policy) {
    const { world, model, settings } = data;
    let goals = Array(policy.length).fill(0);
    let pits = Array(policy.length).fill(0);
    let expected = Array(policy.length).fill(0);
    for (let step = 1; step <= settings.limit; step++) {
        const nextGoals = [];
        const nextPits = [];
        const nextExpected = [];
        for (let state = 0; state < policy.length; state++) {
            let goalTotal = 0;
            let pitTotal = 0;
            let stepTotal = 0;
            for (const transition of model.transitions[state][policy[state]]) {
                if (transition.next < 0) {
                    if (world.cells[transition.cell] === 'G') goalTotal += transition.weight * ABSORPTION_SCALE;
                    else pitTotal += transition.weight * ABSORPTION_SCALE;
                } else {
                    goalTotal += transition.weight * goals[transition.next];
                    pitTotal += transition.weight * pits[transition.next];
                    stepTotal += transition.weight * expected[transition.next];
                }
            }
            nextGoals.push(floorDivide(goalTotal, model.denominator));
            nextPits.push(floorDivide(pitTotal, model.denominator));
            nextExpected.push(ABSORPTION_SCALE + floorDivide(stepTotal, model.denominator));
        }
        goals = nextGoals;
        pits = nextPits;
        expected = nextExpected;
    }
    const start = world.startIndex;
    return [goals[start], pits[start], ABSORPTION_SCALE - goals[start] - pits[start], expected[start]];
}

function behaviourValue(data, policy) {
    const { model, settings } = data;
    const values = Array(policy.length).fill(0);
    const epsilon = settings.finalEpsilon;
    let sweeps = 0;
    while (true) {
        let delta = 0;
        for (let state = 0; state < policy.length; state++) {
            const actions = rowValues(model, values, state, settings.gamma);
            let total = 0;
            for (let action = 0; action < 4; action++) {
                const weight = epsilon + (action === policy[state] ? 4 * (1000 - epsilon) : 0);
                total += weight * actions[action];
            }
            const next = floorDivide(total, 4000);
            delta = Math.max(delta, Math.abs(next - values[state]));
            values[state] = next;
        }
        sweeps++;
        if (delta <= settings.theta) return { start: values[data.world.startIndex], sweeps };
    }
}

function rollouts(data, policy) {
    const { world, model, settings } = data;
    const generator = new Minstd(settings.rolloutSeed);
    const episodes = [];
    const terminals = Array(world.terminals.length).fill(0);
    let totalDiscounted = 0;
    for (let rollout = 0; rollout < settings.rollouts; rollout++) {
        let state = world.startIndex;
        const rewards = [];
        let totalReturn = 0;
        let ending = 'timeout';
        for (let step = 1; step <= settings.limit; step++) {
            const result = model.step(state, policy[state], generator);
            rewards.push(result.reward);
            totalReturn += result.reward;
            if (result.next < 0) {
                const terminal = world.terminalAt[result.cell];
                terminals[terminal.number]++;
                ending = terminal.ending;
                break;
            }
            state = result.next;
        }
        totalDiscounted += discountedReturn(rewards, settings.gamma);
        episodes.push({ totalReturn, steps: rewards.length, ending });
    }
    const returns = episodes.map(episode => episode.totalReturn).sort((a, b) => a - b);
    return { ...episodeStatistics(episodes), totalDiscounted, terminals,
        minimum: returns[0], median: returns[floorDivide(settings.rollouts + 1, 2) - 1], maximum: returns.at(-1) };
}

function qErrors(data, method) {
    const errors = method.table.map((row, state) => Math.abs(maximum(row) - data.optimal.values[state]));
    const perAction = ACTIONS.map((_, action) => {
        let total = 0;
        let count = 0;
        method.table.forEach((row, state) => {
            if (method.visits[state][action] === 0) return;
            total += Math.abs(row[action] - data.optimal.table[state][action]);
            count++;
        });
        return count === 0 ? null : floorDivide(total, count);
    });
    return { mean: floorDivide(sum(errors), errors.length), ...largestEntry(errors), perAction,
        unvisited: method.visitTotals.filter(visits => visits === 0).length,
        tied: method.table.filter(row => row.filter(value => value === maximum(row)).length > 1).length };
}

function assessPolicy(data, source) {
    const { model, settings, optimal, world } = data;
    const evaluation = evaluatePolicy(model, source.policy, settings.gamma, settings.theta);
    const improved = greedyPolicy(actionValues(model, evaluation.values, settings.gamma));
    const improvedValue = evaluatePolicy(model, improved, settings.gamma, settings.theta);
    source.assessment = {
        agree: agreement(source.policy, optimal.policy),
        optimalActions: source.policy.filter((action, state) => optimal.actions[state].includes(action)).length,
        start: evaluation.values[world.startIndex], sweeps: evaluation.sweeps,
        gap: largestEntry(optimal.values.map((value, state) => value - evaluation.values[state])),
    };
    source.improvement = { changed: source.policy.length - agreement(source.policy, improved),
        start: improvedValue.values[world.startIndex], agree: agreement(improved, optimal.policy) };
    source.description = describePolicy(data, source.policy);
    source.absorption = absorption(data, source.policy);
    source.rollouts = rollouts(data, source.policy);
    if (source.table !== undefined) {
        source.behaviour = behaviourValue(data, source.policy);
        source.errors = qErrors(data, source);
    }
}

function trainingSummary(data, method, optimalReturn) {
    let best = method.blocks[0];
    let reach = '-';
    for (const block of method.blocks) {
        if (block.totalReturn > best.totalReturn) best = block;
        if (reach === '-' && 10 * data.settings.rollouts * block.totalReturn >= 9 * data.settings.blockSize * optimalReturn) reach = block.number;
    }
    const visited = method.visitTotals.map((visits, state) => ({ state, visits }))
        .sort((first, second) => second.visits - first.visits || first.state - second.state).slice(0, 3);
    const phases = data.settings.phases.map(phase => ({ ...phase,
        alpha: scheduleValue(data.settings.alpha, phase.first), epsilon: scheduleValue(data.settings.epsilon, phase.first),
        ...episodeStatistics(method.episodes.slice(phase.first - 1, phase.last)) }));
    return { ...episodeStatistics(method.episodes), best, last: method.blocks.at(-1), reach, visited, phases };
}

function sensitivity(data) {
    const analyze = (model, gamma) => {
        const result = valueIteration(model, gamma, data.settings.theta);
        const policy = greedyPolicy(actionValues(model, result.values, gamma));
        const path = nominalPath(data.world, policy, data.world.startIndex, data.settings.limit);
        return { iterations: result.iterations, start: result.values[data.world.startIndex], path,
            differences: policy.length - agreement(policy, data.optimal.policy) };
    };
    return {
        gamma: data.settings.gammaSweep.map(gamma => ({ gamma, ...analyze(data.model, gamma) })),
        slip: data.settings.slipSweep.map(([floorSlip, iceSlip]) => {
            const model = new TransitionModel(data.world, data.settings.denominator, floorSlip, iceSlip, data.settings.stepReward);
            return { floorSlip, iceSlip, ...analyze(model, data.settings.gamma) };
        }),
    };
}

function sections(parts) {
    const lines = [];
    for (const part of parts) {
        if (lines.length > 0) lines.push('');
        for (const line of part) lines.push(line);
    }
    return lines;
}

function worldLines(data) {
    const { world, distance } = data;
    const count = symbols => world.cells.filter(terrain => symbols.includes(terrain)).length;
    const lines = [
        `world rows ${world.height} cols ${world.width} states ${world.states.length} walls ${count('#')} floor ${count('.S')} ice ${count('~')} goals ${count('G')} pits ${count('P')}`,
        `start ${cell(world, world.start)} reachable ${distance.reachable}`,
    ];
    for (const terminal of world.terminals) {
        const value = distance.distances[terminal.cell];
        lines.push(`terminal ${cell(world, terminal.cell)} ${terminal.ending} reward ${terminal.reward} distance ${value < 0 ? '-' : value}`);
    }
    return lines;
}

function valuesReport(data, sweep) {
    const { world, settings, optimal, iteration } = data;
    const valueLines = [`value_iteration gamma ${settings.gamma} theta ${fixed(settings.theta)} iterations ${optimal.iterations}`];
    optimal.changes.forEach((change, index) => valueLines.push(`iteration ${index + 1} max_change ${fixed(change)}`));
    const ties = optimal.actions.filter(actions => actions.length > 1).length;
    const tieLines = [`ties ${ties}`];
    optimal.actions.forEach((actions, state) => {
        if (actions.length > 1) tieLines.push(`tie ${cell(world, world.states[state])} ${actions.map(action => ACTIONS[action]).join('')}`);
    });
    tieLines.push(`symmetry pairs ${data.symmetry.pairs} equal_values ${data.symmetry.values} mirrored_actions ${data.symmetry.actions}`);
    const iterationLines = [`policy_iteration rounds ${iteration.rounds.length}`];
    for (const round of iteration.rounds) iterationLines.push(`round ${round.number} sweeps ${round.sweeps} changed ${round.changed} value_start ${fixed(round.start)}`);
    const difference = largestEntry(optimal.values.map((value, state) => Math.abs(iteration.values[state] - value)));
    const states = world.states.length;
    const backups = sum(iteration.rounds, round => round.sweeps) * states + iteration.rounds.length * states * 4;
    const comparison = [
        `comparison policy_differences ${states - agreement(iteration.policy, optimal.policy)} max_value_difference ${fixed(difference.value)} at ${cell(world, world.states[difference.at])}`,
        `backups value_iteration ${optimal.iterations * states * 4} in_place_iterations ${data.inPlace.iterations} in_place ${data.inPlace.iterations * states * 4} policy_iteration ${backups}`,
    ];
    const detail = result => `iterations ${result.iterations} value_start ${fixed(result.start)} path ${result.path.ending} steps ${result.path.steps} last ${cell(world, result.path.last)} differences ${result.differences}`;
    const gammaLines = ['gamma_sweep', ...sweep.gamma.map(result => `gamma ${result.gamma} ${detail(result)}`)];
    const slipLines = ['slip_sweep', ...sweep.slip.map(result => `slip ${result.floorSlip} ${result.iceSlip} ${detail(result)}`)];
    return sections([
        worldLines(data), valueLines, ['optimal_values', ...grid(world, state => fixed(optimal.values[state]), true)],
        ['optimal_action_counts', ...grid(world, state => optimal.actions[state].length)], tieLines, iterationLines,
        ['policy_iteration_values', ...grid(world, state => fixed(iteration.values[state]), true)], comparison, gammaLines, slipLines,
    ]);
}

function policiesReport(data, policies) {
    const { world } = data;
    const parts = policies.map(policy => {
        const description = policy.description;
        const path = description.path;
        const lines = [policy.name, ...policyGrid(world, policy.policy),
            `path ${path.ending} steps ${path.steps} ${path.path.map(position => cell(world, position)).join(' ')}`,
            `actions N ${description.actions[0]} E ${description.actions[1]} S ${description.actions[2]} W ${description.actions[3]} risk ${description.risk}`,
            'basins', ...grid(world, state => description.basins[state])];
        if (policy.visits !== undefined) {
            lines.push('visits');
            for (const line of grid(world, state => policy.visitTotals[state] === 0 ? 0 : String(policy.visitTotals[state]).length)) lines.push(line);
        }
        return lines;
    });
    return sections(parts);
}

function learningReport(data, methods) {
    const lines = ['method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage'];
    for (const method of methods) {
        for (const block of method.blocks) {
            lines.push([method.name, block.number, average(block.totalReturn, data.settings.blockSize), average(block.totalSteps, data.settings.blockSize),
                block.goals, block.pits, block.timeouts, block.agree, fixed(block.valueError), block.coverage].join(','));
        }
    }
    return lines;
}

function evaluationReport(data, policies, methods) {
    const { world, settings } = data;
    const stateCell = state => cell(world, world.states[state]);
    const values = ['policies', 'policy agree optimal_actions value_start sweeps max_gap at'];
    const improvement = ['improvement', 'policy changed value_start agree'];
    const absorbed = ['absorption', 'policy p_goal p_pit p_timeout expected_steps'];
    const rolloutLines = ['rollouts', 'policy mean_return mean_discounted mean_steps goals pits timeouts min median max'];
    const terminalLines = ['terminals', `policy ${world.terminals.map(terminal => cell(world, terminal.cell)).join(' ')}`];
    const agreementLines = ['agreement', `policy ${policies.map(policy => policy.name).join(' ')}`];
    for (const policy of policies) {
        const evaluation = policy.assessment;
        values.push(`${policy.name} ${evaluation.agree} ${evaluation.optimalActions} ${fixed(evaluation.start)} ${evaluation.sweeps} ${fixed(evaluation.gap.value)} ${stateCell(evaluation.gap.at)}`);
        improvement.push(`${policy.name} ${policy.improvement.changed} ${fixed(policy.improvement.start)} ${policy.improvement.agree}`);
        absorbed.push(`${policy.name} ${policy.absorption.map(value => fixed(floorDivide(value, 10000))).join(' ')}`);
        const trials = policy.rollouts;
        rolloutLines.push(`${policy.name} ${average(trials.totalReturn, settings.rollouts)} ${fixed(floorDivide(trials.totalDiscounted, settings.rollouts))} ${average(trials.totalSteps, settings.rollouts)} ${trials.goals} ${trials.pits} ${trials.timeouts} ${trials.minimum} ${trials.median} ${trials.maximum}`);
        terminalLines.push(`${policy.name} ${trials.terminals.join(' ')}`);
        agreementLines.push(`${policy.name} ${policies.map(other => agreement(policy.policy, other.policy)).join(' ')}`);
    }
    const behaviour = ['behaviour', 'method epsilon value_start sweeps'];
    const errors = ['q_errors', 'method mean_abs max_abs at unvisited tied'];
    const actionErrors = ['q_action_errors', 'method N E S W'];
    const training = ['training', 'method steps goals pits timeouts best_block best_mean last_mean reach'];
    const visited = ['visited'];
    const lastEpisodes = ['last_episodes'];
    const phases = ['phases'];
    for (const method of methods) {
        behaviour.push(`${method.name} ${settings.finalEpsilon} ${fixed(method.behaviour.start)} ${method.behaviour.sweeps}`);
        const error = method.errors;
        errors.push(`${method.name} ${fixed(error.mean)} ${fixed(error.value)} ${stateCell(error.at)} ${error.unvisited} ${error.tied}`);
        actionErrors.push(`${method.name} ${error.perAction.map(fixed).join(' ')}`);
        const summary = method.training;
        training.push(`${method.name} ${summary.totalSteps} ${summary.goals} ${summary.pits} ${summary.timeouts} ${summary.best.number} ${average(summary.best.totalReturn, settings.blockSize)} ${average(summary.last.totalReturn, settings.blockSize)} ${summary.reach}`);
        visited.push(`${method.name} ${summary.visited.map(item => `${stateCell(item.state)}:${item.visits}`).join(' ')}`);
        const last = method.episodes.at(-1);
        lastEpisodes.push(`${method.name} return ${last.totalReturn} steps ${last.steps} end ${last.ending} ${last.path.map(position => cell(world, position)).join(' ')}`);
        for (const phase of summary.phases) {
            phases.push(`${method.name} ${phase.first}-${phase.last} alpha ${phase.alpha} epsilon ${phase.epsilon} mean_return ${average(phase.totalReturn, phase.count)} mean_steps ${average(phase.totalSteps, phase.count)} goals ${phase.goals}`);
        }
    }
    return sections([
        [`summary states ${world.states.length} start ${cell(world, world.start)} rollouts ${settings.rollouts} step_limit ${settings.limit}`],
        values, improvement, absorbed, behaviour, errors, actionErrors, rolloutLines, terminalLines,
        agreementLines, training, visited, lastEpisodes, phases,
    ]);
}

function main() {
    const data = prepareData();
    const methods = METHODS.map(name => learn(data, name));
    const policies = [
        { name: 'value_iteration', policy: data.optimal.policy },
        { name: 'policy_iteration', policy: data.iteration.policy },
        ...methods,
    ];
    for (const policy of policies) assessPolicy(data, policy);
    for (const method of methods) method.training = trainingSummary(data, method, policies[0].rollouts.totalReturn);
    const qTable = ['method,row,col,action,value,visits'];
    for (const line of qRows('value_iteration', data.world, data.optimal.table)) qTable.push(line);
    for (const method of methods) for (const line of qRows(method.name, data.world, method.table, method.visits)) qTable.push(line);
    writeReports({
        'values.txt': valuesReport(data, sensitivity(data)), 'policies.txt': policiesReport(data, policies),
        'q_tables.csv': qTable, 'learning_curves.csv': learningReport(data, methods),
        'evaluation.txt': evaluationReport(data, policies, methods),
    });
}

if (require.main === module) main();
