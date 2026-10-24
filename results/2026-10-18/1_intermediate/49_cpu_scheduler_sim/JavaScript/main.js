import { readFileSync } from 'node:fs';
const algorithms = ['FCFS', 'SJF', 'SRTF', 'RR', 'PRIORITY', 'HRRN', 'EDF', 'LOTTERY', 'MLFQ'];
const parameterKeys = ['cs', 'q', 'k', 's', 'seed'];
const ranges = {
    cs: [0, 5], q: [1, 20], k: [1, 50], s: [0, 500], seed: [1, 2147483646]
};
const used = {
    FCFS: ['cs'], SJF: ['cs'], SRTF: ['cs'], RR: ['cs', 'q'], PRIORITY: ['cs', 'k'], HRRN: ['cs'], EDF: ['cs'], LOTTERY: ['cs',
    'q', 'seed'], MLFQ: ['cs', 's']
};
const metricNames = ['turnaround', 'waiting', 'response'];
const errorIf = (bad, message) => {
    if (bad) throw new Error(message);
};
const truncated = (u, v) => {
    const c = Math.floor(100 * u / v);
    return `${Math.floor(c / 100)}.${String(c % 100).padStart(2, '0')}`;
};
const sum = (xs) => xs.reduce((a, b) => a + b, 0);
function parameters(words, algo = '', preset = '') {
    const p = {
        cs: 0, q: 4, k: 5, s: 0, seed: 1
    }, seen = new Set(preset ? [preset] : []);
    for (const word of words) {
        const [key, text] = word.split('='), v = Number(text);
        errorIf(!parameterKeys.includes(key), `unknown key ${key}`);
        errorIf(!!algo && !used[algo].includes(key), `key ${key} not allowed for ${algo}`);
        errorIf(seen.has(key), `duplicate key ${key}`);
        errorIf(v < ranges[key][0] || v > ranges[key][1], `invalid ${key}`);
        seen.add(key);
        p[key] = v;
    }
    return p;
}
const notation = (p, algo = '') => (algo ? used[algo] : parameterKeys).map(k => `${k}=${p[k]}`).join(' ');
const metrics = (j) => {
    const turnaround = j.finish - j.process.arrival;
    return [turnaround, turnaround - sum(j.process.bursts), j.start - j.process.arrival];
};
function simulate(processes, algo, p, snapshotTime = -1) {
    const jobs = processes.map(process => ({
        process, state: 'FUTURE', burst: 0, left: process.bursts[0], effective: process.priority, wait: 0, level: 0, usage: 0,
        enqueue: 0, start: -1, finish: -1, records: [], timeline: ''
    }));
    const r = {
        jobs, labels: [], modes: [], events: [], counts: {
        }, queueLengths: [], switches: 0, end: 0, busy: 0, switching: 0, idle: 0, totals: [0, 0, 0], met: 0, missed: 0, snapshot: []
    };
    let queues = [[], [], []], cpu = 'IDLE', current = -1, previous = -1, switchLeft = 0, run = 0, time = 0, random = p.seed;
    const allReady = () => queues.flat();
    const event = (name, detail = '') => {
        r.events.push(`${time} ${name}${detail ? ' ' + detail : ''}`);
        r.counts[name] = (r.counts[name] ?? 0) + 1;
    };
    const enqueue = (i) => {
        const j = jobs[i];
        j.state = 'READY';
        j.enqueue = time;
        queues[algo === 'MLFQ' ? j.level : 0].push(i);
    };
    const fresh = (i) => {
        const j = jobs[i];
        j.records.push({
            length: j.left, ready: time, start: -1, end: -1, slices: 0
        });
        enqueue(i);
    };
    const start = () => {
        const j = jobs[current];
        cpu = 'RUN';
        j.state = 'RUN';
        run = 0;
        if (j.start < 0) j.start = time;
        const record = j.records[j.records.length - 1];
        if (record.start < 0) record.start = time;
    };
    const absolute = (i) => jobs[i].process.deadline < 0 ? Infinity : jobs[i].process.arrival + jobs[i].process.deadline;
    const snapshot = () => {
        const out = [cpu === 'IDLE' ? 'CPU IDLE' : `CPU ${cpu} ${jobs[current].process.id}`];
        for (let q = 0; q < (algo === 'MLFQ' ? 3 : 1); ++q) out.push(`QUEUE${algo === 'MLFQ' ? q : ''} ${queues[q].map(i => jobs[i].process.id).join(' ') || 'none'}`);
        for (const j of jobs) {
            let line = `${j.process.id} ${j.state}`;
            if (j.state === 'FUTURE') line += ` at=${j.process.arrival}`;
            else if (j.state === 'DONE') line += ` at=${j.finish}`;
            else {
                line += ` burst=${j.burst + 1} left=${j.left}`;
                if (algo === 'PRIORITY') line += ` prio=${j.effective}`;
                if (algo === 'MLFQ') line += ` level=${j.level} used=${j.usage}`;
            }
            out.push(line);
        }
        return out;
    };
    for (time = 0; ; ++time) {
        if (algo === 'PRIORITY') for (const i of queues[0]) {
            const j = jobs[i];
            if (++j.wait === p.k) {
                j.wait = 0;
                if (j.effective) event('AGE', `${j.process.id} ${--j.effective}`);
            }
        }
        jobs.forEach((j, i) => {
            if (j.state === 'IO' && !j.left) {
                ++j.burst; j.left = j.process.bursts[j.burst]; fresh(i); event('IODONE', j.process.id);
            }
        });
        jobs.forEach((j, i) => {
            if (j.state === 'FUTURE' && j.process.arrival === time) {
                fresh(i); event('ARRIVE', j.process.id);
            }
        });
        if (cpu === 'SWITCH' && !switchLeft) {
            start();
            event('START', jobs[current].process.id);
        }
        else if (cpu === 'RUN') {
            const j = jobs[current];
            if (!j.left && j.burst === j.process.bursts.length - 1) {
                j.state = 'DONE';
                j.finish = time;
                event('DONE', j.process.id);
                cpu = 'IDLE';
            }
            else {
                let demoted = false;
                if (algo === 'MLFQ' && j.level < 2 && j.usage === [4, 8][j.level]) {
                    ++j.level;
                    j.usage = 0;
                    demoted = true;
                    event('DEMOTE', `${j.process.id} ${j.level}`);
                }
                if (!j.left) {
                    ++j.burst;
                    j.left = j.process.bursts[j.burst];
                    j.state = 'IO';
                    cpu = 'IDLE';
                    event('IO', `${j.process.id} ${j.left}`);
                }
                else if (demoted) {
                    enqueue(current);
                    cpu = 'IDLE';
                }
                else if ((algo === 'RR' || algo === 'LOTTERY') && run === p.q) {
                    enqueue(current);
                    cpu = 'IDLE';
                    event('EXPIRE', j.process.id);
                }
                else {
                    const ready = allReady();
                    const preempt = algo === 'SRTF' ? ready.some(i => jobs[i].left < j.left) : algo === 'PRIORITY' ? ready.some(i => jobs[i].effective < j.effective) : algo === 'EDF' ? ready.some(i => absolute(i) < absolute(current)) : algo === 'MLFQ' ? ready.some(i => jobs[i].level < j.level) : false;
                    if (preempt) {
                        enqueue(current);
                        cpu = 'IDLE';
                        event('PREEMPT', j.process.id);
                    }
                }
            }
        }
        if (jobs.every(j => j.state === 'DONE')) {
            r.end = time;
            if (!r.snapshot.length && snapshotTime >= 0) r.snapshot = snapshot();
            break;
        }
        if (algo === 'MLFQ' && p.s && time > 0 && time % p.s === 0) {
            queues = [allReady(), [], []];
            for (const j of jobs) {
                j.level = 0;
                j.usage = 0;
            }
            event('BOOST');
        }
        if (cpu === 'IDLE' && allReady().length) {
            const ready = allReady();
            let chosen = ready[0];
            if (algo === 'LOTTERY') {
                random = random * 48271 % 2147483647;
                let draw = random % sum(ready.map(i => 10 - jobs[i].process.priority));
                for (const i of ready) {
                    draw -= 10 - jobs[i].process.priority;
                    if (draw < 0) {
                        chosen = i;
                        break;
                    }
                }
            }
            else for (const i of ready.slice(1)) {
                const a = jobs[i], b = jobs[chosen];
                const better = algo === 'SJF' || algo === 'SRTF' ? a.left < b.left : algo === 'PRIORITY' ? a.effective < b.effective : algo === 'HRRN' ? (time - a.enqueue + a.left) * b.left > (time - b.enqueue + b.left) * a.left : algo === 'EDF' ? absolute(i) < absolute(chosen) : false;
                if (better) chosen = i;
            }
            const j = jobs[chosen], q = algo === 'MLFQ' ? j.level : 0;
            queues[q] = queues[q].filter(i => i !== chosen);
            current = chosen;
            j.effective = j.process.priority;
            j.wait = 0;
            ++j.records[j.records.length - 1].slices;
            const change = current !== previous;
            if (change) ++r.switches;
            if (change && p.cs) {
                cpu = 'SWITCH';
                j.state = 'SWITCH';
                switchLeft = p.cs;
                event('SWITCH', j.process.id);
            } else {
                start();
                event('DISPATCH', j.process.id);
            }
        }
        if (time === snapshotTime) r.snapshot = snapshot();
        r.queueLengths.push(allReady().length);
        r.modes.push(cpu);
        for (const j of jobs) j.timeline += ({
            FUTURE: '-', READY: '.', SWITCH: 's', RUN: '#', IO: 'i', DONE: '-'
        })[j.state];
        if (cpu === 'RUN') {
            const j = jobs[current];
            --j.left;
            ++run;
            ++j.usage;
            previous = current;
            r.labels.push(j.process.id);
            ++r.busy;
            if (!j.left) j.records[j.records.length - 1].end = time + 1;
        }
        else if (cpu === 'SWITCH') {
            --switchLeft;
            r.labels.push('CS');
            ++r.switching;
        } else {
            r.labels.push('IDLE');
            ++r.idle;
        }
        for (const j of jobs) if (j.state === 'IO') --j.left;
    }
    for (const j of jobs) {
        metrics(j).forEach((v, k) => {
            r.totals[k] += v;
        });
        if (j.process.deadline >= 0) {
            if (j.finish <= j.process.arrival + j.process.deadline) ++r.met;
            else ++r.missed;
        }
    }
    return r;
}
const describe = (p) => `${p.id} arrival=${p.arrival} priority=${p.priority} deadline=${p.deadline < 0 ? 'none' : p.deadline} bursts=${p.bursts.map((b, i) => `${i % 2 ? 'I' : 'C'}${b}`).join(',')}`;
class Scheduler {
    registry = new Map();
    output = [];
    emit(text) {
        this.output.push(text);
    }
    processes() {
        return [...this.registry.values()].sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
    }
    process(id) {
        const p = this.registry.get(id);
        if (!p) throw new Error(`unknown process ${id}`);
        return p;
    }
    execute(line) {
        try {
            const [c, ...a] = line.split(' ');
            this.command(c, a);
        } catch (e) {
            if (!(e instanceof Error)) throw e;
            this.emit(`ERROR ${e.message}`);
        }
    }
    command(c, a) {
        const id = a[0];
        if (c === 'PROC') {
            errorIf(this.registry.has(id), `duplicate process ${id}`);
            errorIf(this.registry.size === 10, 'too many processes');
            const arrival = Number(a[1]), priority = Number(a[2]), words = a.slice(3), bursts = words.map(x => Number(x.slice(1)));
            errorIf(arrival > 200, `invalid arrival ${id}`);
            errorIf(priority > 9, `invalid priority ${id}`);
            errorIf(words.length % 2 === 0 || words.some((w, i) => w[0] !== (i % 2 ? 'I' : 'C') || bursts[i] < 1 || bursts[i] > 30),
            `invalid bursts ${id}`);
            this.registry.set(id, {
                id, arrival, priority, deadline: -1, bursts
            });
            this.emit(`PROC ${id} cpu=${sum(bursts.filter((_, i) => i % 2 === 0))} io=${sum(bursts.filter((_, i) => i % 2 === 1))}`);
            return;
        }
        if (c === 'GEN') {
            const n = Number(a[1]);
            for (let i = 1; i <= n; ++i) errorIf(this.registry.has(id + i), `duplicate process ${id + i}`);
            errorIf(this.registry.size + n > 10, 'too many processes');
            let random = Number(a[2]);
            const draw = (mod) => {
                random = random * 48271 % 2147483647;
                return random % mod;
            };
            this.emit(`GEN count=${n}`);
            for (let i = 1; i <= n; ++i) {
                const arrival = draw(21), priority = draw(10), m = 1 + draw(3), bursts = [];
                for (let j = 0; j < m; ++j) {
                    if (j) bursts.push(1 + draw(8));
                    bursts.push(1 + draw(9));
                }
                const p = {
                    id: id + i, arrival, priority, deadline: -1, bursts
                };
                this.registry.set(p.id, p);
                this.emit(describe(p));
            }
            return;
        }
        if (['SETPRIO', 'DEADLINE', 'DROP'].includes(c)) {
            const p = this.process(id), v = Number(a[1]);
            if (c === 'DROP') {
                this.registry.delete(id);
                this.emit(`DROP ${id}`);
            } else if (c === 'SETPRIO') {
                errorIf(v > 9, `invalid priority ${id}`);
                p.priority = v;
                this.emit(`SETPRIO ${id} priority=${v}`);
            } else {
                errorIf(v > 1000, `invalid deadline ${id}`);
                p.deadline = v || -1;
                this.emit(`DEADLINE ${id} ${v || 'none'}`);
            }
            return;
        }
        if (c === 'CLEAR') {
            this.emit(`CLEAR count=${this.registry.size}`);
            this.registry.clear();
            return;
        }
        if (c === 'LIST') {
            this.emit(`LIST count=${this.registry.size}`);
            for (const p of this.processes()) this.emit(describe(p));
            return;
        }
        const multiple = ['DIFF', 'COMPARE', 'RANK'].includes(c), algo = c === 'COMPARE' || c === 'RANK' ? '' : id;
        if (algo) errorIf(!algorithms.includes(algo), `unknown algorithm ${algo}`);
        if (c === 'DIFF') errorIf(!algorithms.includes(a[1]), `unknown algorithm ${a[1]}`);
        if (c === 'RANK') errorIf(![...metricNames, 'end', 'switches', 'missed'].includes(id), `unknown metric ${id}`);
        let start = c === 'COMPARE' ? 0 : 1, preset = '';
        if (c === 'SNAPSHOT' || c === 'WINDOW') start = 2;
        if (c === 'WINDOW') errorIf(Number(a[1]) < 1 || Number(a[1]) > 1000, 'invalid window');
        if (c === 'DIFF') start = 2;
        if (c === 'SWEEP') {
            const key = a[1], lo = Number(a[2]), hi = Number(a[3]);
            errorIf(!parameterKeys.includes(key), `unknown key ${key}`);
            errorIf(!used[algo].includes(key), `key ${key} not allowed for ${algo}`);
            errorIf(lo > hi || lo < ranges[key][0] || hi > ranges[key][1] || hi - lo > 20, 'invalid range');
            start = 4;
            preset = key;
        }
        const params = parameters(a.slice(start), multiple ? '' : algo, preset);
        errorIf(!this.registry.size, 'no processes');
        const ps = this.processes();
        const run = (m, p = params, t = -1) => simulate(ps, m, p, t);
        const averages = (r) => r.totals.map(n => truncated(n, ps.length));
        const util = (r) => truncated(r.busy * 100, r.end);
        if (c === 'SWEEP') {
            const key = a[1], lo = Number(a[2]), hi = Number(a[3]);
            this.emit(`SWEEP ${algo} ${key} ${lo} ${hi}`);
            let best = lo, value = Infinity;
            for (let v = lo; v <= hi; ++v) {
                const p = {
                    ...params, [key]: v
                }, r = run(algo, p), av = averages(r);
                this.emit(`${notation(p, algo)} turnaround=${av[0]} waiting=${av[1]} response=${av[2]} util=${util(r)} end=${r.end} switches=${r.switches}`);
                if (r.totals[1] < value) {
                    best = v;
                    value = r.totals[1];
                }
            }
            this.emit(`BEST ${key}=${best}`);
            return;
        }
        if (c === 'DIFF') {
            const x = run(algo), y = run(a[1]);
            this.emit(`DIFF ${algo} ${a[1]} ${notation(params)}`);
            let wins = 0, loses = 0, ties = 0;
            x.jobs.forEach((j, i) => {
                const m = metrics(j), n = metrics(y.jobs[i]); this.emit(`${j.process.id} turnaround=${m[0]}/${n[0]} waiting=${m[1]}/${n[1]} response=${m[2]}/${n[2]}`); if (m[0] < n[0]) ++wins; else if (m[0] > n[0]) ++loses; else ++ties;
            });
            this.emit(`WINS ${algo}=${wins} ${a[1]}=${loses} ties=${ties}`);
            return;
        }
        if (c === 'COMPARE' || c === 'RANK') {
            const rs = algorithms.map(m => run(m));
            if (c === 'COMPARE') {
                this.emit(`COMPARE ${notation(params)}`);
                const row = (xs) => xs[0].padEnd(8) + xs.slice(1).map(x => ' ' + x.padStart(8)).join('');
                this.emit(row(['ALGO', 'TURN', 'WAIT', 'RESP', 'UTIL', 'END', 'SWITCH', 'MISS']));
                rs.forEach((r, i) => this.emit(row([algorithms[i], ...averages(r), util(r), String(r.end), String(r.switches), String(r.missed)])));
                this.emit('BEST ' + metricNames.map((m, k) => `${m}=${algorithms[rs.reduce((b, r, i) => r.totals[k] < rs[b].totals[k] ? i : b, 0)]}`).join(' '));
            }
            else {
                this.emit(`RANK ${id} ${notation(params)}`);
                const k = metricNames.indexOf(id), value = (r) => k >= 0 ? r.totals[k] : id === 'end' ? r.end : id === 'switches' ? r.switches : r.missed;
                const order = algorithms.map((_, i) => i).sort((a, b) => value(rs[a]) - value(rs[b]));
                for (const i of order) this.emit(`${1 + rs.filter(r => value(r) < value(rs[i])).length} ${algorithms[i]} ${k >= 0 ? truncated(value(rs[i]), ps.length) : value(rs[i])}`);
            }
            return;
        }
        const r = run(algo, params, c === 'SNAPSHOT' ? Number(a[1]) : -1), header = `${c} ${algo} ${notation(params, algo)}`;
        if (c === 'TIMELINE') {
            errorIf(r.end > 100, `too long ${r.end}`);
            this.emit(`${header} end=${r.end}`);
            for (const j of r.jobs) this.emit(j.process.id.padEnd(8) + ' ' + j.timeline);
            return;
        }
        if (c === 'SNAPSHOT') {
            this.emit(`${header} t=${a[1]}`);
            for (const line of r.snapshot) this.emit(line);
            return;
        }
        this.emit(header);
        if (c === 'TRACE') {
            for (const e of r.events) this.emit(e);
            this.emit(`END ${r.end}`);
        }
        else if (c === 'BURSTS') for (const j of r.jobs) j.records.forEach((b, i) => this.emit(`${j.process.id} #${i + 1} len=${b.length} ready=${b.ready} start=${b.start} end=${b.end} wait=${b.end - b.ready - b.length} slices=${b.slices}`));
        else if (c === 'WINDOW') {
            const w = Number(a[1]);
            for (let start = 0; start < r.end; start += w) {
                const end = Math.min(start + w, r.end), ls = r.labels.slice(start, end), sw = r.modes.slice(start, end).filter(x => x === 'SWITCH').length,
                idle = r.modes.slice(start, end).filter(x => x === 'IDLE').length, busy = ls.length - sw - idle;
                let top = 'none', count = 0;
                for (const p of ps) {
                    const n = ls.filter((x, i) => x === p.id && r.modes[start + i] === 'RUN').length;
                    if (n > count) {
                        count = n;
                        top = p.id;
                    }
                }
                this.emit(`${start}-${end} busy=${busy} switch=${sw} idle=${idle} util=${truncated(busy * 100, end - start)} top=${top}`);
            }
        }
        else if (c === 'STATS') metricNames.forEach((name, k) => {
            const vs = r.jobs.map(j => metrics(j)[k]), sorted = [...vs].sort((a, b) => a - b), n = vs.length, doubled = n % 2 ? 2 * sorted[Math.floor(n / 2)] : sorted[n / 2 - 1] + sorted[n / 2],
            lo = Math.min(...vs), hi = Math.max(...vs); this.emit(`${name} min=${lo} (${ps[vs.indexOf(lo)].id}) max=${hi} (${ps[vs.indexOf(hi)].id}) median=${Math.floor(doubled / 2)}.${doubled % 2 ? 5 : 0} total=${sum(vs)}`);
        });
        else if (c === 'RUN') {
            const segments = [];
            for (let i = 0; i < r.end;) {
                let end = i + 1;
                while (end < r.end && r.labels[end] === r.labels[i]) ++end;
                segments.push(`[${i}-${end} ${r.labels[i]}]`);
                i = end;
            }
            for (let i = 0; i < segments.length; i += 8) this.emit('GANTT ' + segments.slice(i, i + 8).join(''));
            for (const j of r.jobs) {
                const [t, w, response] = metrics(j), p = j.process;
                this.emit(`${p.id} arrival=${p.arrival} done=${j.finish} turnaround=${t} waiting=${w} response=${response} slices=${sum(j.records.map(b => b.slices))}` + (p.deadline < 0 ? '' : ` deadline=${p.arrival + p.deadline} late=${Math.max(0, j.finish - p.arrival - p.deadline)}`));
            }
            const av = averages(r);
            this.emit(`AVERAGE turnaround=${av[0]} waiting=${av[1]} response=${av[2]}`);
            this.emit(`CPU end=${r.end} busy=${r.busy} switch=${r.switching} idle=${r.idle} switches=${r.switches} util=${util(r)}`);
            this.emit(`QUEUE max=${Math.max(...r.queueLengths)} avg=${truncated(sum(r.queueLengths), r.end)}`);
            this.emit('EVENTS ' + ['PREEMPT', 'EXPIRE', 'DEMOTE', 'BOOST', 'AGE'].map(e => `${e.toLowerCase()}=${r.counts[e] ?? 0}`).join(' '));
            this.emit(`DEADLINE met=${r.met} missed=${r.missed}`);
        }
    }
}
const lines = readFileSync(0, 'utf8').trimEnd().split(/\r?\n/), scheduler = new Scheduler();
for (let i = 1; i <= Number(lines[0]); ++i) scheduler.execute(lines[i]);
process.stdout.write(scheduler.output.join('\n') + '\n');
