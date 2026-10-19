function leafOrder(count, nodes) {
  const order = [];
  const stack = [nodes.length - 1];
  while (stack.length > 0) {
    const id = stack.pop();
    if (id < count) order.push(id);
    else stack.push(nodes[id].lower, nodes[id].upper);
  }
  return order;
}

function heightColumn(height, maximum, width) {
  return Math.floor(height / maximum * width);
}

function drawDendrogram(observations, tree, width, cutHeights) {
  const maximum = Math.max(...tree.merges.map(merge => merge.height));
  const grid = observations.map(() => Array(width + 1).fill(0));
  const marks = ' :-|+';
  function mark(row, column, priority) {
    grid[row][column] = Math.max(grid[row][column], priority);
  }
  const cuts = cutHeights.map(height => heightColumn(height, maximum, width));
  for (const column of cuts) {
    if (column <= width) for (let row = 0; row < observations.length; row += 1) mark(row, column, 1);
  }
  const anchors = Array(tree.nodes.length);
  const columns = tree.nodes.map(node => heightColumn(node.height, maximum, width));
  tree.order.forEach((leaf, row) => { anchors[leaf] = row; });
  for (let id = tree.count; id < tree.nodes.length; id += 1) {
    const node = tree.nodes[id];
    const upper = anchors[node.upper];
    const lower = anchors[node.lower];
    const column = columns[id];
    anchors[id] = Math.floor((upper + lower) / 2);
    mark(upper, column, 4);
    mark(lower, column, 4);
    for (let row = upper + 1; row < lower; row += 1) mark(row, column, 3);
    for (const child of [node.upper, node.lower]) {
      const start = child < tree.count ? 0 : columns[child] + 1;
      for (let x = start; x < column; x += 1) mark(anchors[child], x, 2);
    }
  }
  const idWidth = Math.max(...observations.map(observation => observation.id.length));
  const labelWidth = Math.max(...observations.map(observation => observation.label.length));
  const rows = tree.order.map((leaf, row) => {
    const observation = observations[leaf];
    return (observation.id.padEnd(idWidth) + ' ' + observation.label.padEnd(labelWidth) + ' '
      + grid[row].map(priority => marks[priority]).join('')).replace(/ +$/, '');
  });
  const scale = ' '.repeat(idWidth + labelWidth + 2)
    + Array.from({ length: width + 1 }, (_, column) => column % 10 === 0 ? '+' : '-').join('');
  return { maximum, rows, scale, cuts };
}

module.exports = { leafOrder, heightColumn, drawDendrogram };
