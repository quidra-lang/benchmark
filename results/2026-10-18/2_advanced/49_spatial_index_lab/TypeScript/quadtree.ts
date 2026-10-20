import type { Point } from './dataset.ts';

export const NAMES = ['NW', 'NE', 'SW', 'SE'];
export class QuadNode {
  points: Point[] = [];
  children: QuadNode[] | null = null;
  constructor(
    public x: number,
    public y: number,
    public size: number,
  ) {}
}
export function destination(node: QuadNode, point: Point): number {
  const half = node.size / 2;
  return Number(point.x >= node.x + half) + 2 * Number(point.y >= node.y + half);
}
function insert(node: QuadNode, point: Point, bucket: number): void {
  if (node.children) {
    insert(node.children[destination(node, point)], point, bucket);
    return;
  }
  node.points.push(point);
  node.points.sort((a, b) => a.id - b.id);
  if (node.points.length <= bucket) return;
  const h = node.size / 2;
  node.children = [
    new QuadNode(node.x, node.y, h),
    new QuadNode(node.x + h, node.y, h),
    new QuadNode(node.x, node.y + h, h),
    new QuadNode(node.x + h, node.y + h, h),
  ];
  const previous = node.points;
  node.points = [];
  for (const held of previous) insert(node, held, bucket);
}
function remove(node: QuadNode, point: Point, bucket: number): void {
  if (!node.children) {
    node.points.splice(
      node.points.findIndex((p) => p.id === point.id),
      1,
    );
    return;
  }
  remove(node.children[destination(node, point)], point, bucket);
  if (node.children.some((child) => child.children)) return;
  const points = node.children.flatMap((child) => child.points);
  if (points.length <= bucket) {
    node.points = points.sort((a, b) => a.id - b.id);
    node.children = null;
  }
}
export class QuadTree {
  root: QuadNode;
  constructor(
    points: Point[],
    world: number,
    private bucket: number,
  ) {
    this.root = new QuadNode(0, 0, world);
    for (const p of points) this.insert(p);
  }
  insert(point: Point): void {
    insert(this.root, point, this.bucket);
  }
  remove(point: Point): void {
    remove(this.root, point, this.bucket);
  }
}
