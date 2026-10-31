'use strict';

const fs = require('node:fs');
const dataset = require('./dataset');
const kd = require('./kdtree');
const quad = require('./quadtree');
const rt = require('./rtree');
const { Grid } = require('./grid');
const { fraction, ids, writeLines } = require('./report');

const POINT_STRUCTURES = ['kdtree', 'quadtree', 'rtree', 'str', 'grid'];
const RECTANGLE_STRUCTURES = ['rtree_rect', 'str_rect'];
const TREE_STRUCTURES = ['kdtree', 'quadtree', 'rtree', 'str', ...RECTANGLE_STRUCTURES];
const SEARCH_COMMANDS = ['RANGE', 'RADIUS', 'KNN', 'WINDOWCOUNT', 'CONTAINS', 'NEAREST', 'JOIN'];
const fields = (...values) => values.join(' ');

function distance(x, y, point) {
  return (point.x - x) * (point.x - x) + (point.y - y) * (point.y - y);
}

function minimumDistance(x, y, box) {
  const dx = x < box[0] ? box[0] - x : x > box[2] ? x - box[2] : 0;
  const dy = y < box[1] ? box[1] - y : y > box[3] ? y - box[3] : 0;
  return dx * dx + dy * dy;
}

function makeView(source, region, held, children, depth, mark) {
  let count = held.length;
  for (const child of children) count += child.count;
  return { source, region, held, children, count, depth, mark };
}

function kdView(node, region, depth = 0, mark = 'root') {
  const children = [];
  const split = node.axis === 0 ? node.point.x : node.point.y;
  if (node.left) {
    const bounds = region.slice();
    bounds[node.axis + 2] = split;
    children.push(kdView(node.left, bounds, depth + 1, 'L'));
  }
  if (node.right) {
    const bounds = region.slice();
    bounds[node.axis] = split;
    children.push(kdView(node.right, bounds, depth + 1, 'R'));
  }
  return makeView(node, region, [node.point], children, depth, mark);
}

function quadView(node, depth = 0, mark = 'root') {
  const region = [node.x, node.y, node.x + node.size - 1, node.y + node.size - 1];
  const children = node.children ? node.children.map((child, index) => quadView(child, depth + 1, quad.NAMES[index])) : [];
  return makeView(node, region, node.points, children, depth, mark);
}

function rtreeView(node, depth = 0) {
  const children = node.level > 0 ? node.entries.map(entry => rtreeView(entry.child, depth + 1)) : [];
  const held = node.level === 0 ? node.entries.map(entry => entry.object) : [];
  return makeView(node, rt.box(node), held, children, depth, '');
}

function gridView(grid, world) {
  const children = grid.cells.map(cell => {
    const x = cell.column * grid.size;
    const y = cell.row * grid.size;
    return makeView(cell, [x, y, x + grid.size - 1, y + grid.size - 1], cell.points, [], 1, '');
  });
  return makeView(grid, [0, 0, world - 1, world - 1], [], children, 0, '');
}

function currentViews(state) {
  if (state.views) return state.views;
  const world = state.settings.world;
  const structures = state.structures;
  const views = { kdtree: kdView(structures.kdtree.root, [0, 0, world - 1, world - 1]),
    quadtree: quadView(structures.quadtree.root), grid: gridView(structures.grid, world) };
  for (const name of ['rtree', 'str', ...RECTANGLE_STRUCTURES]) views[name] = rtreeView(structures[name].root);
  state.views = views;
  return views;
}

function conditionSearch(root, regionCondition, objectCondition) {
  const answer = [];
  let nodes = 0;
  let tests = 0;
  const pending = [root];
  while (pending.length) {
    const node = pending.pop();
    nodes++;
    tests += node.held.length;
    for (const object of node.held) if (objectCondition(object)) answer.push(object.id);
    for (let index = node.children.length - 1; index >= 0; index--) {
      const child = node.children[index];
      if (regionCondition(child.region)) pending.push(child);
    }
  }
  answer.sort((a, b) => a - b);
  return { answer, nodes, tests };
}

function windowCount(root, window) {
  let answer = 0;
  let nodes = 0;
  let tests = 0;
  const pending = [root];
  while (pending.length) {
    const node = pending.pop();
    nodes++;
    if (rt.contains(window, node.region)) {
      answer += node.count;
      continue;
    }
    tests += node.held.length;
    for (const point of node.held) if (rt.contains(window, point.box)) answer++;
    for (let index = node.children.length - 1; index >= 0; index--) {
      const child = node.children[index];
      if (rt.intersects(child.region, window)) pending.push(child);
    }
  }
  return { answer, nodes, tests };
}

