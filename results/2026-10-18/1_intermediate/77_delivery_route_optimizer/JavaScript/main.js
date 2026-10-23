const fs = require('node:fs');

const stops = new Map(), output = [];
let depot = null, departure = 480, tour = null, plan = null;
function fail(message) { throw new Error('error: ' + message); }
function ids() { return [...stops.keys()].sort((a, b) => a - b); }
function point(id) { return id === 0 ? depot : stops.get(id); }
function distance(a, b) { const x = point(a), y = point(b); return Math.abs(x.x - y.x) + Math.abs(x.y - y.y); }
function length(route) { const path = [0, ...route, 0]; return path.slice(1).reduce((sum, id, i) => sum + distance(path[i], id), 0); }
function load(route) { return route.reduce((sum, id) => sum + stops.get(id).demand, 0); }
function notation(route) { return ['D', ...route, 'D'].join('-'); }
function location(id) { return id === 0 ? 'D' : String(id); }
function minute(text) { const [h, m] = text.split(':').map(Number); return h * 60 + m; }
function clock(time) { return String(Math.floor(time / 60)).padStart(2, '0') + ':' + String(time % 60).padStart(2, '0'); }
function decimal(tenths) { return Math.floor(tenths / 10) + '.' + tenths % 10; }
function requireStops() { if (depot === null) fail('no depot'); if (!stops.size) fail('no stops'); }
function requireTour() { if (tour === null) fail('no tour'); return tour; }
function requirePlan() { if (plan === null) fail('no plan'); return plan; }
function checkCapacity(capacity) { for (const id of ids()) if (stops.get(id).demand > capacity) fail(`stop ${id} demand ${stops.get(id).demand} exceeds capacity ${capacity}`); }
function normalize(routes) {
    return routes.filter(route => route.length).map(route => route[0] > route.at(-1) ? [...route].reverse() : route)
        .sort((a, b) => Math.min(...a) - Math.min(...b));
}
function planLength(value) { return value.routes.reduce((sum, route) => sum + length(route), 0); }
function routeLines(value) { value.routes.forEach((route, i) => output.push(`route ${i + 1}: ${notation(route)} load ${load(route)} length ${length(route)}`)); }
function simulate(route, print = false) {
    let time = departure, previous = 0, waiting = 0, service = 0, violations = 0, lateness = 0;
    for (const id of route) {
        const stop = stops.get(id), arrival = time + distance(previous, id), wait = stop.open === null ? 0 : Math.max(0, stop.open - arrival), begin = arrival + wait;
        const late = stop.close === null ? 0 : Math.max(0, arrival - stop.close);
        time = begin + stop.service; waiting += wait; service += stop.service; if (late > 0) violations++; lateness += late;
        if (print) output.push(`${id} arrive ${clock(arrival)} wait ${wait} begin ${clock(begin)} leave ${clock(time)} ${late ? 'late ' + late : 'ok'}`);
        previous = id;
    }
    time += distance(previous, 0);
    if (print) output.push(`return ${clock(time)}, travel ${length(route)}, wait ${waiting}, service ${service}, violations ${violations}, lateness ${lateness}`);
    return { time, violations, lateness };
}
function twoOpt(route, announce) {
    let moves = 0;
    while (true) {
        let changed = false;
        scan: for (let i = 0; i + 1 < route.length; i++) for (let j = i + 1; j < route.length; j++) {
            const before = route[i - 1] ?? 0, after = route[j + 1] ?? 0;
            const gain = distance(before, route[i]) + distance(route[j], after) - distance(before, route[j]) - distance(route[i], after);
            if (gain > 0) {
                if (announce) output.push(`reverse ${route[i]}..${route[j]} gain ${gain}`);
                route.splice(i, j - i + 1, ...route.slice(i, j + 1).reverse()); moves++; changed = true; break scan;
            }
        }
        if (!changed) return moves;
    }
}
function exact() {
    const names = ids(), memo = new Map();
    function best(previous, mask) {
        if (mask === 0) return distance(previous, 0);
        const key = previous + ':' + mask;
        if (memo.has(key)) return memo.get(key);
        let value = Infinity;
        for (let i = 0; i < names.length; i++) if (mask & (1 << i)) value = Math.min(value, distance(previous, names[i]) + best(names[i], mask ^ (1 << i)));
        memo.set(key, value); return value;
    }
    const result = []; let previous = 0, mask = (1 << names.length) - 1;
    while (mask) {
        const target = best(previous, mask);
        for (let i = 0; i < names.length; i++) if (mask & (1 << i) && distance(previous, names[i]) + best(names[i], mask ^ (1 << i)) === target) {
            result.push(names[i]); previous = names[i]; mask ^= 1 << i; break;
        }
    }
    return result;
}
function spanning(names, first) {
    const tree = [first], remaining = names.filter(id => id !== first), edges = [];
    let total = 0;
    while (remaining.length) {
        let chosen = -1, parent = -1, weight = Infinity;
        for (const id of remaining) for (const from of tree) if (distance(from, id) < weight) { chosen = id; parent = from; weight = distance(from, id); }
        total += weight; edges.push(location(parent) + '-' + chosen); tree.push(chosen); remaining.splice(remaining.indexOf(chosen), 1);
    }
    return { total, edges };
}
function improvePlan(command) {
    const value = requirePlan(), oldLength = planLength(value), oldCount = value.routes.length;
    let moves = 0;
    function step() {
        const routes = value.routes, capacity = value.capacity;
        if (command === 'RELOCATE') {
            for (let r = 0; r < routes.length; r++) for (let p = 0; p < routes[r].length; p++) for (let t = 0; t < routes.length; t++) if (t !== r) {
                const a = routes[r], b = routes[t], c = a[p];
                if (load(b) + stops.get(c).demand > capacity) continue;
                for (let j = 0; j <= b.length; j++) {
                    const before = a[p - 1] ?? 0, after = a[p + 1] ?? 0, u = b[j - 1] ?? 0, v = b[j] ?? 0;
                    const gain = distance(before, c) + distance(c, after) - distance(before, after) - distance(u, c) - distance(c, v) + distance(u, v);
                    if (gain > 0) { output.push(`relocate ${c} from route ${r + 1} to route ${t + 1} after ${location(u)} gain ${gain}`); a.splice(p, 1); b.splice(j, 0, c); value.routes = normalize(routes); return true; }
                }
            }
        } else if (command === 'EXCHANGE') {
            for (let r = 0; r < routes.length; r++) for (let t = r + 1; t < routes.length; t++) for (let p = 0; p < routes[r].length; p++) for (let j = 0; j < routes[t].length; j++) {
                const a = routes[r], b = routes[t], c = a[p], e = b[j];
                if (load(a) - stops.get(c).demand + stops.get(e).demand > capacity || load(b) - stops.get(e).demand + stops.get(c).demand > capacity) continue;
                const nextA = [...a], nextB = [...b]; nextA[p] = e; nextB[j] = c;
                const gain = length(a) + length(b) - length(nextA) - length(nextB);
                if (gain > 0) { output.push(`exchange ${c} (route ${r + 1}) with ${e} (route ${t + 1}) gain ${gain}`); routes[r] = nextA; routes[t] = nextB; value.routes = normalize(routes); return true; }
            }
        } else {
            for (let r = 0; r < routes.length; r++) for (let t = r + 1; t < routes.length; t++) for (let i = 0; i <= routes[r].length; i++) for (let j = 0; j <= routes[t].length; j++) {
                const a = routes[r], b = routes[t], nextA = [...a.slice(0, i), ...b.slice(j)], nextB = [...b.slice(0, j), ...a.slice(i)];
                if (load(nextA) > capacity || load(nextB) > capacity) continue;
                const x = a[i - 1] ?? 0, y = b[j - 1] ?? 0, afterA = a[i] ?? 0, afterB = b[j] ?? 0;
                const gain = distance(x, afterA) + distance(y, afterB) - distance(x, afterB) - distance(y, afterA);
                if (gain > 0) { output.push(`cross route ${r + 1} after ${location(x)} with route ${t + 1} after ${location(y)} gain ${gain}`); routes[r] = nextA; routes[t] = nextB; value.routes = normalize(routes); return true; }
            }
        }
        return false;
    }
    while (step()) moves++;
    output.push(`${command.toLowerCase()}: moves ${moves}${command === 'EXCHANGE' ? '' : `, routes ${oldCount} -> ${value.routes.length}`}, length ${oldLength} -> ${planLength(value)}`);
}
function execute(line) {
    const [command, ...args] = line.split(' '), a = Number(args[0]), b = Number(args[1]);
    if (command === 'DEPOT') { depot = { x: a, y: b }; output.push(`depot at (${a},${b})`); return; }
    if (command === 'START') { departure = minute(args[0]); output.push('start ' + clock(departure)); return; }
    if (command === 'STOP') {
        if (stops.has(a)) fail(`stop ${a} already exists`);
        const open = args.length > 5 ? minute(args[5]) : null, close = args.length > 5 ? minute(args[6]) : null;
        if (open !== null && open > close) fail('invalid window');
        stops.set(a, { x: b, y: Number(args[2]), demand: Number(args[3]), service: Number(args[4]), open, close }); tour = null; plan = null;
        output.push(`stop ${a} added`); return;
    }
    if (command === 'REMOVE') {
        if (!stops.delete(a)) fail('unknown stop ' + a);
        if (!stops.size) { tour = null; plan = null; }
        else { if (tour !== null) tour = tour.filter(id => id !== a); if (plan !== null) plan.routes = normalize(plan.routes.map(route => route.filter(id => id !== a))); }
        output.push(`stop ${a} removed`); return;
    }
    if (command === 'LIST') {
        output.push(depot === null ? 'depot none' : `depot (${depot.x},${depot.y})`, 'start ' + clock(departure), 'stops ' + stops.size);
        for (const id of ids()) { const stop = stops.get(id); output.push(`${id} at (${stop.x},${stop.y}) demand ${stop.demand} service ${stop.service} window ${stop.open === null ? 'none' : clock(stop.open) + '-' + clock(stop.close)}`); }
        return;
    }
    if (command === 'MATRIX') {
        if (depot === null) fail('no depot');
        const locations = [0, ...ids()], rows = [['', ...locations.map(location)], ...locations.map(id => [location(id), ...locations.map(other => String(distance(id, other)))])];
        const width = Math.max(...rows.flat().map(cell => cell.length));
        output.push(...rows.map(row => row.map(cell => cell.padStart(width)).join(' '))); return;
    }
    if (['ORDER', 'NEAREST', 'INSERTION', 'EXACT', 'BOUND', 'VRP', 'SWEEP'].includes(command)) requireStops();
    if (command === 'ORDER') {
        const order = args.map(Number);
        for (const id of order) if (!stops.has(id)) fail('unknown stop ' + id);
        const seen = new Set(); for (const id of order) { if (seen.has(id)) fail('duplicate stop ' + id); seen.add(id); }
        if (order.length !== stops.size) fail(`order has ${order.length} stops, expected ${stops.size}`);
        tour = order;
    } else if (command === 'NEAREST') {
        const remaining = ids(), route = []; let previous = 0;
        while (remaining.length) { remaining.sort((a, b) => distance(previous, a) - distance(previous, b) || a - b); previous = remaining.shift(); route.push(previous); }
        tour = route;
    } else if (command === 'INSERTION') {
        const remaining = ids(), route = [];
        while (remaining.length) {
            let best = Infinity, chosen = -1, position = -1;
            for (const id of remaining) for (let j = 0; j <= route.length; j++) { const before = route[j - 1] ?? 0, after = route[j] ?? 0, increase = distance(before, id) + distance(id, after) - distance(before, after); if (increase < best) { best = increase; chosen = id; position = j; } }
            route.splice(position, 0, chosen); remaining.splice(remaining.indexOf(chosen), 1);
        }
        tour = route;
    } else if (command === 'EXACT') { if (stops.size > 10) fail(`too many stops for exact (${stops.size})`); tour = exact(); }
    if (['ORDER', 'NEAREST', 'INSERTION', 'EXACT'].includes(command)) { output.push(`${command.toLowerCase()}: ${notation(tour)} length ${length(tour)}`); return; }
    if (command === 'TOUR') { const route = requireTour(); output.push(`tour: ${notation(route)} length ${length(route)}`); return; }
    if (['TWOOPT', 'OROPT', 'SWAP'].includes(command)) {
        const route = requireTour(), old = length(route); let moves = 0;
        if (command === 'TWOOPT') moves = twoOpt(route, true);
        else while (true) {
            let changed = false;
            if (command === 'SWAP') {
                scan: for (let i = 0; i + 1 < route.length; i++) for (let j = i + 1; j < route.length; j++) {
                    const next = [...route]; [next[i], next[j]] = [next[j], next[i]]; const gain = length(route) - length(next);
                    if (gain > 0) { output.push(`swap ${route[i]} and ${route[j]} gain ${gain}`); route.splice(0, route.length, ...next); moves++; changed = true; break scan; }
                }
            } else {
                scan: for (let size = 1; size <= 3; size++) for (let i = 0; i + size <= route.length; i++) {
                    const segment = route.slice(i, i + size), rest = [...route.slice(0, i), ...route.slice(i + size)];
                    for (let j = 0; j <= rest.length; j++) if (j !== i) {
                        const next = [...rest.slice(0, j), ...segment, ...rest.slice(j)], gain = length(route) - length(next);
                        if (gain > 0) { output.push(`move ${segment.join('-')} after ${location(rest[j - 1] ?? 0)} gain ${gain}`); route.splice(0, route.length, ...next); moves++; changed = true; break scan; }
                    }
                }
            }
            if (!changed) break;
        }
        output.push(`${command.toLowerCase()}: moves ${moves}, length ${old} -> ${length(route)}`); return;
    }
    if (command === 'TIMECHECK') { const route = args.length ? requirePlan().routes[a - 1] : requireTour(); if (route === undefined) fail('no route ' + a); output.push(`timecheck ${args.length ? 'route ' + a : 'tour'} depart ${clock(departure)}`); simulate(route, true); return; }
    if (command === 'BOUND') {
        const names = ids(), mst = spanning(names, 0), near = names.map(id => distance(0, id)).sort((a, b) => a - b);
        const oneTree = names.length === 1 ? 2 * near[0] : spanning(names, names[0]).total + near[0] + near[1], bound = Math.max(mst.total, oneTree);
        output.push(`mst: ${mst.edges.join(' ')} (length ${mst.total})`, `bound: mst ${mst.total}, one-tree ${oneTree}, best ${bound}`,
            tour === null ? 'gap: no tour' : `gap: tour ${length(tour)}, ${decimal(bound > 0 ? Math.floor((2000 * (length(tour) - bound) + bound) / (2 * bound)) : 0)}%`); return;
    }
    if (command === 'VRP' || command === 'SWEEP' || command === 'SPLIT') {
        if (command === 'SPLIT') requireTour(); checkCapacity(a);
        let routes, merges = 0;
        if (command === 'VRP') {
            const limit = args.length > 1 ? b : null;
            if (limit !== null) for (const id of ids()) if (2 * distance(0, id) > limit) fail(`stop ${id} too far for limit ${limit}`);
            routes = ids().map(id => [id]); const pairs = [];
            for (const i of ids()) for (const j of ids()) if (i < j) { const saving = distance(0, i) + distance(0, j) - distance(i, j); if (saving > 0) pairs.push({ i, j, saving }); }
            pairs.sort((a, b) => b.saving - a.saving || a.i - b.i || a.j - b.j);
            for (const pair of pairs) {
                const x = routes.findIndex(route => route.includes(pair.i)), y = routes.findIndex(route => route.includes(pair.j));
                const first = routes[x], second = routes[y];
                if (x === y || ![first[0], first.at(-1)].includes(pair.i) || ![second[0], second.at(-1)].includes(pair.j) || load(first) + load(second) > a) continue;
                const joined = [...(first.at(-1) === pair.i ? first : [...first].reverse()), ...(second[0] === pair.j ? second : [...second].reverse())];
                if (limit !== null && length(joined) > limit) continue;
                routes = routes.filter((_, i) => i !== x && i !== y); routes.push(joined); merges++;
            }
        } else if (command === 'SPLIT') {
            const route = requireTour(), values = Array(route.length + 1).fill(Infinity), previous = Array(route.length + 1).fill(-1); values[0] = 0;
            for (let j = 1; j <= route.length; j++) for (let i = 0; i < j; i++) { const segment = route.slice(i, j), candidate = values[i] + length(segment); if (load(segment) <= a && candidate < values[j]) { values[j] = candidate; previous[j] = i; } }
            routes = []; for (let j = route.length; j > 0; j = previous[j]) routes.push(route.slice(previous[j], j));
        } else {
            const ordered = ids().sort((a, b) => {
                const x = stops.get(a), y = stops.get(b), dx = x.x - depot.x, dy = x.y - depot.y, ex = y.x - depot.x, ey = y.y - depot.y;
                const zeroA = dx === 0 && dy === 0, zeroB = ex === 0 && ey === 0;
                if (zeroA || zeroB) return zeroA && zeroB ? a - b : zeroA ? -1 : 1;
                const halfA = dy > 0 || dy === 0 && dx > 0 ? 0 : 1, halfB = ey > 0 || ey === 0 && ex > 0 ? 0 : 1, cross = dx * ey - dy * ex;
                return halfA - halfB || (cross === 0 ? distance(0, a) - distance(0, b) || a - b : cross > 0 ? -1 : 1);
            });
            routes = [[]]; for (const id of ordered) { if (load(routes.at(-1)) + stops.get(id).demand > a) routes.push([]); routes.at(-1).push(id); }
        }
        plan = { capacity: a, routes: normalize(routes) };
        output.push(`${command.toLowerCase()}: capacity ${a}${command === 'VRP' ? `, merges ${merges}` : ''}, routes ${plan.routes.length}, length ${planLength(plan)}`); routeLines(plan); return;
    }
    if (command === 'ROUTES') { const value = requirePlan(); output.push(`plan: capacity ${value.capacity}, routes ${value.routes.length}, length ${planLength(value)}`); routeLines(value); return; }
    if (['RELOCATE', 'EXCHANGE', 'CROSS'].includes(command)) { improvePlan(command); return; }
    if (command === 'ROUTEOPT') {
        const value = requirePlan(), old = planLength(value);
        value.routes.forEach((route, i) => { const before = length(route), moves = twoOpt(route, false); output.push(`route ${i + 1}: moves ${moves}, length ${before} -> ${length(route)}`); });
        value.routes = normalize(value.routes); output.push(`routeopt: length ${old} -> ${planLength(value)}`); return;
    }
    if (command === 'REPORT') {
        const all = [...stops.values()]; output.push(`report: stops ${stops.size}, demand ${all.reduce((sum, stop) => sum + stop.demand, 0)}, service ${all.reduce((sum, stop) => sum + stop.service, 0)}, windows ${all.filter(stop => stop.open !== null).length}`);
        if (tour === null) output.push('tour: none'); else { const result = simulate(tour); output.push(`tour: length ${length(tour)}, return ${clock(result.time)}, violations ${result.violations}, lateness ${result.lateness}`); }
        if (plan === null) output.push('plan: none'); else {
            const results = plan.routes.map(route => simulate(route)), denominator = plan.routes.length * plan.capacity, utilization = Math.floor((2000 * plan.routes.reduce((sum, route) => sum + load(route), 0) + denominator) / (2 * denominator));
            output.push(`plan: capacity ${plan.capacity}, routes ${plan.routes.length}, length ${planLength(plan)}, utilization ${decimal(utilization)}%, return ${clock(Math.max(...results.map(result => result.time)))}, violations ${results.reduce((sum, result) => sum + result.violations, 0)}, lateness ${results.reduce((sum, result) => sum + result.lateness, 0)}`);
        }
    }
}
const input = fs.readFileSync(0, 'utf8').split(/\r?\n/), count = Number(input[0]);
for (const line of input.slice(1, count + 1)) { try { execute(line); } catch (error) { output.push(error.message); } }
if (output.length) process.stdout.write(output.join('\n') + '\n');
