'use strict';

const fs = require('node:fs');
const { readTopology, Minstd, Channel } = require('./network');
const { advance, lessEqual, relation, deliverable, missingProcesses, vector } = require('./clocks');
const { readPrograms, Process, expandScheduled } = require('./processes');
const { Snapshot, inspectCut } = require('./snapshot');
const { eventGraph, breadthFirst, concurrentPairs, deliveryRelations, countCuts, predicate } = require('./analysis');

function readParameters() {
    const result = { compares: [], cuts: [], predicates: [] };
    const lines = fs.readFileSync('input/params.txt', 'ascii').slice(0, -1).split('\n');
    for (const line of lines) {
        const [key, ...words] = line.split(' ');
        if (key === 'COMPARE') result.compares.push(words);
        else if (key === 'CUT') result.cuts.push(words.map(Number));
        else if (key === 'PREDICATE') result.predicates.push(Number(words[0]));
        else result[key.toLowerCase()] = Number(words[0]);
    }
    return result;
}

class SchedulingQueue {
    constructor() {
        this.heap = [];
        this.serial = 0;
    }

    compare(left, right) {
        return left.time - right.time || left.process - right.process || left.serial - right.serial;
    }

    push(item) {
        item.serial = ++this.serial;
        let index = this.heap.length;
        this.heap.push(item);
        while (index > 0) {
            const parent = (index - 1) >> 1;
            if (this.compare(this.heap[parent], item) <= 0) break;
            this.heap[index] = this.heap[parent];
            index = parent;
        }
        this.heap[index] = item;
    }

    pop() {
        const first = this.heap[0];
        const last = this.heap.pop();
        if (this.heap.length > 0) {
            let index = 0;
            while (2 * index + 1 < this.heap.length) {
                let child = 2 * index + 1;
                if (child + 1 < this.heap.length && this.compare(this.heap[child + 1], this.heap[child]) < 0) child++;
                if (this.compare(last, this.heap[child]) <= 0) break;
                this.heap[index] = this.heap[child];
                index = child;
            }
            this.heap[index] = last;
        }
        return first;
    }
}

class Simulation {
    constructor(topology, programs, params, raw) {
        this.names = topology.names;
        this.params = params;
        this.raw = raw;
        this.generator = new Minstd(params.seed);
        this.processes = programs.map(program => new Process(program, this.names.length));
        this.channels = topology.channels.map(channel => new Channel(channel, this.names.length));
        this.channelTable = Array.from({ length: this.names.length }, () => []);
        for (const channel of this.channels) this.channelTable[channel.source][channel.destination] = channel;
        this.events = [];
        this.messages = [];
        this.copies = [];
        this.snapshots = [];
        this.snapshotByName = new Map();
        this.timeline = [];
        this.time = 0;
        this.initialTotal = 0;
        for (const process of this.processes) this.initialTotal += process.initial;
        this.queue = new SchedulingQueue();
        for (const item of expandScheduled(programs, params.end)) this.queue.push(item);
    }

    run() {
        while (this.queue.heap.length > 0 && this.queue.heap[0].time <= this.params.end) {
            const item = this.queue.pop();
            this.time = item.time;
            if (item.packet) this.arrive(item.packet);
            else this.execute(this.processes[item.process], item.action);
        }
        return this;
    }

    event(process, type, details = {}) {
        advance(process, type === 'RECV' ? details.copy.message.event : null);
        const event = { ...details, type, number: this.events.length + 1, process: process.index,
            local: process.events.length + 1, time: this.time, L: process.L, V: process.V.slice(), balance: process.balance };
        process.events.push(event);
        process.counts[type]++;
        process.minimum = Math.min(process.minimum, process.balance);
        this.events.push(event);
        this.timeline.push({ event });
        return event;
    }

    dispatch(packet) {
        this.channelTable[packet.source][packet.destination].dispatch(packet, this.time, this.generator);
        this.queue.push({ time: packet.arrival, process: packet.destination, packet });
    }

