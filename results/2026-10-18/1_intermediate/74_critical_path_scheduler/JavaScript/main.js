const fs = require('node:fs');

const tasks = new Map();
let dependencies = [];
const capacities = new Map();
const holidays = new Set();
const output = [];
let startDate = null, deadline = null, baseline = null;
const epoch = Date.UTC(2000, 0, 1);
const dayMilliseconds = 86400000;
function fail(message) { throw new Error('error: ' + message); }
function compare(a, b) { return a < b ? -1 : a > b ? 1 : 0; }
function names() { return [...tasks.keys()].sort(); }
function task(name) {
    const result = tasks.get(name);
    if (result === undefined) fail('unknown task ' + name);
    return result;
}
function duration(item) { return item.base - item.used; }
function signed(value) { return value >= 0 ? '+' + value : String(value); }
function decimal(numerator, denominator) {
    const hundredths = Math.floor(numerator * 100 / denominator);
    return Math.floor(hundredths / 100) + '.' + String(hundredths % 100).padStart(2, '0');
}
function predecessors(name) { return dependencies.filter(dep => dep.b === name).sort((a, b) => compare(a.a, b.a)); }
function successors(name) { return dependencies.filter(dep => dep.a === name).sort((a, b) => compare(a.b, b.b)); }
function topological() {
    const remaining = new Set(names()), order = [];
    while (true) {
        const next = [...remaining].find(name => predecessors(name).every(dep => !remaining.has(dep.a)));
        if (next === undefined) return { order, remaining };
        remaining.delete(next); order.push(next);
    }
}
function cycle() {
    const { remaining } = topological();
    if (!remaining.size) return null;
    const trail = [[...remaining][0]];
    while (true) {
        const next = predecessors(trail[trail.length - 1]).find(dep => remaining.has(dep.a)).a;
        const at = trail.indexOf(next);
        if (at >= 0) {
            const loop = [next, ...trail.slice(at + 1).reverse()];
            const first = loop.indexOf([...loop].sort()[0]), rotated = [...loop.slice(first), ...loop.slice(0, first)];
            return [...rotated, rotated[0]].join(' -> ');
        }
        trail.push(next);
    }
}
function schedule(overrides = new Map()) {
    const { order } = topological(), rows = new Map();
    let total = 0;
    for (const name of order) {
        const item = tasks.get(name), d = overrides.get(name) ?? duration(item);
        let es = item.notBefore;
        for (const dep of predecessors(name)) {
            const old = rows.get(dep.a);
            es = Math.max(es, (dep.kind === 'SS' ? old.es : old.ef) + dep.lag - (dep.kind === 'FF' ? d : 0));
        }
        rows.set(name, { duration: d, es, ef: es + d, ls: 0, lf: 0, tf: 0, ff: 0 });
        total = Math.max(total, es + d);
    }
    for (const name of [...order].reverse()) {
        const row = rows.get(name);
        let lf = total;
        for (const dep of successors(name)) {
            const next = rows.get(dep.b);
            lf = Math.min(lf, (dep.kind === 'FF' ? next.lf : next.ls) - dep.lag + (dep.kind === 'SS' ? row.duration : 0));
        }
        row.lf = lf; row.ls = lf - row.duration; row.tf = row.ls - row.es;
    }
    for (const name of order) {
        const row = rows.get(name);
        row.ff = total - row.ef;
        for (const dep of successors(name)) row.ff = Math.min(row.ff, margin(dep, rows));
    }
    return { rows, total };
}
function margin(dep, rows) {
    const a = rows.get(dep.a), b = rows.get(dep.b);
    return (dep.kind === 'FF' ? b.ef : b.es) - (dep.kind === 'SS' ? a.es : a.ef) - dep.lag;
}
function critical(schedule) { return names().filter(name => schedule.rows.get(name).tf === 0); }
function criticalPaths(schedule) {
    const criticalNames = new Set(critical(schedule));
    const links = dependencies.filter(dep => criticalNames.has(dep.a) && criticalNames.has(dep.b) && margin(dep, schedule.rows) === 0);
    const roots = [...criticalNames].filter(name => !links.some(dep => dep.b === name)), result = [];
    function visit(path) {
        const next = links.filter(dep => dep.a === path[path.length - 1]).map(dep => dep.b).sort();
        if (!next.length) result.push(path);
        for (const name of next) visit([...path, name]);
    }
    for (const name of roots) visit([name]);
    return result;
}
function parseDate(word) {
    const [year, month, day] = word.split('-').map(Number), value = new Date(Date.UTC(year, month - 1, day));
    if (value.getUTCFullYear() !== year || value.getUTCMonth() !== month - 1 || value.getUTCDate() !== day) fail('invalid date ' + word);
    return (value.getTime() - epoch) / dayMilliseconds;
}
function weekday(day) { return (day + 5) % 7; }
function dateText(day) {
    const date = new Date(epoch + day * dayMilliseconds);
    return date.getUTCFullYear().toString().padStart(4, '0') + '-' + String(date.getUTCMonth() + 1).padStart(2, '0') + '-' + String(date.getUTCDate()).padStart(2, '0') + ' ' + ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday(day)];
}
function working(day) { return weekday(day) < 5 && !holidays.has(day); }
function dayDates(count) {
    const result = [];
    for (let day = startDate; result.length < count; day++) if (working(day)) result.push(day);
    return result;
}
function workingBetween(a, b) {
    let count = 0;
    for (let day = a + 1; day <= b; day++) if (working(day)) count++;
    return count;
}
function resources() { return [...new Set([...tasks.values()].map(item => item.resource))].sort(); }
function usage(resource, schedule) {
    const result = Array(schedule.total).fill(0);
    for (const item of tasks.values()) if (item.resource === resource) {
        const row = schedule.rows.get(item.id);
        for (let day = row.es; day < row.ef; day++) result[day] += item.units;
    }
    return result;
}
function level(limit, original) {
    const capacity = resource => capacities.get(resource) ?? limit;
    for (const name of names()) if (tasks.get(name).units > capacity(tasks.get(name).resource)) fail(`capacity ${capacity(tasks.get(name).resource)} too small for ${name}`);
    const undecided = new Set(names()), decided = new Map(), used = new Map(resources().map(name => [name, []])), order = [];
    while (undecided.size) {
        const available = [...undecided].filter(name => predecessors(name).every(dep => decided.has(dep.a)));
        available.sort((a, b) => original.rows.get(a).ls - original.rows.get(b).ls || compare(a, b));
        const name = available[0], item = tasks.get(name), d = duration(item), days = used.get(item.resource);
        let start = item.notBefore;
        for (const dep of predecessors(name)) {
            const old = decided.get(dep.a);
            start = Math.max(start, (dep.kind === 'SS' ? old.es : old.ef) + dep.lag - (dep.kind === 'FF' ? d : 0));
        }
        while (true) {
            let valid = true;
            for (let day = start; day < start + d; day++) if ((days[day] ?? 0) + item.units > capacity(item.resource)) { valid = false; break; }
            if (valid) break;
            start++;
        }
        for (let day = start; day < start + d; day++) days[day] = (days[day] ?? 0) + item.units;
        decided.set(name, { es: start, ef: start + d }); undecided.delete(name); order.push(name);
    }
    const finish = Math.max(...[...decided.values()].map(row => row.ef));
    output.push(`level capacity ${limit}: duration ${original.total} -> ${finish}`);
    for (const name of order) { const row = decided.get(name); output.push(`${name} start ${row.es} finish ${row.ef} shift ${row.es - original.rows.get(name).es}`); }
    for (const resource of resources()) output.push(`resource ${resource} capacity ${capacity(resource)} peak ${Math.max(...usage(resource, original))} -> ${used.get(resource).reduce((peak, value) => Math.max(peak, value), 0)}`);
}
function execute(commandLine) {
    const [command, ...args] = commandLine.split(' '), a = args[0], b = args[1];
    if (command === 'TASK') {
        if (tasks.has(a)) fail(`task ${a} already exists`);
        tasks.set(a, { id: a, base: Number(b), resource: args[2], units: Number(args[3]), notBefore: 0, used: 0, crash: null, pert: null });
        output.push(`task ${a} added`); return;
    }
    if (command === 'DEP' || command === 'UNDEP') {
        task(a); task(b);
        const at = dependencies.findIndex(dep => dep.a === a && dep.b === b);
        if (command === 'DEP') {
            if (a === b) fail('self dependency ' + a);
            if (at >= 0) fail(`dependency ${a} -> ${b} already exists`);
            dependencies.push({ a, b, kind: args[2], lag: Number(args[3]) });
            output.push(`dependency ${a} -> ${b} ${args[2]}${signed(Number(args[3]))} added`);
        } else {
            if (at < 0) fail(`no dependency ${a} -> ${b}`);
            dependencies.splice(at, 1); output.push(`dependency ${a} -> ${b} removed`);
        }
        return;
    }
    if (['REMOVE', 'NOTBEFORE', 'CRASHCOST', 'UNCRASH', 'PERT', 'SHOW', 'IMPACT'].includes(command)) {
        const item = task(a);
        if (command === 'REMOVE') {
            const before = dependencies.length;
            dependencies = dependencies.filter(dep => dep.a !== a && dep.b !== a); tasks.delete(a);
            output.push(`task ${a} removed with ${before - dependencies.length} dependencies`);
        } else if (command === 'NOTBEFORE') { item.notBefore = Number(b); output.push(`notbefore ${a} ${b}`); }
        else if (command === 'CRASHCOST') {
            if (Number(b) >= item.base) fail('crash limit too large for ' + a);
            if (Number(b) < item.used) fail('crash limit below used days for ' + a);
            item.crash = { limit: Number(b), cost: Number(args[2]) }; output.push(`crash ${a} max ${b} cost ${args[2]}`);
        } else if (command === 'UNCRASH') { output.push(`uncrash ${a} restored ${item.used} days`); item.used = 0; }
        else if (command === 'PERT') {
            const [o, m, p] = args.slice(1).map(Number);
            if (o > m || m > p) fail('invalid estimate');
            item.pert = [o, m, p]; output.push(`pert ${a} expected ${decimal(o + 4 * m + p, 6)} variance ${decimal((p - o) ** 2, 36)}`);
        } else if (command === 'IMPACT') {
            const seen = new Set([a]), queue = [a];
            for (let i = 0; i < queue.length; i++) for (const dep of successors(queue[i])) if (!seen.has(dep.b)) { seen.add(dep.b); queue.push(dep.b); }
            seen.delete(a); output.push(`impact ${a}: ${[...seen].sort().join(' ') || 'none'}`);
        } else {
            output.push(`task ${a} duration ${duration(item)} resource ${item.resource} units ${item.units}${item.notBefore ? ` notbefore ${item.notBefore}` : ''}`,
                'preds: ' + (predecessors(a).map(dep => `${dep.a} ${dep.kind}${signed(dep.lag)}`).join(', ') || 'none'),
                'succs: ' + (successors(a).map(dep => `${dep.b} ${dep.kind}${signed(dep.lag)}`).join(', ') || 'none'),
                item.crash ? `crash: max ${item.crash.limit} used ${item.used} cost ${item.crash.cost}` : 'crash: none',
                item.pert ? `pert: ${item.pert.join(' ')}` : 'pert: none');
            if (cycle() !== null) output.push('schedule: unavailable');
            else { const row = schedule().rows.get(a); output.push(`schedule: ES ${row.es} EF ${row.ef} LS ${row.ls} LF ${row.lf} TF ${row.tf} FF ${row.ff}${row.tf === 0 ? ' critical' : ''}`); }
        }
        return;
    }
    if (command === 'CAPACITY') { capacities.set(a, Number(b)); output.push(`capacity ${a} ${b}`); return; }
    if (['START', 'HOLIDAY', 'DEADLINE'].includes(command)) {
        const day = parseDate(a);
        if (command === 'HOLIDAY' && holidays.has(day)) fail('duplicate holiday ' + a);
        if (command === 'START') startDate = day;
        else if (command === 'DEADLINE') deadline = day;
        else holidays.add(day);
        output.push(command.toLowerCase() + ' ' + dateText(day)); return;
    }
    if (command === 'LIST') {
        output.push(`tasks ${tasks.size}, dependencies ${dependencies.length}, holidays ${holidays.size}`);
        for (const name of names()) { const item = tasks.get(name); output.push(`${name} duration ${duration(item)} resource ${item.resource} units ${item.units} preds ${predecessors(name).map(dep => dep.a).join(' ') || 'none'}`); }
        return;
    }
    if (!tasks.size) fail('no tasks');
    const foundCycle = cycle();
    if (foundCycle !== null) fail('cycle ' + foundCycle);
    if (command === 'CALENDAR' && startDate === null) fail('no start date');
    if (command === 'LOAD' && !resources().includes(a)) fail('unknown resource ' + a);
    if (command === 'WHATIF') task(a);
    if (command === 'VARIANCE' && baseline === null) fail('no baseline');
    const current = schedule();
    const byStart = names().sort((a, b) => current.rows.get(a).es - current.rows.get(b).es || compare(a, b));
    switch (command) {
        case 'CPM': {
            const width = Math.max(4, ...names().map(name => name.length));
            output.push('TASK'.padEnd(width) + ['DUR', 'ES', 'EF', 'LS', 'LF', 'TF', 'FF'].map(word => word.padStart(5)).join(''));
            for (const name of names()) {
                const row = current.rows.get(name);
                output.push(name.padEnd(width) + [row.duration, row.es, row.ef, row.ls, row.lf, row.tf, row.ff].map(value => String(value).padStart(5)).join('') + (row.tf === 0 ? ' *' : ''));
            }
            output.push(`project duration ${current.total}`); break;
        }
        case 'CRITICAL': {
            const paths = criticalPaths(current);
            output.push(`critical paths: ${paths.length}`, ...paths.map(path => path.join(' -> '))); break;
        }
        case 'SLACK':
            for (const value of [...new Set([...current.rows.values()].map(row => row.tf))].sort((a, b) => a - b)) output.push(`float ${value}: ${names().filter(name => current.rows.get(name).tf === value).join(' ')}`);
            break;
        case 'DRAG':
            for (const name of critical(current)) output.push(`${name} drag ${current.total - schedule(new Map([[name, 0]])).total}`);
            break;
        case 'STATS': {
            const count = critical(current).length, floats = [...current.rows.values()].reduce((sum, row) => sum + row.tf, 0);
            output.push(`tasks ${tasks.size}, critical ${count}, dependencies ${dependencies.length} (FS ${dependencies.filter(dep => dep.kind === 'FS').length}, SS ${dependencies.filter(dep => dep.kind === 'SS').length}, FF ${dependencies.filter(dep => dep.kind === 'FF').length})`,
                'work ' + resources().map(resource => `${resource} ${[...tasks.values()].filter(item => item.resource === resource).reduce((sum, item) => sum + duration(item) * item.units, 0)}`).join(', '),
                `float total ${floats}, average ${decimal(floats, tasks.size)}`, `duration ${current.total}, critical share ${decimal(100 * count, tasks.size)}%`);
            break;
        }
        case 'CALENDAR': {
            const dates = dayDates(current.total), first = dates[0], last = dates[dates.length - 1];
            for (const name of byStart) { const row = current.rows.get(name); output.push(`${name} ${dateText(dates[row.es])} - ${dateText(dates[row.ef - 1])}`); }
            output.push(`project ${dateText(first)} - ${dateText(last)}, ${current.total} working days, ${last - first + 1} calendar days`);
            if (deadline !== null) output.push(last <= deadline ? `deadline ${dateText(deadline)} met, ${workingBetween(last, deadline)} working days to spare` : `deadline ${dateText(deadline)} missed by ${workingBetween(deadline, last)} working days`);
            const within = [...holidays].filter(day => weekday(day) < 5 && day >= first && day <= last).sort((a, b) => a - b);
            output.push('holidays in span: ' + (within.map(dateText).join(', ') || 'none')); break;
        }
        case 'GANTT': {
            if (current.total > 60) fail(`chart too wide (${current.total} days)`);
            const width = Math.max(...names().map(name => name.length));
            output.push(' '.repeat(width) + ' |' + Array.from({ length: current.total }, (_, i) => i % 10).join('') + '|');
            for (const name of byStart) {
                const row = current.rows.get(name), bar = Array.from({ length: current.total }, (_, day) => day >= row.es && day < row.ef ? row.tf === 0 ? '=' : '-' : day >= row.ef && day < row.lf ? '.' : ' ').join('');
                output.push(name.padEnd(width) + ' |' + bar + '|');
            }
            break;
        }
        case 'LEVEL': level(Number(a), current); break;
        case 'LOAD': {
            const days = usage(a, current), peak = Math.max(...days);
            output.push(`load ${a}: ${days.join(' ')}`, `peak ${peak} on day ${days.indexOf(peak)}`);
            if (capacities.has(a)) output.push(`capacity ${capacities.get(a)} exceeded on ${days.filter(value => value > capacities.get(a)).length} days`);
            break;
        }
        case 'PERTSUM':
            for (const path of criticalPaths(current)) {
                let expected = 0, variance = 0;
                for (const name of path) { const item = tasks.get(name), d = duration(item), [o, m, p] = item.pert ?? [d, d, d]; expected += o + 4 * m + p; variance += (p - o) ** 2; }
                output.push(`${path.join(' -> ')}: expected ${decimal(expected, 6)} variance ${decimal(variance, 36)}`);
            }
            break;
        case 'CRASH': {
            let remaining = Number(a), count = 0, total = current.total, reason;
            while (true) {
                const now = schedule();
                const candidates = critical(now).filter(name => { const item = tasks.get(name); return item.crash !== null && item.used < item.crash.limit && schedule(new Map([[name, duration(item) - 1]])).total < now.total; });
                candidates.sort((a, b) => tasks.get(a).crash.cost - tasks.get(b).crash.cost || compare(a, b));
                if (!candidates.length) { reason = 'no candidate'; break; }
                const name = candidates[0], item = tasks.get(name), cost = item.crash.cost;
                if (cost > remaining) { reason = 'insufficient budget'; break; }
                const old = duration(item); item.used++; remaining -= cost; count++; total = schedule().total;
                output.push(`step ${count}: ${name} ${old} -> ${duration(item)}, cost ${cost}, project ${total}`);
            }
            output.push(`crash done: ${count} days, cost ${Number(a) - remaining}, project ${current.total} -> ${total}, budget left ${remaining}, ${reason}`); break;
        }
        case 'WHATIF': {
            const after = schedule(new Map([[a, Number(b)]]));
            output.push(`whatif ${a} ${duration(tasks.get(a))} -> ${b}: project ${current.total} -> ${after.total}`);
            for (const name of names()) {
                const before = current.rows.get(name), next = after.rows.get(name), fields = ['es', 'ef', 'tf'].filter(key => before[key] !== next[key]);
                if (fields.length) output.push(name + fields.map(key => ` ${key.toUpperCase()} ${before[key]}->${next[key]}`).join(''));
            }
            const beforeCritical = critical(current).join(' '), afterCritical = critical(after).join(' ');
            if (beforeCritical !== afterCritical) output.push(`critical ${beforeCritical} -> ${afterCritical}`);
            break;
        }
        case 'BASELINE':
            baseline = { total: current.total, rows: new Map([...current.rows].map(([name, row]) => [name, { es: row.es, ef: row.ef }])) };
            output.push(`baseline saved: ${tasks.size} tasks, duration ${current.total}`); break;
        case 'VARIANCE': {
            output.push(`variance: duration ${baseline.total} -> ${current.total} (${signed(current.total - baseline.total)})`);
            const before = output.length;
            for (const name of [...new Set([...baseline.rows.keys(), ...tasks.keys()])].sort()) {
                const old = baseline.rows.get(name), row = current.rows.get(name);
                if (row === undefined) output.push(name + ' removed');
                else if (old === undefined) output.push(name + ' new');
                else if (old.es !== row.es || old.ef !== row.ef) output.push(`${name} start ${signed(row.es - old.es)} finish ${signed(row.ef - old.ef)}`);
            }
            if (output.length === before) output.push('no task changes');
            break;
        }
    }
}
const input = fs.readFileSync(0, 'utf8').split(/\r?\n/), count = Number(input[0]);
for (const command of input.slice(1, count + 1)) {
    try { execute(command); } catch (error) { output.push(error.message); }
}
if (output.length) process.stdout.write(output.join('\n') + '\n');
