'use strict';

const fs = require('node:fs');

class PetriNet {
    constructor(places, transitions, arcs, initial, final) {
        this.places = places.slice();
        this.transitions = transitions.toSorted();
        this.arcs = arcs.map(arc => arc.slice());
        this.placeIndex = new Map(places.map((name, i) => [name, i]));
        this.initial = this.placeIndex.get(initial);
        this.final = this.placeIndex.get(final);
        this.inputs = new Map(this.transitions.map(name => [name, []]));
        this.outputs = new Map(this.transitions.map(name => [name, []]));
        for (const [from, to] of arcs) {
            if (this.placeIndex.has(from)) this.inputs.get(to).push(this.placeIndex.get(from));
            else this.outputs.get(from).push(this.placeIndex.get(to));
        }
        for (const indices of this.inputs.values()) indices.sort((a, b) => a - b);
        for (const indices of this.outputs.values()) indices.sort((a, b) => a - b);
    }

    marking(final = false) {
        const tokens = Array(this.places.length).fill(0);
        tokens[final ? this.final : this.initial] = 1;
        return tokens;
    }

    enabled(marking, transition) {
        const inputs = this.inputs.get(transition);
        return inputs !== undefined && inputs.every(place => marking[place] >= 1);
    }

    enabledTransitions(marking) {
        return this.transitions.filter(transition => this.enabled(marking, transition));
    }

    fire(marking, transition) {
        const result = marking.slice();
        for (const place of this.inputs.get(transition)) result[place]--;
        for (const place of this.outputs.get(transition)) result[place]++;
        return result;
    }
}

function readModel() {
    const places = [];
    const transitions = [];
    const arcs = [];
    let initial;
    let final;
    for (const line of fs.readFileSync('input/model.txt', 'ascii').slice(0, -1).split('\n')) {
        const [kind, first, second] = line.split(' ');
        if (kind === 'PLACE') places.push(first);
        else if (kind === 'TRANSITION') transitions.push(first);
        else if (kind === 'ARC') arcs.push([first, second]);
        else if (kind === 'INITIAL') initial = first;
        else final = first;
    }
    return new PetriNet(places, transitions, arcs, initial, final);
}

function replayRecord(net) {
    return {missing: 0, remaining: 0, consumed: 0, produced: 0, skipped: 0, fitting: 0,
        places: net.places.map(() => ({missing: 0, remaining: 0, deviating: 0,
            waitingCount: 0, waitingTotal: 0, waitingMaximum: 0, consumptions: new Map()}))};
}

function fitness(record) {
    const consumed = BigInt(record.consumed);
    const produced = BigInt(record.produced);
    const denominator = 2n * consumed * produced;
    const numerator = denominator - BigInt(record.missing) * produced - BigInt(record.remaining) * consumed;
    return [numerator, denominator];
}

module.exports = {PetriNet, readModel, replayRecord, fitness};
