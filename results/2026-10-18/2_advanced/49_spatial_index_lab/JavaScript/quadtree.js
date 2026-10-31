'use strict';

const NAMES = ['NW', 'NE', 'SW', 'SE'];

class Node {
  constructor(x, y, size) {
    this.x = x;
    this.y = y;
    this.size = size;
    this.points = [];
    this.children = null;
  }
}

function destination(node, point) {
  const half = node.size / 2;
  return (point.x >= node.x + half ? 1 : 0) + (point.y >= node.y + half ? 2 : 0);
}

function insert(node, point, bucket) {
  if (node.children) {
    insert(node.children[destination(node, point)], point, bucket);
    return;
  }
  node.points.push(point);
  node.points.sort((a, b) => a.id - b.id);
  if (node.points.length <= bucket) return;
  const half = node.size / 2;
  node.children = [new Node(node.x, node.y, half), new Node(node.x + half, node.y, half),
    new Node(node.x, node.y + half, half), new Node(node.x + half, node.y + half, half)];
  const previous = node.points;
  node.points = [];
  for (const held of previous) insert(node, held, bucket);
}

function remove(node, point, bucket) {
  if (!node.children) {
    node.points.splice(node.points.findIndex(held => held.id === point.id), 1);
    return;
  }
  remove(node.children[destination(node, point)], point, bucket);
  if (node.children.some(child => child.children)) return;
  const points = node.children.flatMap(child => child.points);
  if (points.length <= bucket) {
    node.points = points.sort((a, b) => a.id - b.id);
    node.children = null;
  }
}

class QuadTree {
  constructor(points, world, bucket) {
    this.root = new Node(0, 0, world);
    this.bucket = bucket;
    for (const point of points) this.insert(point);
  }

  insert(point) {
    insert(this.root, point, this.bucket);
  }

  remove(point) {
    remove(this.root, point, this.bucket);
  }
}

module.exports = { QuadTree, destination, NAMES };
