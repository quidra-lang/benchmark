'use strict';

const {readInputs, timestampMinutes, buildCases, median, quotient} = require('./eventlog');
const {pairKey, count, countFollows, basicRelation, table, footprint} = require('./dfg');
const {compareSequences, comparePairs, extendPair, triangleCounts, alphaPlusRelation} = require('./alpha_miner');
const {dependency, loopMeasure, routingMeasure, compareFractions, subtractFractions} = require('./heuristic_miner');
const {PetriNet, readModel, replayRecord, fitness} = require('./conformance');
const {fraction, percentage, list, writeOutputs} = require('./report');

const nameOrder = (first, second) => first < second ? -1 : first > second ? 1 : 0;
const pairOrder = (first, second) => nameOrder(first.from, second.from) || nameOrder(first.to, second.to);
const uniqueNames = names => [...new Set(names)].sort();
const append = (target, source) => { for (const line of source) target.push(line); };
const increment = (map, key, amount = 1) => map.set(key, (map.get(key) || 0) + amount);

function sum(values) {
    let total = 0;
    for (const value of values) total += value;
    return total;
}

function parameters(values) {
    const ratio = key => values.get(key).split('/').map(BigInt);
    return {filter: Number(values.get('filter_min_follows')), sla: Number(values.get('sla_minutes')),
        observations: Number(values.get('positive_observations')), dependency: ratio('dependency_threshold'),
        relative: ratio('relative_to_best'), loop1: ratio('loop1_threshold'), loop2: ratio('loop2_threshold'),
        and: ratio('and_threshold')};
}

function validate(rows) {
    const events = [];
    const errors = [];
    const adopted = new Set();
    for (const row of rows) {
        const time = timestampMinutes(row.timestamp);
        const key = [row.caseId, row.activity, row.timestamp].join('\0');
        if (time === null) errors.push(`ERROR line ${row.line}: bad timestamp ${row.timestamp}`);
        else if (adopted.has(key)) errors.push(`ERROR line ${row.line}: duplicate event ${row.caseId} ${row.activity} ${row.timestamp}`);
        else {
            adopted.add(key);
            events.push({...row, time});
        }
    }
    return {events, errors};
}

function logSummary(rows, events, errors, cases, activities, resources, net, settings) {
    const lines = errors.slice();
    const chronological = events.toSorted((a, b) => a.time - b.time || a.line - b.line);
    lines.push(`LOG rows ${rows.length} adopted ${events.length} rejected ${errors.length} cases ${cases.length}`
        + ` activities ${activities.length} resources ${resources.length} first ${chronological[0].timestamp} last ${chronological.at(-1).timestamp}`);
    const statistics = new Map(activities.map(name => [name, {events: 0, cases: 0, start: 0, end: 0,
        rework: 0, wait: 0, waits: 0, resources: new Set()}]));
    const weekdays = Array.from({length: 7}, () => ({events: 0, starts: 0, ends: 0}));
    const weekday = time => (quotient(time, 1440) + 3) % 7;
    const dayCounts = new Map();
    let late = 0;
    for (const item of cases) {
        const frequencies = new Map();
        for (let i = 0; i < item.events.length; i++) {
            const event = item.events[i];
            const statistic = statistics.get(event.activity);
            statistic.events++;
            statistic.resources.add(event.resource);
            increment(frequencies, event.activity);
            weekdays[weekday(event.time)].events++;
            if (i > 0) {
                statistic.wait += event.time - item.events[i - 1].time;
                statistic.waits++;
            }
        }
        for (const [activity, frequency] of frequencies) {
            const statistic = statistics.get(activity);
            statistic.cases++;
            if (frequency >= 2) statistic.rework++;
        }
        statistics.get(item.trace[0]).start++;
        statistics.get(item.trace.at(-1)).end++;
        weekdays[weekday(item.events[0].time)].starts++;
        weekdays[weekday(item.events.at(-1).time)].ends++;
        increment(dayCounts, quotient(item.duration, 1440));
        if (item.duration > settings.sla) late++;
    }
    for (const activity of activities) {
        const value = statistics.get(activity);
        lines.push(`ACTIVITY ${activity} events ${value.events} cases ${value.cases} start ${value.start} end ${value.end}`
            + ` rework ${value.rework} wait ${value.waits === 0 ? '-' : fraction(value.wait, value.waits)}`
            + ` resources ${value.resources.size} model ${net.inputs.has(activity) ? 'yes' : 'no'}`);
    }
    for (const [name, values] of [['LENGTH', cases.map(item => item.events.length)], ['DURATION', cases.map(item => item.duration)]]) {
        lines.push(`${name} min ${Math.min(...values)} max ${Math.max(...values)} mean ${fraction(sum(values), values.length)} median ${fraction(median(values))}`);
    }
    const lastDay = Math.max(...dayCounts.keys());
    for (let day = 0; day <= lastDay; day++) {
        const count = dayCounts.get(day) || 0;
        lines.push(`DAYS ${day} cases ${count} share ${percentage(count, cases.length)}`);
    }
    lines.push(`SLA limit ${settings.sla} late ${late} share ${percentage(late, cases.length)}`);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    weekdays.forEach((value, i) => lines.push(`WEEKDAY ${names[i]} events ${value.events} starts ${value.starts} ends ${value.ends}`));
    return lines;
}

