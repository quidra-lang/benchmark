export interface Tree {
  edges: Map<number, Map<number, number>>;
  next: number;
  negative: number;
}
export interface Rooted {
  root: number;
  children: Map<number, number[]>;
  parent: Map<number, number | null>;
  masks: Map<number, number>;
  nodes: number[];
}
export function empty(next: number): Tree {
  return { edges: new Map(), next, negative: 0 };
}
export function connect(tree: Tree, a: number, b: number, length = 0): void {
  if (!tree.edges.has(a)) tree.edges.set(a, new Map());
  if (!tree.edges.has(b)) tree.edges.set(b, new Map());
  tree.edges.get(a)!.set(b, length);
  tree.edges.get(b)!.set(a, length);
}
export function disconnect(tree: Tree, a: number, b: number): void {
  tree.edges.get(a)!.delete(b);
  tree.edges.get(b)!.delete(a);
}
export function clone(tree: Tree): Tree {
  return {
    edges: new Map([...tree.edges].map(([v, adjacent]) => [v, new Map(adjacent)])),
    next: tree.next,
    negative: tree.negative,
  };
}
export function leaves(tree: Tree): number[] {
  return [...tree.edges]
    .filter(([, edges]) => edges.size === 1)
    .map(([v]) => v)
    .sort((a, b) => a - b);
}
export function rooted(tree: Tree, outgroup: number): Rooted {
  const root = tree.edges.get(outgroup)!.keys().next().value!;
  const children = new Map<number, number[]>();
  const parent = new Map<number, number | null>([[root, null]]);
  const nodes = [root];
  for (let i = 0; i < nodes.length; i++) {
    const v = nodes[i];
    const next = [...tree.edges.get(v)!.keys()].filter((c) => c !== parent.get(v));
    children.set(v, next);
    for (const c of next) {
      parent.set(c, v);
      nodes.push(c);
    }
  }
  const masks = new Map<number, number>();
  for (const v of [...nodes].reverse()) {
    const child = children.get(v)!;
    masks.set(
      v,
      child.length
        ? child.reduce((mask, c) => mask | (v === root && c === outgroup ? 0 : masks.get(c)!), 0)
        : 2 ** v,
    );
  }
  return { root, children, parent, masks, nodes };
}
export function splits(tree: Tree, outgroup: number): Set<number> {
  const view = rooted(tree, outgroup);
  return new Set(
    view.nodes
      .filter((v) => v !== view.root && view.children.get(v)!.length > 0)
      .map((v) => view.masks.get(v)!),
  );
}
export function paths(tree: Tree, from: number): Map<number, { length: number; steps: number }> {
  const result = new Map([[from, { length: 0, steps: 0 }]]);
  const queue = [from];
  for (let i = 0; i < queue.length; i++) {
    const v = queue[i];
    const current = result.get(v)!;
    for (const [next, length] of tree.edges.get(v)!) {
      if (!result.has(next)) {
        result.set(next, { length: current.length + length, steps: current.steps + 1 });
        queue.push(next);
      }
    }
  }
  return result;
}
export function patristic(tree: Tree, taxa: number[]): number[][] {
  return taxa.map((i) => {
    const distance = paths(tree, i);
    return taxa.map((j) => distance.get(j)!.length);
  });
}
export function neighborJoining(values: number[][], taxa: number[]): Tree {
  const tree = empty(values.length);
  const distances = new Map<number, Map<number, number>>();
  let active = [...taxa];
  for (const i of taxa) distances.set(i, new Map(taxa.map((j) => [j, values[i][j]])));
  const d = (i: number, j: number): number => distances.get(i)!.get(j)!;
  while (active.length >= 4) {
    const r = active.length;
    const totals = new Map(
      active.map((i) => [i, active.reduce((sum, j) => (i === j ? sum : sum + d(i, j)), 0)]),
    );
    let first = active[0];
    let second = active[1];
    let best = Infinity;
    for (let a = 0; a < r; a++) {
      for (let b = a + 1; b < r; b++) {
        const i = active[a];
        const j = active[b];
        const q = (r - 2) * d(i, j) - totals.get(i)! - totals.get(j)!;
        if (q < best) {
          best = q;
          first = i;
          second = j;
        }
      }
    }
    const node = tree.next++;
    const left = d(first, second) / 2 + (totals.get(first)! - totals.get(second)!) / (2 * (r - 2));
    connect(tree, node, first, left);
    connect(tree, node, second, d(first, second) - left);
    const remaining = active.filter((i) => i !== first && i !== second);
    const row = new Map<number, number>();
    for (const i of remaining) {
      const value = (d(first, i) + d(second, i) - d(first, second)) / 2;
      row.set(i, value);
      distances.get(i)!.set(node, value);
    }
    distances.set(node, row);
    active = [...remaining, node];
  }
  const [a, b, c] = active;
  const node = tree.next++;
  connect(tree, node, a, (d(a, b) + d(a, c) - d(b, c)) / 2);
  connect(tree, node, b, (d(a, b) + d(b, c) - d(a, c)) / 2);
  connect(tree, node, c, (d(a, c) + d(b, c) - d(a, b)) / 2);
  for (const [u, adjacent] of tree.edges) {
    for (const [v, length] of adjacent) {
      if (u < v && length < 0) {
        tree.negative++;
        connect(tree, u, v, 0);
      }
    }
  }
  return tree;
}