    send(process, kind, tag, amount, destination = null) {
        const message = { id: this.messages.length + 1, source: process.index, destination,
            kind, tag, amount, stamp: kind === 'BCAST' ? process.B.slice() : null, copies: [] };
        this.messages.push(message);
        message.event = this.event(process, kind === 'BCAST' ? 'BCAST' : 'SEND', { message });
        const destinations = kind === 'BCAST'
            ? this.processes.filter(other => other.index !== process.index).map(other => other.index) : [destination];
        for (const target of destinations) {
            const copy = { order: this.copies.length, message, source: process.index, destination: target,
                received: null, delivery: null, fifoWait: false, causalWait: false, missing: [], place: null };
            this.copies.push(copy);
            message.copies.push(copy);
            this.dispatch(copy);
        }
    }

    execute(process, action, sender = null) {
        if (action.type === 'LOCAL') this.event(process, 'LOCAL', { label: action.label });
        else if (action.type === 'SNAPSHOT') this.initiate(process, action.name);
        else if (action.type === 'BROADCAST') {
            process.B[process.index]++;
            this.send(process, 'BCAST', action.tag, 0);
        } else {
            const destination = action.destination === 'SENDER' ? sender : action.destination;
            if (action.type === 'SEND') this.send(process, 'P2P', action.tag, 0, destination);
            else if (action.amount > process.balance) {
                this.event(process, 'NOFUNDS', { destination, amount: action.amount });
            } else {
                process.balance -= action.amount;
                process.sent += action.amount;
                this.send(process, 'P2P', 'transfer', action.amount, destination);
            }
        }
    }

    arrive(packet) {
        const process = this.processes[packet.destination];
        const source = packet.source;
        if (this.raw) this.accept(packet);
        else if (packet.sequence !== process.next[source]) {
            packet.fifoWait = true;
            packet.place = 'fifo';
            process.reorder[source].set(packet.sequence, packet);
            this.channelTable[source][process.index].buffered++;
        } else {
            this.accept(packet);
            while (process.reorder[source].has(process.next[source])) {
                const next = process.reorder[source].get(process.next[source]);
                process.reorder[source].delete(process.next[source]);
                this.accept(next);
            }
        }
        let held = process.hold.length;
        for (const buffer of process.reorder) held += buffer.size;
        process.maxHeld = Math.max(process.maxHeld, held);
    }

    accept(packet) {
        const process = this.processes[packet.destination];
        process.next[packet.source]++;
        packet.place = null;
        if (packet.marker) {
            this.marker(packet);
            return;
        }
        for (const snapshot of this.snapshots) {
            if (snapshot.records[process.index] !== null && snapshot.accepted[packet.source][process.index] === null) {
                snapshot.channels[packet.source][process.index].push(packet);
            }
        }
        if (packet.message.kind === 'P2P') this.deliver(packet);
        else if (this.raw || deliverable(packet, process.B)) {
            this.deliver(packet);
            if (!this.raw) {
                for (;;) {
                    const index = process.hold.findIndex(copy => deliverable(copy, process.B));
                    if (index < 0) break;
                    const [copy] = process.hold.splice(index, 1);
                    this.deliver(copy);
                }
            }
        } else {
            packet.causalWait = true;
            packet.missing = missingProcesses(packet, process.B);
            packet.place = 'causal';
            process.hold.push(packet);
        }
    }

    deliver(copy) {
        const process = this.processes[copy.destination];
        if (copy.message.kind === 'BCAST') process.B[copy.source]++;
        process.balance += copy.message.amount;
        process.received += copy.message.amount;
        copy.delivery = this.time;
        copy.place = null;
        copy.received = this.event(process, 'RECV', { copy, message: copy.message });
        process.deliveries.push(copy);
        for (const rule of process.reactions) {
            if (rule.tag === copy.message.tag) this.execute(process, rule.action, copy.source);
        }
    }