class PriorityQueue {
  constructor() {
    this.entries = [];
  }

  push(entry) {
    let index = this.entries.length;
    this.entries.push(entry);
    while (index > 0) {
      const parent = Math.floor((index - 1) / 2);
      if (rt.compare(this.entries[parent].key, entry.key) < 0) break;
      this.entries[index] = this.entries[parent];
      index = parent;
    }
    this.entries[index] = entry;
  }

  pop() {
    const first = this.entries[0];
    const last = this.entries.pop();
    if (this.entries.length === 0) return first;
    let index = 0;
    while (2 * index + 1 < this.entries.length) {
      let child = 2 * index + 1;
      if (child + 1 < this.entries.length && rt.compare(this.entries[child + 1].key, this.entries[child].key) < 0) child++;
      if (rt.compare(last.key, this.entries[child].key) < 0) break;
      this.entries[index] = this.entries[child];
      index = child;
    }
    this.entries[index] = last;
    return first;
  }
}

function nearestSearch(root, x, y, count, rectangles) {
  const pending = new PriorityQueue();
  let serial = 0;
  const enqueue = node => pending.push({ key: [minimumDistance(x, y, node.region), 0, serial++], node });
  enqueue(root);
  let nodes = 0;
  let tests = 0;
  const answer = [];
  while (answer.length < count) {
    const entry = pending.pop();
    if (entry.object) {
      answer.push([entry.object.id, entry.key[0]]);
      continue;
    }
    const node = entry.node;
    nodes++;
    tests += node.held.length;
    for (const object of node.held) {
      const value = rectangles ? minimumDistance(x, y, object.box) : distance(x, y, object);
      pending.push({ key: [value, 1, object.id], object });
    }
    for (const child of node.children) enqueue(child);
  }
  return { answer, nodes, tests };
}

function spatialJoin(pointRoot, rectangleRoot) {
  const answer = [];
  let nodes = 0;
  let tests = 0;
  function visit(points, rectangles) {
    nodes++;
    if (points.children.length === 0 && rectangles.children.length === 0) {
      tests += points.held.length * rectangles.held.length;
      for (const point of points.held) {
        for (const rectangle of rectangles.held) if (rt.contains(rectangle.box, point.box)) answer.push([rectangle.id, point.id]);
      }
    } else if (points.children.length === 0) {
      for (const child of rectangles.children) if (rt.intersects(child.region, points.region)) visit(points, child);
    } else if (rectangles.children.length === 0) {
      for (const child of points.children) if (rt.intersects(child.region, rectangles.region)) visit(child, rectangles);
    } else {
      for (const pointChild of points.children) {
        for (const rectangleChild of rectangles.children) {
          if (rt.intersects(pointChild.region, rectangleChild.region)) visit(pointChild, rectangleChild);
        }
      }
    }
  }
  visit(pointRoot, rectangleRoot);
  answer.sort(rt.compare);
  return { answer, nodes, tests };
}

function searchNames(command) {
  if (command === 'JOIN') return ['rtree', 'str'];
  return command === 'CONTAINS' || command === 'NEAREST' ? RECTANGLE_STRUCTURES : POINT_STRUCTURES;
}

function search(root, command, args) {
  const [x, y] = args;
  switch (command) {
    case 'RANGE': return conditionSearch(root, region => rt.intersects(region, args), object => rt.contains(args, object.box));
    case 'RADIUS': {
      const squared = args[2] * args[2];
      return conditionSearch(root, region => minimumDistance(x, y, region) <= squared,
        object => distance(x, y, object) <= squared);
    }
    case 'CONTAINS': {
      const box = [x, y, x, y];
      return conditionSearch(root, region => rt.contains(region, box), object => rt.contains(object.box, box));
    }
    case 'WINDOWCOUNT': return windowCount(root, args);
    case 'KNN': return nearestSearch(root, x, y, args[2], false);
    case 'NEAREST': return nearestSearch(root, x, y, args[2], true);
  }
}

