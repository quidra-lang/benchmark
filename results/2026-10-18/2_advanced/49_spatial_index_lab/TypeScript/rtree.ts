import type { Box, SpatialObject } from './dataset.ts';

export const area = (b: Box): number => (b[2] - b[0]) * (b[3] - b[1]);
export const union = (a: Box, b: Box): Box => [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[2], b[2]), Math.max(a[3], b[3])];
export const enlargement = (a: Box, b: Box): number => area(union(a, b)) - area(a);
export const contains = (a: Box, b: Box): boolean => a[0] <= b[0] && b[2] <= a[2] && a[1] <= b[1] && b[3] <= a[3];
export const intersects = (a: Box, b: Box): boolean => a[0] <= b[2] && b[0] <= a[2] && a[1] <= b[3] && b[1] <= a[3];
export function overlap(a: Box, b: Box): number {
    const w = Math.min(a[2], b[2]) - Math.max(a[0], b[0]), h = Math.min(a[3], b[3]) - Math.max(a[1], b[1]); return w > 0 && h > 0 ? w * h : 0;
}
export function compare(a: readonly number[], b: readonly number[]): number { for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] - b[i]; return 0; }
export interface Entry { box: Box; object?: SpatialObject; child?: RNode }
export class RNode {
    parent: RNode | null = null;
    constructor(public level: number, public entries: Entry[] = []) { for (const e of entries) if (e.child) e.child.parent = this; }
}
export function box(node: RNode): Box {
    let result = node.entries[0].box;
    for (let i = 1; i < node.entries.length; i++) result = union(result, node.entries[i].box); return result;
}
const leafEntry = (object: SpatialObject): Entry => ({ box: object.box, object });
const childEntry = (child: RNode): Entry => ({ box: box(child), child });
function split(node: RNode, minimum: number): RNode {
    const entries = node.entries; let first = 0, second = 1, waste = -Infinity;
    for (let i = 0; i < entries.length - 1; i++) for (let j = i + 1; j < entries.length; j++) {
        const w = area(union(entries[i].box, entries[j].box)) - area(entries[i].box) - area(entries[j].box);
        if (w > waste) { waste = w; first = i; second = j; }
    }
    const groups = [[entries[first]], [entries[second]]], bounds = groups.map(g => g[0].box), rest = entries.filter((_, i) => i !== first && i !== second);
    while (rest.length) {
        if (groups[0].length + rest.length === minimum) { groups[0].push(...rest); break; }
        if (groups[1].length + rest.length === minimum) { groups[1].push(...rest); break; }
        let chosen = 0, largest = -1;
        for (let i = 0; i < rest.length; i++) {
            const d = Math.abs(enlargement(bounds[0], rest[i].box) - enlargement(bounds[1], rest[i].box)); if (d > largest) { largest = d; chosen = i; }
        }
        const [entry] = rest.splice(chosen, 1), priorities = groups.map((g, i) => [enlargement(bounds[i], entry.box), area(bounds[i]), g.length]);
        const target = compare(priorities[0], priorities[1]) <= 0 ? 0 : 1; groups[target].push(entry); bounds[target] = union(bounds[target], entry.box);
    }
    node.entries = groups[0]; for (const e of node.entries) if (e.child) e.child.parent = node;
    return new RNode(node.level, groups[1]);
}
function bulkLoad(objects: SpatialObject[], maximum: number): RNode {
    let entries: (Entry & { number: number })[] = objects.map(object => ({ ...leafEntry(object), number: object.id })), level = 0;
    for (;;) {
        const pages = Math.ceil(entries.length / maximum); let slabs = 1; while (slabs * slabs < pages) slabs++;
        entries.sort((a, b) => compare([a.box[0] + a.box[2], a.box[1] + a.box[3], a.number], [b.box[0] + b.box[2], b.box[1] + b.box[3], b.number]));
        const nodes: RNode[] = [];
        for (let start = 0; start < entries.length; start += slabs * maximum) {
            const slab = entries.slice(start, start + slabs * maximum).sort((a, b) => compare([a.box[1] + a.box[3], a.box[0] + a.box[2], a.number], [b.box[1] + b.box[3], b.box[0] + b.box[2], b.number]));
            for (let offset = 0; offset < slab.length; offset += maximum) nodes.push(new RNode(level, slab.slice(offset, offset + maximum)));
        }
        if (nodes.length === 1) return nodes[0]; entries = nodes.map((node, number) => ({ ...childEntry(node), number })); level++;
    }
}
function findLeaf(node: RNode, object: SpatialObject): { node: RNode; index: number } | null {
    if (node.level === 0) { const index = node.entries.findIndex(e => e.object!.id === object.id); return index < 0 ? null : { node, index }; }
    for (const e of node.entries) if (contains(e.box, object.box)) { const found = findLeaf(e.child!, object); if (found) return found; }
    return null;
}
export class RTree {
    root: RNode;
    constructor(objects: SpatialObject[], private maximum: number, private minimum: number, bulk = false) {
        this.root = bulk ? bulkLoad(objects, maximum) : new RNode(0); if (!bulk) for (const object of objects) this.insert(object);
    }
    private choose(entry: Entry, level: number): RNode {
        let node = this.root;
        while (node.level > level) {
            let selected = 0, priority = [enlargement(node.entries[0].box, entry.box), area(node.entries[0].box)];
            for (let i = 1; i < node.entries.length; i++) { const p = [enlargement(node.entries[i].box, entry.box), area(node.entries[i].box)]; if (compare(p, priority) < 0) { selected = i; priority = p; } }
            node = node.entries[selected].child!;
        }
        return node;
    }
    private insertEntry(entry: Entry, level: number): void {
        let node = this.choose(entry, level); node.entries.push(entry); if (entry.child) entry.child.parent = node;
        for (;;) {
            const sibling = node.entries.length > this.maximum ? split(node, this.minimum) : null;
            if (node === this.root) { if (sibling) this.root = new RNode(node.level + 1, [childEntry(node), childEntry(sibling)]); return; }
            const parent = node.parent!; parent.entries.find(e => e.child === node)!.box = box(node);
            if (sibling) { parent.entries.push(childEntry(sibling)); sibling.parent = parent; } node = parent;
        }
    }
    insert(object: SpatialObject): void { this.insertEntry(leafEntry(object), 0); }
    remove(object: SpatialObject): void {
        const found = findLeaf(this.root, object)!; found.node.entries.splice(found.index, 1);
        let node = found.node; const removed: RNode[] = [];
        while (node !== this.root) {
            const parent = node.parent!, index = parent.entries.findIndex(e => e.child === node);
            if (node.entries.length < this.minimum) { parent.entries.splice(index, 1); removed.push(node); node.parent = null; }
            else parent.entries[index].box = box(node); node = parent;
        }
        for (const detached of removed) for (const e of detached.entries) this.insertEntry(e, detached.level);
        while (this.root.level > 0 && this.root.entries.length === 1) { this.root = this.root.entries[0].child!; this.root.parent = null; }
    }
}
