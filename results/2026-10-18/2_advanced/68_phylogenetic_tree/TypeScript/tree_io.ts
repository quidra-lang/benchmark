import { mkdirSync, writeFileSync } from 'node:fs';
import { rooted, type Tree, type Rooted } from './tree_building.ts';
export function real(value: number | null, digits: number): string {
  if (value === null) return '-'; if (Math.abs(value) >= 1e21) return `${BigInt(value)}.${'0'.repeat(digits)}`;
  const text = value.toFixed(digits); return +text === 0 ? (0).toFixed(digits) : text;
}
export function symbol(mask: number, count: number): string { return Array.from({ length: count }, (_, i) => mask & 2 ** i ? '*' : '.').join(''); }
export function ordered(view: Rooted, names: string[]): Map<number, number[]> {
  const minimum = new Map<number, string>(), children = new Map<number, number[]>();
  for (const v of [...view.nodes].reverse()) {
    const next = view.children.get(v)!; minimum.set(v, next.length ? next.map(c => minimum.get(c)!).sort()[0] : names[v]);
    children.set(v, [...next].sort((a, b) => minimum.get(a)! < minimum.get(b)! ? -1 : minimum.get(a)! > minimum.get(b)! ? 1 : 0));
  }
  return children;
}
export function newick(tree: Tree, outgroup: number, names: string[], mode: 'plain' | 'length' | 'support' = 'plain', support = new Map<number, number>()): string {
  const view = rooted(tree, outgroup), children = ordered(view, names);
  function node(v: number): string {
    const next = children.get(v)!; let text = next.length ? '(' + next.map(node).join(',') + ')' : names[v];
    if (v !== view.root) { if (mode === 'support' && next.length) text += support.get(view.masks.get(v)!) ?? 0; if (mode === 'length') text += ':' + real(tree.edges.get(v)!.get(view.parent.get(v)!)!, 5); }
    return text;
  }
  return node(view.root) + ';';
}
export function cladogram(tree: Tree, outgroup: number, names: string[], support: Map<number, number>): string[] {
  const view = rooted(tree, outgroup), children = ordered(view, names), lines = ['*'];
  function visit(v: number, prefix: string, last: boolean): void {
    const next = children.get(v)!; lines.push(prefix + (last ? '`-- ' : '|-- ') + (next.length ? `[${support.get(view.masks.get(v)!) ?? 0}]` : names[v]));
    next.forEach((c, i) => visit(c, prefix + (last ? '    ' : '|   '), i === next.length - 1));
  }
  const top = children.get(view.root)!; top.forEach((v, i) => visit(v, '', i === top.length - 1)); return lines;
}
export function write(name: string, lines: string[]): void { mkdirSync('output', { recursive: true }); writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii'); }