    initiate(process, name) {
        let snapshot = this.snapshotByName.get(name);
        if (snapshot === undefined) {
            snapshot = new Snapshot(name, this.time, this.names.length);
            this.snapshots.push(snapshot);
            this.snapshotByName.set(name, snapshot);
        }
        if (snapshot.records[process.index] !== null) snapshot.ignored.push({ process: process.index, time: this.time });
        else this.record(process, snapshot, 'initiate');
    }

    record(process, snapshot, reason) {
        const record = snapshot.record(process, this.time, reason);
        this.timeline.push({ record });
        for (let destination = 0; destination < this.names.length; destination++) {
            if (destination === process.index) continue;
            snapshot.dispatched[process.index][destination] = this.time;
            this.dispatch({ marker: snapshot, source: process.index, destination });
        }
    }

    marker(packet) {
        const snapshot = packet.marker;
        const process = this.processes[packet.destination];
        if (snapshot.records[process.index] === null) this.record(process, snapshot, `marker ${this.names[packet.source]}`);
        snapshot.accepted[packet.source][process.index] = this.time;
        snapshot.remaining--;
        if (snapshot.remaining === 0) snapshot.completed = this.time;
    }
}

const yesNo = value => value ? 'yes' : 'no';
const messageName = message => `m${message.id}`;
const eventName = (event, names) => `${names[event.process]}.${event.local}`;
const copyName = (copy, names) => `${messageName(copy.message)}->${names[copy.destination]}`;
const nameList = (indices, names) => indices.map(index => names[index]).join(',');

function traceReport(simulation) {
    const { names } = simulation;
    const lines = [];
    for (const event of simulation.events) {
        let details;
        if (event.type === 'LOCAL') details = event.label;
        else if (event.type === 'NOFUNDS') details = `to ${names[event.destination]} amount ${event.amount} balance ${event.balance}`;
        else {
            const message = event.message;
            if (event.type === 'BCAST') details = `${messageName(message)} tag ${message.tag}`;
            else {
                const route = event.type === 'SEND' ? `to ${names[message.destination]}` : `from ${names[message.source]}`;
                details = `${messageName(message)} ${route} tag ${message.tag}`;
                if (message.tag === 'transfer') details += ` amount ${message.amount} balance ${event.balance}`;
            }
        }
        lines.push(`${event.number} t=${event.time} ${eventName(event, names)} ${event.type} ${details} L=${event.L} V=${vector(event.V)}`);
    }
    const delivered = simulation.copies.filter(copy => copy.received !== null).length;
    lines.push(`SUMMARY events ${simulation.events.length} messages ${simulation.messages.length} copies ${simulation.copies.length}`
        + ` delivered ${delivered} undelivered ${simulation.copies.length - delivered} draws ${simulation.generator.draws}`);
    for (const process of simulation.processes) {
        lines.push(`FINAL ${names[process.index]} events ${process.events.length} L=${process.L} V=${vector(process.V)}`
            + ` B=${vector(process.B)} balance ${process.balance} in ${process.received} out ${process.sent}`
            + ` refused ${process.counts.NOFUNDS} min ${process.minimum}`);
    }
    for (const process of simulation.processes) {
        lines.push(`COUNTS ${names[process.index]} local ${process.counts.LOCAL} nofunds ${process.counts.NOFUNDS}`
            + ` send ${process.counts.SEND} bcast ${process.counts.BCAST} recv ${process.counts.RECV}`);
    }
    return lines;
}

function broadcastOrder(process) {
    return process.events.filter(event => event.type === 'BCAST' || event.type === 'RECV' && event.message.kind === 'BCAST')
        .map(event => event.message.id);
}

function waitMode(copy, names) {
    if (copy.causalWait) return `${copy.fifoWait ? 'fifo+causal' : 'causal'} ${nameList(copy.missing, names)}`;
    return copy.fifoWait ? 'fifo' : 'direct';
}

