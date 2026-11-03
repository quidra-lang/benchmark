'use strict';

const fs = require('node:fs');
const { COMMANDS, readInputs, parseCommand } = require('./mutator');
const { createObject, addObject, objectPair, freeAmount, dec2, pct, classTable, heapMap } = require('./heap');
const { mark, sweep, MarkSweep, MarkCompact } = require('./mark_sweep');
const { Copying } = require('./copying');
const { Generational } = require('./generational');

function pairText(pair) {
    return `${pair[0]} ${pair[1]}`;
}

function sum(values, valueOf) {
    let total = 0;
    for (const value of values) total += valueOf(value);
    return total;
}

function sumPairs(values, pairOf) {
    const total = [0, 0];
    for (const value of values) {
        const pair = pairOf(value);
        total[0] += pair[0];
        total[1] += pair[1];
    }
    return total;
}

function slotValue(roots, slot) {
    return slot === null ? null : roots[slot];
}

function reachable(roots) {
    const seen = new Set();
    const pending = [];
    for (const root of roots) {
        if (root !== null && !seen.has(root)) {
            seen.add(root);
            pending.push(root);
        }
    }
    while (pending.length > 0) {
        const object = pending.pop();
        for (const value of object.fields) {
            if (value === null || seen.has(value)) continue;
            seen.add(value);
            pending.push(value);
        }
    }
    return seen;
}

function stateError(command, roots, labels) {
    const { op, i, f, r, n, label } = command;
    if (['ALLOC', 'PUSH', 'LOAD'].includes(op) && roots.length === 64) return 'stack';
    if (i !== undefined && i >= roots.length) return 'stack';
    if (r !== undefined && r !== null && r >= roots.length) return 'stack';
    if (op === 'POP' && n > roots.length) return 'stack';
    if ((op === 'LOAD' || op === 'SET') && roots[i] === null) return 'null';
    if ((op === 'LOAD' || op === 'SET') && f >= roots[i].pointers) return 'field';
    if (op === 'CHECKPOINT' && labels.has(label)) return 'duplicate';
    return null;
}

function executeReference(state, command) {
    const roots = state.roots;
    switch (command.op) {
        case 'ALLOC': {
            const object = createObject(state.objects.length + 1, command.p, command.d);
            object.birth = state.clock;
            object.death = null;
            object.lifetime = null;
            state.clock += object.size;
            state.objects.push(object);
            roots.push(object);
            command.number = object.number;
            break;
        }
        case 'PUSH': roots.push(slotValue(roots, command.r)); break;
        case 'LOAD': roots.push(roots[command.i].fields[command.f]); break;
        case 'POP': roots.splice(roots.length - command.n, command.n); break;
        case 'SET': roots[command.i].fields[command.f] = slotValue(roots, command.r); break;
        case 'OVERWRITE': roots[command.i] = slotValue(roots, command.r); break;
        case 'CHECKPOINT': state.labels.add(command.label); break;
    }
}

function analyzeScript(lines) {
    const state = {
        lines: lines.length, roots: [], objects: [], clock: 0, labels: new Set(),
        commands: [], errors: [], checkpoints: [], live: new Set(),
        counts: Object.fromEntries(COMMANDS.map(command => [command, 0])),
        peak: { pair: [0, -1], line: 0 },
    };
    let previousCount = 0;
    let previousClock = 0;
    lines.forEach((text, index) => {
        const command = parseCommand(text, index + 1);
        const reason = command.reason ?? stateError(command, state.roots, state.labels);
        if (reason !== null) {
            state.errors.push({ line: index + 1, reason });
            return;
        }
        executeReference(state, command);
        state.commands.push(command);
        state.counts[command.op]++;
        const live = reachable(state.roots);
        for (const object of state.live) {
            if (live.has(object)) continue;
            object.death = command.line;
            object.lifetime = state.clock - object.birth - object.size;
        }
        state.live = live;
        const amount = objectPair(live);
        if (amount[1] > state.peak.pair[1]) state.peak = { pair: amount, line: command.line };
        if (command.op === 'CHECKPOINT') {
            const survivors = objectPair([...live].filter(object => object.number > previousCount));
            state.checkpoints.push({
                label: command.label, line: command.line, stack: state.roots.length, live: amount,
                ids: new Set([...live].map(object => object.number)),
                allocated: [state.objects.length, state.clock],
                phase: [state.objects.length - previousCount, state.clock - previousClock], survivors,
            });
            previousCount = state.objects.length;
            previousClock = state.clock;
        }
    });
    state.checkpointByLine = new Map(state.checkpoints.map(checkpoint => [checkpoint.line, checkpoint]));
    return state;
}

