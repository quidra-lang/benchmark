'use strict';

const { lessEqual, relation } = require('./clocks');
const { balanceAt } = require('./processes');

function eventGraph(processes, events, copies) {
    const graph = Array.from({ length: events.length }, () => []);
    for (const process of processes) {
        for (let i = 1; i < process.events.length; i++) {
            graph[process.events[i - 1].number - 1].push(process.events[i].number - 1);
        }
    }
    for (const copy of copies) {
        if (copy.received !== null) graph[copy.message.event.number - 1].push(copy.received.number - 1);
    }
    return graph;
}

function breadthFirst(graph, start, end) {
    const parents = Array(graph.length).fill(-1);
    parents[start] = start;
    const queue = [start];
    for (let head = 0; head < queue.length; head++) {
        const source = queue[head];
        for (const destination of graph[source]) {
            if (parents[destination] !== -1) continue;
            parents[destination] = source;
            if (destination === end) {
                const path = [end];
                while (path[path.length - 1] !== start) path.push(parents[path[path.length - 1]]);
                return path.reverse();
            }
            queue.push(destination);
        }
    }
    return null;
}

function concurrentPairs(events, size) {
    let ordered = 0;
    let concurrent = 0;
    let sameLamport = 0;
    let inversions = 0;
    const pairs = Array.from({ length: size }, () => Array(size).fill(0));
    for (let i = 0; i < events.length; i++) {
        for (let j = i + 1; j < events.length; j++) {
            const left = events[i];
            const right = events[j];
            if (relation(left.V, right.V) === '||') {
                concurrent++;
                if (left.L === right.L) sameLamport++;
                pairs[Math.min(left.process, right.process)][Math.max(left.process, right.process)]++;
            } else ordered++;
            if ((left.time < right.time && left.L > right.L)
                || (left.time > right.time && left.L < right.L)) inversions++;
        }
    }
    return { ordered, concurrent, sameLamport, inversions, pairs };
}

function deliveryRelations(processes) {
    const races = [];
    const violations = [];
    let fifo = 0;
    for (const process of processes) {
        const deliveries = process.deliveries;
        for (let i = 0; i < deliveries.length; i++) {
            const first = deliveries[i];
            if (i + 1 < deliveries.length && relation(first.message.event.V, deliveries[i + 1].message.event.V) === '||') {
                races.push({ process: process.index, first, second: deliveries[i + 1] });
            }
            for (let j = i + 1; j < deliveries.length; j++) {
                const second = deliveries[j];
                if (relation(second.message.event.V, first.message.event.V) !== '->') continue;
                violations.push({ process: process.index, first, second });
                if (first.source === second.source) fifo++;
            }
        }
    }
    return { races, violations, fifo };
}

function nextCut(cut, bounds) {
    for (let i = 0; i < cut.length; i++) {
        if (cut[i] < bounds[i]) {
            cut[i]++;
            return;
        }
        cut[i] = 0;
    }
}

function countCuts(processes, time, initialTotal) {
    const bounds = processes.map(process => process.events.filter(event => event.time <= time).length);
    const strides = [];
    let product = 1;
    let maximumLevel = 0;
    for (const bound of bounds) {
        strides.push(product);
        product *= bound + 1;
        maximumLevel += bound;
    }
    const valid = new Uint8Array(product);
    const amount = new Int32Array(product);
    const levels = Array(maximumLevel + 1).fill(0);
    const cut = Array(bounds.length).fill(0);
    let consistent = 0;
    for (let index = 0; index < product; index++) {
        const accepted = cut.every((count, i) => count === 0 || lessEqual(processes[i].events[count - 1].V, cut));
        if (accepted) {
            valid[index] = 1;
            consistent++;
            let level = 0;
            let balances = 0;
            for (let i = 0; i < cut.length; i++) {
                level += cut[i];
                balances += balanceAt(processes[i], cut[i]);
            }
            levels[level]++;
            amount[index] = initialTotal - balances;
        }
        nextCut(cut, bounds);
    }
    return { bounds, strides, product, valid, amount, levels, consistent };
}

function predicate(cuts, threshold) {
    const reachable = new Uint8Array(cuts.product);
    const cut = Array(cuts.bounds.length).fill(0);
    let count = 0;
    for (let index = 0; index < cuts.product; index++) {
        if (cuts.valid[index]) {
            if (cuts.amount[index] >= threshold) count++;
            else if (index === 0 || cut.some((value, i) => value > 0 && reachable[index - cuts.strides[i]])) {
                reachable[index] = 1;
            }
        }
        nextCut(cut, cuts.bounds);
    }
    return { count, possibly: count > 0, definitely: reachable[cuts.product - 1] === 0 };
}

module.exports = { eventGraph, breadthFirst, concurrentPairs, deliveryRelations, countCuts, predicate };