function groupVariants(cases, follows, settings) {
    const groups = new Map();
    for (const item of cases) {
        const key = item.trace.join(',');
        if (!groups.has(key)) groups.set(key, {trace: item.trace, cases: []});
        groups.get(key).cases.push(item);
    }
    const variants = [...groups.values()].sort((a, b) => b.cases.length - a.cases.length || compareSequences(a.trace, b.trace));
    variants.forEach((variant, i) => {
        variant.number = i + 1;
        variant.keep = variant.trace.every((activity, j) => j === 0 || count(follows, variant.trace[j - 1], activity) >= settings.filter);
        for (const item of variant.cases) item.variant = variant.number;
    });
    return variants;
}

function variantReport(variants, cases, eventCount, settings, referenceReplay) {
    const lines = [];
    let keptVariants = 0;
    let keptCases = 0;
    let keptEvents = 0;
    for (const variant of variants) {
        const count = variant.cases.length;
        const first = variant.cases[0];
        const durations = variant.cases.map(item => item.duration);
        const late = durations.filter(duration => duration > settings.sla).length;
        const fit = fitness(referenceReplay.cases.get(first.id));
        lines.push(`VARIANT ${variant.number} count ${count} share ${percentage(count, cases.length)} length ${variant.trace.length}`
            + ` first ${first.id} duration ${fraction(sum(durations), count)} late ${late} fitness ${fraction(fit)}`
            + ` ${variant.keep ? 'KEEP' : 'DROP'} ${variant.trace.join(',')}`);
        if (variant.keep) {
            keptVariants++;
            keptCases += count;
            keptEvents += count * variant.trace.length;
        }
    }
    lines.push(`FILTER min_follows ${settings.filter} variants ${keptVariants} of ${variants.length} cases ${keptCases} of ${cases.length}`
        + ` events ${keptEvents} of ${eventCount}`);
    return lines;
}