function mutatorReport(reference) {
    const lines = [`script lines ${reference.lines} valid ${reference.commands.length} errors ${reference.errors.length}`];
    for (const error of reference.errors) lines.push(`error line ${error.line} ${error.reason}`);
    lines.push('commands ' + COMMANDS.map(command => `${command} ${reference.counts[command]}`).join(' '));
    lines.push(`allocated objects ${reference.objects.length} words ${reference.clock} sizes ${classTable(reference.objects.map(object => object.size))}`);
    lines.push(`peak_live objects ${reference.peak.pair[0]} words ${reference.peak.pair[1]} line ${reference.peak.line}`);
    const end = objectPair(reference.live);
    lines.push(`end_live objects ${end[0]} words ${end[1]} stack ${reference.roots.length}`);
    const lifetimes = [0, 0, 0, 0, 0, 0];
    for (const object of reference.objects) {
        const value = object.lifetime;
        const index = value === null ? 5 : value <= 63 ? 0 : value <= 255 ? 1 : value <= 1023 ? 2 : value <= 4095 ? 3 : 4;
        lifetimes[index]++;
    }
    lines.push('lifetimes ' + ['0-63', '64-255', '256-1023', '1024-4095', '4096+', 'live']
        .map((label, index) => `${label} ${lifetimes[index]}`).join(' '));
    for (const checkpoint of reference.checkpoints) {
        lines.push(`checkpoint ${checkpoint.label} line ${checkpoint.line} stack ${checkpoint.stack} live ${pairText(checkpoint.live)} allocated ${pairText(checkpoint.allocated)} phase ${pairText(checkpoint.phase)} survivors ${pairText(checkpoint.survivors)} survival ${pct(checkpoint.survivors[1], checkpoint.phase[1])}`);
    }
    return lines;
}

function leakGraph(objects) {
    const members = new Set(objects);
    const outgoing = new Map(objects.map(object => [object, []]));
    const incoming = new Map(objects.map(object => [object, []]));
    const adjacent = new Map(objects.map(object => [object, []]));
    for (const object of objects) {
        for (const value of object.fields) {
            if (!members.has(value)) continue;
            outgoing.get(object).push(value);
            incoming.get(value).push(object);
            adjacent.get(object).push(value);
            adjacent.get(value).push(object);
        }
    }
    return { outgoing, incoming, adjacent };
}

function leakGroups(objects, graph) {
    const groups = [];
    const seen = new Set();
    for (const start of objects) {
        if (seen.has(start)) continue;
        const group = [];
        const stack = [start];
        seen.add(start);
        while (stack.length > 0) {
            const object = stack.pop();
            group.push(object);
            for (const neighbor of graph.adjacent.get(object)) {
                if (seen.has(neighbor)) continue;
                seen.add(neighbor);
                stack.push(neighbor);
            }
        }
        group.sort((first, second) => first.number - second.number);
        groups.push(group);
    }
    return groups;
}

