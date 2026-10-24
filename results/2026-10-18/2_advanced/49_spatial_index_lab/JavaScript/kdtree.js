'use strict';

class Node {
  constructor(point, axis) {
    this.point = point;
    this.axis = axis;
    this.left = null;
    this.right = null;
  }
}

function compare(first, second, axis) {
  return axis === 0 ? first.x - second.x || first.y - second.y || first.id - second.id
    : first.y - second.y || first.x - second.x || first.id - second.id;
}

function build(points, depth = 0) {
  if (points.length === 0) return null;
  const axis = depth % 2;
  const ordered = points.slice().sort((a, b) => compare(a, b, axis));
  const middle = Math.floor(ordered.length / 2);
  const node = new Node(ordered[middle], axis);
  node.left = build(ordered.slice(0, middle), depth + 1);
  node.right = build(ordered.slice(middle + 1), depth + 1);
  return node;
}

function minimum(node, axis) {
  if (node.axis === axis) return node.left ? minimum(node.left, axis) : node.point;
  let best = node.point;
  for (const child of [node.left, node.right]) {
    if (!child) continue;
    const candidate = minimum(child, axis);
    if (compare(candidate, best, axis) < 0) best = candidate;
  }
  return best;
}

function remove(node, point) {
  if (node.point.id === point.id) {
    if (node.right) {
      node.point = minimum(node.right, node.axis);
      node.right = remove(node.right, node.point);
    } else if (node.left) {
      node.point = minimum(node.left, node.axis);
      node.right = remove(node.left, node.point);
      node.left = null;
    } else return null;
  } else if (compare(point, node.point, node.axis) < 0) node.left = remove(node.left, point);
  else node.right = remove(node.right, point);
  return node;
}

class KDTree {
  constructor(points) {
    this.root = build(points);
  }

  insert(point) {
    if (!this.root) {
      this.root = new Node(point, 0);
      return;
    }
    let node = this.root;
    while (true) {
      const side = compare(point, node.point, node.axis) < 0 ? 'left' : 'right';
      if (!node[side]) {
        node[side] = new Node(point, 1 - node.axis);
        return;
      }
      node = node[side];
    }
  }

  remove(point) {
    this.root = remove(this.root, point);
  }
}

module.exports = { KDTree, compare };