function deliveriesReport(simulation) {
    const { names, copies } = simulation;
    const lines = [];
    for (const process of simulation.processes) {
        lines.push(`PROCESS ${names[process.index]}`);
        const counts = { direct: 0, fifo: 0, causal: 0, both: 0 };
        let waiting = 0;
        let maxWait = 0;
        for (let i = 0; i < process.deliveries.length; i++) {
            const copy = process.deliveries[i];
            const message = copy.message;
            const wait = copy.delivery - copy.arrival;
            waiting += wait;
            maxWait = Math.max(maxWait, wait);
            counts[copy.causalWait ? (copy.fifoWait ? 'both' : 'causal') : (copy.fifoWait ? 'fifo' : 'direct')]++;
            lines.push(`${i + 1} ${messageName(message)} from ${names[copy.source]} ${message.kind} tag ${message.tag}`
                + ` sent ${message.event.time} arrived ${copy.arrival} delivered ${copy.delivery} wait ${wait} ${waitMode(copy, names)}`);
        }
        const undelivered = copies.filter(copy => copy.destination === process.index && copy.received === null);
        for (const copy of undelivered) {
            if (copy.arrival > simulation.params.end) continue;
            const message = copy.message;
            const place = copy.place === 'fifo' ? 'fifo' : `causal ${nameList(copy.missing, names)}`;
            lines.push(`HELD ${messageName(message)} from ${names[copy.source]} ${message.kind} tag ${message.tag}`
                + ` sent ${message.event.time} arrived ${copy.arrival} ${place}`);
        }
        for (const copy of undelivered) {
            if (copy.arrival <= simulation.params.end) continue;
            const message = copy.message;
            lines.push(`TRANSIT ${messageName(message)} from ${names[copy.source]} ${message.kind} tag ${message.tag}`
                + ` sent ${message.event.time} arrival ${copy.arrival}`);
        }
        lines.push(`TOTAL delivered ${process.deliveries.length} direct ${counts.direct} fifo ${counts.fifo} causal ${counts.causal}`
            + ` both ${counts.both} wait ${waiting} max_wait ${maxWait} max_held ${process.maxHeld}`);
        const order = broadcastOrder(process);
        lines.push(`BCASTS ${order.length ? order.map(id => `m${id}`).join(' ') : 'none'}`);
    }
    for (const channel of simulation.channels) {
        const delay = channel.low === channel.high ? String(channel.low) : `${channel.low}-${channel.high}`;
        lines.push(`CHANNEL ${names[channel.source]}->${names[channel.destination]} ${channel.type} ${delay}`
            + ` messages ${channel.messages} markers ${channel.markers} buffered ${channel.buffered}`
            + ` max_delay ${channel.maxDelay} entries ${channel.entries}`);
    }
    const tags = [...new Set(copies.map(copy => copy.message.tag))].sort();
    for (const tag of tags) {
        let count = 0;
        let delivered = 0;
        let latency = 0;
        let maximum = 0;
        for (const copy of copies) {
            if (copy.message.tag !== tag) continue;
            count++;
            if (copy.received !== null) {
                delivered++;
                const value = copy.delivery - copy.message.event.time;
                latency += value;
                maximum = Math.max(maximum, value);
            }
        }
        lines.push(`TAG ${tag} copies ${count} delivered ${delivered} latency ${latency} max ${maximum}`);
    }
    const broadcasts = simulation.messages.filter(message => message.kind === 'BCAST');
    for (const message of broadcasts) {
        let stable = 0;
        for (const copy of message.copies) if (copy.received !== null) stable = Math.max(stable, copy.delivery);
        const value = message.copies.every(copy => copy.received !== null) ? stable : 'none';
        lines.push(`STABLE ${messageName(message)} ${names[message.source]} tag ${message.tag} sent ${message.event.time} stable ${value}`);
    }
    const orders = simulation.processes.map(broadcastOrder);
    let disagreements = 0;
    for (let i = 0; i < broadcasts.length; i++) {
        for (let j = i + 1; j < broadcasts.length; j++) {
            const earlier = [];
            const later = [];
            for (let process = 0; process < names.length; process++) {
                const first = orders[process].indexOf(broadcasts[i].id);
                const second = orders[process].indexOf(broadcasts[j].id);
                if (first >= 0 && second >= 0) (first < second ? earlier : later).push(process);
            }
            if (earlier.length > 0 && later.length > 0) {
                disagreements++;
                lines.push(`DISAGREE ${messageName(broadcasts[i])} ${messageName(broadcasts[j])}`
                    + ` ${nameList(earlier, names)} ${nameList(later, names)}`);
            }
        }
    }
    lines.push(`DISAGREEMENTS ${disagreements}`);
    return lines;
}