function cycleObjects(objects, graph) {
    const seen = new Set();
    const finished = [];
    for (const start of objects) {
        if (seen.has(start)) continue;
        const stack = [{ object: start, next: 0 }];
        seen.add(start);
        while (stack.length > 0) {
            const frame = stack.at(-1);
            const edges = graph.outgoing.get(frame.object);
            if (frame.next === edges.length) {
                finished.push(frame.object);
                stack.pop();
                continue;
            }
            const value = edges[frame.next++];
            if (!seen.has(value)) {
                seen.add(value);
                stack.push({ object: value, next: 0 });
            }
        }
    }
    seen.clear();
    const cycles = new Set();
    for (let index = finished.length - 1; index >= 0; index--) {
        const start = finished[index];
        if (seen.has(start)) continue;
        const component = [];
        const stack = [start];
        seen.add(start);
        while (stack.length > 0) {
            const object = stack.pop();
            component.push(object);
            for (const value of graph.incoming.get(object)) {
                if (seen.has(value)) continue;
                seen.add(value);
                stack.push(value);
            }
        }
        if (component.length > 1 || graph.outgoing.get(start).includes(start)) {
            for (const object of component) cycles.add(object);
        }
    }
    return cycles;
}

function leakReport(title, garbage, reference) {
    const objects = [...garbage].sort((first, second) => first.number - second.number);
    const graph = leakGraph(objects);
    const groups = leakGroups(objects, graph);
    const cycles = cycleObjects(objects, graph);
    const amount = objectPair(objects);
    const lines = [`${title} groups ${groups.length} objects ${amount[0]} words ${amount[1]}`];
    groups.forEach((group, index) => {
        const pair = objectPair(group);
        let died = 0;
        let cyclic = 0;
        const ids = [];
        for (const object of group) {
            died = Math.max(died, reference.objects[object.number - 1].death);
            if (cycles.has(object)) cyclic++;
            ids.push(`${object.number}${cycles.has(object) ? '*' : ''}`);
        }
        lines.push(`group ${index + 1} objects ${pair[0]} words ${pair[1]} cycle ${cyclic} died ${died} ids ${ids.join(' ')}`);
    });
    return lines;
}

class ReferenceCount extends MarkSweep {
    constructor(heap, roots, run, reference) {
        super(heap, roots);
        this.kind = 'backup';
        this.run = run;
        this.reference = reference;
        this.increments = 0;
        this.decrements = 0;
        this.cascades = [];
        this.leaks = [];
    }

    retain(value) {
        if (value === null) return;
        value.references++;
        this.increments++;
    }

    release(value, cascade) {
        const pending = [value];
        while (pending.length > 0) {
            const object = pending.pop();
            if (object === null) continue;
            object.references--;
            this.decrements++;
            if (object.references !== 0) continue;
            this.heap.objects.delete(object.number);
            addObject(cascade.freed, object);
            cascade.work += 1 + object.pointers;
            for (let field = object.fields.length - 1; field >= 0; field--) pending.push(object.fields[field]);
        }
    }

    collect(record) {
        const marked = mark(this.heap, this.roots, record);
        const garbage = [...this.heap.objects.values()].filter(object => !marked.has(object));
        this.leaks.push(leakReport(`backup ${this.run.records.length + 1} line ${record.line}`, garbage, this.reference));
        const freed = sweep(this.heap, marked, record);
        for (const object of freed) {
            for (const value of object.fields) {
                if (value === null || !marked.has(value)) continue;
                value.references--;
                this.decrements++;
            }
        }
    }

    finish() {
        const live = reachable(this.roots);
        const garbage = [...this.heap.objects.values()].filter(object => !live.has(object));
        this.leaks.push(leakReport('end', garbage, this.reference));
    }
}

class Timeline {
    constructor() {
        this.segments = [];
        this.length = 0;
        this.mutator = 0;
    }

    append(length, mutator) {
        if (length === 0) return;
        const previous = this.segments.at(-1);
        if (previous !== undefined && previous.mutator === mutator) previous.end += length;
        else this.segments.push({ start: this.length, end: this.length + length, before: this.mutator, mutator });
        this.length += length;
        if (mutator) this.mutator += length;
    }

    prefix(time) {
        if (time === this.length) return this.mutator;
        let low = 0;
        let high = this.segments.length;
        while (low < high) {
            const middle = Math.floor((low + high) / 2);
            if (this.segments[middle].end <= time) low = middle + 1;
            else high = middle;
        }
        const segment = this.segments[low];
        return segment.before + (segment.mutator ? time - segment.start : 0);
    }