function bruteForce(state, command, args) {
  const points = [...state.points.values()].sort((a, b) => a.id - b.id);
  const [x, y] = args;
  switch (command) {
    case 'RANGE': return points.filter(point => rt.contains(args, point.box)).map(point => point.id);
    case 'RADIUS': return points.filter(point => distance(x, y, point) <= args[2] * args[2]).map(point => point.id);
    case 'WINDOWCOUNT': return points.filter(point => rt.contains(args, point.box)).length;
    case 'CONTAINS': return state.rectangles.filter(rectangle => rt.contains(rectangle.box, [x, y, x, y])).map(rectangle => rectangle.id);
    case 'KNN': return points.map(point => [point.id, distance(x, y, point)])
      .sort((a, b) => a[1] - b[1] || a[0] - b[0]).slice(0, args[2]);
    case 'NEAREST': return state.rectangles.map(rectangle => [rectangle.id, minimumDistance(x, y, rectangle.box)])
      .sort((a, b) => a[1] - b[1] || a[0] - b[0]).slice(0, args[2]);
    case 'JOIN': {
      const pairs = [];
      for (const rectangle of state.rectangles) {
        for (const point of points) if (rt.contains(rectangle.box, point.box)) pairs.push([rectangle.id, point.id]);
      }
      return pairs;
    }
  }
}

function sameAnswer(actual, expected) {
  if (!Array.isArray(expected)) return actual === expected;
  if (!Array.isArray(actual) || actual.length !== expected.length) return false;
  return expected.every((value, index) => Array.isArray(value)
    ? Array.isArray(actual[index]) && actual[index].length === value.length && value.every((part, position) => part === actual[index][position])
    : value === actual[index]);
}

function recordVisit(state, query, command, name, result) {
  state.visits.push([query, command, name, result.nodes, result.tests].join(','));
  if (!state.totals.has(command)) state.totals.set(command, new Map());
  const totals = state.totals.get(command);
  if (!totals.has(name)) totals.set(name, { queries: 0, nodes: 0, tests: 0, maximum: 0 });
  const total = totals.get(name);
  total.queries++;
  total.nodes += result.nodes;
  total.tests += result.tests;
  total.maximum = Math.max(total.maximum, result.nodes);
}

function executeSearch(state, query, command, args) {
  const expected = bruteForce(state, command, args);
  const views = currentViews(state);
  const mismatches = [];
  for (const name of searchNames(command)) {
    const result = command === 'JOIN' ? spatialJoin(views[name], views[name + '_rect']) : search(views[name], command, args);
    recordVisit(state, query, command, name, result);
    if (!sameAnswer(result.answer, expected)) mismatches.push(name);
  }
  const check = mismatches.length ? 'mismatch ' + mismatches.join(' ') : 'ok';
  if (command === 'WINDOWCOUNT') return fields(query, command, 'count', expected, 'check', check);
  if (command === 'JOIN') {
    for (const pair of expected) state.joins.push([query, ...pair].join(','));
    return fields(query, command, 'count', expected.length, 'check', check);
  }
  const values = command === 'KNN' || command === 'NEAREST' ? expected.map(pair => pair.join(':')) : expected;
  return fields(query, command, 'count', expected.length, 'ids', ids(values), 'check', check);
}

function preorder(root) {
  const nodes = [];
  const pending = [root];
  while (pending.length) {
    const node = pending.pop();
    nodes.push(node);
    for (let index = node.children.length - 1; index >= 0; index--) pending.push(node.children[index]);
  }
  return nodes;
}

function dumpTree(name, root) {
  return preorder(root).map(view => {
    const node = view.source;
    let line;
    if (name === 'kdtree') line = fields(view.mark, node.axis === 0 ? 'x' : 'y', node.point.id,
      node.point.x, node.point.y, 'box', ...view.region);
    else if (name === 'quadtree') line = fields(view.mark, node.x, node.y, node.size,
      node.children ? fields('node count', view.count) : fields('leaf', ids(view.held.map(point => point.id))));
    else line = node.level === 0 ? fields('leaf', ...view.region, 'ids', ids(view.held.map(object => object.id)))
      : fields('node', node.level, ...view.region, 'entries', node.entries.length);
    return ' '.repeat(2 * (view.depth + 1)) + line;
  });
}

function kdStatistics(root) {
  const nodes = preorder(root);
  const depths = [];
  let leaves = 0;
  let oneChild = 0;
  let depthSum = 0;
  for (const node of nodes) {
    while (depths.length <= node.depth) depths.push({ nodes: 0, leaves: 0, oneChild: 0 });
    const depth = depths[node.depth];
    depth.nodes++;
    depthSum += node.depth;
    if (node.children.length === 0) {
      depth.leaves++;
      leaves++;
    } else if (node.children.length === 1) {
      depth.oneChild++;
      oneChild++;
    }
  }
  let ideal = 0;
  while (2 ** ideal - 1 < nodes.length) ideal++;
  return [fields('kdtree height', depths.length, 'ideal', ideal, 'nodes', nodes.length, 'leaves', leaves,
    'one_child', oneChild, 'depth_sum', depthSum, 'avg_depth', fraction(depthSum, nodes.length)),
  ...depths.map((value, depth) => '  ' + fields('depth', depth, 'nodes', value.nodes, 'leaves', value.leaves, 'one_child', value.oneChild))];
}

