import { mkdirSync, writeFileSync } from 'node:fs';
import { COMMANDS, readInputs, parseCommand, type Command, type Settings, type CollectorDefinition } from './mutator.ts';
import { createObject, addObject, objectPair, freeAmount, dec2, pct, classTable, heapMap, type HeapObject, type Heap, type Pair, type Collector, type CollectionRecord } from './heap.ts';
import { mark, sweep, MarkSweep, MarkCompact } from './mark_sweep.ts';
import { Copying } from './copying.ts';
import { Generational } from './generational.ts';
interface Checkpoint { label: string; line: number; stack: number; live: Pair; ids: Set<number>; allocated: Pair; phase: Pair; survivors: Pair }
interface Reference { lines: number; roots: (HeapObject | null)[]; objects: HeapObject[]; clock: number; labels: Set<string>; commands: Command[]; errors: { line: number; reason: string }[]; checkpoints: Checkpoint[]; checkpointByLine: Map<number, Checkpoint>; live: Set<HeapObject>; counts: Map<Command['op'], number>; peak: { pair: Pair; line: number } }
interface Pause { line: number; work: number; freed: Pair; collection: boolean }
const pairText = (p: Pair) => p.join(' ');
function sum<T>(values: Iterable<T>, valueOf: (v: T) => number) { let total = 0; for (const v of values) total += valueOf(v); return total; }
function sumPairs<T>(values: Iterable<T>, pairOf: (v: T) => Pair): Pair { const result: Pair = [0, 0]; for (const v of values) { const p = pairOf(v); result[0] += p[0]; result[1] += p[1]; } return result; }
const slotValue = (roots: (HeapObject | null)[], slot: number | null) => slot === null ? null : roots[slot];
function reachable(roots: (HeapObject | null)[]) {
    const seen = new Set<HeapObject>(), pending: HeapObject[] = [];
    for (const root of roots) if (root && !seen.has(root)) { seen.add(root); pending.push(root); }
    while (pending.length) for (const v of pending.pop()!.fields) if (v && !seen.has(v)) { seen.add(v); pending.push(v); }
    return seen;
}
function stateError(c: Command, roots: (HeapObject | null)[], labels: Set<string>) {
    if ((c.op === 'ALLOC' || c.op === 'PUSH' || c.op === 'LOAD') && roots.length === 64) return 'stack';
    if ('i' in c && c.i >= roots.length) return 'stack';
    if ('r' in c && c.r !== null && c.r >= roots.length) return 'stack';
    if (c.op === 'POP' && c.n > roots.length) return 'stack';
    if ((c.op === 'LOAD' || c.op === 'SET') && roots[c.i] === null) return 'null';
    if ((c.op === 'LOAD' || c.op === 'SET') && c.f >= roots[c.i]!.pointers) return 'field';
    if (c.op === 'CHECKPOINT' && labels.has(c.label)) return 'duplicate';
    return null;
}
function executeReference(s: Reference, c: Command) {
    const roots = s.roots;
    switch (c.op) {
        case 'ALLOC': {
            const o = createObject(s.objects.length + 1, c.p, c.d); o.birth = s.clock; s.clock += o.size; s.objects.push(o); roots.push(o); c.number = o.number; break;
        }
        case 'PUSH': roots.push(slotValue(roots, c.r)); break;
        case 'LOAD': roots.push(roots[c.i]!.fields[c.f]); break;
        case 'POP': roots.splice(roots.length - c.n, c.n); break;
        case 'SET': roots[c.i]!.fields[c.f] = slotValue(roots, c.r); break;
        case 'OVERWRITE': roots[c.i] = slotValue(roots, c.r); break;
        case 'CHECKPOINT': s.labels.add(c.label); break;
    }
}
function analyzeScript(lines: string[]): Reference {
    const s: Reference = { lines: lines.length, roots: [], objects: [], clock: 0, labels: new Set(), commands: [], errors: [], checkpoints: [], checkpointByLine: new Map(), live: new Set(), counts: new Map(COMMANDS.map(c => [c, 0])), peak: { pair: [0, -1], line: 0 } };
    let previousCount = 0, previousClock = 0;
    for (const [index, text] of lines.entries()) {
        const c = parseCommand(text, index + 1);
        if ('reason' in c) { s.errors.push({ line: index + 1, reason: c.reason }); continue; }
        const reason = stateError(c, s.roots, s.labels);
        if (reason) { s.errors.push({ line: c.line, reason }); continue; }
        executeReference(s, c); s.commands.push(c); s.counts.set(c.op, s.counts.get(c.op)! + 1);
        const live = reachable(s.roots);
        for (const o of s.live) if (!live.has(o)) { o.death = c.line; o.lifetime = s.clock - o.birth - o.size; }
        s.live = live;
        const amount = objectPair(live);
        if (amount[1] > s.peak.pair[1]) s.peak = { pair: amount, line: c.line };
        if (c.op === 'CHECKPOINT') {
            const survivors = objectPair([...live].filter(o => o.number > previousCount));
            const cp: Checkpoint = { label: c.label, line: c.line, stack: s.roots.length, live: amount, ids: new Set([...live].map(o => o.number)),
                allocated: [s.objects.length, s.clock], phase: [s.objects.length - previousCount, s.clock - previousClock], survivors };
            s.checkpoints.push(cp); s.checkpointByLine.set(c.line, cp); previousCount = s.objects.length; previousClock = s.clock;
        }
    }
    return s;
}
function mutatorReport(s: Reference) {
    const lines = [`script lines ${s.lines} valid ${s.commands.length} errors ${s.errors.length}`, ...s.errors.map(e => `error line ${e.line} ${e.reason}`),
        'commands ' + COMMANDS.map(c => `${c} ${s.counts.get(c)}`).join(' '),
        `allocated objects ${s.objects.length} words ${s.clock} sizes ${classTable(s.objects.map(o => o.size))}`,
        `peak_live objects ${s.peak.pair[0]} words ${s.peak.pair[1]} line ${s.peak.line}`];
    const end = objectPair(s.live), lifetimes = [0, 0, 0, 0, 0, 0];
    lines.push(`end_live objects ${end[0]} words ${end[1]} stack ${s.roots.length}`);
    for (const o of s.objects) { const v = o.lifetime; lifetimes[v === null ? 5 : v <= 63 ? 0 : v <= 255 ? 1 : v <= 1023 ? 2 : v <= 4095 ? 3 : 4]++; }
    lines.push('lifetimes ' + ['0-63', '64-255', '256-1023', '1024-4095', '4096+', 'live'].map((label, i) => `${label} ${lifetimes[i]}`).join(' '));
    for (const c of s.checkpoints) lines.push(`checkpoint ${c.label} line ${c.line} stack ${c.stack} live ${pairText(c.live)} allocated ${pairText(c.allocated)} phase ${pairText(c.phase)} survivors ${pairText(c.survivors)} survival ${pct(c.survivors[1], c.phase[1])}`);
    return lines;
}
function leakReport(title: string, garbage: HeapObject[], reference: Reference) {
    const objects = garbage.toSorted((a, b) => a.number - b.number), members = new Set(objects);
    const outgoing = new Map<HeapObject, HeapObject[]>(), incoming = new Map<HeapObject, HeapObject[]>(), adjacent = new Map<HeapObject, HeapObject[]>();
    for (const o of objects) { outgoing.set(o, []); incoming.set(o, []); adjacent.set(o, []); }
    for (const o of objects) for (const v of o.fields) if (v && members.has(v)) {
        outgoing.get(o)!.push(v); incoming.get(v)!.push(o); adjacent.get(o)!.push(v); adjacent.get(v)!.push(o);
    }
    const seen = new Set<HeapObject>(), groups: HeapObject[][] = [], finished: HeapObject[] = [];
    for (const start of objects) {
        if (seen.has(start)) continue;
        const group: HeapObject[] = [], stack = [start]; seen.add(start);
        while (stack.length) { const o = stack.pop()!; group.push(o); for (const v of adjacent.get(o)!) if (!seen.has(v)) { seen.add(v); stack.push(v); } }
        groups.push(group.sort((a, b) => a.number - b.number));
    }
    seen.clear();
    for (const start of objects) {
        if (seen.has(start)) continue;
        const stack = [{ object: start, next: 0 }]; seen.add(start);
        while (stack.length) {
            const f = stack[stack.length - 1], edges = outgoing.get(f.object)!;
            if (f.next === edges.length) { finished.push(f.object); stack.pop(); continue; }
            const v = edges[f.next++]; if (!seen.has(v)) { seen.add(v); stack.push({ object: v, next: 0 }); }
        }
    }
    seen.clear();
    const cycles = new Set<HeapObject>();
    for (let i = finished.length - 1; i >= 0; i--) {
        const start = finished[i]; if (seen.has(start)) continue;
        const component: HeapObject[] = [], stack = [start]; seen.add(start);
        while (stack.length) { const o = stack.pop()!; component.push(o); for (const v of incoming.get(o)!) if (!seen.has(v)) { seen.add(v); stack.push(v); } }
        if (component.length > 1 || outgoing.get(start)!.includes(start)) for (const o of component) cycles.add(o);
    }
    const amount = objectPair(objects), lines = [`${title} groups ${groups.length} objects ${amount[0]} words ${amount[1]}`];
    for (const [i, group] of groups.entries()) {
        const pair = objectPair(group), died = Math.max(...group.map(o => reference.objects[o.number - 1].death!));
        lines.push(`group ${i + 1} objects ${pair[0]} words ${pair[1]} cycle ${group.filter(o => cycles.has(o)).length} died ${died} ids ${group.map(o => `${o.number}${cycles.has(o) ? '*' : ''}`).join(' ')}`);
    }
    return lines;
}
class ReferenceCount extends MarkSweep {
    override kind = 'backup' as const;
    increments = 0;
    decrements = 0;
    cascades: Pause[] = [];
    leaks: string[][] = [];
    constructor(heap: Heap, roots: (HeapObject | null)[], public run: Run, public reference: Reference) { super(heap, roots); }
    retain(v: HeapObject | null) { if (v) { v.references++; this.increments++; } }
    release(v: HeapObject | null, cascade: Pause) {
        const pending = [v];
        while (pending.length) {
            const o = pending.pop(); if (!o) continue;
            o.references--; this.decrements++;
            if (o.references !== 0) continue;
            this.heap.objects.delete(o.number); addObject(cascade.freed, o); cascade.work += 1 + o.pointers;
            for (let f = o.fields.length - 1; f >= 0; f--) pending.push(o.fields[f]);
        }
    }
    override collect(rec: CollectionRecord) {
        const marked = mark(this.roots, rec), garbage = [...this.heap.objects.values()].filter(o => !marked.has(o));
        this.leaks.push(leakReport(`backup ${this.run.records.length + 1} line ${rec.line}`, garbage, this.reference));
        for (const o of sweep(this.heap, marked, rec)) for (const v of o.fields) if (v && marked.has(v)) { v.references--; this.decrements++; }
    }
    finish() { const live = reachable(this.roots); this.leaks.push(leakReport('end', [...this.heap.objects.values()].filter(o => !live.has(o)), this.reference)); }
}
interface Segment { start: number; end: number; before: number; mutator: boolean }
class Timeline {
    segments: Segment[] = [];
    length = 0;
    mutator = 0;
    append(length: number, mutator: boolean) {
        if (!length) return;
        const last = this.segments.at(-1);
        if (last && last.mutator === mutator) last.end += length;
        else this.segments.push({ start: this.length, end: this.length + length, before: this.mutator, mutator });
        this.length += length; if (mutator) this.mutator += length;
    }
    prefix(time: number) {
        if (time === this.length) return this.mutator;
        let low = 0, high = this.segments.length;
        while (low < high) { const mid = Math.floor((low + high) / 2); if (this.segments[mid].end <= time) low = mid + 1; else high = mid; }
        const s = this.segments[low]; return s.before + (s.mutator ? time - s.start : 0);
    }
    minimum(width: number) {
        if (width > this.length) return '-';
        const last = this.length - width, starts = new Set([0, last]);
        for (const s of this.segments) for (const start of [s.end, s.end - width]) if (start >= 0 && start <= last) starts.add(start);
        let minimum = width;
        for (const start of starts) minimum = Math.min(minimum, this.prefix(start + width) - this.prefix(start));
        return pct(minimum, width);
    }
}
class Run {
    heap: Heap;
    roots: (HeapObject | null)[] = [];
    created: HeapObject[] = [];
    records: CollectionRecord[] = [];
    pauses: Pause[] = [];
    timeline = new Timeline();
    observations = new Map<string, string[]>();
    outOfMemory: { line: number; request: number } | null = null;
    peakUsed = 0;
    collector: Collector;
    refcount: ReferenceCount | null;
    constructor(public settings: Settings, public definition: CollectorDefinition, public reference: Reference) {
        this.heap = { size: settings.heap, objects: new Map() };
        switch (definition.type) {
            case 'MARK_SWEEP': this.collector = new MarkSweep(this.heap, this.roots); break;
            case 'MARK_COMPACT': this.collector = new MarkCompact(this.heap, this.roots); break;
            case 'COPYING': this.collector = new Copying(this.heap, this.roots); break;
            case 'GENERATIONAL': this.collector = new Generational(this.heap, this.roots, definition.young, definition.age); break;
            case 'REFCOUNT': this.collector = new ReferenceCount(this.heap, this.roots, this, reference); break;
        }
        this.refcount = this.collector instanceof ReferenceCount ? this.collector : null;
    }
    recordCollection(rec: CollectionRecord) { rec.number = this.records.length + 1; this.records.push(rec); this.pauses.push({ line: rec.line, work: rec.work, freed: rec.freed, collection: true }); this.timeline.append(rec.work, false); }
    push(v: HeapObject | null) { this.refcount?.retain(v); this.roots.push(v); }
    execute(c: Command) {
        const roots = this.roots, cascade: Pause = { line: c.line, freed: [0, 0], work: 0, collection: false };
        let units = 1;
        switch (c.op) {
            case 'ALLOC': {
                units = 1 + c.p + c.d;
                const address = this.collector.allocate(units, c.line, rec => this.recordCollection(rec));
                if (address === null) { this.outOfMemory = { line: c.line, request: units }; return false; }
                const o = createObject(c.number, c.p, c.d); o.address = address; this.heap.objects.set(o.number, o); this.created.push(o); this.push(o);
                this.peakUsed = Math.max(this.peakUsed, objectPair(this.heap.objects.values())[1]); break;
            }
            case 'PUSH': this.push(slotValue(roots, c.r)); break;
            case 'LOAD': this.push(roots[c.i]!.fields[c.f]); break;
            case 'POP': for (let i = 0; i < c.n; i++) { const value = roots.pop()!; this.refcount?.release(value, cascade); } break;
            case 'SET': {
                const o = roots[c.i]!, before = o.fields[c.f], v = slotValue(roots, c.r);
                if (this.collector instanceof Generational) this.collector.writeBarrier(o, v);
                this.refcount?.retain(v); o.fields[c.f] = v; this.refcount?.release(before, cascade); break;
            }
            case 'OVERWRITE': {
                const before = roots[c.i], v = slotValue(roots, c.r); this.refcount?.retain(v); roots[c.i] = v; this.refcount?.release(before, cascade); break;
            }
            case 'CHECKPOINT': break;
        }
        this.timeline.append(units, true);
        if (cascade.freed[0]) { this.refcount!.cascades.push(cascade); this.pauses.push(cascade); this.timeline.append(cascade.work, false); }
        if (c.op === 'CHECKPOINT') this.observations.set(c.label, this.observe(this.reference.checkpointByLine.get(c.line)!));
        return true;
    }
    observe(c: Checkpoint) {
        const objects = [...this.heap.objects.values()], live = objects.filter(o => c.ids.has(o.number)), garbage = objects.filter(o => !c.ids.has(o.number));
        const blocks = this.collector.freeList(), [total, largest] = freeAmount(blocks);
        const lines = [`heap objects ${pairText(objectPair(objects))} reachable ${pairText(objectPair(live))} garbage ${pairText(objectPair(garbage))}`,
            `free total ${total} largest ${largest} blocks ${blocks.length} sizes ${classTable(blocks.map(b => b.length))} fragmentation ${pct(total - largest, total)}`];
        let pointers = 0, forward = 0, backward = 0, distance = 0;
        for (const o of live) for (const v of o.fields) if (v) { pointers++; if (v.address > o.address) forward++; if (v.address < o.address) backward++; distance += Math.abs(v.address - o.address); }
        lines.push(`locality pointers ${pointers} forward ${forward} backward ${backward} mean_distance ${pointers ? dec2(distance, pointers) : '-'}`);
        if (this.collector instanceof Generational) {
            const limit = this.collector.young, young = objects.filter(o => o.address < limit), old = objects.filter(o => o.address >= limit), ages = [0, 0, 0, 0];
            for (const o of young) ages[Math.min(o.age, 3)]++;
            lines.push(`generations young ${pairText(objectPair(young))} old ${pairText(objectPair(old))} remembered ${this.collector.remembered.size} ages 0:${ages[0]} 1:${ages[1]} 2:${ages[2]} 3+:${ages[3]}`);
        }
        if (this.settings.maps.has(c.label)) lines.push(...heapMap(this.heap, this.collector.inactive(), c.ids, this.settings.width));
        return lines;
    }
    simulate() { for (const c of this.reference.commands) if (!this.execute(c)) break; if (!this.outOfMemory) this.refcount?.finish(); }
}
function pauseStatistics(pauses: Pause[]) {
    const work = pauses.map(p => p.work).sort((a, b) => a - b);
    const quantile = (x: number) => work.length ? work[Math.floor((x * work.length + 99) / 100) - 1] : '-';
    return { work: sum(pauses, p => p.work), freed: sum(pauses, p => p.freed[1]), p50: quantile(50), p90: quantile(90), maximum: work.at(-1) ?? 0 };
}
function collectionReport(run: Run) {
    const lines = [`collector ${run.definition.name} ${run.definition.type}`];
    for (const r of run.records) lines.push(`${r.number} line ${r.line} size ${r.request} kind ${r.kind} live ${pairText(r.live)} freed ${pairText(r.freed)} moved ${pairText(r.moved)} promoted ${pairText(r.promoted)} stack ${r.stack} work ${r.work} before ${pairText(r.before)} after ${pairText(r.after)}`);
    const s = pauseStatistics(run.pauses);
    lines.push(`totals collections ${run.records.length} pauses ${run.pauses.length} work ${s.work} freed ${s.freed} pause p50 ${s.p50} p90 ${s.p90} max ${s.maximum}`,
        `utilization ${pct(run.timeline.mutator, run.timeline.length)} mmu ${run.settings.windows.map(w => `${w}:${run.timeline.minimum(w)}`).join(' ')}`);
    if (run.collector instanceof Generational) {
        const kinds = ['minor', 'major', 'tenure', 'full'].map(k => { const records = run.records.filter(r => r.kind === k); return `${k} ${records.length} ${sum(records, r => r.work)}`; });
        lines.push(`generational ${kinds.join(' ')} promoted ${pairText(sumPairs(run.records, r => r.promoted))} barrier ${run.collector.barriers} remembered ${run.collector.remembers}`);
    }
    if (run.refcount) {
        const rc = run.refcount;
        let largest: Pause | null = null;
        for (const c of rc.cascades) if (!largest || c.work > largest.work) largest = c;
        lines.push(`refcount increments ${rc.increments} decrements ${rc.decrements} cascades ${rc.cascades.length} freed ${pairText(sumPairs(rc.cascades, c => c.freed))} max_cascade ${largest ? `${largest.freed[0]} ${largest.work} line ${largest.line}` : '0 0 line -'}`);
    }
    let previous = 0;
    for (const c of run.reference.checkpoints) {
        if (!run.observations.has(c.label)) lines.push(`phase ${c.label} out_of_memory`);
        else {
            const pauses = run.pauses.filter(p => p.line > previous && p.line <= c.line), p = pauseStatistics(pauses);
            lines.push(`phase ${c.label} collections ${pauses.filter(p => p.collection).length} pauses ${pauses.length} work ${p.work} freed ${p.freed} max_pause ${p.maximum}`);
        }
        previous = c.line;
    }
    lines.push(run.outOfMemory ? `status out_of_memory line ${run.outOfMemory.line} size ${run.outOfMemory.request}` : 'status completed');
    return lines;
}
function summaryRow(run: Run) {
    const s = pauseStatistics(run.pauses), movedObjects = run.created.filter(o => o.moves > 0).length, maxMoves = Math.max(0, ...run.created.map(o => o.moves));
    const row: (string | number)[] = [run.definition.name, run.definition.type, run.outOfMemory ? 'out_of_memory' : 'completed', run.records.length, run.pauses.length,
        sum(run.records, r => r.live[0]), sum(run.records, r => r.moved[0]), movedObjects, maxMoves, s.freed, s.work, s.p50, s.p90, s.maximum, run.peakUsed];
    if (run.outOfMemory) row.push('-', '-', '-', '-');
    else { const [total, largest] = freeAmount(run.collector.freeList()); row.push(objectPair(run.heap.objects.values())[1], total, largest, pct(total - largest, total)); }
    return row.join(',');
}
function main() {
    const { settings, lines } = readInputs(), reference = analyzeScript(lines), runs = settings.collectors.map(d => new Run(settings, d, reference));
    for (const run of runs) run.simulate();
    const maps: string[] = [], leaks: string[] = [];
    for (const c of reference.checkpoints) for (const run of runs) maps.push([`checkpoint ${c.label} line ${c.line} collector ${run.definition.name}`, ...(run.observations.get(c.label) ?? ['out_of_memory'])].join('\n'));
    for (const run of runs) if (run.refcount) {
        const block = [`collector ${run.definition.name}`, ...run.refcount.leaks.flat()]; if (run.outOfMemory) block.push('status out_of_memory'); leaks.push(block.join('\n'));
    }
    const header = 'collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation';
    const reports: Record<string, string> = { 'mutator.txt': mutatorReport(reference).join('\n'), 'heap_maps.txt': maps.join('\n\n'),
        'collections.txt': runs.map(r => collectionReport(r).join('\n')).join('\n\n'), 'summary.csv': [header, ...runs.map(summaryRow)].join('\n'), 'leaks.txt': leaks.join('\n\n') || 'none' };
    mkdirSync('output', { recursive: true });
    for (const [name, text] of Object.entries(reports)) writeFileSync('output/' + name, text ? text + '\n' : '', 'ascii');
}
main();