    minimum(width) {
        if (width > this.length) return '-';
        const last = this.length - width;
        const starts = new Set([0, last]);
        // The window count is linear until either end crosses a segment boundary.
        for (const segment of this.segments) {
            for (const start of [segment.end, segment.end - width]) {
                if (start >= 0 && start <= last) starts.add(start);
            }
        }
        let minimum = width;
        for (const start of starts) minimum = Math.min(minimum, this.prefix(start + width) - this.prefix(start));
        return pct(minimum, width);
    }
}

function observe(run, checkpoint, settings) {
    const objects = [...run.heap.objects.values()];
    const live = objects.filter(object => checkpoint.ids.has(object.number));
    const garbage = objects.filter(object => !checkpoint.ids.has(object.number));
    const blocks = run.collector.freeList();
    const [total, largest] = freeAmount(blocks);
    const lines = [
        `heap objects ${pairText(objectPair(objects))} reachable ${pairText(objectPair(live))} garbage ${pairText(objectPair(garbage))}`,
        `free total ${total} largest ${largest} blocks ${blocks.length} sizes ${classTable(blocks.map(block => block.length))} fragmentation ${pct(total - largest, total)}`,
    ];
    let pointers = 0;
    let forward = 0;
    let backward = 0;
    let distance = 0;
    for (const object of live) {
        for (const value of object.fields) {
            if (value === null) continue;
            pointers++;
            if (value.address > object.address) forward++;
            if (value.address < object.address) backward++;
            distance += Math.abs(value.address - object.address);
        }
    }
    lines.push(`locality pointers ${pointers} forward ${forward} backward ${backward} mean_distance ${pointers === 0 ? '-' : dec2(distance, pointers)}`);
    if (run.definition.type === 'GENERATIONAL') {
        const young = objects.filter(object => object.address < run.definition.young);
        const old = objects.filter(object => object.address >= run.definition.young);
        const ages = [0, 0, 0, 0];
        for (const object of young) ages[Math.min(object.age, 3)]++;
        lines.push(`generations young ${pairText(objectPair(young))} old ${pairText(objectPair(old))} remembered ${run.collector.remembered.size} ages 0:${ages[0]} 1:${ages[1]} 2:${ages[2]} 3+:${ages[3]}`);
    }
    if (settings.maps.has(checkpoint.label)) {
        for (const line of heapMap(run.heap, run.collector, checkpoint.ids, settings.width)) lines.push(line);
    }
    return lines;
}

class Run {
    constructor(settings, definition, reference) {
        this.settings = settings;
        this.definition = definition;
        this.reference = reference;
        this.heap = { size: settings.heap, objects: new Map() };
        this.roots = [];
        this.created = [];
        this.records = [];
        this.pauses = [];
        this.timeline = new Timeline();
        this.observations = new Map();
        this.outOfMemory = null;
        this.peakUsed = 0;
        switch (definition.type) {
            case 'MARK_SWEEP': this.collector = new MarkSweep(this.heap, this.roots); break;
            case 'MARK_COMPACT': this.collector = new MarkCompact(this.heap, this.roots); break;
            case 'COPYING': this.collector = new Copying(this.heap, this.roots); break;
            case 'GENERATIONAL': this.collector = new Generational(this.heap, this.roots, definition.young, definition.age); break;
            case 'REFCOUNT': this.collector = new ReferenceCount(this.heap, this.roots, this, reference); break;
        }
        this.refcount = definition.type === 'REFCOUNT' ? this.collector : null;
    }

    recordCollection(record) {
        record.number = this.records.length + 1;
        this.records.push(record);
        this.pauses.push({ line: record.line, work: record.work, freed: record.freed, collection: true });
        this.timeline.append(record.work, false);
    }

    push(value) {
        if (this.refcount !== null) this.refcount.retain(value);
        this.roots.push(value);
    }

    release(value, cascade) {
        if (this.refcount !== null) this.refcount.release(value, cascade);
    }