function directlyFollowsReport(cases, activities, follows) {
    const starts = new Map();
    const ends = new Map();
    const edges = new Map();
    for (const item of cases) {
        increment(starts, item.trace[0]);
        const end = item.trace.at(-1);
        if (!ends.has(end)) ends.set(end, []);
        ends.get(end).push(item.duration);
        for (let i = 1; i < item.events.length; i++) {
            const first = item.events[i - 1];
            const second = item.events[i];
            const key = pairKey(first.activity, second.activity);
            if (!edges.has(key)) edges.set(key, {from: first.activity, to: second.activity, count: 0, cases: new Set(), waits: []});
            const edge = edges.get(key);
            edge.count++;
            edge.cases.add(item.id);
            edge.waits.push(second.time - first.time);
        }
    }
    const lines = [];
    const sortedStarts = [...starts].sort((a, b) => b[1] - a[1] || nameOrder(a[0], b[0]));
    for (const [activity, count] of sortedStarts) lines.push(`START ${activity} count ${count}`);
    const sortedEnds = [...ends].sort((a, b) => b[1].length - a[1].length || nameOrder(a[0], b[0]));
    for (const [activity, durations] of sortedEnds) {
        lines.push(`END ${activity} count ${durations.length} duration ${fraction(sum(durations), durations.length)}`);
    }
    const sortedEdges = [...edges.values()].sort((a, b) => b.count - a.count || pairOrder(a, b));
    for (const edge of sortedEdges) {
        lines.push(`EDGE ${edge.from} ${edge.to} count ${edge.count} cases ${edge.cases.size}`
            + ` mean ${fraction(sum(edge.waits), edge.waits.length)} min ${Math.min(...edge.waits)} max ${Math.max(...edge.waits)}`);
    }
    append(lines, footprint(activities, (a, b) => basicRelation(follows, a, b)));
    return lines;
}

function discoverAlpha(log, activities, relation) {
    const candidates = [];
    const known = new Set();
    const add = pair => {
        const key = pair.A.join(',') + '|' + pair.B.join(',');
        if (!known.has(key)) {
            known.add(key);
            candidates.push({...pair, maximal: true});
        }
    };
    let causal = 0;
    for (const first of activities) {
        for (const second of activities) {
            if (relation(first, second) !== '->') continue;
            causal++;
            if (relation(first, first) === '#' && relation(second, second) === '#') add({A: [first], B: [second]});
        }
    }
    for (let i = 0; i < candidates.length; i++) {
        const pair = candidates[i];
        for (const activity of activities) {
            for (const side of ['A', 'B']) {
                const extended = extendPair(pair, activity, side, relation);
                if (extended !== null) {
                    pair.maximal = false;
                    add(extended);
                }
            }
        }
    }
    const pairs = candidates.filter(pair => pair.maximal).sort(comparePairs);
    const starts = uniqueNames(log.map(entry => entry.trace[0]));
    const ends = uniqueNames(log.map(entry => entry.trace.at(-1)));
    const places = ['start', ...pairs.map((_, i) => `p${i + 1}`), 'end'];
    const arcs = [];
    for (const activity of starts) arcs.push(['start', activity]);
    for (const activity of ends) arcs.push([activity, 'end']);
    pairs.forEach((pair, i) => {
        for (const activity of pair.A) arcs.push([activity, places[i + 1]]);
        for (const activity of pair.B) arcs.push([places[i + 1], activity]);
    });
    return {activities, relation, causal, candidates: candidates.length, pairs, starts, ends,
        net: new PetriNet(places, activities, arcs, 'start', 'end')};
}

function netLines(discovery) {
    const {net, starts, ends, pairs} = discovery;
    const lines = [`PLACE start - ${list(starts)}`];
    pairs.forEach((pair, i) => lines.push(`PLACE p${i + 1} ${list(pair.A)} ${list(pair.B)}`));
    lines.push(`PLACE end ${list(ends)} -`);
    for (const transition of net.transitions) {
        const inputs = net.inputs.get(transition).map(index => net.places[index]);
        const outputs = net.outputs.get(transition).map(index => net.places[index]);
        lines.push(`TRANSITION ${transition} in ${list(inputs)} out ${list(outputs)}`);
    }
    lines.push(`NET places ${net.places.length} transitions ${net.transitions.length} arcs ${net.arcs.length}`);
    return lines;
}