function cutVerdict(result, names) {
    return result.orphans.length === 0 ? 'yes' : 'no ' + result.orphans.map(copy => copyName(copy, names)).join(' ');
}

function snapshotDetails(simulation, snapshot) {
    const cut = snapshot.cut();
    const result = inspectCut(simulation.processes, simulation.copies, cut);
    const captured = [];
    let balances = 0;
    let pending = 0;
    for (const record of snapshot.records) {
        balances += record.balance;
        pending += record.pending.length;
        for (const copy of record.pending) captured.push(copy);
    }
    let channels = 0;
    let channelMoney = 0;
    for (const channel of simulation.channels) {
        const copies = snapshot.channels[channel.source][channel.destination];
        channels += copies.length;
        for (const copy of copies) {
            captured.push(copy);
            channelMoney += copy.message.amount;
        }
    }
    captured.sort((a, b) => a.order - b.order);
    const match = captured.length === result.transit.length && captured.every((copy, i) => copy === result.transit[i]);
    return { cut, result, balances, pending, channels, channelMoney, money: balances + channelMoney, match,
        vectorVerdict: snapshot.records.every(record => lessEqual(record.V, cut)) };
}

function snapshotsReport(simulation, raw) {
    const { names } = simulation;
    const lines = [];
    for (const snapshot of simulation.snapshots) {
        const details = snapshotDetails(simulation, snapshot);
        lines.push(`SNAPSHOT ${snapshot.name} started ${snapshot.started} completed ${snapshot.completed}`);
        for (const record of snapshot.records) {
            const pending = record.pending.length ? record.pending.map(copy => messageName(copy.message)).join(' ') : 'none';
            lines.push(`RECORD ${names[record.process]} t=${record.time} ${record.reason} balance ${record.balance}`
                + ` L=${record.L} V=${vector(record.V)} pending ${pending}`);
        }
        for (const channel of simulation.channels) {
            const { source, destination } = channel;
            const copies = snapshot.channels[source][destination];
            const state = copies.length ? copies.map(copy => messageName(copy.message)
                + (copy.message.amount === 0 ? '' : `:${copy.message.amount}`)).join(' ') : 'empty';
            lines.push(`CHANNEL ${names[source]}->${names[destination]} marker ${snapshot.dispatched[source][destination]}`
                + ` ${snapshot.accepted[source][destination]} state ${state}`);
        }
        for (const ignored of snapshot.ignored) lines.push(`IGNORED ${names[ignored.process]} t=${ignored.time}`);
        lines.push(`CUT ${vector(details.cut)} consistent ${cutVerdict(details.result, names)} vector ${yesNo(details.vectorVerdict)}`);
        lines.push(`TRANSIT channels ${details.channels} pending ${details.pending} cut ${details.result.transit.length} match ${yesNo(details.match)}`);
        lines.push(`MONEY balances ${details.balances} channels ${details.channelMoney} total ${details.money}`
            + ` initial ${simulation.initialTotal} conserved ${yesNo(details.money === simulation.initialTotal)}`);
    }
    for (const snapshot of raw.snapshots) {
        const details = snapshotDetails(raw, snapshot);
        lines.push(`RAW ${snapshot.name} completed ${snapshot.completed} cut ${vector(details.cut)}`
            + ` consistent ${cutVerdict(details.result, names)} money ${details.money} conserved ${yesNo(details.money === raw.initialTotal)}`);
    }
    return lines;
}

