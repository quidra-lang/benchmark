'use strict';

const { balanceAt } = require('./processes');

class Snapshot {
    constructor(name, time, size) {
        this.name = name;
        this.started = time;
        this.completed = null;
        this.records = Array(size).fill(null);
        this.channels = Array.from({ length: size }, () => Array.from({ length: size }, () => []));
        this.dispatched = Array.from({ length: size }, () => Array(size).fill(null));
        this.accepted = Array.from({ length: size }, () => Array(size).fill(null));
        this.remaining = size * (size - 1);
        this.ignored = [];
    }

    record(process, time, reason) {
        const record = { process: process.index, time, reason, balance: process.balance,
            L: process.L, V: process.V.slice(), pending: process.hold.slice(), snapshot: this };
        this.records[process.index] = record;
        return record;
    }

    cut() {
        return this.records.map((record, i) => record.V[i]);
    }
}

function inspectCut(processes, copies, cut) {
    const orphans = [];
    const transit = [];
    for (const copy of copies) {
        const sent = copy.message.event.local <= cut[copy.source];
        const received = copy.received !== null && copy.received.local <= cut[copy.destination];
        if (received && !sent) orphans.push(copy);
        if (sent && !received) transit.push(copy);
    }
    let balances = 0;
    for (let i = 0; i < processes.length; i++) balances += balanceAt(processes[i], cut[i]);
    let money = balances;
    for (const copy of transit) money += copy.message.amount;
    return { orphans, transit, balances, money };
}

module.exports = { Snapshot, inspectCut };
