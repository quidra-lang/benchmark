import type { Attribute, Row, Settings } from './dataset.ts';
import { statistics, evaluationValue, compareFractions, improves } from './impurity.ts';
import type { Fraction, Statistics } from './impurity.ts';

export type Split =
  | { attribute: number; kind: 'INT'; threshold: number }
  | { attribute: number; kind: 'CAT'; value: number };
export type Direction = 'left' | 'right';
export interface Surrogate {
  split: Split;
  direction: Direction;
  score: number;
}
interface NodeData extends Statistics {
  number: number;
  depth: number;
}
export interface LeafNode extends NodeData {
  kind: 'leaf';
}
export interface BranchNode extends NodeData {
  kind: 'branch';
  split: Split;
  left: TreeNode;
  right: TreeNode;
  surrogates: Surrogate[];
  defaultDirection: Direction;
}
export type TreeNode = LeafNode | BranchNode;
export interface TreeView {
  root: TreeNode;
  cuts: Set<number>;
}
export interface SplitCandidate {
  split: Split;
  left: Row[];
  right: Row[];
  value: Fraction;
}

export function candidates(rows: Row[], attribute: Attribute, index: number): Split[] {
  const present = new Set<number>();
  for (const row of rows) {
    const value = row.values[index];
    if (value !== null) present.add(value);
  }
  const values = [...present].sort((a, b) => a - b);
  if (values.length < 2) return [];
  if (attribute.kind === 'CAT') {
    return values.map((value) => ({ attribute: index, kind: 'CAT', value }));
  }
  return values
    .slice(0, -1)
    .map((value, i) => ({ attribute: index, kind: 'INT', threshold: value + values[i + 1] }));
}
export function goesLeft(split: Split, row: Row): boolean {
  const value = row.values[split.attribute];
  if (value === null) throw new Error('A split requires an observed value');
  return split.kind === 'INT' ? 2 * value <= split.threshold : value === split.value;
}
export function bestForAttribute(
  rows: Row[],
  attribute: Attribute,
  index: number,
  minLeaf: number,
  classes: number,
): SplitCandidate | null {
  let best: SplitCandidate | null = null;
  for (const split of candidates(rows, attribute, index)) {
    const left: Row[] = [];
    const right: Row[] = [];
    for (const row of rows) (goesLeft(split, row) ? left : right).push(row);
    if (left.length < minLeaf || right.length < minLeaf) continue;
    const value = evaluationValue(statistics(left, classes), statistics(right, classes));
    if (best === null || compareFractions(value, best.value) > 0) {
      best = { split, left, right, value };
    }
  }
  return best;
}
export function bestSplit(
  rows: Row[],
  attributes: Attribute[],
  minLeaf: number,
  classes: number,
): SplitCandidate | null {
  let best: SplitCandidate | null = null;
  for (let i = 0; i < attributes.length; i++) {
    const candidate = bestForAttribute(rows, attributes[i], i, minLeaf, classes);
    if (candidate && (best === null || compareFractions(candidate.value, best.value) > 0)) {
      best = candidate;
    }
  }
  return best;
}
function findSurrogates(
  rows: Row[],
  primary: Split,
  attributes: Attribute[],
  limit: number,
  leftCount: number,
  rightCount: number,
): Surrogate[] {
  const retained: Surrogate[] = [];
  const directions = rows.map((row) => goesLeft(primary, row));
  for (let a = 0; a < attributes.length; a++) {
    if (a === primary.attribute) continue;
    let best: Surrogate | null = null;
    for (const split of candidates(rows, attributes[a], a)) {
      let agreement = 0;
      rows.forEach((row, i) => {
        if (goesLeft(split, row) === directions[i]) agreement++;
      });
      const reverse = rows.length - agreement;
      const direction = agreement >= reverse ? 'left' : 'right';
      const score = Math.max(agreement, reverse);
      if (best === null || score > best.score) best = { split, direction, score };
    }
    if (best && best.score > Math.max(leftCount, rightCount)) retained.push(best);
  }
  retained.sort((a, b) => b.score - a.score || a.split.attribute - b.split.attribute);
  return retained.slice(0, limit);
}
export function growTree(
  rows: Row[],
  attributes: Attribute[],
  classes: number,
  settings: Settings,
): TreeNode {
  function grow(sequence: Row[], number: number, depth: number): TreeNode {
    const stats = statistics(sequence, classes);
    const leaf: LeafNode = { ...stats, number, depth, kind: 'leaf' };
    if (
      stats.error === 0 ||
      depth === settings.maxDepth ||
      sequence.length < settings.minSamplesSplit
    ) {
      return leaf;
    }
    const best = bestSplit(sequence, attributes, settings.minSamplesLeaf, classes);
    if (best === null || !improves(best.value, stats)) return leaf;
    return {
      ...stats,
      number,
      depth,
      kind: 'branch',
      split: best.split,
      defaultDirection: best.left.length >= best.right.length ? 'left' : 'right',
      surrogates: findSurrogates(
        sequence,
        best.split,
        attributes,
        settings.maxSurrogates,
        best.left.length,
        best.right.length,
      ),
      left: grow(best.left, 2 * number, depth + 1),
      right: grow(best.right, 2 * number + 1, depth + 1),
    };
  }
  return grow(rows, 1, 0);
}
