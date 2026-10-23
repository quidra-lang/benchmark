const fs = require('node:fs');

class Network {
    names = [];
    edges = [];
    demands = [];
    owner = { kind: 'none', source: -1, sink: -1 };
    copy() {
        const result = new Network();
        result.names = [...this.names];
        result.demands = [...this.demands];
        result.edges = this.edges.map(edge => ({ ...edge, flow: 0 }));
        return result;
    }
}
const network = new Network();
const output = [];
function fail(message) { throw new Error('ERROR ' + message); }
function vertex(name) {
    const index = network.names.indexOf(name);
    if (index < 0) fail('UNKNOWN NODE ' + name);
    return index;
}
function endpoints(a, b) {
    const source = vertex(a), sink = vertex(b);
    if (source === sink) fail('SAME NODE');
    return [source, sink];
}
function edgeAt(word) {
    const index = Number(word) - 1;
    if (index < 0 || index >= network.edges.length) fail('UNKNOWN EDGE ' + word);
    return network.edges[index];
}
function balances(net) {
    const result = Array(net.names.length).fill(0);
    for (const edge of net.edges) { result[edge.u] += edge.flow; result[edge.v] -= edge.flow; }
    return result;
}
function totalCost(net) { return net.edges.reduce((sum, edge) => sum + edge.flow * edge.cost, 0); }
function globalArcs(net) {
    const forward = net.edges.map((edge, index) => ({ edge: index, forward: true, from: edge.u, to: edge.v }));
    const backward = net.edges.map((edge, index) => ({ edge: index, forward: false, from: edge.v, to: edge.u }));
    return [...forward, ...backward];
}
function adjacency(net) {
    const result = Array.from({ length: net.names.length }, () => []);
    for (const arc of globalArcs(net)) result[arc.from].push(arc);
    return result;
}
function residual(net, arc) {
    const edge = net.edges[arc.edge];
    return arc.forward ? edge.capacity - edge.flow : edge.flow;
}
function push(net, path, amount) {
    for (const arc of path) net.edges[arc.edge].flow += arc.forward ? amount : -amount;
}
function bottleneck(net, path) { return Math.min(...path.map(arc => residual(net, arc))); }
function bfs(net, source, threshold = 1) {
    const level = Array(net.names.length).fill(-1), parent = Array(net.names.length).fill(null), queue = [source];
    const lists = adjacency(net);
    level[source] = 0;
    for (let i = 0; i < queue.length; i++) {
        const u = queue[i];
        for (const arc of lists[u]) if (residual(net, arc) >= threshold && level[arc.to] < 0) {
            level[arc.to] = level[u] + 1; parent[arc.to] = arc; queue.push(arc.to);
        }
    }
    return { level, parent };
}
function restorePath(parent, source, sink) {
    const result = [];
    for (let at = sink; at !== source;) { const arc = parent[at]; result.push(arc); at = arc.from; }
    return result.reverse();
}
function single(net, source, sink, threshold = 1) {
    const search = bfs(net, source, threshold);
    if (search.level[sink] < 0) return null;
    const path = restorePath(search.parent, source, sink), amount = bottleneck(net, path);
    push(net, path, amount);
    return { path, amount, phase: 0, delta: threshold, cost: 0 };
}
function edmondsKarp(net, source, sink) {
    const paths = [];
    while (true) { const augmentation = single(net, source, sink); if (augmentation === null) return paths; paths.push(augmentation); }
}
function dinic(net, source, sink) {
    const paths = [];
    let phases = 0;
    const lists = adjacency(net);
    while (true) {
        const { level } = bfs(net, source);
        if (level[sink] < 0) return { paths, phases };
        phases++;
        const pointers = Array(net.names.length).fill(0);
        let path = [], current = source;
        while (true) {
            if (current === sink) {
                const amount = bottleneck(net, path);
                push(net, path, amount);
                paths.push({ path: [...path], amount, phase: phases, delta: 1, cost: 0 });
                path = []; current = source;
            } else if (pointers[current] >= lists[current].length) {
                if (current === source) break;
                const arc = path.pop(); current = arc.from; pointers[current]++;
            } else {
                const arc = lists[current][pointers[current]];
                if (residual(net, arc) > 0 && level[arc.to] === level[current] + 1) { path.push(arc); current = arc.to; }
                else pointers[current]++;
            }
        }
    }
}
function scaling(net, source, sink) {
    const paths = [], maximum = Math.max(1, ...net.edges.map(edge => edge.capacity));
    let delta = 1;
    while (delta * 2 <= maximum) delta *= 2;
    while (delta >= 1) {
        while (true) { const augmentation = single(net, source, sink, delta); if (augmentation === null) break; paths.push(augmentation); }
        delta = Math.floor(delta / 2);
    }
    return paths;
}
function negativeCycle(net, lowerBounds = false) {
    const distance = Array(net.names.length).fill(0);
    for (let pass = 0; pass < net.names.length; pass++) {
        let changed = false;
        for (const edge of net.edges) if (edge.capacity - (lowerBounds ? edge.lower : 0) > 0 && distance[edge.v] > distance[edge.u] + edge.cost) {
            distance[edge.v] = distance[edge.u] + edge.cost; changed = true;
        }
        if (!changed) return false;
        if (pass + 1 === net.names.length) return true;
    }
    return false;
}
function shortest(net, source, sink) {
    const arcs = globalArcs(net).filter(arc => residual(net, arc) > 0);
    const distance = Array(net.names.length).fill(null), parent = Array(net.names.length).fill(null);
    distance[source] = 0;
    while (true) {
        let changed = false;
        for (const arc of arcs) {
            if (distance[arc.from] === null) continue;
            const cost = net.edges[arc.edge].cost * (arc.forward ? 1 : -1), next = distance[arc.from] + cost;
            if (distance[arc.to] === null || next < distance[arc.to]) { distance[arc.to] = next; parent[arc.to] = arc; changed = true; }
        }
        if (!changed) break;
    }
    return distance[sink] === null ? null : { path: restorePath(parent, source, sink), cost: distance[sink] };
}
function minCost(net, source, sink, target = null) {
    const paths = [];
    let flow = 0, cost = 0;
    while (target === null || flow < target) {
        const cheapest = shortest(net, source, sink);
        if (cheapest === null) break;
        const amount = Math.min(bottleneck(net, cheapest.path), target === null ? Infinity : target - flow);
        push(net, cheapest.path, amount); flow += amount; cost += amount * cheapest.cost;
        paths.push({ path: cheapest.path, amount, phase: 0, delta: 1, cost: cheapest.cost });
    }
    return { paths, flow, cost };
}
function decompose(net) {
    const remaining = net.edges.map(edge => edge.flow), balance = balances(net), result = [];
    while (remaining.some(value => value > 0)) {
        let start = balance.findIndex(value => value > 0);
        if (start < 0) start = net.edges[remaining.findIndex(value => value > 0)].u;
        const vertices = [start], edges = [];
        while (true) {
            const current = vertices[vertices.length - 1];
            const index = net.edges.findIndex((edge, i) => edge.u === current && remaining[i] > 0);
            const next = net.edges[index].v;
            edges.push(index);
            const repeat = vertices.indexOf(next);
            if (repeat >= 0) {
                const cycle = edges.slice(repeat), amount = Math.min(...cycle.map(i => remaining[i]));
                for (const i of cycle) remaining[i] -= amount;
                result.push({ cycle: true, start: next, edges: cycle, amount });
                break;
            }
            vertices.push(next);
            if (balance[next] < 0) {
                const amount = Math.min(...edges.map(i => remaining[i]), balance[start], -balance[next]);
                for (const i of edges) remaining[i] -= amount;
                balance[start] -= amount; balance[next] += amount;
                result.push({ cycle: false, start, edges: [...edges], amount });
                break;
            }
        }
    }
    return result;
}
function pathText(net, path, source) {
    return [net.names[source], ...path.flatMap(arc => [(arc.forward ? '+' : '-') + (arc.edge + 1), net.names[arc.to]])].join(' ');
}
function decompositionText(net, item, originalEdges = Infinity) {
    const result = [net.names[item.start]];
    for (const index of item.edges) if (index < originalEdges) result.push('+' + (index + 1), net.names[net.edges[index].v]);
    return result.join(' ');
}
function flowList() {
    network.edges.forEach((edge, i) => output.push(`FLOW ${i + 1} ${network.names[edge.u]} ${network.names[edge.v]} ${edge.flow}/${edge.capacity}`));
}
function startFlow(source, sink) {
    if (network.owner.kind !== 'flow' || network.owner.source !== source || network.owner.sink !== sink) for (const edge of network.edges) edge.flow = 0;
    network.owner = { kind: 'flow', source, sink };
    return balances(network)[source];
}
function matching(a, b, pairs) {
    const left = a.split(','), right = b.split(','), links = pairs === '-' ? [] : pairs.split(',').map(pair => pair.split('-'));
    const seen = new Set();
    for (const name of [...left, ...right]) { if (seen.has(name)) fail('DUPLICATE VERTEX ' + name); seen.add(name); }
    const used = new Set();
    for (const [u, v] of links) {
        if (!left.includes(u)) fail('UNKNOWN VERTEX ' + u);
        if (!right.includes(v)) fail('UNKNOWN VERTEX ' + v);
        if (used.has(u + '-' + v)) fail('DUPLICATE PAIR ' + u + '-' + v);
        used.add(u + '-' + v);
    }
    const partnerLeft = new Map(), partnerRight = new Map();
    function attempt(name, examined) {
        for (const [u, v] of links) if (u === name && !examined.has(v)) {
            examined.add(v);
            if (!partnerRight.has(v) || attempt(partnerRight.get(v), examined)) { partnerLeft.set(u, v); partnerRight.set(v, u); return true; }
        }
        return false;
    }
    for (const name of left) attempt(name, new Set());
    const free = left.filter(name => !partnerLeft.has(name)), zl = new Set(free), zr = new Set(), queue = [...free];
    for (let i = 0; i < queue.length; i++) for (const [u, v] of links) if (u === queue[i] && partnerLeft.get(u) !== v && !zr.has(v)) {
        zr.add(v);
        const partner = partnerRight.get(v);
        if (partner !== undefined && !zl.has(partner)) { zl.add(partner); queue.push(partner); }
    }
    const cover = [...left.filter(name => !zl.has(name)), ...right.filter(name => zr.has(name))];
    output.push(`MATCH size=${partnerLeft.size} left=${left.length} right=${right.length}`);
    for (const name of left) if (partnerLeft.has(name)) output.push(`PAIR ${name} ${partnerLeft.get(name)}`);
    output.push(`FREE ${free.join(',') || '-'} ${right.filter(name => !partnerRight.has(name)).join(',') || '-'}`,
        `COVER size=${cover.length}${cover.length ? ' ' + cover.join(' ') : ''}`);
    if (free.length) output.push(`HALL ${left.filter(name => zl.has(name)).join(',')} ${right.filter(name => zr.has(name)).join(',') || '-'}`);
}
function assignment(mode, size, words) {
    if (size < 1 || size > 8) fail('BAD SIZE');
    if (words.length !== size * size) fail('BAD LENGTH');
    let best = null, count = 0, chosen = [];
    const current = [];
    function visit(row, used, sum) {
        if (row === size) {
            if (best === null || (mode === 'MIN' ? sum < best : sum > best)) { best = sum; count = 1; chosen = [...current]; }
            else if (sum === best) count++;
            return;
        }
        for (let col = 0; col < size; col++) if (!(used & (1 << col)) && words[row * size + col] !== 'x') {
            current.push(col); visit(row + 1, used | (1 << col), sum + Number(words[row * size + col])); current.pop();
        }
    }
    visit(0, 0, 0);
    if (best === null) output.push(`ASSIGN ${mode} n=${size} infeasible`);
    else {
        output.push(`ASSIGN ${mode} n=${size} total=${best} optimal=${count}`);
        chosen.forEach((col, row) => output.push(`MATE ${row + 1} ${col + 1} ${words[row * size + col]}`));
    }
}
function execute(commandLine) {
    const [command, ...args] = commandLine.split(' '), a = args[0], b = args[1];
    switch (command) {
        case 'NODE': {
            const seen = new Set(network.names);
            for (const name of args) { if (seen.has(name)) fail('DUPLICATE NODE ' + name); seen.add(name); }
            if (network.names.length + args.length > 20) fail('TOO MANY NODES');
            network.names.push(...args); network.demands.push(...args.map(() => 0));
            output.push(`NODE added=${args.length} total=${network.names.length}`);
            break;
        }
        case 'EDGE': {
            const u = vertex(a), v = vertex(b);
            if (u === v) fail('SELF LOOP');
            if (network.edges.length === 60) fail('TOO MANY EDGES');
            const capacity = Number(args[2]), cost = Number(args[3] ?? 0);
            network.edges.push({ u, v, capacity, cost, lower: 0, flow: 0 });
            output.push(`EDGE ${network.edges.length} ${a} ${b} cap=${capacity} cost=${cost}`);
            break;
        }
        case 'LOWER': {
            const edge = edgeAt(a), lower = Number(b);
            if (lower > edge.capacity) fail('BAD BOUND');
            edge.lower = lower; output.push(`LOWER ${a} low=${lower} cap=${edge.capacity}`);
            break;
        }
        case 'CAP': {
            const edge = edgeAt(a), capacity = Number(b);
            if (capacity < edge.lower) fail('BAD BOUND');
            if (capacity < edge.flow) fail('BELOW FLOW');
            edge.capacity = capacity; output.push(`CAP ${a} low=${edge.lower} cap=${capacity}`);
            break;
        }
        case 'COST': { const edge = edgeAt(a); edge.cost = Number(b); output.push(`COST ${a} cost=${b}`); break; }
        case 'DEMAND': {
            const index = vertex(a); network.demands[index] = Number(b);
            output.push(`DEMAND ${a} ${b} total=${network.demands.reduce((sum, demand) => sum + demand, 0)}`);
            break;
        }
        case 'RESET': {
            const count = network.edges.filter(edge => edge.flow !== 0).length;
            for (const edge of network.edges) edge.flow = 0;
            network.owner = { kind: 'none', source: -1, sink: -1 };
            output.push(`RESET edges=${count}`); break;
        }
        case 'CLEAR':
            output.push(`CLEAR nodes=${network.names.length} edges=${network.edges.length}`);
            network.names = []; network.demands = []; network.edges = []; network.owner = { kind: 'none', source: -1, sink: -1 };
            break;
        case 'SHOW': {
            const out = Array(network.names.length).fill(0), incoming = Array(network.names.length).fill(0);
            for (const edge of network.edges) { out[edge.u] += edge.flow; incoming[edge.v] += edge.flow; }
            const owner = network.owner;
            output.push(`NETWORK nodes=${network.names.length} edges=${network.edges.length}`);
            output.push(owner.kind === 'none' ? 'STATE none' : owner.kind === 'circulation' ? `STATE circulation cost=${totalCost(network)}` : `STATE flow ${network.names[owner.source]} ${network.names[owner.sink]} value=${balances(network)[owner.source]} cost=${totalCost(network)}`);
            network.names.forEach((name, i) => output.push(`NODE ${name} demand=${network.demands[i]} out=${out[i]} in=${incoming[i]}`));
            network.edges.forEach((edge, i) => output.push(`EDGE ${i + 1} ${network.names[edge.u]} ${network.names[edge.v]} cap=${edge.capacity} cost=${edge.cost} low=${edge.lower} flow=${edge.flow}`));
            break;
        }
        case 'AUGMENT': case 'MAXFLOW': case 'DINIC': case 'SCALING': case 'MINCUT': {
            const [source, sink] = endpoints(a, b), start = startFlow(source, sink);
            if (command === 'AUGMENT') {
                const augmentation = single(network, source, sink);
                output.push(`AUGMENT ${a} ${b} value=${balances(network)[source]}${augmentation === null ? ' none' : ` amount=${augmentation.amount} ${pathText(network, augmentation.path, source)}`}`);
                break;
            }
            const result = command === 'DINIC' ? dinic(network, source, sink) : { paths: command === 'SCALING' ? scaling(network, source, sink) : edmondsKarp(network, source, sink), phases: 0 };
            const value = balances(network)[source];
            if (command === 'MINCUT') {
                const { level } = bfs(network, source), cut = network.edges.map((edge, i) => i).filter(i => level[network.edges[i].u] >= 0 && level[network.edges[i].v] < 0);
                output.push(`MINCUT ${a} ${b} value=${value} edges=${cut.length}`,
                    'SOURCE ' + network.names.filter((_, i) => level[i] >= 0).join(' '), 'SINK ' + network.names.filter((_, i) => level[i] < 0).join(' '));
                for (const i of cut) { const edge = network.edges[i]; output.push(`CUT ${i + 1} ${network.names[edge.u]} ${network.names[edge.v]} ${edge.capacity}`); }
            } else {
                output.push(`${command} ${a} ${b} value=${value} start=${start}${command === 'DINIC' ? ` phases=${result.phases}` : ''} paths=${result.paths.length}`);
                result.paths.forEach((item, i) => output.push(`AUG ${i + 1}${command === 'DINIC' ? ` phase=${item.phase}` : command === 'SCALING' ? ` delta=${item.delta}` : ''} amount=${item.amount} ${pathText(network, item.path, source)}`));
                flowList();
            }
            break;
        }
        case 'SENSITIVITY': {
            const [source, sink] = endpoints(a, b), base = network.copy();
            edmondsKarp(base, source, sink); const value = balances(base)[source], effective = [];
            for (let i = 0; i < network.edges.length; i++) {
                const up = network.copy(); up.edges[i].capacity++; edmondsKarp(up, source, sink);
                let downEffective = false;
                if (network.edges[i].capacity > 0) { const down = network.copy(); down.edges[i].capacity--; edmondsKarp(down, source, sink); downEffective = balances(down)[source] < value; }
                effective.push({ up: balances(up)[source] > value, down: downEffective });
            }
            output.push(`SENSITIVITY ${a} ${b} value=${value} up=${effective.filter(item => item.up).length} down=${effective.filter(item => item.down).length}`);
            effective.forEach((item, i) => { if (item.up || item.down) { const edge = network.edges[i]; output.push(`CRITICAL ${i + 1} ${network.names[edge.u]} ${network.names[edge.v]} up=${item.up ? 'yes' : 'no'} down=${item.down ? 'yes' : 'no'}`); } });
            break;
        }
        case 'MINCOST': {
            const [source, sink] = endpoints(a, b);
            if (negativeCycle(network)) fail('NEGATIVE CYCLE');
            const working = network.copy(), target = args[2] === 'MAX' ? null : Number(args[2]), result = minCost(working, source, sink, target);
            if (target !== null && result.flow < target) { output.push(`MINCOST ${a} ${b} k=${args[2]} infeasible max=${result.flow}`); break; }
            network.edges.forEach((edge, i) => edge.flow = working.edges[i].flow); network.owner = { kind: 'flow', source, sink };
            output.push(`MINCOST ${a} ${b} k=${args[2]} flow=${result.flow} cost=${result.cost}`);
            result.paths.forEach((item, i) => output.push(`AUG ${i + 1} amount=${item.amount} cost=${item.cost} ${pathText(working, item.path, source)}`));
            flowList(); break;
        }
        case 'DISJOINT': {
            const [source, sink] = endpoints(a, b), working = network.copy(), original = network.edges.length;
            for (const edge of working.edges) edge.capacity = edge.capacity > 0 ? 1 : 0;
            if (args[2] === 'VERTEX') {
                const exits = working.names.map((_, i) => i);
                for (let i = 0; i < network.names.length; i++) if (i !== source && i !== sink) { exits[i] = working.names.length; working.names.push(network.names[i]); working.demands.push(0); }
                for (const edge of working.edges) edge.u = exits[edge.u];
                for (let i = 0; i < network.names.length; i++) if (i !== source && i !== sink) working.edges.push({ u: i, v: exits[i], capacity: 1, cost: 0, lower: 0, flow: 0 });
            }
            edmondsKarp(working, source, sink);
            const paths = decompose(working).filter(item => !item.cycle);
            output.push(`DISJOINT ${a} ${b} ${args[2]} count=${paths.length}`);
            paths.forEach((item, i) => output.push(`PATH ${i + 1} ${decompositionText(working, item, original)}`));
            break;
        }
        case 'DECOMPOSE': {
            const pieces = decompose(network);
            output.push(`DECOMPOSE paths=${pieces.filter(item => !item.cycle).length} cycles=${pieces.filter(item => item.cycle).length}`);
            let paths = 0, cycles = 0;
            for (const item of pieces) output.push(`${item.cycle ? 'CYCLE' : 'PATH'} ${item.cycle ? ++cycles : ++paths} amount=${item.amount} ${decompositionText(network, item)}`);
            break;
        }
        case 'VERIFY': {
            const violations = [], balance = balances(network);
            network.edges.forEach((edge, i) => { if (edge.flow < edge.lower) violations.push(`LOW ${i + 1} flow=${edge.flow} low=${edge.lower}`); });
            network.names.forEach((name, i) => {
                if (network.owner.kind === 'flow' && (network.owner.source === i || network.owner.sink === i)) return;
                const need = network.owner.kind === 'flow' ? 0 : network.demands[i];
                if (-balance[i] !== need) violations.push(`BALANCE ${name} net=${-balance[i]} need=${need}`);
            });
            output.push(...(violations.length ? [`VERIFY violations=${violations.length}`, ...violations] : ['VERIFY ok']));
            break;
        }
        case 'CIRCULATION': {
            if (a === 'MINCOST' && negativeCycle(network, true)) fail('NEGATIVE CYCLE');
            const sum = network.demands.reduce((total, demand) => total + demand, 0);
            if (sum !== 0) { output.push(`CIRCULATION infeasible unbalanced=${sum}`); break; }
            const working = network.copy(), balance = [...network.demands], source = working.names.length, sink = source + 1;
            working.names.push('superSource', 'superSink'); working.demands.push(0, 0);
            working.edges.forEach((edge, i) => { const lower = network.edges[i].lower; edge.capacity -= lower; balance[edge.u] += lower; balance[edge.v] -= lower; });
            for (let i = 0; i < balance.length; i++) if (balance[i] < 0) working.edges.push({ u: source, v: i, capacity: -balance[i], cost: 0, lower: 0, flow: 0 });
            for (let i = 0; i < balance.length; i++) if (balance[i] > 0) working.edges.push({ u: i, v: sink, capacity: balance[i], cost: 0, lower: 0, flow: 0 });
            if (a === 'ANY') edmondsKarp(working, source, sink); else minCost(working, source, sink);
            const required = balance.filter(value => value > 0).reduce((total, value) => total + value, 0), achieved = working.edges.filter(edge => edge.v === sink).reduce((total, edge) => total + edge.flow, 0);
            if (achieved < required) {
                const { level } = bfs(working, source);
                output.push(`CIRCULATION infeasible required=${required} achieved=${achieved}`, 'CUT ' + network.names.filter((_, i) => level[i] >= 0).join(' '));
            } else {
                network.edges.forEach((edge, i) => edge.flow = edge.lower + working.edges[i].flow); network.owner = { kind: 'circulation', source: -1, sink: -1 };
                output.push(`CIRCULATION feasible required=${required} cost=${totalCost(network)}`); flowList();
            }
            break;
        }
        case 'MATCH': matching(a, b, args[2]); break;
        case 'ASSIGN': assignment(a, Number(b), args.slice(2)); break;
    }
}
const input = fs.readFileSync(0, 'utf8').split(/\r?\n/), count = Number(input[0]);
for (const command of input.slice(1, count + 1)) {
    try { execute(command); } catch (error) { output.push(error.message); }
}
if (output.length) process.stdout.write(output.join('\n') + '\n');
