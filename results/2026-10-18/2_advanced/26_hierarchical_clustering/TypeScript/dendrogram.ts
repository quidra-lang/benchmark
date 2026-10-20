import type { Merge } from './agglomerative.ts';
import type { Observation } from './dataset.ts';
import type { Matrix } from './distances.ts';

export interface TreeNode extends Merge {
  id: number; minimum: number; maximum: number; depth: number;
  upper: number; lower: number; members: number[];
}
export interface Tree {
  count: number; merges: Merge[]; nodes: TreeNode[]; joining: number[]; cophenetic: Matrix; order: number[];
}

export function leafOrder(count: number, nodes: TreeNode[]): number[] {
  const order: number[] = [], stack = [nodes.length - 1];
  while (stack.length > 0) {
    const id = stack.pop()!;
    if (id < count) order.push(id);
    else stack.push(nodes[id].lower, nodes[id].upper);
  }
  return order;
}

export function heightColumn(height: number, maximum: number, width: number): number {
  return Math.floor(height / maximum * width);
}

export function drawDendrogram(observations: Observation[], tree: Tree, width: number, cutHeights: number[]) {
  const maximum = Math.max(...tree.merges.map(merge => merge.height));
  const grid = observations.map(() => Array<number>(width + 1).fill(0));
  const marks = ' :-|+';
  const mark = (row: number, column: number, priority: number) => {
    grid[row][column] = Math.max(grid[row][column], priority);
  };
  const cuts = cutHeights.map(height => heightColumn(height, maximum, width));
  for (const column of cuts) if (column <= width) {
    for (let row = 0; row < observations.length; row++) mark(row, column, 1);
  }
  const anchors = Array<number>(tree.nodes.length);
  const columns = tree.nodes.map(node => heightColumn(node.height, maximum, width));
  tree.order.forEach((leaf, row) => { anchors[leaf] = row; });
  for (const node of tree.nodes.slice(tree.count)) {
    const upper = anchors[node.upper], lower = anchors[node.lower], column = columns[node.id];
    anchors[node.id] = Math.floor((upper + lower) / 2);
    mark(upper, column, 4); mark(lower, column, 4);
    for (let row = upper + 1; row < lower; row++) mark(row, column, 3);
    for (const child of [node.upper, node.lower]) {
      const start = child < tree.count ? 0 : columns[child] + 1;
      for (let x = start; x < column; x++) mark(anchors[child], x, 2);
    }
  }
  const idWidth = Math.max(...observations.map(o => o.id.length));
  const labelWidth = Math.max(...observations.map(o => o.label.length));
  const rows = tree.order.map((leaf, row) => {
    const o = observations[leaf];
    return (o.id.padEnd(idWidth) + ' ' + o.label.padEnd(labelWidth) + ' '
      + grid[row].map(priority => marks[priority]).join('')).trimEnd();
  });
  const scale = ' '.repeat(idWidth + labelWidth + 2)
    + Array.from({ length: width + 1 }, (_, x) => x % 10 === 0 ? '+' : '-').join('');
  return { maximum, rows, scale, cuts };
}
