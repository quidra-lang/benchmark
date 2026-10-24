import { readFileSync } from 'node:fs';

type Vector = number[];
type Process = { id: number; max: Vector; alloc: Vector; born: number };
type Waiting = { id: number; v: Vector; since: number };
type Event = { time: number; kind: string; id: number; v: Vector; wait: number };
type State = { total: Vector; available: Vector; processes: Process[]; queue: Waiting[]; history: Event[] };
type Check = { sequence: number[]; remaining: number[] };
type Decision = { kind: string; reason: string; sequence: number[] };
const output: string[] = [];
const emit = (s: string): void => { output.push(s); };
const vec = (v: Vector): string => `(${v.join(',')})`;
const names = (ids: number[]): string => ids.map(id => `P${id}`).join(' ');
const sum = (v: Vector): number => v.reduce((a, b) => a + b, 0);
const plus = (a: Vector, b: Vector): Vector => a.map((v, i) => v + b[i]);
const minus = (a: Vector, b: Vector): Vector => a.map((v, i) => v - b[i]);
const le = (a: Vector, b: Vector): boolean => a.every((v, i) => v <= b[i]);
const zero = (v: Vector): boolean => v.every(x => x === 0);
const copy = (s: State): State => structuredClone(s);
let state: State = { total: [], available: [], processes: [], queue: [], history: [] };
let mode = 'AVOID', policy = 'ALLOC', trace = false, auto = false, time = 0;
const snapshots = new Map<string, State>();
const ordered = (): Process[] => state.processes.slice().sort((a, b) => a.id - b.id);
const need = (p: Process): Vector => minus(p.max, p.alloc);
const waiting = (id: number): Waiting | undefined => state.queue.find(q => q.id === id);
const record = (kind: string, id: number, v: Vector, wait = 0): void => {
    state.history.push({ time, kind, id, v: v.slice(), wait });
};
function check(detect = false, verbose = false): Check {
    let work = state.available.slice();
    const idle = detect ? ordered().filter(p => zero(p.alloc)).map(p => p.id) : [];
    let remaining = ordered().filter(p => !idle.includes(p.id));
    const sequence: number[] = [];
    const tag = detect ? 'detect' : 'safety';
    if (verbose) emit(`[${tag}] start work=${vec(work)}${idle.length ? ' idle ' + names(idle) : ''}`);
    while (true) {
        const p = remaining.find(p => le(detect ? (waiting(p.id)?.v ?? state.total.map(() => 0)) : need(p), work));
        if (!p) break;
        work = plus(work, p.alloc);
        sequence.push(p.id);
        remaining = remaining.filter(q => q.id !== p.id);
        if (verbose) emit(`[${tag}] P${p.id} can finish, work=${vec(work)}`);
    }
    const ids = remaining.map(p => p.id);
    if (verbose && ids.length) emit(`[${tag}] stuck work=${vec(work)} remaining ${names(ids)}`);
    return { sequence, remaining: ids };
}
function decide(p: Process, v: Vector, reject: boolean, verbose: boolean): Decision {
    let reason = '';
    if (reject) {
        if (waiting(p.id)) reason = `process P${p.id} is blocked`;
        else if (zero(v)) reason = 'zero vector';
        else if (!le(v, need(p))) reason = 'request exceeds need';
        else if (mode === 'ORDER' && !zero(p.alloc)) {
            const last = p.alloc.reduce((last, x, i) => x > 0 ? i : last, -1);
            if (v.some((x, i) => x > 0 && i <= last)) reason = 'resource order violation';
        }
    }
    if (reason) return { kind: 'rejected', reason, sequence: [] };
    if (!le(v, state.available)) return { kind: 'blocked', reason: 'insufficient resources', sequence: [] };
    let sequence: number[] = [];
    if (mode === 'AVOID') {
        p.alloc = plus(p.alloc, v);
        state.available = minus(state.available, v);
        const result = check(false, verbose);
        p.alloc = minus(p.alloc, v);
        state.available = plus(state.available, v);
        sequence = result.sequence;
        if (result.remaining.length) return { kind: 'blocked', reason: 'unsafe state', sequence };
    }
    return { kind: 'granted', reason: '', sequence };
}
function allocate(p: Process, v: Vector): void {
    p.alloc = plus(p.alloc, v);
    state.available = minus(state.available, v);
}
function retry(): void {
    const pending = state.queue.slice();
    for (const q of pending) {
        const p = state.processes.find(p => p.id === q.id)!;
        if (decide(p, q.v, false, trace).kind === 'granted') {
            allocate(p, q.v);
            state.queue = state.queue.filter(w => w.id !== q.id);
            emit(`unblocked P${q.id} ${vec(q.v)}`);
            record('unblocked', q.id, q.v, time - q.since);
        }
    }
}
function terminate(p: Process, kind: string, retries = true): void {
    state.available = plus(state.available, p.alloc);
    state.processes = state.processes.filter(q => q.id !== p.id);
    state.queue = state.queue.filter(q => q.id !== p.id);
    emit(`${kind} P${p.id} released ${vec(p.alloc)}`);
    record(kind, p.id, p.alloc);
    if (retries) retry();
}
function cycles(graph: Map<number, { to: number; label: number[] }[]>, resource: boolean): void {
    const found: number[][] = [];
    function visit(start: number, p: number, path: number[], seen: number[]): void {
        for (const edge of graph.get(p) ?? []) {
            const next = resource ? path.concat(edge.label[0], edge.to) : path.concat(edge.to);
            if (edge.to === start) found.push(next);
            else if (edge.to > start && !seen.includes(edge.to)) visit(start, edge.to, next, seen.concat(edge.to));
        }
    }
    for (const p of ordered()) visit(p.id, p.id, [p.id], [p.id]);
    found.sort((a, b) => {
        for (let i = 0; i < Math.min(a.length, b.length); i++) if (a[i] !== b[i]) return a[i] - b[i];
        return a.length - b.length;
    });
    for (const c of found) emit('cycle: ' + c.map((n, i) => resource && i % 2 ? String.fromCharCode(65 + n) : `P${n}`).join(' -> '));
    if (!found.length) emit('no cycles');
}
function execute(tokens: string[]): void {
    const [command, ...args] = tokens;
    const id = Number(args[0]);
    const p = state.processes.find(p => p.id === id);
    const hasId = ['PROCESS', 'CLAIM', 'REQUEST', 'WHATIF', 'RELEASE'].includes(command);
    const v = args.slice(hasId ? 1 : 0).map(Number);
    const error = (message: string): void => emit('error: ' + message);
    if (['PROCESS', 'CLAIM', 'ADD', 'REMOVE', 'REQUEST', 'WHATIF', 'RELEASE'].includes(command) && v.length !== state.total.length) {
        error('wrong vector length'); return;
    }
    if (['CLAIM', 'REQUEST', 'WHATIF', 'RELEASE', 'FINISH', 'ABORT', 'CANCEL', 'MAXGRANT'].includes(command) && !p) {
        error(`unknown process P${id}`); return;
    }
    switch (command) {
        case 'RESOURCES':
            state = { total: v.slice(), available: v.slice(), processes: [], queue: [], history: [] };
            emit('resources ' + vec(v)); break;
        case 'MODE': mode = args[0]; emit('mode ' + mode); break;
        case 'POLICY': policy = args[0]; emit('policy ' + policy); break;
        case 'TRACE': trace = args[0] === 'ON'; emit('trace ' + args[0]); break;
        case 'AUTODETECT': auto = args[0] === 'ON'; emit('autodetect ' + args[0]); break;
        case 'PROCESS':
            if (p) error(`duplicate process P${id}`);
            else if (!le(v, state.total)) error('max exceeds total');
            else {
                state.processes.push({ id, max: v.slice(), alloc: v.map(() => 0), born: time });
                emit(`process P${id} max ${vec(v)}`);
            }
            break;
        case 'CLAIM': {
            if (waiting(id)) { error(`process P${id} is blocked`); break; }
            if (!le(p!.alloc, v)) { error('claim below allocation'); break; }
            if (!le(v, state.total)) { error('max exceeds total'); break; }
            const old = p!.max;
            p!.max = v.slice();
            if (mode === 'AVOID' && check(false, trace).remaining.length) {
                p!.max = old; error('claim makes state unsafe'); break;
            }
            emit(`claim P${id} max ${vec(v)}`); retry(); break;
        }
        case 'ADD':
            if (zero(v)) { error('zero vector'); break; }
            state.total = plus(state.total, v); state.available = plus(state.available, v);
            emit(`added ${vec(v)} total ${vec(state.total)}`); retry(); break;
        case 'REMOVE': {
            if (zero(v)) { error('zero vector'); break; }
            if (!le(v, state.available)) { error('remove exceeds available'); break; }
            const total = minus(state.total, v);
            if (total.some(x => x === 0)) { error('total must stay positive'); break; }
            if (state.processes.some(p => !le(p.max, total))) { error('max exceeds total'); break; }
            state.available = minus(state.available, v);
            if (mode === 'AVOID' && check(false, trace).remaining.length) {
                state.available = plus(state.available, v); error('removal makes state unsafe'); break;
            }
            state.total = total; emit(`removed ${vec(v)} total ${vec(total)}`); break;
        }
        case 'REQUEST': case 'WHATIF': {
            const d = decide(p!, v, true, trace);
            if (command === 'WHATIF') {
                emit(`whatif P${id} ${vec(v)}: ` + (d.kind === 'granted' ? 'granted' + (mode === 'AVOID' ? ', safe sequence ' + names(d.sequence) : '') : `${d.kind} (${d.reason})`));
            } else if (d.kind === 'rejected') error(d.reason);
            else if (d.kind === 'granted') {
                allocate(p!, v); emit(`granted P${id} ${vec(v)}`); record('granted', id, v);
            } else {
                state.queue.push({ id, v: v.slice(), since: time });
                emit(`blocked P${id} ${vec(v)}: ${d.reason}`); record('blocked', id, v);
                if (auto) {
                    const dead = check(true, trace).remaining;
                    if (dead.length) emit('deadlock detected: ' + names(dead));
                }
            }
            break;
        }
        case 'RELEASE':
            if (waiting(id)) error(`process P${id} is blocked`);
            else if (zero(v)) error('zero vector');
            else if (!le(v, p!.alloc)) error('release exceeds allocation');
            else {
                p!.alloc = minus(p!.alloc, v); state.available = plus(state.available, v);
                emit(`released P${id} ${vec(v)}`); record('released', id, v); retry();
            }
            break;
        case 'FINISH': case 'ABORT':
            if (command === 'FINISH' && waiting(id)) error(`process P${id} is blocked`);
            else terminate(p!, command === 'FINISH' ? 'finished' : 'aborted');
            break;
        case 'CANCEL': {
            const q = waiting(id);
            if (!q) error(`process P${id} is not blocked`);
            else {
                state.queue = state.queue.filter(q => q.id !== id);
                emit(`cancelled P${id} ${vec(q.v)}`); record('cancelled', id, q.v);
            }
            break;
        }
        case 'MAXGRANT': {
            if (waiting(id)) { error(`process P${id} is blocked`); break; }
            const result = need(p!).map((n, i) => {
                let low = 0, high = n;
                while (low < high) {
                    const mid = Math.floor((low + high + 1) / 2), q = state.total.map(() => 0);
                    q[i] = mid;
                    if (decide(p!, q, true, false).kind === 'granted') low = mid; else high = mid - 1;
                }
                return low;
            });
            emit(`maxgrant P${id}: ${vec(result)}`); break;
        }
        case 'SAFE': {
            if (!state.processes.length) { emit('safe: no processes'); break; }
            const c = check(false, trace);
            emit(c.remaining.length ? `unsafe: ${names(c.remaining)} cannot finish` : 'safe: ' + names(c.sequence)); break;
        }
        case 'SEQUENCES': {
            if (!state.processes.length) { emit('safe sequences: no processes'); break; }
            let count = 0;
            const first: number[][] = [];
            function walk(rest: Process[], work: Vector, seq: number[]): void {
                if (!rest.length) { count++; if (first.length < id) first.push(seq); return; }
                for (const q of rest) if (le(need(q), work)) walk(rest.filter(p => p !== q), plus(work, q.alloc), seq.concat(q.id));
            }
            walk(ordered(), state.available, []);
            emit('safe sequences: ' + count); first.forEach(s => emit(names(s))); break;
        }
        case 'DEFICIT': {
            const original = state.available.slice();
            const deficits = state.total.map((_, i) => {
                let low = 0, high = state.processes.reduce((s, p) => s + need(p)[i], 0);
                state.available = original.slice(); state.available[i] += high;
                if (check().remaining.length) return '-';
                while (low < high) {
                    const mid = Math.floor((low + high) / 2);
                    state.available = original.slice(); state.available[i] += mid;
                    if (check().remaining.length) low = mid + 1; else high = mid;
                }
                return String(low);
            });
            state.available = original; emit(`deficit: (${deficits.join(',')})`); break;
        }
        case 'STATE': {
            const widths = state.total.map(t => String(t).length);
            const rowName = widths.map((w, i) => String.fromCharCode(65 + i).padStart(w)).join(' ');
            const cols = [10, 3, 4, 7].map(w => Math.max(w, rowName.length));
            const table = (v: Vector): string => v.map((x, i) => String(x).padStart(widths[i])).join(' ');
            const row = (heading: string, values: string[]): void => emit((heading.padEnd(9) + cols.map((w, i) => '  ' + (values[i] ?? '').padEnd(w)).join('')).trimEnd());
            row('Process', ['Allocation', 'Max', 'Need', 'Request']); row('', cols.map(() => rowName));
            ordered().forEach(p => row(`P${p.id}`, [p.alloc, p.max, need(p), waiting(p.id)?.v ?? state.total.map(() => 0)].map(table)));
            row('Available', [table(state.available)]); row('Total', [table(state.total)]);
            emit('blocked queue: ' + (state.queue.length ? state.queue.map(q => `P${q.id} ${vec(q.v)} since t=${q.since}`).join(', ') : 'empty')); break;
        }
        case 'STATS': {
            state.total.forEach((t, i) => {
                const u = t - state.available[i], percent = Math.floor(u * 1000 / t);
                emit(`${String.fromCharCode(65 + i)}: allocated ${u}/${t} (${Math.floor(percent / 10)}.${percent % 10}%), requested ${state.queue.reduce((s, q) => s + q.v[i], 0)}`);
            });
            const kinds = ['granted', 'blocked', 'unblocked', 'released', 'finished', 'aborted', 'cancelled'];
            emit('events: ' + kinds.map(k => `${k} ${state.history.filter(e => e.kind === k).length}`).join(', '));
            const waits = state.history.filter(e => e.kind === 'unblocked'), total = waits.reduce((s, e) => s + e.wait, 0);
            const average = waits.length ? Math.floor(total * 100 / waits.length) : 0;
            emit(waits.length ? `waits: ${waits.length} unblocked, total ${total}, average ${Math.floor(average / 100)}.${String(average % 100).padStart(2, '0')}` : 'waits: none'); break;
        }
        case 'DETECT': {
            const dead = check(true, trace).remaining;
            emit(dead.length ? 'deadlocked: ' + names(dead) : 'no deadlock'); break;
        }
        case 'VICTIMS': {
            const dead = check(true).remaining;
            if (!dead.length) { emit('no deadlock'); break; }
            const candidates: number[][] = [];
            for (let mask = 1; mask < 2 ** dead.length; mask++) candidates.push(dead.filter((_, i) => mask & (1 << i)));
            const cost = (ids: number[]): number => ids.reduce((s, id) => s + sum(state.processes.find(p => p.id === id)!.alloc), 0);
            candidates.sort((a, b) => {
                if (a.length !== b.length) return a.length - b.length;
                if (cost(a) !== cost(b)) return cost(a) - cost(b);
                for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] - b[i];
                return 0;
            });
            const saved = copy(state);
            for (const ids of candidates) {
                state = copy(saved);
                for (const id of ids) {
                    const p = state.processes.find(p => p.id === id)!;
                    state.available = plus(state.available, p.alloc);
                }
                state.processes = state.processes.filter(p => !ids.includes(p.id));
                state.queue = state.queue.filter(q => !ids.includes(q.id));
                if (!check(true).remaining.length) { emit('victims: ' + names(ids)); break; }
            }
            state = saved; break;
        }
        case 'RECOVER': {
            let count = 0;
            if (args[0] === 'ALL') {
                const dead = check(true, trace).remaining;
                for (const id of dead) { terminate(state.processes.find(p => p.id === id)!, 'aborted', false); count++; }
                if (count) retry();
            } else {
                while (true) {
                    const dead = check(true, trace).remaining;
                    if (!dead.length) break;
                    const choices = ordered().filter(p => dead.includes(p.id));
                    choices.sort((a, b) => policy === 'YOUNGEST' ? b.born - a.born : (policy === 'ALLOC' ? sum(a.alloc) - sum(b.alloc) : sum(need(b)) - sum(need(a))) || b.id - a.id);
                    terminate(choices[0], 'aborted'); count++;
                }
            }
            emit(count ? `recovered: ${count} aborted` : 'no deadlock'); break;
        }
        case 'WAITGRAPH': case 'GRAPH': {
            const resource = command === 'GRAPH';
            if (resource && state.total.some(x => x !== 1)) { error('not single-instance'); break; }
            const graph = new Map<number, { to: number; label: number[] }[]>();
            if (resource) {
                state.total.forEach((_, i) => ordered().forEach(p => { if (p.alloc[i]) emit(`assign ${String.fromCharCode(65 + i)} -> P${p.id}`); }));
                for (const p of ordered()) {
                    const q = waiting(p.id);
                    if (!q) continue;
                    q.v.forEach((v, i) => {
                        if (!v) return;
                        emit(`request P${p.id} -> ${String.fromCharCode(65 + i)}`);
                        for (const holder of ordered()) if (holder.alloc[i]) {
                            const edges = graph.get(p.id) ?? []; edges.push({ to: holder.id, label: [i] }); graph.set(p.id, edges);
                        }
                    });
                }
                for (const p of ordered()) need(p).forEach((v, i) => {
                    if (v && !(waiting(p.id)?.v[i] ?? 0)) emit(`claim P${p.id} -> ${String.fromCharCode(65 + i)}`);
                });
            } else {
                let count = 0;
                for (const p of ordered()) {
                    const q = waiting(p.id); if (!q) continue;
                    for (const other of ordered()) if (p !== other) {
                        const label = q.v.flatMap((v, i) => v > state.available[i] && other.alloc[i] > 0 ? [i] : []);
                        if (!label.length) continue;
                        emit(`P${p.id} -> P${other.id} on ${label.map(i => String.fromCharCode(65 + i)).join(',')}`); count++;
                        const edges = graph.get(p.id) ?? []; edges.push({ to: other.id, label }); graph.set(p.id, edges);
                    }
                }
                if (!count) emit('no wait edges');
            }
            cycles(graph, resource); break;
        }
        case 'HISTORY': {
            const events = state.history.filter(e => !args.length || (args[0] === String(e.id)) || args[0] === e.kind);
            events.forEach(e => emit(`t=${e.time} ${e.kind} P${e.id} ${vec(e.v)}${e.kind === 'unblocked' ? ' waited ' + e.wait : ''}`));
            if (!events.length) emit('no events'); break;
        }
        case 'SNAPSHOT': snapshots.set(args[0], copy(state)); emit('saved ' + args[0]); break;
        case 'RESTORE': {
            const saved = snapshots.get(args[0]);
            if (!saved) error('unknown snapshot ' + args[0]); else { state = copy(saved); emit('restored ' + args[0]); }
            break;
        }
    }
}
const lines = readFileSync(0, 'utf8').trimEnd().split('\n');
for (time = 1; time <= Number(lines[0]); time++) execute(lines[time].trimEnd().split(' '));
process.stdout.write(output.join('\n') + '\n');