    execute(command) {
        const roots = this.roots;
        const cascade = { line: command.line, freed: [0, 0], work: 0, collection: false };
        let units = 1;
        switch (command.op) {
            case 'ALLOC': {
                units = 1 + command.p + command.d;
                const address = this.collector.allocate(units, command.line, record => this.recordCollection(record));
                if (address === null) {
                    this.outOfMemory = { line: command.line, request: units };
                    return false;
                }
                const object = createObject(command.number, command.p, command.d);
                object.address = address;
                this.heap.objects.set(object.number, object);
                this.created.push(object);
                this.push(object);
                this.peakUsed = Math.max(this.peakUsed, objectPair(this.heap.objects.values())[1]);
                break;
            }
            case 'PUSH': this.push(slotValue(roots, command.r)); break;
            case 'LOAD': this.push(roots[command.i].fields[command.f]); break;
            case 'POP':
                for (let index = 0; index < command.n; index++) this.release(roots.pop(), cascade);
                break;
            case 'SET': {
                const object = roots[command.i];
                const before = object.fields[command.f];
                const value = slotValue(roots, command.r);
                if (this.definition.type === 'GENERATIONAL') this.collector.writeBarrier(object, value);
                if (this.refcount !== null) this.refcount.retain(value);
                object.fields[command.f] = value;
                this.release(before, cascade);
                break;
            }
            case 'OVERWRITE': {
                const before = roots[command.i];
                const value = slotValue(roots, command.r);
                if (this.refcount !== null) this.refcount.retain(value);
                roots[command.i] = value;
                this.release(before, cascade);
                break;
            }
            case 'CHECKPOINT': break;
        }
        this.timeline.append(units, true);
        if (cascade.freed[0] > 0) {
            this.refcount.cascades.push(cascade);
            this.pauses.push(cascade);
            this.timeline.append(cascade.work, false);
        }
        if (command.op === 'CHECKPOINT') {
            const checkpoint = this.reference.checkpointByLine.get(command.line);
            this.observations.set(command.label, observe(this, checkpoint, this.settings));
        }
        return true;
    }

    simulate() {
        for (const command of this.reference.commands) if (!this.execute(command)) break;
        if (this.outOfMemory === null && this.refcount !== null) this.refcount.finish();
    }
}

function pauseStatistics(pauses) {
    const work = pauses.map(pause => pause.work).sort((first, second) => first - second);
    const quantile = percent => work.length === 0 ? '-' : work[Math.floor((percent * work.length + 99) / 100) - 1];
    return {
        work: sum(pauses, pause => pause.work), freed: sum(pauses, pause => pause.freed[1]),
        p50: quantile(50), p90: quantile(90), maximum: work.at(-1) ?? 0,
    };
}

function collectorStatistics(run) {
    const stats = pauseStatistics(run.pauses);
    const lines = [
        `totals collections ${run.records.length} pauses ${run.pauses.length} work ${stats.work} freed ${stats.freed} pause p50 ${stats.p50} p90 ${stats.p90} max ${stats.maximum}`,
        `utilization ${pct(run.timeline.mutator, run.timeline.length)} mmu ${run.settings.windows.map(width => `${width}:${run.timeline.minimum(width)}`).join(' ')}`,
    ];
    if (run.definition.type === 'GENERATIONAL') {
        const kinds = ['minor', 'major', 'tenure', 'full'].map(kind => {
            const records = run.records.filter(record => record.kind === kind);
            return `${kind} ${records.length} ${sum(records, record => record.work)}`;
        });
        const promoted = sumPairs(run.records, record => record.promoted);
        lines.push(`generational ${kinds.join(' ')} promoted ${pairText(promoted)} barrier ${run.collector.barriers} remembered ${run.collector.remembers}`);
    }
    if (run.refcount !== null) {
        const rc = run.refcount;
        const freed = sumPairs(rc.cascades, cascade => cascade.freed);
        let largest = null;
        for (const cascade of rc.cascades) if (largest === null || cascade.work > largest.work) largest = cascade;
        const detail = largest === null ? '0 0 line -' : `${largest.freed[0]} ${largest.work} line ${largest.line}`;
        lines.push(`refcount increments ${rc.increments} decrements ${rc.decrements} cascades ${rc.cascades.length} freed ${pairText(freed)} max_cascade ${detail}`);
    }
    let previous = 0;
    for (const checkpoint of run.reference.checkpoints) {
        if (!run.observations.has(checkpoint.label)) lines.push(`phase ${checkpoint.label} out_of_memory`);
        else {
            const pauses = run.pauses.filter(pause => pause.line > previous && pause.line <= checkpoint.line);
            const phase = pauseStatistics(pauses);
            const collections = pauses.filter(pause => pause.collection).length;
            lines.push(`phase ${checkpoint.label} collections ${collections} pauses ${pauses.length} work ${phase.work} freed ${phase.freed} max_pause ${phase.maximum}`);
        }
        previous = checkpoint.line;
    }
    lines.push(run.outOfMemory === null ? 'status completed'
        : `status out_of_memory line ${run.outOfMemory.line} size ${run.outOfMemory.request}`);
    return lines;
}

