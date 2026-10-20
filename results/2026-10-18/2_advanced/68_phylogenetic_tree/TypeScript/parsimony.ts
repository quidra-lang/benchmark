import { baseSets, bases } from './alignment.ts';
import { clone, connect, disconnect, rooted, type Tree, type Rooted } from './tree_building.ts';
export function merge(a: number, b: number): number { return (a & b) || (a | b); }
export interface Branch { u: number; v: number; mask: number; length: number }
export function branches(tree: Tree, outgroup: number): Branch[] {
  const view = rooted(tree, outgroup);
  return view.nodes.filter(v => v !== view.root).map(v => ({ u: view.parent.get(v)!, v, mask: view.masks.get(v === outgroup ? view.root : v)!, length: tree.edges.get(v)!.get(view.parent.get(v)!)! })).sort((a, b) => a.mask - b.mask);
}
export function provisional(view: Rooted, sequences: string[], column: number, outgroup: number) {
  const sets = new Map<number, number>(); let changes = 0;
  const combine = (a: number, b: number): number => { if (!(a & b)) changes++; return merge(a, b); };
  for (const node of [...view.nodes].reverse()) {
    const children = view.children.get(node)!;
    if (!children.length) sets.set(node, baseSets[sequences[node][column]]);
    else {
      const [a, b] = children.filter(c => node !== view.root || c !== outgroup); sets.set(node, combine(sets.get(a)!, sets.get(b)!));
      if (node === view.root) combine(sets.get(node)!, sets.get(outgroup)!);
    }
  }
  return { sets, changes };
}
export function fitch(tree: Tree, sequences: string[], outgroup: number) {
  const view = rooted(tree, outgroup), columns = Array.from({ length: sequences[0].length }, (_, c) => provisional(view, sequences, c, outgroup).changes);
  return { columns, score: columns.reduce((sum, n) => sum + n, 0) };
}
export function reconstruct(tree: Tree, sequences: string[], outgroup: number) {
  const view = rooted(tree, outgroup), list = branches(tree, outgroup), changes = new Map(list.map(b => [b.mask, 0])), ancestors = new Map(view.nodes.map(v => [v, ''])), columns: number[] = [];
  const first = (set: number): number => [1, 2, 4, 8].find(base => (set & base) !== 0)!;
  for (let c = 0; c < sequences[0].length; c++) {
    const provisionalColumn = provisional(view, sequences, c, outgroup), sets = provisionalColumn.sets, chosen = new Map<number, number>(), x0 = first(merge(sets.get(view.root)!, sets.get(outgroup)!)); columns.push(provisionalColumn.changes);
    chosen.set(view.root, sets.get(view.root)! & x0 ? x0 : first(sets.get(view.root)!)); chosen.set(outgroup, sets.get(outgroup)! & x0 ? x0 : first(sets.get(outgroup)!));
    for (const v of view.nodes) if (v !== view.root && v !== outgroup) { const parent = chosen.get(view.parent.get(v)!)!, set = sets.get(v)!; chosen.set(v, set & parent ? parent : first(set)); }
    for (const v of view.nodes) ancestors.set(v, ancestors.get(v)! + bases[[1, 2, 4, 8].indexOf(chosen.get(v)!)]);
    for (const b of list) if (chosen.get(b.u) !== chosen.get(b.v)) changes.set(b.mask, changes.get(b.mask)! + 1);
  }
  const result = clone(tree); for (const b of list) connect(result, b.u, b.v, changes.get(b.mask)! / sequences[0].length);
  return { tree: result, changes, ancestors, columns, score: columns.reduce((sum, n) => sum + n, 0) };
}
export function insert(tree: Tree, branch: Branch, taxon: number): Tree {
  const next = clone(tree), node = next.next++; disconnect(next, branch.u, branch.v); connect(next, branch.u, node); connect(next, node, branch.v); connect(next, node, taxon); return next;
}
export function nni(tree: Tree, branch: Branch, swap: 1 | 2, outgroup: number): Tree {
  const view = rooted(tree, outgroup), u = branch.u, v = branch.v, s = view.children.get(u)!.find(c => c !== v && c !== outgroup)!;
  const children = [...view.children.get(v)!].sort((a, b) => view.masks.get(a)! - view.masks.get(b)!), c = children[swap - 1], next = clone(tree), us = tree.edges.get(u)!.get(s)!, vc = tree.edges.get(v)!.get(c)!;
  disconnect(next, u, s); disconnect(next, v, c); connect(next, u, c, vc); connect(next, v, s, us); return next;
}