function alphaMining(variants) {
    const filtered = variants.filter(variant => variant.keep).map(variant => ({trace: variant.trace, weight: variant.cases.length}));
    const activities = uniqueNames(filtered.flatMap(entry => entry.trace));
    const follows = countFollows(filtered);
    const loops = activities.filter(activity => count(follows, activity, activity) > 0);
    const loopSet = new Set(loops);
    const alpha = discoverAlpha(filtered, activities, (a, b) => basicRelation(follows, a, b));
    const reduced = filtered.map(entry => ({trace: entry.trace.filter(activity => !loopSet.has(activity)), weight: entry.weight}));
    const reducedActivities = activities.filter(activity => !loopSet.has(activity));
    const triangles = triangleCounts(reduced);
    const plus = discoverAlpha(reduced, reducedActivities, alphaPlusRelation(countFollows(reduced), triangles));
    const arcs = plus.net.arcs.slice();
    const loopLines = [];
    for (const activity of loops) {
        const before = reducedActivities.filter(other => count(follows, other, activity) > 0);
        const after = reducedActivities.filter(other => count(follows, activity, other) > 0);
        const index = plus.pairs.findIndex(pair => compareSequences(pair.A, before) === 0 && compareSequences(pair.B, after) === 0);
        const place = index < 0 ? '-' : `p${index + 1}`;
        if (index >= 0) arcs.push([place, activity], [activity, place]);
        loopLines.push(`LOOP ${activity} before ${list(before)} after ${list(after)} place ${place}`);
    }
    plus.net = new PetriNet(plus.net.places, activities, arcs, 'start', 'end');
    const lines = [`LOG variants ${filtered.length} cases ${sum(filtered.map(entry => entry.weight))} activities ${list(activities)}`,
        `LOOPS ${list(loops)}`, 'MINER alpha'];
    append(lines, footprint(alpha.activities, alpha.relation));
    lines.push(`PAIRS causal ${alpha.causal} candidates ${alpha.candidates} maximal ${alpha.pairs.length}`);
    append(lines, netLines(alpha));
    lines.push('MINER alpha_plus');
    for (const first of reducedActivities) {
        for (const second of reducedActivities) {
            const frequency = count(triangles, first, second);
            if (frequency > 0) lines.push(`TRIANGLE ${first} ${second} count ${frequency}`);
        }
    }
    append(lines, footprint(plus.activities, plus.relation));
    lines.push(`PAIRS causal ${plus.causal} candidates ${plus.candidates} maximal ${plus.pairs.length}`);
    append(lines, loopLines);
    append(lines, netLines(plus));
    return {alpha: alpha.net, plus: plus.net, lines};
}