function collectionReport(run) {
    const lines = [`collector ${run.definition.name} ${run.definition.type}`];
    for (const record of run.records) {
        lines.push(`${record.number} line ${record.line} size ${record.request} kind ${record.kind} live ${pairText(record.live)} freed ${pairText(record.freed)} moved ${pairText(record.moved)} promoted ${pairText(record.promoted)} stack ${record.stack} work ${record.work} before ${pairText(record.before)} after ${pairText(record.after)}`);
    }
    for (const line of collectorStatistics(run)) lines.push(line);
    return lines;
}

function summaryRow(run) {
    const stats = pauseStatistics(run.pauses);
    let movedObjects = 0;
    let maxMoves = 0;
    for (const object of run.created) {
        if (object.moves > 0) movedObjects++;
        maxMoves = Math.max(maxMoves, object.moves);
    }
    const row = [
        run.definition.name, run.definition.type, run.outOfMemory === null ? 'completed' : 'out_of_memory',
        run.records.length, run.pauses.length, sum(run.records, record => record.live[0]),
        sum(run.records, record => record.moved[0]), movedObjects, maxMoves,
        stats.freed, stats.work, stats.p50, stats.p90, stats.maximum, run.peakUsed,
    ];
    if (run.outOfMemory !== null) row.push('-', '-', '-', '-');
    else {
        const [total, largest] = freeAmount(run.collector.freeList());
        row.push(objectPair(run.heap.objects.values())[1], total, largest, pct(total - largest, total));
    }
    return row.join(',');
}

function writeReports(reference, runs) {
    const maps = [];
    for (const checkpoint of reference.checkpoints) {
        for (const run of runs) {
            const header = `checkpoint ${checkpoint.label} line ${checkpoint.line} collector ${run.definition.name}`;
            maps.push([header, ...(run.observations.get(checkpoint.label) ?? ['out_of_memory'])].join('\n'));
        }
    }
    const leaks = [];
    for (const run of runs) {
        if (run.refcount === null) continue;
        const lines = [`collector ${run.definition.name}`];
        for (const report of run.refcount.leaks) for (const line of report) lines.push(line);
        if (run.outOfMemory !== null) lines.push('status out_of_memory');
        leaks.push(lines.join('\n'));
    }
    const header = 'collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation';
    const reports = {
        'mutator.txt': mutatorReport(reference).join('\n'),
        'heap_maps.txt': maps.join('\n\n'),
        'collections.txt': runs.map(run => collectionReport(run).join('\n')).join('\n\n'),
        'summary.csv': [header, ...runs.map(summaryRow)].join('\n'),
        'leaks.txt': leaks.length === 0 ? 'none' : leaks.join('\n\n'),
    };
    fs.mkdirSync('output', { recursive: true });
    for (const [name, text] of Object.entries(reports)) fs.writeFileSync(`output/${name}`, text === '' ? '' : text + '\n', 'ascii');
}

function main() {
    const { settings, lines } = readInputs();
    const reference = analyzeScript(lines);
    const runs = settings.collectors.map(definition => new Run(settings, definition, reference));
    for (const run of runs) run.simulate();
    writeReports(reference, runs);
}

if (require.main === module) main();