function rangeNotation(events, names) {
    const parts = [];
    for (let start = 0; start < events.length;) {
        let end = start;
        while (end + 1 < events.length && events[end + 1].process === events[start].process) end++;
        parts.push(eventName(events[start], names) + (start === end ? '' : `-${events[end].local}`));
        start = end + 1;
    }
    return parts.join(' ');
}

function longestChain(simulation) {
    let current = simulation.events[0];
    for (const event of simulation.events) if (event.L > current.L) current = event;
    const chain = [current];
    while (current.L > 1) {
        if (current.type === 'RECV' && current.copy.message.event.L === current.L - 1) current = current.copy.message.event;
        else current = simulation.processes[current.process].events[current.local - 2];
        chain.push(current);
    }
    return chain.reverse();
}

function analysisReport(simulation, raw) {
    const { names, events, processes, copies, params } = simulation;
    const lines = [];
    const graph = eventGraph(processes, events, copies);
    const byName = new Map(events.map(event => [eventName(event, names), event]));
    for (const [firstName, secondName] of params.compares) {
        const first = byName.get(firstName);
        const second = byName.get(secondName);
        const vectorRelation = relation(first.V, second.V);
        let path = breadthFirst(graph, first.number - 1, second.number - 1);
        let graphRelation = '->';
        if (path === null) {
            path = breadthFirst(graph, second.number - 1, first.number - 1);
            graphRelation = path === null ? '||' : '<-';
        }
        lines.push(`COMPARE ${firstName} ${vectorRelation} ${secondName} L=${first.L},${second.L}`
            + ` graph ${graphRelation} agree ${yesNo(vectorRelation === graphRelation)}`);
        if (path !== null) {
            const sequence = path.map(index => events[index]);
            let messages = 0;
            for (let i = 1; i < sequence.length; i++) if (sequence[i].process !== sequence[i - 1].process) messages++;
            lines.push(`PATH length ${sequence.length} messages ${messages} ${rangeNotation(sequence, names)}`);
        }
        for (const event of [first, second]) {
            const future = processes.map(process => process.events.filter(other => other.V[event.process] < event.local).length);
            lines.push(`WINDOW ${eventName(event, names)} past ${vector(event.V)} future ${vector(future)}`);
        }
    }
    const concurrency = concurrentPairs(events, names.length);
    lines.push(`CONCURRENCY events ${events.length} pairs ${concurrency.ordered + concurrency.concurrent}`
        + ` ordered ${concurrency.ordered} concurrent ${concurrency.concurrent} same_lamport ${concurrency.sameLamport}`
        + ` inversions ${concurrency.inversions}`);
    for (let i = 0; i < names.length; i++) {
        for (let j = i + 1; j < names.length; j++) lines.push(`PAIR ${names[i]} ${names[j]} ${concurrency.pairs[i][j]}`);
    }
    const chain = longestChain(simulation);
    lines.push(`CHAIN length ${chain.length} ${rangeNotation(chain, names)}`);
    const deliveries = deliveryRelations(processes);
    for (const { process, first, second } of deliveries.races) {
        lines.push(`RACE ${names[process]} ${messageName(first.message)} ${names[first.source]}`
            + ` ${messageName(second.message)} ${names[second.source]}`);
    }
    lines.push(`RACES ${deliveries.races.length}`);
    for (const { process, first, second } of deliveries.violations) {
        lines.push(`VIOLATION ${names[process]} ${messageName(first.message)} ${names[first.source]}`
            + ` overtook ${messageName(second.message)} ${names[second.source]}`);
    }
    lines.push(`VIOLATIONS causal ${deliveries.violations.length} fifo ${deliveries.fifo}`);
    const rawRelations = deliveryRelations(raw.processes);
    const rawDelivered = raw.copies.filter(copy => copy.received !== null).length;
    lines.push(`RAW events ${raw.events.length} delivered ${rawDelivered} causal ${rawRelations.violations.length} fifo ${rawRelations.fifo}`);
    for (const cut of params.cuts) {
        const result = inspectCut(processes, copies, cut);
        const status = result.orphans.length === 0 ? 'consistent'
            : 'inconsistent orphans ' + result.orphans.map(copy => copyName(copy, names)).join(' ');
        lines.push(`CUT ${vector(cut)} ${status} transit ${result.transit.length} money ${result.money} initial ${simulation.initialTotal}`);
    }
    const cuts = countCuts(processes, params.cutcount, simulation.initialTotal);
    lines.push(`CUTCOUNT t=${params.cutcount} events ${vector(cuts.bounds)} product ${cuts.product} consistent ${cuts.consistent}`);
    lines.push(`LEVELS ${cuts.levels.join(' ')}`);
    for (const threshold of params.predicates) {
        const result = predicate(cuts, threshold);
        lines.push(`PREDICATE transit>=${threshold} cuts ${result.count} possibly ${yesNo(result.possibly)} definitely ${yesNo(result.definitely)}`);
    }
    return lines;
}