function heuristicReport(log, activities, follows, settings) {
    const lines = [];
    const triangles = triangleCounts(log);
    const loops1 = new Set();
    const loops2 = new Set();
    const edges = new Set();
    let loopPairs = 0;
    for (const activity of activities) {
        const frequency = count(follows, activity, activity);
        if (frequency === 0) continue;
        const measure = loopMeasure(frequency);
        const accepted = frequency >= settings.observations && compareFractions(measure, settings.loop1) >= 0;
        lines.push(`L1 ${activity} count ${frequency} measure ${fraction(measure)} ${accepted ? 'ACCEPT' : 'REJECT'}`);
        if (accepted) {
            loops1.add(activity);
            edges.add(pairKey(activity, activity));
        }
    }
    for (let i = 0; i < activities.length; i++) {
        for (let j = i + 1; j < activities.length; j++) {
            const first = activities[i];
            const second = activities[j];
            if (loops1.has(first) || loops1.has(second)) continue;
            const frequency = count(triangles, first, second) + count(triangles, second, first);
            if (frequency === 0) continue;
            const measure = loopMeasure(frequency);
            const accepted = frequency >= settings.observations && compareFractions(measure, settings.loop2) >= 0;
            lines.push(`L2 ${first} ${second} count ${frequency} measure ${fraction(measure)} ${accepted ? 'ACCEPT' : 'REJECT'}`);
            if (accepted) {
                loops2.add(pairKey(first, second));
                loops2.add(pairKey(second, first));
                loopPairs++;
            }
        }
    }
    const dependencies = [];
    const bestOut = new Map();
    const bestIn = new Map();
    for (const first of activities) {
        for (const second of activities) {
            const frequency = count(follows, first, second);
            if (first === second || frequency === 0) continue;
            const measure = dependency(follows, first, second);
            dependencies.push({first, second, frequency, measure});
            if (!bestOut.has(first) || compareFractions(measure, bestOut.get(first)) > 0) bestOut.set(first, measure);
            if (!bestIn.has(second) || compareFractions(measure, bestIn.get(second)) > 0) bestIn.set(second, measure);
        }
    }
    for (const {first, second, frequency, measure} of dependencies) {
        let verdict = 'ACCEPT';
        if (loops2.has(pairKey(first, second))) verdict = 'LOOP2';
        else if (frequency < settings.observations) verdict = 'REJECT_COUNT';
        else if (compareFractions(measure, settings.dependency) < 0) verdict = 'REJECT_MEASURE';
        else if (compareFractions(subtractFractions(bestOut.get(first), measure), settings.relative) > 0
            && compareFractions(subtractFractions(bestIn.get(second), measure), settings.relative) > 0) verdict = 'REJECT_BEST';
        if (verdict === 'ACCEPT' || verdict === 'LOOP2') edges.add(pairKey(first, second));
        lines.push(`DEP ${first} ${second} count ${frequency} reverse ${count(follows, second, first)} measure ${fraction(measure)} ${verdict}`);
    }
    const nodes = activities.map(activity => ({activity,
        inputs: activities.filter(other => edges.has(pairKey(other, activity))),
        outputs: activities.filter(other => edges.has(pairKey(activity, other)))}));
    for (const node of nodes) lines.push(`NODE ${node.activity} in ${list(node.inputs)} out ${list(node.outputs)}`);
    for (const node of nodes) {
        for (const split of [true, false]) {
            const neighbors = (split ? node.outputs : node.inputs).filter(other => other !== node.activity);
            for (let i = 0; i < neighbors.length; i++) {
                for (let j = i + 1; j < neighbors.length; j++) {
                    const measure = routingMeasure(follows, node.activity, neighbors[i], neighbors[j], split);
                    const verdict = compareFractions(measure, settings.and) >= 0 ? 'AND' : 'XOR';
                    lines.push(`${split ? 'SPLIT' : 'JOIN'} ${node.activity} ${neighbors[i]} ${neighbors[j]} measure ${fraction(measure)} ${verdict}`);
                }
            }
        }
    }
    lines.push(`GRAPH activities ${activities.length} edges ${edges.size} loops1 ${loops1.size} loops2 ${loopPairs}`);
    return lines;
}

function explore(net) {
    const initial = net.marking();
    const states = [initial];
    const stateIds = new Map([[initial.join(','), 0]]);
    const reverseEdges = [[]];
    const finalKey = net.marking(true).join(',');
    const dead = new Set(net.transitions);
    const follows = new Map();
    let edges = 0;
    let unsafe = 0;
    let deadlocks = 0;
    for (let index = 0; index < states.length; index++) {
        const marking = states[index];
        const enabled = net.enabledTransitions(marking);
        if (enabled.length === 0 && marking.join(',') !== finalKey) deadlocks++;
        for (const transition of enabled) {
            dead.delete(transition);
            const next = net.fire(marking, transition);
            if (next.some(tokens => tokens > 1)) {
                unsafe++;
                continue;
            }
            edges++;
            const key = next.join(',');
            if (!stateIds.has(key)) {
                stateIds.set(key, states.length);
                states.push(next);
                reverseEdges.push([]);
            }
            reverseEdges[stateIds.get(key)].push(index);
            for (const successor of net.enabledTransitions(next)) follows.set(pairKey(transition, successor), 1);
        }
    }
    const canFinish = new Set();
    if (stateIds.has(finalKey)) {
        const queue = [stateIds.get(finalKey)];
        canFinish.add(queue[0]);
        for (let i = 0; i < queue.length; i++) {
            for (const predecessor of reverseEdges[queue[i]]) {
                if (!canFinish.has(predecessor)) {
                    canFinish.add(predecessor);
                    queue.push(predecessor);
                }
            }
        }
    }
    const stuck = states.length - canFinish.size;
    return {markings: states.length, edges, unsafe, deadlocks, stuck, final: stateIds.has(finalKey),
        dead: net.transitions.filter(transition => dead.has(transition)), sound: unsafe === 0 && stuck === 0 && dead.size === 0, follows};
}

