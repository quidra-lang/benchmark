const fs = require('node:fs');

class Graph {
    constructor(n) { this.n = n; this.rows = Array(n).fill(0); }
    add(u, v) { this.rows[u] |= 1 << v; this.rows[v] |= 1 << u; }
    adjacent(u, v) { return (this.rows[u] & (1 << v)) !== 0; }
    neighbors(u) { return Array.from({ length: this.n }, (_, v) => v).filter(v => this.adjacent(u, v)); }
    edges() {
        const result = [];
        for (let u = 0; u < this.n; u++) for (let v = u + 1; v < this.n; v++) if (this.adjacent(u, v)) result.push([u, v]);
        return result;
    }
}
const registry = new Map();
const output = [];
function fail(message) { throw new Error(`error: ${message}`); }
function lex(a, b) {
    for (let i = 0; i < Math.min(a.length, b.length); i++) if (a[i] !== b[i]) return a[i] - b[i];
    return a.length - b.length;
}
function popcount(mask) {
    let count = 0;
    while (mask) { mask &= mask - 1; count++; }
    return count;
}
function cells(colors) {
    const result = Array.from({ length: Math.max(...colors) + 1 }, () => []);
    colors.forEach((color, vertex) => result[color].push(vertex));
    return result;
}
function refine(graph, initial) {
    let colors = [...initial], rounds = 0;
    while (true) {
        const signatures = colors.map((color, vertex) => [color, ...graph.neighbors(vertex).map(v => colors[v]).sort((a, b) => a - b)]);
        const order = Array.from({ length: graph.n }, (_, v) => v).sort((a, b) => lex(signatures[a], signatures[b]));
        const next = Array(graph.n).fill(0);
        let color = 0;
        for (let i = 0; i < order.length; i++) {
            if (i && lex(signatures[order[i - 1]], signatures[order[i]]) !== 0) color++;
            next[order[i]] = color;
        }
        if (color + 1 === Math.max(...colors) + 1) return { colors, rounds };
        colors = next; rounds++;
    }
}
function stable(graph) {
    if (!graph.stable) {
        const degrees = graph.rows.map(popcount), unique = [...new Set(degrees)].sort((a, b) => a - b);
        graph.stable = refine(graph, degrees.map(degree => unique.indexOf(degree)));
    }
    return graph.stable;
}
function individualize(colors, vertex) {
    const x = colors[vertex];
    return colors.map((color, w) => color < x || w === vertex ? color : color + 1);
}
function leafString(graph, labels) {
    const inverse = Array(graph.n);
    labels.forEach((label, v) => inverse[label] = v);
    let result = '';
    for (let i = 0; i < graph.n; i++) for (let j = i + 1; j < graph.n; j++) result += graph.adjacent(inverse[i], inverse[j]) ? '1' : '0';
    return result;
}
function canon(graph) {
    if (graph.canonical) return graph.canonical;
    const result = { nodes: 0, leaves: 0, labels: [], string: '', bestLeaves: [] };
    function visit(colors) {
        result.nodes++;
        const partition = cells(colors);
        if (partition.length === graph.n) {
            result.leaves++;
            const string = leafString(graph, colors);
            if (!result.bestLeaves.length || string > result.string) {
                result.string = string;
                result.labels = [...colors];
                result.bestLeaves = [[...colors]];
            } else if (string === result.string) result.bestLeaves.push([...colors]);
            return;
        }
        const chosen = partition.filter(cell => cell.length > 1).reduce((best, cell) => cell.length < best.length ? cell : best);
        for (const vertex of chosen) visit(refine(graph, individualize(colors, vertex)).colors);
    }
    visit(stable(graph).colors);
    graph.canonical = result;
    return result;
}
function invariants(graph) {
    if (graph.invariants) return graph.invariants;
    const n = graph.n, degrees = graph.rows.map(popcount).sort((a, b) => b - a), sizes = [];
    const seen = new Set();
    let triangles = 0, shortest = Infinity, bipartite = true;
    const eccentricities = [];
    for (let u = 0; u < n; u++) for (let v = u + 1; v < n; v++) for (let w = v + 1; w < n; w++) {
        if (graph.adjacent(u, v) && graph.adjacent(u, w) && graph.adjacent(v, w)) triangles++;
    }
    for (let start = 0; start < n; start++) {
        const distance = Array(n).fill(-1), parent = Array(n).fill(-1), queue = [start];
        distance[start] = 0;
        for (let i = 0; i < queue.length; i++) {
            const u = queue[i];
            for (const v of graph.neighbors(u)) {
                if (distance[v] < 0) { distance[v] = distance[u] + 1; parent[v] = u; queue.push(v); }
                else if (parent[u] !== v) shortest = Math.min(shortest, distance[u] + distance[v] + 1);
                if (distance[v] % 2 === distance[u] % 2) bipartite = false;
            }
        }
        eccentricities.push(Math.max(...distance));
        if (!seen.has(start)) { sizes.push(queue.length); for (const v of queue) seen.add(v); }
    }
    sizes.sort((a, b) => b - a);
    const result = {
        degrees, triangles, sizes, girth: shortest === Infinity ? 'none' : String(shortest),
        diameter: sizes.length > 1 ? 'INF' : String(Math.max(...eccentricities)),
        radius: sizes.length > 1 ? 'INF' : String(Math.min(...eccentricities)),
        bipartite: bipartite ? 'yes' : 'no'
    };
    graph.invariants = result;
    return result;
}
function clique(graph) {
    let best = [];
    for (let mask = 1; mask < 1 << graph.n; mask++) {
        const vertices = Array.from({ length: graph.n }, (_, v) => v).filter(v => (mask & (1 << v)) !== 0);
        if (vertices.length < best.length) continue;
        if (vertices.every(u => vertices.every(v => u === v || graph.adjacent(u, v))) &&
            (vertices.length > best.length || lex(vertices, best) < 0)) best = vertices;
    }
    return best;
}
function coloring(graph, lower) {
    const colors = Array(graph.n).fill(-1);
    function search(vertex, count) {
        if (vertex === graph.n) return true;
        for (let color = 0; color < count; color++) {
            let valid = true;
            for (let u = 0; u < vertex; u++) if (colors[u] === color && graph.adjacent(u, vertex)) { valid = false; break; }
            if (!valid) continue;
            colors[vertex] = color;
            if (search(vertex + 1, count)) return true;
        }
        colors[vertex] = -1;
        return false;
    }
    for (let count = lower; count <= graph.n; count++) if (search(0, count)) return [...colors];
    return colors;
}
class DisjointSet {
    constructor(n) { this.parent = Array.from({ length: n }, (_, i) => i); }
    find(x) { return this.parent[x] === x ? x : this.parent[x] = this.find(this.parent[x]); }
    join(a, b) { this.parent[this.find(b)] = this.find(a); }
    groups() {
        const groups = new Map();
        for (let i = 0; i < this.parent.length; i++) {
            const root = this.find(i);
            if (!groups.has(root)) groups.set(root, []);
            groups.get(root).push(i);
        }
        return [...groups.values()].sort((a, b) => a[0] - b[0]);
    }
}
const formats = new Map([
    ['GRAPH', { fixed: ['name', 'num'], rest: 'edge' }],
    ...['CYCLE', 'PATH', 'COMPLETE', 'STAR', 'WHEEL', 'HYPERCUBE'].map(command => [command, { fixed: ['name', 'num'] }]),
    ['BIPARTITE', { fixed: ['name', 'num', 'num'] }], ['PETERSEN', { fixed: ['name'] }],
    ['CIRCULANT', { fixed: ['name', 'num', 'num'], rest: 'num' }], ['GRID', { fixed: ['name', 'num', 'num'] }],
    ...['COMPLEMENT', 'LINE', 'CANONIZE'].map(command => [command, { fixed: ['name', 'graph'] }]),
    ...['PRODUCT', 'UNION'].map(command => [command, { fixed: ['name', 'graph', 'graph'] }]),
    ['RELABEL', { fixed: ['name', 'graph'], rest: 'num' }], ['INDUCED', { fixed: ['name', 'graph', 'num'], rest: 'num' }],
    ...['DELETE', 'SHOW', 'INVARIANTS', 'CANON', 'AUT'].map(command => [command, { fixed: ['graph'] }]),
    ['LIST', { fixed: [] }], ['REFINE', { fixed: ['graph'], rest: 'num' }],
    ...['ISO', 'SUBISO'].map(command => [command, { fixed: ['graph', 'graph'] }]),
    ['CLASSIFY', { fixed: ['num'] }]
]);
const namePattern = /^[a-z][a-z0-9]{0,7}$/;
const numberPattern = /^(0|[1-9][0-9]{0,2})$/;
function valid(word, kind) {
    if (kind === 'num') return numberPattern.test(word);
    if (kind === 'edge') { const pair = word.split('-'); return pair.length === 2 && pair.every(value => numberPattern.test(value)); }
    return namePattern.test(word);
}
function checkSize(n, minimum = 1) {
    if (n < minimum) fail('bad value');
    if (n > 16) fail('too large');
}
function relabel(graph, permutation) {
    const result = new Graph(graph.n);
    for (const [u, v] of graph.edges()) result.add(permutation[u], permutation[v]);
    return result;
}
function define(command, args) {
    const n = Number(args[1]), source = registry.get(args[1]);
    let result;
    switch (command) {
        case 'GRAPH': {
            checkSize(n); result = new Graph(n);
            for (const word of args.slice(2)) {
                const [u, v] = word.split('-').map(Number);
                if (u >= n || v >= n || u === v) fail(`bad edge ${word}`);
                if (result.adjacent(u, v)) fail(`duplicate edge ${word}`);
                result.add(u, v);
            }
            return result;
        }
        case 'CYCLE': case 'PATH': case 'COMPLETE':
            checkSize(n, command === 'CYCLE' ? 3 : 1); result = new Graph(n);
            for (let u = 0; u < n; u++) for (let v = u + 1; v < n; v++) {
                if (command === 'COMPLETE' || v === u + 1 || command === 'CYCLE' && u === 0 && v === n - 1) result.add(u, v);
            }
            return result;
        case 'BIPARTITE': {
            const b = Number(args[2]);
            if (!n || !b) fail('bad value');
            checkSize(n + b); result = new Graph(n + b);
            for (let u = 0; u < n; u++) for (let v = 0; v < b; v++) result.add(u, n + v);
            return result;
        }
        case 'STAR': case 'WHEEL':
            if (n < (command === 'WHEEL' ? 3 : 1)) fail('bad value');
            checkSize(n + 1); result = new Graph(n + 1);
            for (let v = 1; v <= n; v++) result.add(0, v);
            if (command === 'WHEEL') for (let v = 1; v <= n; v++) result.add(v, v % n + 1);
            return result;
        case 'PETERSEN':
            result = new Graph(10);
            for (let i = 0; i < 5; i++) { result.add(i, (i + 1) % 5); result.add(i, i + 5); result.add(i + 5, 5 + (i + 2) % 5); }
            return result;
        case 'HYPERCUBE':
            if (!n) fail('bad value');
            if (n >= 5) fail('too large');
            result = new Graph(2 ** n);
            for (let u = 0; u < result.n; u++) for (let bit = 0; bit < n; bit++) result.add(u, u ^ (1 << bit));
            return result;
        case 'CIRCULANT': {
            checkSize(n, 3);
            const jumps = args.slice(2).map(Number);
            if (jumps.some((jump, i) => jump === 0 || 2 * jump > n || i > 0 && jumps[i - 1] >= jump)) fail('bad value');
            result = new Graph(n);
            for (let u = 0; u < n; u++) for (const jump of jumps) result.add(u, (u + jump) % n);
            return result;
        }
        case 'GRID': {
            const c = Number(args[2]);
            if (!n || !c) fail('bad value');
            checkSize(n * c); result = new Graph(n * c);
            for (let x = 0; x < n; x++) for (let y = 0; y < c; y++) {
                if (y + 1 < c) result.add(x * c + y, x * c + y + 1);
                if (x + 1 < n) result.add(x * c + y, (x + 1) * c + y);
            }
            return result;
        }
        case 'COMPLEMENT':
            result = new Graph(source.n);
            for (let u = 0; u < source.n; u++) for (let v = u + 1; v < source.n; v++) if (!source.adjacent(u, v)) result.add(u, v);
            return result;
        case 'LINE': {
            const edges = source.edges();
            if (!edges.length) fail('no edges');
            checkSize(edges.length); result = new Graph(edges.length);
            for (let u = 0; u < edges.length; u++) for (let v = u + 1; v < edges.length; v++) if (edges[u].some(vertex => edges[v].includes(vertex))) result.add(u, v);
            return result;
        }
        case 'PRODUCT': case 'UNION': {
            const other = registry.get(args[2]), a = source.n, b = other.n;
            checkSize(command === 'PRODUCT' ? a * b : a + b);
            result = new Graph(command === 'PRODUCT' ? a * b : a + b);
            if (command === 'UNION') {
                for (const [u, v] of source.edges()) result.add(u, v);
                for (const [u, v] of other.edges()) result.add(u + a, v + a);
            } else {
                for (let x = 0; x < a; x++) for (const [u, v] of other.edges()) result.add(x * b + u, x * b + v);
                for (const [u, v] of source.edges()) for (let y = 0; y < b; y++) result.add(u * b + y, v * b + y);
            }
            return result;
        }
        case 'RELABEL': {
            const permutation = args.slice(2).map(Number);
            if (permutation.length !== source.n || new Set(permutation).size !== source.n || permutation.some(v => v >= source.n)) fail('bad permutation');
            return relabel(source, permutation);
        }
        case 'INDUCED': {
            const vertices = args.slice(2).map(Number);
            if (new Set(vertices).size !== vertices.length || vertices.some(v => v >= source.n)) fail('bad vertices');
            result = new Graph(vertices.length);
            for (let u = 0; u < vertices.length; u++) for (let v = u + 1; v < vertices.length; v++) if (source.adjacent(vertices[u], vertices[v])) result.add(u, v);
            return result;
        }
        case 'CANONIZE': return relabel(source, canon(source).labels);
    }
    return new Graph(1);
}
function iso(a, b) {
    if (a.n !== b.n) { output.push(`not isomorphic vertices ${a.n} ${b.n}`); return; }
    const ma = a.edges().length, mb = b.edges().length;
    if (ma !== mb) { output.push(`not isomorphic edges ${ma} ${mb}`); return; }
    const x = invariants(a), y = invariants(b);
    if (lex(x.degrees, y.degrees)) { output.push('not isomorphic degrees'); return; }
    const checks = [
        ['triangles', x.triangles, y.triangles], ['components', x.sizes.length, y.sizes.length],
        ['girth', x.girth, y.girth], ['diameter', x.diameter, y.diameter], ['bipartite', x.bipartite, y.bipartite]
    ];
    for (const [name, p, q] of checks) if (p !== q) { output.push(`not isomorphic ${name} ${p} ${q}`); return; }
    const r = stable(a), s = stable(b);
    if (r.rounds !== s.rounds || lex(cells(r.colors).map(cell => cell.length), cells(s.colors).map(cell => cell.length))) {
        output.push('not isomorphic refinement'); return;
    }
    const ca = canon(a), cb = canon(b);
    if (ca.string !== cb.string) { output.push('not isomorphic canonical'); return; }
    const inverse = Array(b.n);
    cb.labels.forEach((label, v) => inverse[label] = v);
    output.push('isomorphic', `mapping ${ca.labels.map(label => inverse[label]).join(' ')}`);
}
function automorphisms(name, graph) {
    const canonical = canon(graph), edges = graph.edges();
    const vertices = new DisjointSet(graph.n), edgeOrbits = new DisjointSet(edges.length);
    const inverse = Array(graph.n);
    canonical.labels.forEach((label, v) => inverse[label] = v);
    const edgeIndices = new Map(edges.map(([u, v], i) => [`${u}-${v}`, i]));
    for (const labels of canonical.bestLeaves) {
        const sigma = labels.map(label => inverse[label]);
        sigma.forEach((w, v) => vertices.join(v, w));
        edges.forEach(([u, v], i) => {
            const a = Math.min(sigma[u], sigma[v]), b = Math.max(sigma[u], sigma[v]);
            edgeOrbits.join(i, edgeIndices.get(`${a}-${b}`));
        });
    }
    const vg = vertices.groups(), eg = edgeOrbits.groups();
    output.push(`aut ${name} order ${canonical.bestLeaves.length}`, `vertex orbits ${vg.length}`);
    for (const group of vg) output.push(`orbit ${group.join(' ')}`);
    output.push(`edge orbits ${eg.length}`);
    for (const group of eg) output.push(`orbit ${group.map(i => edges[i].join('-')).join(' ')}`);
    output.push(`transitive vertex ${vg.length === 1 ? 'yes' : 'no'} edge ${eg.length === 1 ? 'yes' : 'no'}`);
}
function subiso(nameA, nameB, pattern, target) {
    let embeddings = 0, induced = 0;
    const first = [], mapping = [];
    function search(vertex, used, isInduced) {
        if (vertex === pattern.n) {
            embeddings++; if (isInduced) induced++;
            if (first.length < 5) first.push({ mapping: [...mapping], induced: isInduced });
            return;
        }
        for (let v = 0; v < target.n; v++) if (!(used & (1 << v))) {
            let valid = true, nextInduced = isInduced;
            for (let u = 0; u < vertex; u++) {
                if (pattern.adjacent(u, vertex) && !target.adjacent(mapping[u], v)) { valid = false; break; }
                if (!pattern.adjacent(u, vertex) && target.adjacent(mapping[u], v)) nextInduced = false;
            }
            if (valid) { mapping.push(v); search(vertex + 1, used | (1 << v), nextInduced); mapping.pop(); }
        }
    }
    if (pattern.n <= target.n) search(0, 0, true);
    const order = canon(pattern).bestLeaves.length;
    output.push(`subiso ${nameA} ${nameB} embeddings ${embeddings} induced ${induced}`, `copies ${embeddings / order} induced ${induced / order}`);
    for (const item of first) output.push(`embedding ${item.mapping.join(' ')}${item.induced ? ' induced' : ''}`);
}
function classify(n) {
    if (!n) fail('bad value');
    if (n > 5) fail('too large');
    const levels = [[canon(new Graph(n)).string]];
    const max = n * (n - 1) / 2;
    for (let m = 0; m < max; m++) {
        const next = new Set();
        for (const string of levels[m]) {
            const graph = new Graph(n);
            let i = 0;
            for (let u = 0; u < n; u++) for (let v = u + 1; v < n; v++) if (string[i++] === '1') graph.add(u, v);
            for (let u = 0; u < n; u++) for (let v = u + 1; v < n; v++) if (!graph.adjacent(u, v)) {
                const added = relabel(graph, Array.from({ length: n }, (_, vertex) => vertex));
                added.add(u, v); next.add(canon(added).string);
            }
        }
        levels.push([...next].sort());
    }
    output.push(`classify ${n} total ${levels.reduce((sum, level) => sum + level.length, 0)}`);
    levels.forEach((level, m) => output.push(`edges ${m} count ${level.length} ${level.map(string => string || '-').join(' ')}`));
}
function execute(line) {
    const [command, ...args] = line.split(' '), format = formats.get(command);
    if (!format) fail(`unknown command ${command}`);
    if (args.length < format.fixed.length || !format.rest && args.length !== format.fixed.length) fail('bad arguments');
    for (let i = 0; i < args.length; i++) if (!valid(args[i], format.fixed[i] ?? format.rest)) fail('bad arguments');
    format.fixed.forEach((kind, i) => { if (kind === 'graph' && !registry.has(args[i])) fail(`no graph ${args[i]}`); });
    const name = args[0], graph = registry.get(name);
    if (format.fixed[0] === 'name') {
        const result = define(command, args), redefined = registry.has(name);
        registry.set(name, result);
        output.push(`${redefined ? 'redefined' : 'defined'} ${name} n ${result.n} m ${result.edges().length}`);
        return;
    }
    switch (command) {
        case 'DELETE': registry.delete(name); output.push(`deleted ${name}`); break;
        case 'LIST':
            output.push(`graphs ${registry.size}`);
            for (const key of [...registry.keys()].sort()) {
                const item = registry.get(key);
                output.push(`${key} n ${item.n} m ${item.edges().length}`);
            }
            break;
        case 'SHOW':
            output.push(`graph ${name} n ${graph.n} m ${graph.edges().length}`);
            for (let v = 0; v < graph.n; v++) { const neighbors = graph.neighbors(v); output.push(`${v}:${neighbors.length ? ` ${neighbors.join(' ')}` : ''}`); }
            break;
        case 'INVARIANTS': {
            const value = invariants(graph);
            output.push(`invariants ${name}`, `degrees ${value.degrees.join(' ')}`, `edges ${graph.edges().length} triangles ${value.triangles}`,
                `components ${value.sizes.length} sizes ${value.sizes.join(' ')}`, `girth ${value.girth} diameter ${value.diameter} radius ${value.radius}`, `bipartite ${value.bipartite}`);
            if (graph.n > 12) output.push('clique -', 'chromatic -');
            else {
                const largest = clique(graph), colors = coloring(graph, largest.length);
                output.push(`clique ${largest.length} ${largest.join(' ')}`, `chromatic ${Math.max(...colors) + 1} ${colors.join(' ')}`);
            }
            break;
        }
        case 'REFINE': {
            const vertices = args.slice(1).map(Number);
            if (vertices.some(v => v >= graph.n)) fail('bad vertices');
            let { colors, rounds } = stable(graph);
            for (const vertex of vertices) {
                if (colors.filter(color => color === colors[vertex]).length === 1) fail(`singleton ${vertex}`);
                const next = refine(graph, individualize(colors, vertex));
                colors = next.colors; rounds += next.rounds;
            }
            const partition = cells(colors);
            output.push(`refine ${name} rounds ${rounds} cells ${partition.length}`);
            partition.forEach((cell, color) => output.push(`${color}: ${cell.join(' ')}`));
            break;
        }
        case 'CANON': {
            const result = canon(graph);
            output.push(`canon ${name} nodes ${result.nodes} leaves ${result.leaves}`, `labels ${result.labels.join(' ')}`, `string ${result.string || '-'}`);
            break;
        }
        case 'ISO': iso(graph, registry.get(args[1])); break;
        case 'AUT': automorphisms(name, graph); break;
        case 'SUBISO': subiso(name, args[1], graph, registry.get(args[1])); break;
        case 'CLASSIFY': classify(Number(name)); break;
    }
}
const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/), count = Number(lines[0]);
for (const line of lines.slice(1, count + 1)) {
    try { execute(line); }
    catch (error) { output.push(error.message); }
}
if (output.length) process.stdout.write(output.join('\n') + '\n');
