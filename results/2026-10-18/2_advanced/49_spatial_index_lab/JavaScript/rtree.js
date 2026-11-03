'use strict';

function area(box) {
  return (box[2] - box[0]) * (box[3] - box[1]);
}

function union(first, second) {
  return [Math.min(first[0], second[0]), Math.min(first[1], second[1]),
    Math.max(first[2], second[2]), Math.max(first[3], second[3])];
}

function box(node) {
  let result = node.entries[0].box;
  for (let index = 1; index < node.entries.length; index++) result = union(result, node.entries[index].box);
  return result;
}

function enlargement(first, second) {
  return area(union(first, second)) - area(first);
}

function contains(first, second) {
  return first[0] <= second[0] && second[2] <= first[2] && first[1] <= second[1] && second[3] <= first[3];
}

function intersects(first, second) {
  return first[0] <= second[2] && second[0] <= first[2] && first[1] <= second[3] && second[1] <= first[3];
}

function overlap(first, second) {
  const width = Math.min(first[2], second[2]) - Math.max(first[0], second[0]);
  const height = Math.min(first[3], second[3]) - Math.max(first[1], second[1]);
  return width > 0 && height > 0 ? width * height : 0;
}

function compare(first, second) {
  for (let index = 0; index < first.length; index++) if (first[index] !== second[index]) return first[index] - second[index];
  return 0;
}

class Node {
  constructor(level, entries = []) {
    this.level = level;
    this.entries = entries;
    this.parent = null;
    for (const entry of entries) if (entry.child) entry.child.parent = this;
  }
}

function leafEntry(object) {
  return { box: object.box, object };
}

function childEntry(child) {
  return { box: box(child), child };
}

function split(node, minimum) {
  const entries = node.entries;
  let seeds = [0, 1];
  let waste = -Infinity;
  for (let first = 0; first < entries.length - 1; first++) {
    for (let second = first + 1; second < entries.length; second++) {
      const value = area(union(entries[first].box, entries[second].box)) - area(entries[first].box) - area(entries[second].box);
      if (value > waste) {
        waste = value;
        seeds = [first, second];
      }
    }
  }
  const groups = [[entries[seeds[0]]], [entries[seeds[1]]]];
  const bounds = groups.map(group => group[0].box);
  const rest = entries.filter((entry, index) => index !== seeds[0] && index !== seeds[1]);
  while (rest.length) {
    if (groups[0].length + rest.length === minimum) {
      groups[0].push(...rest);
      break;
    }
    if (groups[1].length + rest.length === minimum) {
      groups[1].push(...rest);
      break;
    }
    let chosen = 0;
    let largest = -1;
    for (let index = 0; index < rest.length; index++) {
      const difference = Math.abs(enlargement(bounds[0], rest[index].box) - enlargement(bounds[1], rest[index].box));
      if (difference > largest) {
        largest = difference;
        chosen = index;
      }
    }
    const [entry] = rest.splice(chosen, 1);
    const priorities = groups.map((group, index) => [enlargement(bounds[index], entry.box), area(bounds[index]), group.length]);
    const target = compare(priorities[0], priorities[1]) <= 0 ? 0 : 1;
    groups[target].push(entry);
    bounds[target] = union(bounds[target], entry.box);
  }
  node.entries = groups[0];
  for (const entry of node.entries) if (entry.child) entry.child.parent = node;
  return new Node(node.level, groups[1]);
}

function bulkLoad(objects, maximum) {
  let entries = objects.map(object => ({ ...leafEntry(object), number: object.id }));
  let level = 0;
  while (true) {
    const pages = Math.floor((entries.length + maximum - 1) / maximum);
    let slabs = 1;
    while (slabs * slabs < pages) slabs++;
    entries.sort((a, b) => compare([a.box[0] + a.box[2], a.box[1] + a.box[3], a.number],
      [b.box[0] + b.box[2], b.box[1] + b.box[3], b.number]));
    const nodes = [];
    for (let start = 0; start < entries.length; start += slabs * maximum) {
      const slab = entries.slice(start, start + slabs * maximum).sort((a, b) =>
        compare([a.box[1] + a.box[3], a.box[0] + a.box[2], a.number],
          [b.box[1] + b.box[3], b.box[0] + b.box[2], b.number]));
      for (let offset = 0; offset < slab.length; offset += maximum) nodes.push(new Node(level, slab.slice(offset, offset + maximum)));
    }
    if (nodes.length === 1) return nodes[0];
    entries = nodes.map((node, number) => ({ ...childEntry(node), number }));
    level++;
  }
}

function findLeaf(node, object) {
  if (node.level === 0) {
    const index = node.entries.findIndex(entry => entry.object.id === object.id);
    return index < 0 ? null : { node, index };
  }
  for (const entry of node.entries) {
    if (!contains(entry.box, object.box)) continue;
    const found = findLeaf(entry.child, object);
    if (found) return found;
  }
  return null;
}

class RTree {
  constructor(objects, maximum, minimum, bulk = false) {
    this.maximum = maximum;
    this.minimum = minimum;
    this.root = bulk ? bulkLoad(objects, maximum) : new Node(0);
    if (!bulk) for (const object of objects) this.insert(object);
  }

  choose(entry, level) {
    let node = this.root;
    while (node.level > level) {
      let selected = 0;
      let priority = [enlargement(node.entries[0].box, entry.box), area(node.entries[0].box)];
      for (let index = 1; index < node.entries.length; index++) {
        const candidate = [enlargement(node.entries[index].box, entry.box), area(node.entries[index].box)];
        if (compare(candidate, priority) < 0) {
          priority = candidate;
          selected = index;
        }
      }
      node = node.entries[selected].child;
    }
    return node;
  }

  insertEntry(entry, level) {
    let node = this.choose(entry, level);
    node.entries.push(entry);
    if (entry.child) entry.child.parent = node;
    while (true) {
      const sibling = node.entries.length > this.maximum ? split(node, this.minimum) : null;
      if (node === this.root) {
        if (sibling) this.root = new Node(node.level + 1, [childEntry(node), childEntry(sibling)]);
        return;
      }
      const parent = node.parent;
      parent.entries.find(item => item.child === node).box = box(node);
      if (sibling) {
        parent.entries.push(childEntry(sibling));
        sibling.parent = parent;
      }
      node = parent;
    }
  }

  insert(object) {
    this.insertEntry(leafEntry(object), 0);
  }

  remove(object) {
    const found = findLeaf(this.root, object);
    found.node.entries.splice(found.index, 1);
    let node = found.node;
    const removed = [];
    while (node !== this.root) {
      const parent = node.parent;
      const index = parent.entries.findIndex(entry => entry.child === node);
      if (node.entries.length < this.minimum) {
        parent.entries.splice(index, 1);
        removed.push(node);
        node.parent = null;
      } else parent.entries[index].box = box(node);
      node = parent;
    }
    // Condensing records lower nodes first; their entries must be reinserted first.
    for (const detached of removed) {
      for (const entry of detached.entries) this.insertEntry(entry, detached.level);
    }
    while (this.root.level > 0 && this.root.entries.length === 1) {
      this.root = this.root.entries[0].child;
      this.root.parent = null;
    }
  }
}

module.exports = { RTree, area, box, union, enlargement, contains, intersects, overlap, compare };
