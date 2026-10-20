import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { readTopology, Minstd, Channel } from './network.ts';
import { advance, lessEqual, relation, deliverable, missingProcesses, vector } from './clocks.ts';
import { readPrograms, Process, expandScheduled, type Program, type Action, type Packet, type Copy, type Marker,
    type Message, type SimEvent, type EventType, type EventDetails, type Scheduled } from './processes.ts';
import { Snapshot, inspectCut, type SnapshotRecord } from './snapshot.ts';
import { eventGraph, breadthFirst, concurrentPairs, deliveryRelations, countCuts, predicate } from './analysis.ts';

interface Parameters { seed: number; end: number; cutcount: number; compares: [string, string][]; cuts: number[][]; predicates: number[] }
function readParameters(): Parameters {
    const p: Parameters = { seed: 0, end: 0, cutcount: 0, compares: [], cuts: [], predicates: [] };
    for (const line of readFileSync('input/params.txt', 'ascii').trimEnd().split('\n')) {
        const [key, ...w] = line.split(' ');
        if (key === 'COMPARE') p.compares.push([w[0], w[1]]); else if (key === 'CUT') p.cuts.push(w.map(Number));
        else if (key === 'PREDICATE') p.predicates.push(Number(w[0])); else if (key === 'SEED') p.seed = Number(w[0]); else if (key === 'END') p.end = Number(w[0]); else p.cutcount = Number(w[0]);
    }
    return p;
}
type Timeline = { kind: 'event'; event: SimEvent } | { kind: 'record'; record: SnapshotRecord };
type Item = (Scheduled | { kind: 'arrival'; time: number; process: number; packet: Packet }) & { serial: number };
const packetFields = (source: number, destination: number) => ({ source, destination, sequence: 0, dispatched: 0, arrival: 0, fifoWait: false, place: null });
class Simulation {
    names: string[]; generator: Minstd; processes: Process[]; channels: Channel[]; channelTable: Channel[][];
    events: SimEvent[] = []; messages: Message[] = []; copies: Copy[] = []; snapshots: Snapshot[] = []; snapshotByName = new Map<string, Snapshot>();
    timeline: Timeline[] = []; time = 0; initialTotal: number; private queue: Item[] = []; private serial = 0;
    constructor(topology: ReturnType<typeof readTopology>, programs: Program[], public params: Parameters, private raw: boolean) {
        this.names = topology.names; this.generator = new Minstd(params.seed); this.processes = programs.map(p => new Process(p, this.names.length));
        this.channels = topology.channels.map(c => new Channel(c, this.names.length)); this.channelTable = this.names.map(() => []);
        for (const c of this.channels) this.channelTable[c.source][c.destination] = c;
        this.initialTotal = this.processes.reduce((sum, p) => sum + p.initial, 0);
        for (const item of expandScheduled(programs, params.end)) this.enqueue(item);
    }
    private enqueue(item: Scheduled | { kind: 'arrival'; time: number; process: number; packet: Packet }): void { this.queue.push({ ...item, serial: ++this.serial }); }
    run(): this {
        while (this.queue.length) {
            this.queue.sort((a, b) => a.time - b.time || a.process - b.process || a.serial - b.serial);
            const item = this.queue.shift()!; if (item.time > this.params.end) break; this.time = item.time;
            if (item.kind === 'arrival') this.arrive(item.packet); else this.execute(this.processes[item.process], item.action);
        }
        return this;
    }
    private event(p: Process, type: EventType, details: EventDetails = {}): SimEvent {
        advance(p, type === 'RECV' ? details.copy!.message.event! : null);
        const event: SimEvent = { ...details, type, number: this.events.length + 1, process: p.index, local: p.events.length + 1, time: this.time, L: p.L, V: p.V.slice(), balance: p.balance };
        p.events.push(event); p.counts[type]++; p.minimum = Math.min(p.minimum, p.balance); this.events.push(event); this.timeline.push({ kind: 'event', event }); return event;
    }
    private dispatch(packet: Packet): void {
        this.channelTable[packet.source][packet.destination].dispatch(packet, this.time, this.generator);
        this.enqueue({ kind: 'arrival', time: packet.arrival, process: packet.destination, packet });
    }
    private send(p: Process, kind: Message['kind'], tag: string, amount: number, destination: number | null = null): void {
        const message: Message = { id: this.messages.length + 1, source: p.index, destination, kind, tag, amount, stamp: kind === 'BCAST' ? p.B.slice() : [], copies: [] };
        this.messages.push(message); message.event = this.event(p, kind === 'BCAST' ? 'BCAST' : 'SEND', { message });
        const destinations = kind === 'BCAST' ? this.processes.filter(q => q.index !== p.index).map(q => q.index) : [destination!];
        for (const target of destinations) {
            const copy: Copy = { ...packetFields(p.index, target), kind: 'copy', order: this.copies.length, message, received: null, delivery: null, causalWait: false, missing: [] };
            this.copies.push(copy); message.copies.push(copy); this.dispatch(copy);
        }
    }
    private execute(p: Process, action: Action, sender: number | null = null): void {
        if (action.type === 'LOCAL') this.event(p, 'LOCAL', { label: action.label });
        else if (action.type === 'SNAPSHOT') this.initiate(p, action.name);
        else if (action.type === 'BROADCAST') { p.B[p.index]++; this.send(p, 'BCAST', action.tag, 0); }
        else {
            const destination = action.destination === 'SENDER' ? sender! : action.destination;
            if (action.type === 'SEND') this.send(p, 'P2P', action.tag, 0, destination);
            else if (action.amount > p.balance) this.event(p, 'NOFUNDS', { destination, amount: action.amount });
            else { p.balance -= action.amount; p.sent += action.amount; this.send(p, 'P2P', 'transfer', action.amount, destination); }
        }
    }
    private arrive(packet: Packet): void {
        const p = this.processes[packet.destination], source = packet.source;
        if (this.raw) this.accept(packet);
        else if (packet.sequence !== p.next[source]) { packet.fifoWait = true; packet.place = 'fifo'; p.reorder[source].set(packet.sequence, packet); this.channelTable[source][p.index].buffered++; }
        else {
            this.accept(packet);
            while (p.reorder[source].has(p.next[source])) { const next = p.reorder[source].get(p.next[source])!; p.reorder[source].delete(p.next[source]); this.accept(next); }
        }
        let held = p.hold.length; for (const buffer of p.reorder) held += buffer.size; p.maxHeld = Math.max(p.maxHeld, held);
    }
    private accept(packet: Packet): void {
        const p = this.processes[packet.destination]; p.next[packet.source]++; packet.place = null;
        if (packet.kind === 'marker') { this.marker(packet); return; }
        for (const s of this.snapshots) if (s.records[p.index] !== null && s.accepted[packet.source][p.index] === null) s.channels[packet.source][p.index].push(packet);
        if (packet.message.kind === 'P2P') this.deliver(packet);
        else if (this.raw || deliverable(packet, p.B)) {
            this.deliver(packet);
            if (!this.raw) for (;;) { const index = p.hold.findIndex(c => deliverable(c, p.B)); if (index < 0) break; const [copy] = p.hold.splice(index, 1); this.deliver(copy); }
        } else { packet.causalWait = true; packet.missing = missingProcesses(packet, p.B); packet.place = 'causal'; p.hold.push(packet); }
    }
    private deliver(copy: Copy): void {
        const p = this.processes[copy.destination]; if (copy.message.kind === 'BCAST') p.B[copy.source]++;
        p.balance += copy.message.amount; p.received += copy.message.amount; copy.delivery = this.time; copy.place = null;
        copy.received = this.event(p, 'RECV', { copy, message: copy.message }); p.deliveries.push(copy);
        for (const rule of p.reactions) if (rule.tag === copy.message.tag) this.execute(p, rule.action, copy.source);
    }
    private initiate(p: Process, name: string): void {
        let s = this.snapshotByName.get(name); if (s === undefined) { s = new Snapshot(name, this.time, this.names.length); this.snapshots.push(s); this.snapshotByName.set(name, s); }
        if (s.records[p.index] !== null) s.ignored.push({ process: p.index, time: this.time }); else this.record(p, s, 'initiate');
    }
    private record(p: Process, s: Snapshot, reason: string): void {
        this.timeline.push({ kind: 'record', record: s.record(p, this.time, reason) });
        for (let destination = 0; destination < this.names.length; destination++) if (destination !== p.index) {
            s.dispatched[p.index][destination] = this.time; this.dispatch({ ...packetFields(p.index, destination), kind: 'marker', snapshot: s });
        }
    }
    private marker(packet: Marker): void {
        const s = packet.snapshot, p = this.processes[packet.destination]; if (s.records[p.index] === null) this.record(p, s, `marker ${this.names[packet.source]}`);
        s.accepted[packet.source][p.index] = this.time; if (--s.remaining === 0) s.completed = this.time;
    }
}
const yes = (value: boolean): string => value ? 'yes' : 'no';
const messageName = (m: Message): string => `m${m.id}`;
const eventName = (e: SimEvent, names: string[]): string => `${names[e.process]}.${e.local}`;
const copyName = (c: Copy, names: string[]): string => `${messageName(c.message)}->${names[c.destination]}`;
const nameList = (indices: number[], names: string[]): string => indices.map(i => names[i]).join(',');
function traceReport(s: Simulation): string[] {
    const n = s.names, lines: string[] = [];
    for (const e of s.events) {
        let details: string;
        if (e.type === 'LOCAL') details = e.label!;
        else if (e.type === 'NOFUNDS') details = `to ${n[e.destination!]} amount ${e.amount} balance ${e.balance}`;
        else { const m = e.message!; details = e.type === 'BCAST' ? `${messageName(m)} tag ${m.tag}` : `${messageName(m)} ${e.type === 'SEND' ? 'to ' + n[m.destination!] : 'from ' + n[m.source]} tag ${m.tag}`;
            if (e.type !== 'BCAST' && m.tag === 'transfer') details += ` amount ${m.amount} balance ${e.balance}`; }
        lines.push(`${e.number} t=${e.time} ${eventName(e, n)} ${e.type} ${details} L=${e.L} V=${vector(e.V)}`);
    }
    const delivered = s.copies.filter(c => c.received !== null).length;
    lines.push(`SUMMARY events ${s.events.length} messages ${s.messages.length} copies ${s.copies.length} delivered ${delivered} undelivered ${s.copies.length - delivered} draws ${s.generator.draws}`);
    for (const p of s.processes) lines.push(`FINAL ${n[p.index]} events ${p.events.length} L=${p.L} V=${vector(p.V)} B=${vector(p.B)} balance ${p.balance} in ${p.received} out ${p.sent} refused ${p.counts.NOFUNDS} min ${p.minimum}`);
    for (const p of s.processes) lines.push(`COUNTS ${n[p.index]} local ${p.counts.LOCAL} nofunds ${p.counts.NOFUNDS} send ${p.counts.SEND} bcast ${p.counts.BCAST} recv ${p.counts.RECV}`); return lines;
}
const broadcastOrder = (p: Process): number[] => p.events.filter(e => e.type === 'BCAST' || e.type === 'RECV' && e.message!.kind === 'BCAST').map(e => e.message!.id);
function deliveriesReport(s: Simulation): string[] {
    const n = s.names, lines: string[] = [];
    for (const p of s.processes) {
        lines.push(`PROCESS ${n[p.index]}`); const counts = { direct: 0, fifo: 0, causal: 0, both: 0 }; let waiting = 0, maximum = 0;
        p.deliveries.forEach((c, i) => {
            const m = c.message, wait = c.delivery! - c.arrival; waiting += wait; maximum = Math.max(maximum, wait);
            counts[c.causalWait ? c.fifoWait ? 'both' : 'causal' : c.fifoWait ? 'fifo' : 'direct']++;
            const mode = c.causalWait ? `${c.fifoWait ? 'fifo+causal' : 'causal'} ${nameList(c.missing, n)}` : c.fifoWait ? 'fifo' : 'direct';
            lines.push(`${i + 1} ${messageName(m)} from ${n[c.source]} ${m.kind} tag ${m.tag} sent ${m.event!.time} arrived ${c.arrival} delivered ${c.delivery} wait ${wait} ${mode}`);
        });
        const undelivered = s.copies.filter(c => c.destination === p.index && c.received === null);
        for (const c of undelivered) if (c.arrival <= s.params.end) lines.push(`HELD ${messageName(c.message)} from ${n[c.source]} ${c.message.kind} tag ${c.message.tag} sent ${c.message.event!.time} arrived ${c.arrival} ${c.place === 'fifo' ? 'fifo' : 'causal ' + nameList(c.missing, n)}`);
        for (const c of undelivered) if (c.arrival > s.params.end) lines.push(`TRANSIT ${messageName(c.message)} from ${n[c.source]} ${c.message.kind} tag ${c.message.tag} sent ${c.message.event!.time} arrival ${c.arrival}`);
        lines.push(`TOTAL delivered ${p.deliveries.length} direct ${counts.direct} fifo ${counts.fifo} causal ${counts.causal} both ${counts.both} wait ${waiting} max_wait ${maximum} max_held ${p.maxHeld}`);
        const order = broadcastOrder(p); lines.push('BCASTS ' + (order.length ? order.map(id => `m${id}`).join(' ') : 'none'));
    }
    for (const c of s.channels) lines.push(`CHANNEL ${n[c.source]}->${n[c.destination]} ${c.type} ${c.low === c.high ? c.low : `${c.low}-${c.high}`} messages ${c.messages} markers ${c.markers} buffered ${c.buffered} max_delay ${c.maxDelay} entries ${c.entries}`);
    for (const tag of [...new Set(s.copies.map(c => c.message.tag))].sort()) {
        const copies = s.copies.filter(c => c.message.tag === tag); let delivered = 0, latency = 0, maximum = 0;
        for (const c of copies) if (c.received !== null) { delivered++; const value = c.delivery! - c.message.event!.time; latency += value; maximum = Math.max(maximum, value); }
        lines.push(`TAG ${tag} copies ${copies.length} delivered ${delivered} latency ${latency} max ${maximum}`);
    }
    const broadcasts = s.messages.filter(m => m.kind === 'BCAST'), orders = s.processes.map(broadcastOrder);
    for (const m of broadcasts) lines.push(`STABLE ${messageName(m)} ${n[m.source]} tag ${m.tag} sent ${m.event!.time} stable ${m.copies.every(c => c.received !== null) ? Math.max(...m.copies.map(c => c.delivery!)) : 'none'}`);
    let disagreements = 0;
    for (let i = 0; i < broadcasts.length; i++) for (let j = i + 1; j < broadcasts.length; j++) {
        const earlier: number[] = [], later: number[] = [];
        for (let p = 0; p < n.length; p++) { const a = orders[p].indexOf(broadcasts[i].id), b = orders[p].indexOf(broadcasts[j].id); if (a >= 0 && b >= 0) (a < b ? earlier : later).push(p); }
        if (earlier.length && later.length) { disagreements++; lines.push(`DISAGREE ${messageName(broadcasts[i])} ${messageName(broadcasts[j])} ${nameList(earlier, n)} ${nameList(later, n)}`); }
    }
    lines.push(`DISAGREEMENTS ${disagreements}`); return lines;
}
const cutVerdict = (r: ReturnType<typeof inspectCut>, names: string[]): string => r.orphans.length ? 'no ' + r.orphans.map(c => copyName(c, names)).join(' ') : 'yes';
function snapshotDetails(s: Simulation, snapshot: Snapshot) {
    const cut = snapshot.cut(), result = inspectCut(s.processes, s.copies, cut), captured: Copy[] = []; let balances = 0, pending = 0, channels = 0, channelMoney = 0;
    for (const record of snapshot.records) { balances += record!.balance; pending += record!.pending.length; captured.push(...record!.pending); }
    for (const channel of s.channels) {
        const copies = snapshot.channels[channel.source][channel.destination]; channels += copies.length;
        for (const copy of copies) { captured.push(copy); channelMoney += copy.message.amount; }
    }
    captured.sort((a, b) => a.order - b.order);
    return { cut, result, balances, pending, channels, channelMoney, money: balances + channelMoney,
        match: captured.length === result.transit.length && captured.every((c, i) => c === result.transit[i]), vectorVerdict: snapshot.records.every(r => lessEqual(r!.V, cut)) };
}
function snapshotsReport(s: Simulation, raw: Simulation): string[] {
    const n = s.names, lines: string[] = [];
    for (const snapshot of s.snapshots) {
        const d = snapshotDetails(s, snapshot); lines.push(`SNAPSHOT ${snapshot.name} started ${snapshot.started} completed ${snapshot.completed}`);
        for (const record of snapshot.records) {
            const r = record!, pending = r.pending.length ? r.pending.map(c => messageName(c.message)).join(' ') : 'none';
            lines.push(`RECORD ${n[r.process]} t=${r.time} ${r.reason} balance ${r.balance} L=${r.L} V=${vector(r.V)} pending ${pending}`);
        }
        for (const { source: a, destination: b } of s.channels) {
            const copies = snapshot.channels[a][b], state = copies.length ? copies.map(c => messageName(c.message) + (c.message.amount ? `:${c.message.amount}` : '')).join(' ') : 'empty';
            lines.push(`CHANNEL ${n[a]}->${n[b]} marker ${snapshot.dispatched[a][b]} ${snapshot.accepted[a][b]} state ${state}`);
        }
        for (const ignored of snapshot.ignored) lines.push(`IGNORED ${n[ignored.process]} t=${ignored.time}`);
        lines.push(`CUT ${vector(d.cut)} consistent ${cutVerdict(d.result, n)} vector ${yes(d.vectorVerdict)}`, `TRANSIT channels ${d.channels} pending ${d.pending} cut ${d.result.transit.length} match ${yes(d.match)}`,
            `MONEY balances ${d.balances} channels ${d.channelMoney} total ${d.money} initial ${s.initialTotal} conserved ${yes(d.money === s.initialTotal)}`);
    }
    for (const snapshot of raw.snapshots) { const d = snapshotDetails(raw, snapshot); lines.push(`RAW ${snapshot.name} completed ${snapshot.completed} cut ${vector(d.cut)} consistent ${cutVerdict(d.result, n)} money ${d.money} conserved ${yes(d.money === raw.initialTotal)}`); }
    return lines;
}
function rangeNotation(events: SimEvent[], names: string[]): string {
    const parts: string[] = [];
    for (let start = 0; start < events.length;) { let end = start; while (end + 1 < events.length && events[end + 1].process === events[start].process) end++;
        parts.push(eventName(events[start], names) + (start === end ? '' : `-${events[end].local}`)); start = end + 1; } return parts.join(' ');
}
function longestChain(s: Simulation): SimEvent[] {
    let current = s.events[0]; for (const e of s.events) if (e.L > current.L) current = e; const chain = [current];
    while (current.L > 1) {
        current = current.type === 'RECV' && current.copy!.message.event!.L === current.L - 1 ? current.copy!.message.event! : s.processes[current.process].events[current.local - 2]; chain.push(current);
    }
    return chain.reverse();
}
function analysisReport(s: Simulation, raw: Simulation): string[] {
    const { names: n, events, processes, copies, params } = s, lines: string[] = [], graph = eventGraph(processes, events, copies), byName = new Map(events.map(e => [eventName(e, n), e]));
    for (const [a, b] of params.compares) {
        const first = byName.get(a)!, second = byName.get(b)!, r = relation(first.V, second.V); let path = breadthFirst(graph, first.number - 1, second.number - 1), graphRelation = '->';
        if (path === null) { path = breadthFirst(graph, second.number - 1, first.number - 1); graphRelation = path === null ? '||' : '<-'; }
        lines.push(`COMPARE ${a} ${r} ${b} L=${first.L},${second.L} graph ${graphRelation} agree ${yes(r === graphRelation)}`);
        if (path !== null) { const sequence = path.map(i => events[i]); let messages = 0; for (let i = 1; i < sequence.length; i++) if (sequence[i].process !== sequence[i - 1].process) messages++;
            lines.push(`PATH length ${sequence.length} messages ${messages} ${rangeNotation(sequence, n)}`); }
        for (const e of [first, second]) lines.push(`WINDOW ${eventName(e, n)} past ${vector(e.V)} future ${vector(processes.map(p => p.events.filter(f => f.V[e.process] < e.local).length))}`);
    }
    const c = concurrentPairs(events, n.length); lines.push(`CONCURRENCY events ${events.length} pairs ${c.ordered + c.concurrent} ordered ${c.ordered} concurrent ${c.concurrent} same_lamport ${c.sameLamport} inversions ${c.inversions}`);
    for (let i = 0; i < n.length; i++) for (let j = i + 1; j < n.length; j++) lines.push(`PAIR ${n[i]} ${n[j]} ${c.pairs[i][j]}`);
    const chain = longestChain(s); lines.push(`CHAIN length ${chain.length} ${rangeNotation(chain, n)}`);
    const d = deliveryRelations(processes);
    for (const { process: p, first: a, second: b } of d.races) lines.push(`RACE ${n[p]} ${messageName(a.message)} ${n[a.source]} ${messageName(b.message)} ${n[b.source]}`);
    lines.push(`RACES ${d.races.length}`);
    for (const { process: p, first: a, second: b } of d.violations) lines.push(`VIOLATION ${n[p]} ${messageName(a.message)} ${n[a.source]} overtook ${messageName(b.message)} ${n[b.source]}`);
    lines.push(`VIOLATIONS causal ${d.violations.length} fifo ${d.fifo}`); const rd = deliveryRelations(raw.processes);
    lines.push(`RAW events ${raw.events.length} delivered ${raw.copies.filter(c => c.received !== null).length} causal ${rd.violations.length} fifo ${rd.fifo}`);
    for (const cut of params.cuts) {
        const r = inspectCut(processes, copies, cut), status = r.orphans.length ? 'inconsistent orphans ' + r.orphans.map(c => copyName(c, n)).join(' ') : 'consistent';
        lines.push(`CUT ${vector(cut)} ${status} transit ${r.transit.length} money ${r.money} initial ${s.initialTotal}`);
    }
    const cuts = countCuts(processes, params.cutcount, s.initialTotal); lines.push(`CUTCOUNT t=${params.cutcount} events ${vector(cuts.bounds)} product ${cuts.product} consistent ${cuts.consistent}`, `LEVELS ${cuts.levels.join(' ')}`);
    for (const threshold of params.predicates) { const p = predicate(cuts, threshold); lines.push(`PREDICATE transit>=${threshold} cuts ${p.count} possibly ${yes(p.possibly)} definitely ${yes(p.definitely)}`); } return lines;
}
function writeText(characters: string[], position: number, text: string): void { for (let i = 0; i < text.length; i++) characters[position + i] = text[i]; }
function diagramHeader(names: string[], label: string): string {
    const chars: string[] = Array(8 * names.length - 1).fill(' '); writeText(chars, 0, `    ${label}`); names.forEach((name, i) => writeText(chars, 8 * i + 6, name)); return chars.join('').trimEnd();
}
function diagramLine(entry: Timeline, names: string[], value: number): string {
    const chars: string[] = Array(8 * names.length - 1).fill(' '), columns = names.map((_, i) => 8 * i + 6);
    writeText(chars, 0, String(value).padStart(5)); for (const column of columns) chars[column] = '|';
    if (entry.kind === 'record') { const r = entry.record, own = columns[r.process]; chars[own] = '#'; writeText(chars, own + 1, r.snapshot.name); }
    else {
        const e = entry.event, own = columns[e.process], symbols: Record<EventType, string> = { LOCAL: '*', NOFUNDS: 'x', SEND: 'S', BCAST: 'B', RECV: 'R' }; chars[own] = symbols[e.type];
        if (e.type === 'SEND' || e.type === 'BCAST') writeText(chars, own + 1, messageName(e.message!));
        if (e.type === 'RECV') { const source = columns[e.copy!.source], a = Math.min(source, own), z = Math.max(source, own);
            for (let p = a + 1; p < z; p++) chars[p] = columns.includes(p) ? '+' : '-'; chars[source < own ? z - 1 : a + 1] = source < own ? '>' : '<'; writeText(chars, a + 2, messageName(e.message!)); }
    }
    return chars.join('').trimEnd();
}
function diagramReport(s: Simulation): string[] {
    const lines = [diagramHeader(s.names, 't')]; for (const entry of s.timeline) lines.push(diagramLine(entry, s.names, entry.kind === 'event' ? entry.event.time : entry.record.time));
    lines.push(diagramHeader(s.names, 'L')); for (const e of s.events.toSorted((a, b) => a.L - b.L || a.process - b.process)) lines.push(diagramLine({ kind: 'event', event: e }, s.names, e.L)); return lines;
}
function main(): void {
    const topology = readTopology(), programs = readPrograms(topology.names), params = readParameters(), s = new Simulation(topology, programs, params, false).run(), raw = new Simulation(topology, programs, params, true).run();
    const reports: [string, string[]][] = [['trace.txt', traceReport(s)], ['deliveries.txt', deliveriesReport(s)], ['snapshots.txt', snapshotsReport(s, raw)], ['analysis.txt', analysisReport(s, raw)], ['diagram.txt', diagramReport(s)]];
    mkdirSync('output', { recursive: true }); for (const [name, lines] of reports) writeFileSync('output/' + name, lines.join('\n') + (lines.length ? '\n' : ''), 'ascii');
}
main();