function footprintFitness(activities, follows, net, reachability) {
    const names = uniqueNames(activities.concat(net.transitions));
    const differences = [];
    let differing = 0;
    for (const first of names) {
        for (const second of names) {
            const observed = basicRelation(follows, first, second);
            const model = basicRelation(reachability.follows, first, second);
            if (observed !== model) {
                differing++;
                if (nameOrder(first, second) <= 0) differences.push(`DIFF ${first} ${second} log ${observed} model ${model}`);
            }
        }
    }
    const cells = names.length * names.length;
    return {activities: names.length, cells, differing, fitness: [cells - differing, cells], differences};
}

function buildPrefixes(cases) {
    const prefixes = new Map();
    for (const item of cases) {
        for (let length = 0; length <= item.trace.length; length++) {
            const trace = item.trace.slice(0, length);
            const key = trace.join(',');
            if (!prefixes.has(key)) prefixes.set(key, {trace, weight: 0, followers: new Set()});
            const prefix = prefixes.get(key);
            prefix.weight++;
            if (length < item.trace.length) prefix.followers.add(item.trace[length]);
        }
    }
    return [...prefixes.values()];
}

function precision(net, prefixes) {
    let fitting = 0;
    let allowed = 0;
    let escaping = 0;
    const escapes = new Map();
    for (const prefix of prefixes) {
        let marking = net.marking();
        let fits = true;
        for (const transition of prefix.trace) {
            if (!net.enabled(marking, transition)) {
                fits = false;
                break;
            }
            marking = net.fire(marking, transition);
        }
        if (!fits) continue;
        fitting++;
        const enabled = net.enabledTransitions(marking);
        allowed += prefix.weight * enabled.length;
        for (const transition of enabled) {
            if (!prefix.followers.has(transition)) {
                escaping += prefix.weight;
                increment(escapes, transition, prefix.weight);
            }
        }
    }
    return {prefixes: fitting, allowed, escaping, escapes,
        value: allowed === 0 ? [1, 1] : [allowed - escaping, allowed]};
}

function replayCase(net, item) {
    const record = replayRecord(net);
    const tokens = net.places.map(() => ({times: [], consumed: 0}));
    tokens[net.initial].times.push(item.events[0].time);
    record.produced = 1;
    for (const event of item.events) {
        if (!net.inputs.has(event.activity)) {
            record.skipped++;
            continue;
        }
        for (const place of net.inputs.get(event.activity)) {
            record.consumed++;
            const queue = tokens[place];
            const statistic = record.places[place];
            if (queue.consumed < queue.times.length) {
                const waiting = event.time - queue.times[queue.consumed++];
                statistic.waitingCount++;
                statistic.waitingTotal += waiting;
                statistic.waitingMaximum = Math.max(statistic.waitingMaximum, waiting);
                increment(statistic.consumptions, event.activity);
            } else {
                record.missing++;
                statistic.missing++;
            }
        }
        for (const place of net.outputs.get(event.activity)) {
            tokens[place].times.push(event.time);
            record.produced++;
        }
    }
    record.consumed++;
    const final = tokens[net.final];
    if (final.consumed < final.times.length) final.consumed++;
    else {
        record.missing++;
        record.places[net.final].missing++;
    }
    for (let place = 0; place < net.places.length; place++) {
        const remaining = tokens[place].times.length - tokens[place].consumed;
        record.remaining += remaining;
        record.places[place].remaining = remaining;
        record.places[place].deviating = record.places[place].missing > 0 || remaining > 0 ? 1 : 0;
    }
    record.fitting = record.missing === 0 && record.remaining === 0 ? 1 : 0;
    return record;
}

