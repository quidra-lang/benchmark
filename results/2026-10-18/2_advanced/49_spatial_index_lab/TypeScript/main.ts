import { mkdirSync } from 'node:fs';
import { readDataset, point, type Point, type SpatialObject, type Box, type Settings } from './dataset.ts';
import { KDTree, KDNode, compare as compareKD } from './kdtree.ts';
import { QuadTree, QuadNode, destination, NAMES } from './quadtree.ts';
import { RTree, RNode, box, contains, intersects, compare, area, overlap } from './rtree.ts';
import { Grid } from './grid.ts';
import { fraction, ids, writeLines } from './report.ts';

const POINT_NAMES = ['kdtree', 'quadtree', 'rtree', 'str', 'grid'] as const;
const RECT_NAMES = ['rtree_rect', 'str_rect'] as const;
const R_NAMES = ['rtree', 'str', ...RECT_NAMES] as const;
const TREE_NAMES = ['kdtree', 'quadtree', ...R_NAMES] as const;
type Structure = typeof POINT_NAMES[number] | typeof RECT_NAMES[number];
const SEARCHES = ['RANGE', 'RADIUS', 'KNN', 'WINDOWCOUNT', 'CONTAINS', 'NEAREST', 'JOIN'];
type Pair = [number, number];
type Answer = { kind: 'ids'; values: number[] } | { kind: 'pairs'; values: Pair[] } | { kind: 'count'; value: number };
interface SearchResult { answer: Answer; nodes: number; tests: number }
interface View { region: Box; held: SpatialObject[]; children: View[]; count: number; depth: number; line: string; level: number; entries: number }
interface Totals { queries: number; nodes: number; tests: number; maximum: number }
interface State {
    settings: Settings; points: Map<number, Point>; rectangles: SpatialObject[];
    structures: { kdtree: KDTree; quadtree: QuadTree; rtree: RTree; str: RTree; grid: Grid; rtree_rect: RTree; str_rect: RTree };
    snapshots: number; answers: string[]; visits: string[]; joins: string[]; dumps: string[]; statistics: string[];
    totals: Map<string, Map<Structure, Totals>>;
}
const fields = (...values: (number | string)[]): string => values.join(' ');
function minimumDistance(x: number, y: number, b: Box): number {
    const dx = x < b[0] ? b[0] - x : x > b[2] ? x - b[2] : 0, dy = y < b[1] ? b[1] - y : y > b[3] ? y - b[3] : 0; return dx * dx + dy * dy;
}
const bounds = (args: number[]): Box => [args[0], args[1], args[2], args[3]];
function makeView(region: Box, held: SpatialObject[], children: View[], depth: number, line: string, level = 0, entries = 0): View {
    return { region, held, children, depth, line, level, entries, count: held.length + children.reduce((n, c) => n + c.count, 0) };
}
function kdView(node: KDNode, region: Box, depth = 0, mark = 'root'): View {
    const children: View[] = [], split = node.axis === 0 ? node.point.x : node.point.y;
    if (node.left) { const b: Box = [...region]; b[node.axis + 2] = split; children.push(kdView(node.left, b, depth + 1, 'L')); }
    if (node.right) { const b: Box = [...region]; b[node.axis] = split; children.push(kdView(node.right, b, depth + 1, 'R')); }
    return makeView(region, [node.point], children, depth, fields(mark, node.axis === 0 ? 'x' : 'y', node.point.id, node.point.x, node.point.y, 'box', ...region));
}
function quadView(node: QuadNode, depth = 0, mark = 'root'): View {
    const region: Box = [node.x, node.y, node.x + node.size - 1, node.y + node.size - 1];
    const children = node.children ? node.children.map((child, i) => quadView(child, depth + 1, NAMES[i])) : [];
    const view = makeView(region, node.points, children, depth, '');
    view.line = fields(mark, node.x, node.y, node.size, node.children ? `node count ${view.count}` : `leaf ${ids(node.points.map(p => p.id))}`); return view;
}
function rtreeView(node: RNode, depth = 0): View {
    const children = node.level > 0 ? node.entries.map(e => rtreeView(e.child!, depth + 1)) : [], held = node.level === 0 ? node.entries.map(e => e.object!) : [];
    const region = box(node), line = node.level === 0 ? fields('leaf', ...region, 'ids', ids(held.map(o => o.id))) : fields('node', node.level, ...region, 'entries', node.entries.length);
    return makeView(region, held, children, depth, line, node.level, node.entries.length);
}
function currentViews(state: State): Record<Structure, View> {
    const { world } = state.settings, s = state.structures;
    const cells = s.grid.cells.map(cell => {
        const x = cell.column * s.grid.size, y = cell.row * s.grid.size;
        return makeView([x, y, x + s.grid.size - 1, y + s.grid.size - 1], cell.points, [], 1, '');
    });
    return { kdtree: kdView(s.kdtree.root!, [0, 0, world - 1, world - 1]), quadtree: quadView(s.quadtree.root),
        rtree: rtreeView(s.rtree.root), str: rtreeView(s.str.root), rtree_rect: rtreeView(s.rtree_rect.root), str_rect: rtreeView(s.str_rect.root),
        grid: makeView([0, 0, world - 1, world - 1], [], cells, 0, '') };
}
function conditionSearch(root: View, regionCondition: (box: Box) => boolean, objectCondition: (object: SpatialObject) => boolean): SearchResult {
    const answer: number[] = [], pending = [root]; let nodes = 0, tests = 0;
    while (pending.length) {
        const node = pending.pop()!; nodes++; tests += node.held.length;
        for (const object of node.held) if (objectCondition(object)) answer.push(object.id);
        for (let i = node.children.length - 1; i >= 0; i--) if (regionCondition(node.children[i].region)) pending.push(node.children[i]);
    }
    answer.sort((a, b) => a - b); return { answer: { kind: 'ids', values: answer }, nodes, tests };
}
function windowCount(root: View, window: Box): SearchResult {
    let answer = 0, nodes = 0, tests = 0; const pending = [root];
    while (pending.length) {
        const node = pending.pop()!; nodes++;
        if (contains(window, node.region)) { answer += node.count; continue; }
        tests += node.held.length; for (const object of node.held) if (contains(window, object.box)) answer++;
        for (let i = node.children.length - 1; i >= 0; i--) if (intersects(node.children[i].region, window)) pending.push(node.children[i]);
    }
    return { answer: { kind: 'count', value: answer }, nodes, tests };
}
type QueueEntry = { key: [number, number, number]; kind: 'node'; node: View } | { key: [number, number, number]; kind: 'object'; object: SpatialObject };
class PriorityQueue {
    private entries: QueueEntry[] = [];
    push(entry: QueueEntry): void {
        let i = this.entries.length; this.entries.push(entry);
        while (i > 0) { const parent = Math.floor((i - 1) / 2); if (compare(this.entries[parent].key, entry.key) < 0) break; this.entries[i] = this.entries[parent]; i = parent; }
        this.entries[i] = entry;
    }
    pop(): QueueEntry {
        const first = this.entries[0], last = this.entries.pop()!;
        if (!this.entries.length) return first;
        let i = 0;
        while (2 * i + 1 < this.entries.length) {
            let child = 2 * i + 1;
            if (child + 1 < this.entries.length && compare(this.entries[child + 1].key, this.entries[child].key) < 0) child++;
            if (compare(last.key, this.entries[child].key) < 0) break;
            this.entries[i] = this.entries[child]; i = child;
        }
        this.entries[i] = last; return first;
    }
}
function nearestSearch(root: View, x: number, y: number, count: number): SearchResult {
    const pending = new PriorityQueue(), answer: Pair[] = []; let serial = 0, nodes = 0, tests = 0;
    const enqueue = (node: View): void => pending.push({ key: [minimumDistance(x, y, node.region), 0, serial++], kind: 'node', node }); enqueue(root);
    while (answer.length < count) {
        const entry = pending.pop();
        if (entry.kind === 'object') { answer.push([entry.object.id, entry.key[0]]); continue; }
        const node = entry.node; nodes++; tests += node.held.length;
        for (const object of node.held) pending.push({ key: [minimumDistance(x, y, object.box), 1, object.id], kind: 'object', object });
        for (const child of node.children) enqueue(child);
    }
    return { answer: { kind: 'pairs', values: answer }, nodes, tests };
}
function spatialJoin(pointRoot: View, rectangleRoot: View): SearchResult {
    const answer: Pair[] = []; let nodes = 0, tests = 0;
    function visit(a: View, b: View): void {
        nodes++;
        if (!a.children.length && !b.children.length) {
            tests += a.held.length * b.held.length;
            for (const p of a.held) for (const r of b.held) if (contains(r.box, p.box)) answer.push([r.id, p.id]);
        } else if (!a.children.length) { for (const child of b.children) if (intersects(child.region, a.region)) visit(a, child); }
        else if (!b.children.length) { for (const child of a.children) if (intersects(child.region, b.region)) visit(child, b); }
        else for (const p of a.children) for (const r of b.children) if (intersects(p.region, r.region)) visit(p, r);
    }
    visit(pointRoot, rectangleRoot); answer.sort(compare); return { answer: { kind: 'pairs', values: answer }, nodes, tests };
}
function searchNames(command: string): readonly Structure[] { return command === 'JOIN' ? ['rtree', 'str'] : command === 'CONTAINS' || command === 'NEAREST' ? RECT_NAMES : POINT_NAMES; }
function search(root: View, command: string, args: number[]): SearchResult {
    const [x, y] = args, q: Box = [x, y, x, y];
    if (command === 'RANGE') { const b = bounds(args); return conditionSearch(root, r => intersects(r, b), o => contains(b, o.box)); }
    if (command === 'RADIUS') { const r2 = args[2] * args[2]; return conditionSearch(root, b => minimumDistance(x, y, b) <= r2, o => minimumDistance(x, y, o.box) <= r2); }
    if (command === 'CONTAINS') return conditionSearch(root, b => contains(b, q), o => contains(o.box, q));
    if (command === 'WINDOWCOUNT') return windowCount(root, bounds(args));
    return nearestSearch(root, x, y, args[2]);
}
function bruteForce(state: State, command: string, args: number[]): Answer {
    const points = [...state.points.values()].sort((a, b) => a.id - b.id), [x, y] = args;
    if (command === 'JOIN') {
        const pairs: Pair[] = []; for (const r of state.rectangles) for (const p of points) if (contains(r.box, p.box)) pairs.push([r.id, p.id]);
        return { kind: 'pairs', values: pairs };
    }
    if (command === 'KNN' || command === 'NEAREST') {
        const objects = command === 'KNN' ? points : state.rectangles;
        const values = objects.map((o): Pair => [o.id, minimumDistance(x, y, o.box)]);
        values.sort((a, b) => a[1] - b[1] || a[0] - b[0]); return { kind: 'pairs', values: values.slice(0, args[2]) };
    }
    const values = command === 'CONTAINS' ? state.rectangles.filter(r => contains(r.box, [x, y, x, y])).map(r => r.id)
        : points.filter(p => command === 'RADIUS' ? minimumDistance(x, y, p.box) <= args[2] * args[2] : contains(bounds(args), p.box)).map(p => p.id);
    return command === 'WINDOWCOUNT' ? { kind: 'count', value: values.length } : { kind: 'ids', values };
}
function recordVisit(state: State, query: number, command: string, name: Structure, result: SearchResult): void {
    state.visits.push([query, command, name, result.nodes, result.tests].join(','));
    if (!state.totals.has(command)) state.totals.set(command, new Map());
    const totals = state.totals.get(command)!;
    if (!totals.has(name)) totals.set(name, { queries: 0, nodes: 0, tests: 0, maximum: 0 });
    const t = totals.get(name)!; t.queries++; t.nodes += result.nodes; t.tests += result.tests; t.maximum = Math.max(t.maximum, result.nodes);
}
function executeSearch(state: State, query: number, command: string, args: number[]): string {
    const expected = bruteForce(state, command, args), views = currentViews(state), mismatches: Structure[] = [];
    for (const name of searchNames(command)) {
        const result = command === 'JOIN' ? spatialJoin(views[name], name === 'rtree' ? views.rtree_rect : views.str_rect) : search(views[name], command, args);
        recordVisit(state, query, command, name, result); if (JSON.stringify(result.answer) !== JSON.stringify(expected)) mismatches.push(name);
    }
    const check = mismatches.length ? 'mismatch ' + mismatches.join(' ') : 'ok';
    if (expected.kind === 'count') return fields(query, command, 'count', expected.value, 'check', check);
    if (command === 'JOIN' && expected.kind === 'pairs') { for (const pair of expected.values) state.joins.push([query, ...pair].join(',')); return fields(query, command, 'count', expected.values.length, 'check', check); }
    const values = expected.kind === 'pairs' ? expected.values.map(pair => pair.join(':')) : expected.values;
    return fields(query, command, 'count', values.length, 'ids', ids(values), 'check', check);
}
function preorder(root: View): View[] {
    const nodes: View[] = [], pending = [root];
    while (pending.length) { const node = pending.pop()!; nodes.push(node); for (let i = node.children.length - 1; i >= 0; i--) pending.push(node.children[i]); } return nodes;
}
function kdStatistics(root: View): string[] {
    const nodes = preorder(root), depths: { nodes: number; leaves: number; oneChild: number }[] = [];
    let leaves = 0, oneChild = 0, depthSum = 0;
    for (const node of nodes) {
        while (depths.length <= node.depth) depths.push({ nodes: 0, leaves: 0, oneChild: 0 });
        const d = depths[node.depth]; d.nodes++; depthSum += node.depth;
        if (!node.children.length) { d.leaves++; leaves++; } else if (node.children.length === 1) { d.oneChild++; oneChild++; }
    }
    let ideal = 0; while (2 ** ideal - 1 < nodes.length) ideal++;
    return [fields('kdtree height', depths.length, 'ideal', ideal, 'nodes', nodes.length, 'leaves', leaves, 'one_child', oneChild, 'depth_sum', depthSum, 'avg_depth', fraction(depthSum, nodes.length)),
        ...depths.map((d, t) => '  ' + fields('depth', t, 'nodes', d.nodes, 'leaves', d.leaves, 'one_child', d.oneChild))];
}
function quadStatistics(root: View, bucket: number): string[] {
    const depths: { internal: number; leaves: number; points: number }[] = []; let internal = 0, leaves = 0, empty = 0, maximum = 0;
    for (const node of preorder(root)) {
        while (depths.length <= node.depth) depths.push({ internal: 0, leaves: 0, points: 0 }); const d = depths[node.depth];
        if (node.children.length) { d.internal++; internal++; }
        else { d.leaves++; d.points += node.held.length; leaves++; if (!node.held.length) empty++; maximum = Math.max(maximum, node.held.length); }
    }
    return [fields('quadtree height', depths.length, 'internal', internal, 'leaves', leaves, 'empty', empty, 'max_leaf', maximum, 'fill', fraction(root.count, leaves * bucket)),
        ...depths.map((d, t) => '  ' + fields('depth', t, 'internal', d.internal, 'leaves', d.leaves, 'points', d.points))];
}
function rtreeStatistics(name: string, root: View, settings: Settings): string[] {
    const nodes = preorder(root), height = root.level + 1, levels: View[][] = Array.from({ length: height }, () => []); let leaves = 0, entries = 0;
    for (const node of nodes) { levels[node.level].push(node); entries += node.entries; if (node.level === 0) leaves++; }
    const lines = [fields(name, 'height', height, 'nodes', nodes.length, 'leaves', leaves, 'entries', entries, 'fill', fraction(entries, nodes.length * settings.maximum))];
    for (let level = height - 1; level >= 0; level--) {
        const group = levels[level]; let total = 0, minimum = Infinity, maximum = 0, under = 0, totalArea = 0, totalOverlap = 0;
        for (let i = 0; i < group.length; i++) {
            const node = group[i]; total += node.entries; minimum = Math.min(minimum, node.entries); maximum = Math.max(maximum, node.entries);
            if (node.entries < settings.minimum) under++; totalArea += area(node.region);
            for (let j = i + 1; j < group.length; j++) totalOverlap += overlap(node.region, group[j].region);
        }
        lines.push('  ' + fields('level', level, 'nodes', group.length, 'entries', total, 'min', minimum, 'max', maximum, 'under', under, 'area', totalArea, 'overlap', totalOverlap));
    }
    return lines;
}
function gridStatistics(root: View): string[] {
    const occupancy = new Map<number, number>(); let used = 0, maximum = 0;
    for (const cell of root.children) { const count = cell.held.length; occupancy.set(count, (occupancy.get(count) ?? 0) + 1); if (count) used++; maximum = Math.max(maximum, count); }
    return [fields('grid cells', root.children.length, 'used', used, 'max', maximum), '  occupancy ' + [...occupancy].sort((a, b) => a[0] - b[0]).map(pair => pair.join(':')).join(' ')];
}
function snapshot(state: State, query: number): number {
    const number = state.snapshots++, views = currentViews(state), header = fields('snapshot', number, 'query', query, 'points', state.points.size, 'rects', state.rectangles.length);
    if (number > 0) { state.dumps.push(''); state.statistics.push(''); }
    state.dumps.push(header); state.statistics.push(header);
    for (const name of TREE_NAMES) state.dumps.push(name, ...preorder(views[name]).map(v => ' '.repeat(2 * (v.depth + 1)) + v.line));
    state.statistics.push(...kdStatistics(views.kdtree), ...quadStatistics(views.quadtree, state.settings.bucket));
    for (const name of R_NAMES) state.statistics.push(...rtreeStatistics(name, views[name], state.settings));
    state.statistics.push(...gridStatistics(views.grid)); return number;
}
function locateKD(root: KDNode, point: Point): string {
    let node = root, path = '';
    while (node.point.id !== point.id) { const left = compareKD(point, node.point, node.axis) < 0; path += left ? 'L' : 'R'; node = left ? node.left! : node.right!; }
    return path || '-';
}
function locateQuad(root: QuadNode, point: Point): string {
    let node = root; const path: string[] = [];
    while (node.children) { const child = destination(node, point); path.push(NAMES[child]); node = node.children[child]; } return path.join('/') || '-';
}
function locateRTree(node: RNode, point: Point): number[] | null {
    if (node.level === 0) { const index = node.entries.findIndex(e => e.object!.id === point.id); return index < 0 ? null : [index + 1]; }
    for (let i = 0; i < node.entries.length; i++) if (contains(node.entries[i].box, point.box)) { const found = locateRTree(node.entries[i].child!, point); if (found) return [i + 1, ...found]; }
    return null;
}
function locate(state: State, query: number, id: number): string {
    const p = state.points.get(id); if (!p) return fields(query, 'LOCATE', id, 'missing');
    const s = state.structures, cell = s.grid.cell(p);
    return fields(query, 'LOCATE', id, 'kdtree', locateKD(s.kdtree.root!, p), 'quadtree', locateQuad(s.quadtree.root, p),
        'rtree', locateRTree(s.rtree.root, p)!.join('/'), 'str', locateRTree(s.str.root, p)!.join('/'), 'grid', cell.column, cell.row);
}
function updatePoint(state: State, query: number, command: string, args: number[]): string {
    const id = args[0];
    if (command === 'INSERT') {
        const p = point(id, args[1], args[2]); for (const name of POINT_NAMES) state.structures[name].insert(p); state.points.set(id, p);
        return fields(query, command, id, 'inserted points', state.points.size);
    }
    const p = state.points.get(id); if (!p) return fields(query, command, id, 'missing points', state.points.size);
    for (const name of POINT_NAMES) state.structures[name].remove(p); state.points.delete(id); return fields(query, command, id, 'deleted points', state.points.size);
}
function visitSummary(state: State): string[] {
    const lines = ['visits'];
    for (const command of SEARCHES) {
        const totals = state.totals.get(command); if (!totals) continue; const names = searchNames(command);
        for (const name of names) { const t = totals.get(name)!; lines.push(fields(command, name, 'queries', t.queries, 'nodes', t.nodes, 'tests', t.tests, 'max_nodes', t.maximum, 'mean_nodes', fraction(t.nodes, t.queries))); }
        const ranking = names.map((name, i) => ({ name, i, ...totals.get(name)! })).sort((a, b) => a.nodes - b.nodes || a.tests - b.tests || a.i - b.i);
        lines.push(fields('rank', command, ...ranking.map(r => r.name)));
    }
    return lines;
}
function initialize(data: ReturnType<typeof readDataset>): State {
    const { points, rectangles, settings: p } = data;
    return { settings: p, points: new Map(points.map(p => [p.id, p])), rectangles: rectangles.slice().sort((a, b) => a.id - b.id),
        structures: { kdtree: new KDTree(points), quadtree: new QuadTree(points, p.world, p.bucket), grid: new Grid(points, p.world, p.cell),
            rtree: new RTree(points, p.maximum, p.minimum), str: new RTree(points, p.maximum, p.minimum, true),
            rtree_rect: new RTree(rectangles, p.maximum, p.minimum), str_rect: new RTree(rectangles, p.maximum, p.minimum, true) },
        snapshots: 0, answers: [], visits: ['query,command,structure,nodes,tests'], joins: ['query,rect,point'], dumps: [], statistics: [], totals: new Map() };
}
function main(): void {
    const data = readDataset(), state = initialize(data); snapshot(state, 0);
    data.commands.forEach(({ name, args }, i) => {
        const query = i + 1;
        state.answers.push(SEARCHES.includes(name) ? executeSearch(state, query, name, args) : name === 'LOCATE' ? locate(state, query, args[0])
            : name === 'DUMP' ? fields(query, 'DUMP snapshot', snapshot(state, query)) : updatePoint(state, query, name, args));
    });
    state.statistics.push('', ...visitSummary(state)); mkdirSync('output', { recursive: true });
    for (const [name, lines] of [['answers.txt', state.answers], ['visits.csv', state.visits], ['join.csv', state.joins], ['structures.txt', state.dumps], ['stats.txt', state.statistics]] satisfies [string, string[]][]) writeLines(name, lines);
}
main();