function writeText(characters, position, text) {
    for (let i = 0; i < text.length; i++) characters[position + i] = text[i];
}

function diagramHeader(names, label) {
    const characters = Array(8 * names.length - 1).fill(' ');
    writeText(characters, 0, `    ${label}`);
    for (let i = 0; i < names.length; i++) writeText(characters, 8 * i + 6, names[i]);
    return characters.join('').replace(/ +$/, '');
}

function diagramLine(entry, names, value) {
    const characters = Array(8 * names.length - 1).fill(' ');
    const columns = names.map((name, i) => 8 * i + 6);
    writeText(characters, 0, String(value).padStart(5));
    for (const column of columns) characters[column] = '|';
    const item = entry.event ?? entry.record;
    const own = columns[item.process];
    if (entry.record) {
        characters[own] = '#';
        writeText(characters, own + 1, item.snapshot.name);
    } else {
        const symbols = { LOCAL: '*', NOFUNDS: 'x', SEND: 'S', BCAST: 'B', RECV: 'R' };
        characters[own] = symbols[item.type];
        if (item.type === 'SEND' || item.type === 'BCAST') writeText(characters, own + 1, messageName(item.message));
        if (item.type === 'RECV') {
            const source = columns[item.copy.source];
            const first = Math.min(source, own);
            const last = Math.max(source, own);
            for (let position = first + 1; position < last; position++) characters[position] = columns.includes(position) ? '+' : '-';
            characters[source < own ? last - 1 : first + 1] = source < own ? '>' : '<';
            writeText(characters, first + 2, messageName(item.message));
        }
    }
    return characters.join('').replace(/ +$/, '');
}

function diagramReport(simulation) {
    const lines = [diagramHeader(simulation.names, 't')];
    for (const entry of simulation.timeline) lines.push(diagramLine(entry, simulation.names, (entry.event ?? entry.record).time));
    lines.push(diagramHeader(simulation.names, 'L'));
    const ordered = simulation.events.toSorted((a, b) => a.L - b.L || a.process - b.process);
    for (const event of ordered) lines.push(diagramLine({ event }, simulation.names, event.L));
    return lines;
}

function writeReport(filename, lines) {
    fs.mkdirSync('output', { recursive: true });
    fs.writeFileSync(`output/${filename}`, lines.join('\n') + (lines.length ? '\n' : ''), 'ascii');
}

function main() {
    const topology = readTopology();
    const programs = readPrograms(topology.names);
    const params = readParameters();
    const simulation = new Simulation(topology, programs, params, false).run();
    const raw = new Simulation(topology, programs, params, true).run();
    writeReport('trace.txt', traceReport(simulation));
    writeReport('deliveries.txt', deliveriesReport(simulation));
    writeReport('snapshots.txt', snapshotsReport(simulation, raw));
    writeReport('analysis.txt', analysisReport(simulation, raw));
    writeReport('diagram.txt', diagramReport(simulation));
}

main();