function replayAll(net, cases) {
    const totals = replayRecord(net);
    const records = new Map();
    for (const item of cases) {
        const record = replayCase(net, item);
        records.set(item.id, record);
        for (const field of ['missing', 'remaining', 'consumed', 'produced', 'skipped', 'fitting']) totals[field] += record[field];
        for (let place = 0; place < net.places.length; place++) {
            const target = totals.places[place];
            const source = record.places[place];
            for (const field of ['missing', 'remaining', 'deviating', 'waitingCount', 'waitingTotal']) target[field] += source[field];
            target.waitingMaximum = Math.max(target.waitingMaximum, source.waitingMaximum);
            for (const [transition, count] of source.consumptions) increment(target.consumptions, transition, count);
        }
    }
    return {totals, cases: records};
}

function conformanceReport(results, cases) {
    const reference = results[0].net;
    const lines = [`MODEL places ${reference.places.length} transitions ${reference.transitions.length} arcs ${reference.arcs.length}`];
    for (const {name, reachability: value} of results) {
        lines.push(`REACHABILITY ${name} markings ${value.markings} edges ${value.edges} unsafe ${value.unsafe} deadlocks ${value.deadlocks}`
            + ` stuck ${value.stuck} final ${value.final ? 'yes' : 'no'} dead ${list(value.dead)} sound ${value.sound ? 'yes' : 'no'}`);
    }
    for (const {name, footprint: value} of results) {
        lines.push(`FOOTPRINT ${name} activities ${value.activities} cells ${value.cells} differing ${value.differing} fitness ${fraction(value.fitness)}`);
        if (name === 'reference') append(lines, value.differences);
    }
    for (const {name, precision: value} of results) {
        lines.push(`PRECISION ${name} prefixes ${value.prefixes} allowed ${value.allowed} escaping ${value.escaping} precision ${fraction(value.value)}`);
        const escapes = [...value.escapes].sort((a, b) => b[1] - a[1] || nameOrder(a[0], b[0]));
        for (const [transition, weight] of escapes) lines.push(`ESCAPE ${name} ${transition} weight ${weight}`);
    }
    for (const {name, net, replay} of results) {
        const value = replay.totals;
        lines.push(`REPLAY ${name} cases ${cases.length} fitting ${value.fitting} skipped ${value.skipped} missing ${value.missing}`
            + ` remaining ${value.remaining} consumed ${value.consumed} produced ${value.produced} fitness ${fraction(fitness(value))}`);
        for (let place = 0; place < net.places.length; place++) {
            const statistic = value.places[place];
            const mean = statistic.waitingCount === 0 ? '-' : fraction(statistic.waitingTotal, statistic.waitingCount);
            const maximum = statistic.waitingCount === 0 ? '-' : statistic.waitingMaximum;
            lines.push(`PLACE ${name} ${net.places[place]} missing ${statistic.missing} remaining ${statistic.remaining}`
                + ` deviating ${statistic.deviating} tokens ${statistic.waitingCount} mean ${mean} max ${maximum}`);
        }
        for (let place = 0; place < net.places.length; place++) {
            const outputs = net.transitions.filter(transition => net.inputs.get(transition).includes(place));
            if (outputs.length < 2) continue;
            const routes = outputs.map(transition => `${transition}=${value.places[place].consumptions.get(transition) || 0}`);
            lines.push(`ROUTE ${name} ${net.places[place]} ${routes.join(',')}`);
        }
    }
    return lines;
}

function conformanceCsv(cases, replay) {
    const lines = ['case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness'];
    for (const item of cases) {
        const value = replay.cases.get(item.id);
        lines.push([item.id, item.variant, item.events.length, value.skipped, value.missing, value.remaining,
            value.consumed, value.produced, fraction(fitness(value))].join(','));
    }
    return lines;
}

