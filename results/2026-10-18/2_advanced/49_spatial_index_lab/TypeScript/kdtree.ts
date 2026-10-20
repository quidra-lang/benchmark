import type { Point } from './dataset.ts';

export class KDNode {
    left: KDNode | null = null;
    right: KDNode | null = null;
    constructor(public point: Point, public axis: number) {}
}
export function compare(a: Point, b: Point, axis: number): number {
    return axis === 0 ? a.x - b.x || a.y - b.y || a.id - b.id : a.y - b.y || a.x - b.x || a.id - b.id;
}
function build(points: Point[], depth = 0): KDNode | null {
    if (!points.length) return null;
    const axis = depth % 2, ordered = points.slice().sort((a, b) => compare(a, b, axis)), middle = Math.floor(ordered.length / 2);
    const node = new KDNode(ordered[middle], axis);
    node.left = build(ordered.slice(0, middle), depth + 1); node.right = build(ordered.slice(middle + 1), depth + 1); return node;
}
function minimum(node: KDNode, axis: number): Point {
    if (node.axis === axis) return node.left ? minimum(node.left, axis) : node.point;
    let best = node.point;
    for (const child of [node.left, node.right]) if (child) { const p = minimum(child, axis); if (compare(p, best, axis) < 0) best = p; }
    return best;
}
function remove(node: KDNode, point: Point): KDNode | null {
    if (node.point.id === point.id) {
        if (node.right) { node.point = minimum(node.right, node.axis); node.right = remove(node.right, node.point); }
        else if (node.left) { node.point = minimum(node.left, node.axis); node.right = remove(node.left, node.point); node.left = null; }
        else return null;
    } else if (compare(point, node.point, node.axis) < 0) node.left = remove(node.left!, point);
    else node.right = remove(node.right!, point);
    return node;
}
export class KDTree {
    root: KDNode | null;
    constructor(points: Point[]) { this.root = build(points); }
    insert(point: Point): void {
        if (!this.root) { this.root = new KDNode(point, 0); return; }
        let node = this.root;
        for (;;) {
            const side = compare(point, node.point, node.axis) < 0 ? 'left' : 'right', child = node[side];
            if (!child) { node[side] = new KDNode(point, 1 - node.axis); return; } node = child;
        }
    }
    remove(point: Point): void { this.root = remove(this.root!, point); }
}
