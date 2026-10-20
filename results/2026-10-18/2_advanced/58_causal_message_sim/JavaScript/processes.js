'use strict';

const fs = require('node:fs');

function action(words, names) {
    const type = words[0];
    if (type === 'LOCAL') return { type, label: words[1] };
    if (type === 'BROADCAST') return { type, tag: words[1] };
    if (type === 'SNAPSHOT') return { type, name: words[1] };
    const destination = words[1] === 'SENDER' ? 'SENDER' : names.indexOf(words[1]);
    return type === 'SEND' ? { type, destination, tag: words[2] }
        : { type, destination, amount: Number(words[2]) };
}

function readPrograms(names) {
    const rows = fs.readFileSync('input/programs.txt', 'ascii').slice(0, -1)
        .split('\n').map(line => line.split(' '));
    const programs = [];
    let current = null;
    for (const words of rows) {
        if (words[0] === 'PROCESS') {
            current = { index: names.indexOf(words[1]), balance: Number(words[3]), scheduled: [], reactions: [] };
            programs.push(current);
        } else if (words[0] === 'ON') {
            current.reactions.push({ tag: words[1], action: action(words.slice(2), names) });
        } else if (words[0] === 'AT') {
            const recurring = words[2] === 'EVERY';
            current.scheduled.push({ time: Number(words[1]), period: recurring ? Number(words[3]) : 0,
                action: action(words.slice(recurring ? 4 : 2), names) });
        }
    }
    return programs;
}

class Process {
    constructor(program, size) {
        this.index = program.index;
        this.initial = program.balance;
        this.balance = program.balance;
        this.minimum = program.balance;
        this.L = 0;
        this.V = Array(size).fill(0);
        this.B = Array(size).fill(0);
        this.next = Array(size).fill(1);
        this.reorder = Array.from({ length: size }, () => new Map());
        this.hold = [];
        this.reactions = program.reactions;
        this.events = [];
        this.deliveries = [];
        this.maxHeld = 0;
        this.received = 0;
        this.sent = 0;
        this.counts = { LOCAL: 0, NOFUNDS: 0, SEND: 0, BCAST: 0, RECV: 0 };
    }
}

function expandScheduled(programs, end) {
    const items = [];
    for (const program of programs) {
        for (const line of program.scheduled) {
            for (let time = line.time; time <= end; time += line.period) {
                items.push({ time, process: program.index, action: line.action });
                if (line.period === 0) break;
            }
        }
    }
    return items;
}

function balanceAt(process, count) {
    return count === 0 ? process.initial : process.events[count - 1].balance;
}

module.exports = { readPrograms, Process, expandScheduled, balanceAt };