function resourceReport(cases, resources) {
    const statistics = new Map(resources.map(resource => [resource, {events: 0, cases: new Set(), work: new Map()}]));
    const handovers = new Map();
    const subcontracting = new Map();
    const together = new Map();
    let total = 0;
    let self = 0;
    for (const item of cases) {
        const present = uniqueNames(item.events.map(event => event.resource));
        for (const event of item.events) {
            const statistic = statistics.get(event.resource);
            statistic.events++;
            statistic.cases.add(item.id);
            increment(statistic.work, event.activity);
        }
        for (let i = 0; i < present.length; i++) {
            for (let j = i + 1; j < present.length; j++) increment(together, pairKey(present[i], present[j]));
        }
        for (let i = 1; i < item.events.length; i++) {
            const from = item.events[i - 1].resource;
            const to = item.events[i].resource;
            const key = pairKey(from, to);
            if (!handovers.has(key)) handovers.set(key, {from, to, count: 0, cases: new Set()});
            const handover = handovers.get(key);
            handover.count++;
            handover.cases.add(item.id);
            total++;
            if (from === to) self++;
            if (i + 1 < item.events.length && from !== to && from === item.events[i + 1].resource) increment(subcontracting, key);
        }
    }
    const lines = [];
    resources.forEach((resource, i) => {
        const statistic = statistics.get(resource);
        const work = [...statistic.work].sort((a, b) => nameOrder(a[0], b[0])).map(([activity, count]) => `${activity}=${count}`);
        lines.push(`RESOURCE ${i + 1} ${resource} events ${statistic.events} cases ${statistic.cases.size} work ${work.join(',')}`);
    });
    const transfers = [...handovers.values()].filter(value => value.from !== value.to)
        .sort((a, b) => b.count - a.count || pairOrder(a, b));
    for (const value of transfers) lines.push(`HANDOVER ${value.from} ${value.to} count ${value.count} cases ${value.cases.size}`);
    const cells = resources.map(from => resources.map(to => handovers.get(pairKey(from, to))?.count || 0));
    append(lines, table(cells, 5));
    const sortedCounts = counts => [...counts].map(([key, count]) => {
        const [from, to] = key.split('\0');
        return {from, to, count};
    }).sort((a, b) => b.count - a.count || pairOrder(a, b));
    for (const value of sortedCounts(subcontracting)) lines.push(`SUBCONTRACT ${value.from} ${value.to} count ${value.count}`);
    for (const value of sortedCounts(together)) lines.push(`TOGETHER ${value.from} ${value.to} cases ${value.count}`);
    lines.push(`TOTAL handovers ${total} self ${self} other ${total - self}`);
    return lines;
}

function main() {
    const input = readInputs();
    const settings = parameters(input.parameters);
    const {events, errors} = validate(input.rows);
    const cases = buildCases(events);
    const activities = uniqueNames(events.map(event => event.activity));
    const resources = uniqueNames(events.map(event => event.resource));
    const reference = readModel();
    const fullLog = cases.map(item => ({trace: item.trace, weight: 1}));
    const follows = countFollows(fullLog);
    const variants = groupVariants(cases, follows, settings);
    const discovered = alphaMining(variants);
    const prefixes = buildPrefixes(cases);
    const results = [['reference', reference], ['alpha', discovered.alpha], ['alpha_plus', discovered.plus]].map(([name, net]) => {
        const reachability = explore(net);
        return {name, net, reachability, footprint: footprintFitness(activities, follows, net, reachability),
            precision: precision(net, prefixes), replay: replayAll(net, cases)};
    });
    writeOutputs({
        'log_summary.txt': logSummary(input.rows, events, errors, cases, activities, resources, reference, settings),
        'variants.txt': variantReport(variants, cases, events.length, settings, results[0].replay),
        'dfg.txt': directlyFollowsReport(cases, activities, follows), 'alpha_net.txt': discovered.lines,
        'heuristic_net.txt': heuristicReport(fullLog, activities, follows, settings),
        'conformance.csv': conformanceCsv(cases, results[0].replay), 'conformance.txt': conformanceReport(results, cases),
        'resources.txt': resourceReport(cases, resources)
    });
}

main();