function quadStatistics(root, bucket) {
  const depths = [];
  let internal = 0;
  let leaves = 0;
  let empty = 0;
  let maximum = 0;
  for (const node of preorder(root)) {
    while (depths.length <= node.depth) depths.push({ internal: 0, leaves: 0, points: 0 });
    const depth = depths[node.depth];
    if (node.children.length) {
      depth.internal++;
      internal++;
    } else {
      depth.leaves++;
      depth.points += node.held.length;
      leaves++;
      if (node.held.length === 0) empty++;
      maximum = Math.max(maximum, node.held.length);
    }
  }
  return [fields('quadtree height', depths.length, 'internal', internal, 'leaves', leaves, 'empty', empty,
    'max_leaf', maximum, 'fill', fraction(root.count, leaves * bucket)),
  ...depths.map((value, depth) => '  ' + fields('depth', depth, 'internal', value.internal, 'leaves', value.leaves, 'points', value.points))];
}

function rtreeStatistics(name, root, settings) {
  const nodes = preorder(root);
  const height = root.source.level + 1;
  const levels = Array.from({ length: height }, () => []);
  let leaves = 0;
  let entries = 0;
  for (const node of nodes) {
    levels[node.source.level].push(node);
    entries += node.source.entries.length;
    if (node.source.level === 0) leaves++;
  }
  const lines = [fields(name, 'height', height, 'nodes', nodes.length, 'leaves', leaves,
    'entries', entries, 'fill', fraction(entries, nodes.length * settings.maximum))];
  for (let level = height - 1; level >= 0; level--) {
    const group = levels[level];
    let totalEntries = 0;
    let minimum = Infinity;
    let maximum = 0;
    let under = 0;
    let area = 0;
    let overlap = 0;
    for (let first = 0; first < group.length; first++) {
      const node = group[first];
      const count = node.source.entries.length;
      totalEntries += count;
      minimum = Math.min(minimum, count);
      maximum = Math.max(maximum, count);
      if (count < settings.minimum) under++;
      area += rt.area(node.region);
      for (let second = first + 1; second < group.length; second++) overlap += rt.overlap(node.region, group[second].region);
    }
    lines.push('  ' + fields('level', level, 'nodes', group.length, 'entries', totalEntries,
      'min', minimum, 'max', maximum, 'under', under, 'area', area, 'overlap', overlap));
  }
  return lines;
}

function gridStatistics(root) {
  const occupancy = new Map();
  let used = 0;
  let maximum = 0;
  for (const cell of root.children) {
    const count = cell.held.length;
    occupancy.set(count, (occupancy.get(count) || 0) + 1);
    if (count > 0) used++;
    maximum = Math.max(maximum, count);
  }
  const counts = [...occupancy].sort((a, b) => a[0] - b[0]).map(pair => pair.join(':'));
  return [fields('grid cells', root.children.length, 'used', used, 'max', maximum), '  ' + fields('occupancy', ...counts)];
}

function snapshot(state, query) {
  const number = state.snapshots++;
  const views = currentViews(state);
  const header = fields('snapshot', number, 'query', query, 'points', state.points.size, 'rects', state.rectangles.length);
  if (number > 0) {
    state.dumps.push('');
    state.statistics.push('');
  }
  state.dumps.push(header);
  state.statistics.push(header);
  for (const name of TREE_STRUCTURES) state.dumps.push(name, ...dumpTree(name, views[name]));
  state.statistics.push(...kdStatistics(views.kdtree), ...quadStatistics(views.quadtree, state.settings.bucket));
  for (const name of ['rtree', 'str', ...RECTANGLE_STRUCTURES]) state.statistics.push(...rtreeStatistics(name, views[name], state.settings));
  state.statistics.push(...gridStatistics(views.grid));
  return number;
}

function locateKD(root, point) {
  let node = root;
  let path = '';
  while (node.point.id !== point.id) {
    const left = kd.compare(point, node.point, node.axis) < 0;
    path += left ? 'L' : 'R';
    node = left ? node.left : node.right;
  }
  return path || '-';
}

