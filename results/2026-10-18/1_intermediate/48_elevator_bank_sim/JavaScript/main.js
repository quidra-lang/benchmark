import { readFileSync } from 'node:fs';
const policies = ['COST', 'NEAREST', 'ROUND', 'ETA'];
const keys = ['FLOORS', 'CARS', 'CAPACITY', 'DOOR', 'START', 'POLICY', 'ZONES', 'PARK', 'PATIENCE', 'BYPASS', 'PERIOD',
'LIMIT', 'COMPARE'];
const counts = {
    CALL: 3, CANCEL: 1, OUT: 1, IN: 1, HOLD: 2, FIRE: 1, RESET: 0, WHERE: 1, STATUS: 0
};
const join = (xs) => xs.join(',') || '-';
const avg = (sum, count) => {
    if (!count) return '-';
    const c = Math.floor(sum * 100 / count);
    return `${Math.floor(c / 100)}.${String(c % 100).padStart(2, '0')}`;
};
const ensure = (bad, message) => {
    if (bad) throw new Error(message);
};
function configuration(lines) {
    const entries = new Map();
    for (const [key, ...values] of lines) {
        ensure(!keys.includes(key), `unknown key ${key}`);
        ensure(entries.has(key), `duplicate key ${key}`);
        entries.set(key, values);
    }
    for (const key of keys.slice(0, 5)) ensure(!entries.has(key), `missing key ${key}`);
    const c = {
        floors: 0, cars: 0, capacity: 0, door: 0, starts: [], policy: 'COST', zones: [], park: -1, homes: [], patience: -1,
        bypass: 100, period: -1, limit: 1000, compare: []
    };
    for (const key of keys) {
        const a = entries.get(key);
        if (!a) continue;
        const n = key === 'START' || key === 'ZONES' ? c.cars : key === 'PARK' ? c.cars + 1 : 1;
        ensure(key === 'COMPARE' ? a.length < 1 || a.length > 4 : a.length !== n, `wrong number of values for ${key}`);
        const bounded = (text, lo, hi) => {
            const n = Number(text);
            ensure(n < lo || n > hi, `bad value for ${key}`);
            return n;
        };
        switch (key) {
            case 'FLOORS': c.floors = bounded(a[0], 2, 50);
            break;
            case 'CARS': c.cars = bounded(a[0], 1, 8);
            break;
            case 'CAPACITY': c.capacity = bounded(a[0], 1, 20);
            break;
            case 'DOOR': c.door = bounded(a[0], 1, 9);
            break;
            case 'START': c.starts = a.map(x => bounded(x, 1, c.floors));
            break;
            case 'POLICY': ensure(!policies.includes(a[0]), 'bad value for POLICY');
            c.policy = a[0];
            break;
            case 'ZONES': c.zones = a.map(x => {
                const [lo, hi] = x.split(':').map(Number); ensure(lo < 1 || lo >= hi || hi > c.floors, 'bad value for ZONES'); return [lo,
                hi];
            });
            break;
            case 'PARK': c.park = bounded(a[0], 0, 100);
            c.homes = a.slice(1).map(x => bounded(x, 1, c.floors));
            break;
            case 'PATIENCE': c.patience = bounded(a[0], 1, 1000);
            break;
            case 'BYPASS': c.bypass = bounded(a[0], 50, 100);
            break;
            case 'PERIOD': c.period = bounded(a[0], 1, 1000);
            break;
            case 'LIMIT': c.limit = bounded(a[0], 1, 5000);
            break;
            case 'COMPARE': ensure(a.some(x => !policies.includes(x)) || new Set(a).size !== a.length, 'bad value for COMPARE');
            c.compare = a;
            break;
        }
    }
    if (!c.zones.length) c.zones = c.starts.map(() => [1, c.floors]);
    for (let i = 0; i < c.cars; ++i) {
        const [lo, hi] = c.zones[i];
        ensure(c.starts[i] < lo || c.starts[i] > hi, `car ${i + 1} starts outside its zone`);
        ensure(c.park >= 0 && (c.homes[i] < lo || c.homes[i] > hi), `car ${i + 1} home outside its zone`);
    }
    return c;
}
const serves = (c, i, a, b) => c.zones[i][0] <= Math.min(a, b) && Math.max(a, b) <= c.zones[i][1];
function events(c, lines, output) {
    const accepted = [];
    let last = 0, groups = 0, fire = false;
    const out = new Set();
    for (const line of lines) {
        const [time, command, ...args] = line.words;
        const t = Number(time), v = args.map(Number), [a, b, n] = v;
        let error = '';
        if (!(command in counts)) error = `unknown command ${command}`;
        else if (args.length !== counts[command]) error = `wrong number of arguments for ${command}`;
        else if (t < last) error = 'time goes backwards';
        else if (command === 'CALL') {
            if (a < 1 || a > c.floors || b < 1 || b > c.floors) error = 'bad floor';
            else if (a === b) error = 'same floor';
            else if (n < 1 || n > 99) error = 'bad count';
            else if (!c.starts.some((_, i) => serves(c, i, a, b))) error = `no car serves ${a}->${b}`;
            else if (fire) error = 'fire service active';
        } else if (command === 'CANCEL' || command === 'WHERE') {
            if (a < 1 || a > groups) error = 'unknown group';
        }
        else if (['OUT', 'IN', 'HOLD'].includes(command)) {
            if (a < 1 || a > c.cars) error = 'bad car';
            else if (command === 'OUT' && out.has(a)) error = `car ${a} already out`;
            else if (command === 'IN' && !out.has(a)) error = `car ${a} already in`;
            else if (command === 'HOLD' && (b < 1 || b > 9)) error = 'bad ticks';
        } else if (command === 'FIRE') {
            if (a < 1 || a > c.floors) error = 'bad floor';
            else if (fire) error = 'fire already active';
        }
        else if (command === 'RESET' && !fire) error = 'fire not active';
        if (error) {
            output.push(`line ${line.number}: ${error}`);
            continue;
        }
        accepted.push({
            time: t, command, values: v
        });
        last = t;
        if (command === 'CALL') ++groups;
        if (command === 'OUT') out.add(a);
        if (command === 'IN') out.delete(a);
        if (command === 'FIRE') fire = true;
        if (command === 'RESET') fire = false;
    }
    return accepted;
}
function simulate(c, input, policy, logging = true) {
    const r = {
        groups: [], cars: c.starts.map(floor => ({
            floor, direction: 0, door: 0, inService: true, idle: 0, passengers: [], calls: [], distance: 0, stops: 0, boarded: 0,
            busy: 0, energy: 0
        })), delivered: 0, abandoned: 0, evacuated: 0, wait: 0, travel: 0, maxWait: 0, end: 0, aborted: false, log: []
    };
    let pending = [], fire = false, evacuation = 0, round = -1, time = 0, cursor = 0;
    const emit = (text) => {
        if (logging) r.log.push(`${time} ${text}`);
    };
    const load = (car) => car.passengers.reduce((n, p) => n + p.count, 0);
    const direction = (g) => Math.sign(g.b - g.a);
    const targets = (car) => [...new Set([...car.passengers.map(p => r.groups[p.group].b), ...car.calls.map(g => r.groups[g].a)])];
    const remove = (g) => {
        const group = r.groups[g];
        if (group.car < 0) pending = pending.filter(x => x !== g);
        else {
            const car = r.cars[group.car];
            car.calls = car.calls.filter(x => x !== g);
        }
        group.car = -1;
    };
    function assign(g, exclude = -1) {
        const group = r.groups[g], candidates = r.cars.map((car, i) => ({
            car, i
        })).filter(x => x.i !== exclude && x.car.inService && serves(c, x.i, group.a, group.b));
        if (!candidates.length) return false;
        const cost = (car) => {
            const f = car.floor, d = car.direction, x = group.a, u = direction(group), s = targets(car);
            if (policy === 'NEAREST' || !d) return Math.abs(f - x);
            let distance, via;
            if (u === d && (x - f) * d >= 0) {
                distance = Math.abs(x - f);
                via = s.filter(y => (y - f) * d > 0 && (x - y) * d > 0).length;
            }
            else {
                const m = d > 0 ? Math.max(f, ...s) : Math.min(f, ...s);
                distance = Math.abs(f - m) + Math.abs(m - x);
                via = s.filter(y => (y - f) * d > 0).length;
            }
            return distance + (policy === 'ETA' ? c.door * via + car.door : 0);
        };
        let chosen = candidates[0];
        if (policy === 'ROUND') chosen = candidates.find(x => x.i > round) ?? chosen;
        else for (const x of candidates) if (cost(x.car) < cost(chosen.car)) chosen = x;
        const chosenCost = cost(chosen.car);
        remove(g);
        group.car = chosen.i;
        chosen.car.calls.push(g);
        if (policy === 'ROUND') round = chosen.i;
        emit(`E${chosen.i + 1} ASSIGN G${g + 1}` + (policy === 'ROUND' ? '' : ` cost=${chosenCost}`));
        return true;
    }
    const makePending = (g) => {
        r.groups[g].car = -1;
        pending.push(g);
        emit(`PENDING G${g + 1}`);
    };
    const abandon = (g, word) => {
        const group = r.groups[g];
        remove(g);
        emit(`${word} G${g + 1} x${group.waiting}`);
        r.abandoned += group.waiting;
        group.lost += group.waiting;
        group.waiting = 0;
    };
    const choose = (car) => {
        const f = car.floor, d = car.direction, s = targets(car), calls = load(car) * 100 >= c.capacity * c.bypass ? [] : car.calls.filter(g => r.groups[g].a === f);
        if (d && (s.some(y => (y - f) * d > 0) || calls.some(g => direction(r.groups[g]) === d))) return d;
        if (calls.length) return direction(r.groups[calls[0]]);
        if (d && s.some(y => (y - f) * d < 0)) return -d;
        if (!d && car.calls.length) return Math.sign(r.groups[car.calls[0]].a - f);
        return 0;
    };
    const move = (car, n) => {
        car.energy += n > 0 ? 3 + load(car) : 1;
        car.floor += n;
        ++car.distance;
    };
    for (time = 0; time <= c.limit; ++time) {
        if (c.patience >= 0) r.groups.forEach((g, i) => {
            if (g.waiting && time === g.time + c.patience) abandon(i, 'ABANDON');
        });
        while (cursor < input.length && input[cursor].time === time) {
            const e = input[cursor++], [a, b, n] = e.values;
            if (e.command === 'CALL') {
                const g = r.groups.length;
                r.groups.push({
                    a, b, n, time, waiting: n, car: -1, boarded: 0, delivered: 0, lost: 0, lastBoard: -1, lastAlight: -1, cars: new Set(),
                    wait: 0, travel: 0, maxWait: 0
                });
                emit(`CALL G${g + 1} ${a}->${b} x${n}`);
                if (!assign(g)) makePending(g);
            } else if (e.command === 'CANCEL') {
                if (r.groups[a - 1].waiting) abandon(a - 1, 'CANCEL');
                else emit(`CANCEL G${a} ignored`);
            }
            else if (e.command === 'OUT') {
                const car = r.cars[a - 1];
                car.inService = false;
                emit(`E${a} OUT`);
                const calls = [...car.calls];
                car.calls = [];
                for (const g of calls) {
                    r.groups[g].car = -1;
                    if (!assign(g)) makePending(g);
                }
            }
            else if (e.command === 'IN') {
                const car = r.cars[a - 1];
                car.inService = true;
                car.idle = time;
                emit(`E${a} IN`);
                const calls = pending;
                pending = [];
                for (const g of calls) if (!assign(g)) pending.push(g);
            }
            else if (e.command === 'HOLD') {
                const car = r.cars[a - 1];
                if (car.door) {
                    car.door += b;
                    emit(`E${a} HOLD ${car.door}`);
                } else emit(`E${a} HOLD ignored`);
            }
            else if (e.command === 'FIRE') {
                fire = true;
                evacuation = a;
                emit(`FIRE ${a}`);
                r.groups.forEach((g, i) => {
                    if (g.waiting) abandon(i, 'ABANDON');
                });
            }
            else if (e.command === 'RESET') {
                fire = false;
                emit('RESET');
                r.cars.forEach(car => {
                    car.idle = time;
                });
            }
            else if (e.command === 'WHERE') {
                const g = r.groups[a - 1], riding = r.cars.map((car, i) => {
                    const n = car.passengers.filter(p => p.group === a - 1).reduce((n, p) => n + p.count, 0); return n ? `E${i + 1}x${n}` : '';
                }).filter(Boolean);
                emit(`WHERE G${a} waiting=${g.waiting} car=${!g.waiting ? '-' : g.car < 0 ? 'pending' : `E${g.car + 1}`} riding=${join(riding)} delivered=${g.delivered} lost=${g.lost}`);
            }
            else if (e.command === 'STATUS') {
                r.cars.forEach((car, i) => emit(`STATUS E${i + 1} floor=${car.floor} dir=${car.direction > 0 ? 'up' : car.direction < 0 ? 'down' : 'idle'} door=${car.door} load=${load(car)} stops=${join([...new Set(car.passengers.map(p => r.groups[p.group].b))].sort((a, b) => a - b))} calls=${join(car.calls.map(g => `G${g + 1}`))} service=${car.inService ? 'in' : 'out'}`));
                emit(`STATUS pending=${join(pending.map(g => `G${g + 1}`))}`);
            }
        }
        r.cars.forEach((car, i) => {
            let moved = false;
            if (car.door) --car.door;
            if (!car.door) {
                const f = car.floor, d = car.direction, n = fire ? Math.sign(evacuation - f) : choose(car);
                const stop = fire ? n === 0 && car.passengers.length > 0 : car.passengers.some(p => r.groups[p.group].b === f) || (load(car) * 100 < c.capacity * c.bypass && car.calls.some(g => r.groups[g].a === f && direction(r.groups[g]) === n));
                if (stop) {
                    emit(`E${i + 1} OPEN ${f}`); car.door = c.door; ++car.stops; car.energy += 2;
                    const riding = [];
                    for (const p of car.passengers) {
                        const g = r.groups[p.group];
                        if (g.b === f) {
                            emit(`E${i + 1} ALIGHT G${p.group + 1} x${p.count}`); g.delivered += p.count; g.lastAlight = time; g.wait += (p.time - g.time) * p.count; g.travel += (time - g.time) * p.count; g.maxWait = Math.max(g.maxWait,
                            p.time - g.time); r.delivered += p.count; r.wait += (p.time - g.time) * p.count; r.travel += (time - g.time) * p.count; r.maxWait = Math.max(r.maxWait,
                            p.time - g.time);
                        }
                        else if (fire) {
                            emit(`E${i + 1} EVACUATE G${p.group + 1} x${p.count}`); g.lost += p.count; r.evacuated += p.count;
                        }
                        else riding.push(p);
                    }
                    car.passengers = riding;
                    if (!fire) {
                        const n = choose(car); if (n) car.direction = n;
                        const calls = car.calls.filter(g => r.groups[g].a === f && direction(r.groups[g]) === n);
                        for (const gi of calls) {
                            const g = r.groups[gi], k = Math.min(c.capacity - load(car), g.waiting); if (k) {
                                car.passengers.push({
                                    group: gi, count: k, time
                                }); g.waiting -= k; g.boarded += k; g.lastBoard = time; g.cars.add(i + 1); car.boarded += k; emit(`E${i + 1} BOARD G${gi + 1} x${k}`);
                            }
                            if (!g.waiting) remove(gi); else {
                                emit(`E${i + 1} LEFT G${gi + 1} x${g.waiting}`); assign(gi, i);
                            }
                        }
                    }
                } else if (n) {
                    car.direction = n; move(car, n); moved = true;
                }
                else {
                    if (d) {
                        emit(`E${i + 1} IDLE ${f}`); car.direction = 0; car.idle = time;
                    }
                    if (!fire && car.inService && c.park >= 0 && f !== c.homes[i] && time - car.idle >= c.park) {
                        move(car, Math.sign(c.homes[i] - f)); moved = true; if (car.floor === c.homes[i]) emit(`E${i + 1} PARK ${car.floor}`);
                    }
                }
            }
            if (car.door || moved) ++car.busy;
        });
        r.end = time;
        if (cursor === input.length && r.cars.every((car, i) => !car.door && !car.passengers.length && !car.calls.length && (fire ? car.floor === evacuation : !car.inService || c.park < 0 || car.floor === c.homes[i]))) {
            emit('END');
            break;
        }
        if (time === c.limit) {
            emit('ABORT');
            r.aborted = true;
        }
    }
    return r;
}
function statistics(c, r, out) {
    r.groups.forEach((g, i) => out.push(`G${i + 1} t=${g.time} ${g.a}->${g.b} n=${g.n} delivered=${g.delivered} lost=${g.lost} wait=${g.boarded === g.n ? g.lastBoard - g.time : '-'} travel=${g.delivered === g.n ? g.lastAlight - g.time : '-'} cars=${join([...g.cars].sort((a, b) => a - b))}`));
    r.cars.forEach((car, i) => {
        const u = Math.floor(car.busy * 1000 / (r.end + 1)); out.push(`E${i + 1} distance=${car.distance} stops=${car.stops} boarded=${car.boarded} busy=${car.busy} util=${Math.floor(u / 10)}.${u % 10}% energy=${car.energy}`);
    });
    const aggregate = (label, gs) => out.push(`${label}: groups=${gs.length} passengers=${gs.reduce((n, g) => n + g.n, 0)} delivered=${gs.reduce((n, g) => n + g.delivered, 0)} avg_wait=${avg(gs.reduce((n, g) => n + g.wait, 0), gs.reduce((n, g) => n + g.delivered, 0))}`);
    for (const f of [...new Set(r.groups.map(g => g.a))].sort((a, b) => a - b)) aggregate(`F${f}`, r.groups.filter(g => g.a === f));
    if (c.period >= 0) for (const k of [...new Set(r.groups.map(g => Math.floor(g.time / c.period)))].sort((a, b) => a - b)) aggregate(`P${k} ${k * c.period}-${k * c.period + c.period - 1}`,
    r.groups.filter(g => Math.floor(g.time / c.period) === k));
    out.push(`summary: groups=${r.groups.length} passengers=${r.groups.reduce((n, g) => n + g.n, 0)} delivered=${r.delivered} abandoned=${r.abandoned} evacuated=${r.evacuated} avg_wait=${avg(r.wait, r.delivered)} avg_travel=${avg(r.travel, r.delivered)} max_wait=${r.delivered ? r.maxWait : '-'} end=${r.end}`);
}
const lines = readFileSync(0, 'utf8').trimEnd().split(/\r?\n/), output = [], scenarios = [];
let cursor = 1;
for (let s = 0; s < Number(lines[0]); ++s) {
    const name = lines[cursor++].split(' ')[1], settings = [], raw = [];
    while (lines[cursor] !== 'END') {
        const words = lines[cursor].split(' ');
        if (/^[0-9]/.test(words[0])) raw.push({
            number: cursor + 1, words
        });
        else settings.push(words);
        ++cursor;
    }
    ++cursor;
    output.push(`== ${name} ==`);
    let config;
    try {
        config = configuration(settings);
    } catch (e) {
        if (!(e instanceof Error)) throw e;
        output.push(`error: ${e.message}`);
        scenarios.push({
            name, config: null, result: null
        });
        continue;
    }
    const c = config;
    output.push(`config: floors=${c.floors} cars=${c.cars} capacity=${c.capacity} door=${c.door} policy=${c.policy} park=${c.park < 0 ? 'off' : c.park} patience=${c.patience < 0 ? 'off' : c.patience} bypass=${c.bypass} period=${c.period < 0 ? 'off' : c.period} limit=${c.limit} compare=${join(c.compare)}`);
    c.starts.forEach((floor, i) => output.push(`E${i + 1}: start=${floor} zone=${c.zones[i][0]}-${c.zones[i][1]} home=${c.park < 0 ? '-' : c.homes[i]}`));
    const input = events(c, raw, output), r = simulate(c, input, c.policy);
    for (const line of r.log) output.push(line);
    statistics(c, r, output);
    scenarios.push({
        name, config: c, result: r
    });
    for (const policy of c.compare) {
        const x = simulate(c, input, policy, false);
        output.push(`compare ${policy}: delivered=${x.delivered} avg_wait=${avg(x.wait, x.delivered)} avg_travel=${avg(x.travel, x.delivered)} max_wait=${x.delivered ? x.maxWait : '-'} end=${x.end} status=${x.aborted ? 'abort' : 'end'}`);
    }
}
output.push('== ranking ==');
const ranked = scenarios.filter((s) => s.config !== null && s.result !== null && !s.result.aborted && s.result.delivered > 0);
ranked.sort((a, b) => a.result.wait * b.result.delivered - b.result.wait * a.result.delivered || a.result.travel * b.result.delivered - b.result.travel * a.result.delivered);
ranked.forEach((s, i) => output.push(`${i + 1}. ${s.name} policy=${s.config.policy} avg_wait=${avg(s.result.wait, s.result.delivered)} avg_travel=${avg(s.result.travel, s.result.delivered)} max_wait=${s.result.maxWait}`));
for (const s of scenarios) if (!ranked.includes(s)) output.push(`- ${s.name} ${!s.result ? 'invalid' : s.result.aborted ? 'aborted' : 'empty'}`);
output.push('== policies ==');
for (const p of policies) {
    const ss = ranked.filter(s => s.config.policy === p);
    if (ss.length) {
        const n = ss.reduce((n, s) => n + s.result.delivered, 0);
        output.push(`${p}: runs=${ss.length} avg_wait=${avg(ss.reduce((n, s) => n + s.result.wait, 0), n)} avg_travel=${avg(ss.reduce((n, s) => n + s.result.travel, 0), n)}`);
    }
}
process.stdout.write(output.join('\n') + '\n');