function locateQuad(root, point) {
  let node = root;
  const path = [];
  while (node.children) {
    const child = quad.destination(node, point);
    path.push(quad.NAMES[child]);
    node = node.children[child];
  }
  return path.join('/') || '-';
}

function locateRTree(node, point) {
  if (node.level === 0) {
    const index = node.entries.findIndex(entry => entry.object.id === point.id);
    return index < 0 ? null : [index + 1];
  }
  for (let index = 0; index < node.entries.length; index++) {
    const entry = node.entries[index];
    if (!rt.contains(entry.box, point.box)) continue;
    const found = locateRTree(entry.child, point);
    if (found) return [index + 1, ...found];
  }
  return null;
}

function locate(state, query, id) {
  const point = state.points.get(id);
  if (!point) return fields(query, 'LOCATE', id, 'missing');
  const structures = state.structures;
  const cell = structures.grid.cell(point);
  return fields(query, 'LOCATE', id, 'kdtree', locateKD(structures.kdtree.root, point),
    'quadtree', locateQuad(structures.quadtree.root, point), 'rtree', locateRTree(structures.rtree.root, point).join('/'),
    'str', locateRTree(structures.str.root, point).join('/'), 'grid', cell.column, cell.row);
}

function updatePoint(state, query, command, args) {
  const id = args[0];
  if (command === 'INSERT') {
    const point = dataset.point(...args);
    for (const name of POINT_STRUCTURES) state.structures[name].insert(point);
    state.points.set(id, point);
    state.views = null;
    return fields(query, command, id, 'inserted points', state.points.size);
  }
  const point = state.points.get(id);
  if (!point) return fields(query, command, id, 'missing points', state.points.size);
  for (const name of POINT_STRUCTURES) state.structures[name].remove(point);
  state.points.delete(id);
  state.views = null;
  return fields(query, command, id, 'deleted points', state.points.size);
}

function visitSummary(state) {
  const lines = ['visits'];
  for (const command of SEARCH_COMMANDS) {
    const totals = state.totals.get(command);
    if (!totals) continue;
    const names = searchNames(command);
    for (const name of names) {
      const total = totals.get(name);
      lines.push(fields(command, name, 'queries', total.queries, 'nodes', total.nodes, 'tests', total.tests,
        'max_nodes', total.maximum, 'mean_nodes', fraction(total.nodes, total.queries)));
    }
    const ranking = names.map((name, index) => ({ name, index, ...totals.get(name) }))
      .sort((a, b) => a.nodes - b.nodes || a.tests - b.tests || a.index - b.index);
    lines.push(fields('rank', command, ...ranking.map(item => item.name)));
  }
  return lines;
}

function initialize(data) {
  const { points, rectangles, settings } = data;
  const structures = { kdtree: new kd.KDTree(points), quadtree: new quad.QuadTree(points, settings.world, settings.bucket),
    rtree: new rt.RTree(points, settings.maximum, settings.minimum), str: new rt.RTree(points, settings.maximum, settings.minimum, true),
    grid: new Grid(points, settings.world, settings.cell), rtree_rect: new rt.RTree(rectangles, settings.maximum, settings.minimum),
    str_rect: new rt.RTree(rectangles, settings.maximum, settings.minimum, true) };
  return { structures, settings, points: new Map(points.map(point => [point.id, point])),
    rectangles: rectangles.slice().sort((a, b) => a.id - b.id), views: null, snapshots: 0,
    answers: [], visits: ['query,command,structure,nodes,tests'], joins: ['query,rect,point'],
    dumps: [], statistics: [], totals: new Map() };
}

function main() {
  const data = dataset.readDataset();
  const state = initialize(data);
  snapshot(state, 0);
  data.commands.forEach((command, index) => {
    const query = index + 1;
    const { name, args } = command;
    let answer;
    if (SEARCH_COMMANDS.includes(name)) answer = executeSearch(state, query, name, args);
    else if (name === 'LOCATE') answer = locate(state, query, args[0]);
    else if (name === 'DUMP') answer = fields(query, 'DUMP snapshot', snapshot(state, query));
    else answer = updatePoint(state, query, name, args);
    state.answers.push(answer);
  });
  state.statistics.push('', ...visitSummary(state));
  fs.mkdirSync('output', { recursive: true });
  writeLines('answers.txt', state.answers);
  writeLines('visits.csv', state.visits);
  writeLines('join.csv', state.joins);
  writeLines('structures.txt', state.dumps);
  writeLines('stats.txt', state.statistics);
}

if (require.main === module) main();
