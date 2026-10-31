import type { Row } from './dataset.ts';
import { goesLeft } from './tree_builder.ts';
import type { TreeNode, BranchNode, TreeView } from './tree_builder.ts';

export type RoutingMethod = 'primary' | 'surrogate' | 'default';
export interface RouteStep {
  node: BranchNode;
  left: boolean;
  method: RoutingMethod;
}
export interface Route {
  leaf: TreeNode;
  prediction: number;
  path: TreeNode[];
  steps: RouteStep[];
}
export function isBranch(node: TreeNode, view: TreeView): node is BranchNode {
  return node.kind === 'branch' && !view.cuts.has(node.number);
}
export function preorder(view: TreeView): TreeNode[] {
  const nodes: TreeNode[] = [];
  function visit(node: TreeNode): void {
    nodes.push(node);
    if (isBranch(node, view)) {
      visit(node.left);
      visit(node.right);
    }
  }
  visit(view.root);
  return nodes;
}
export function route(view: TreeView, row: Row): Route {
  const path: TreeNode[] = [];
  const steps: RouteStep[] = [];
  let node = view.root;
  while (true) {
    path.push(node);
    if (!isBranch(node, view)) return { leaf: node, prediction: node.majority, path, steps };
    let left: boolean;
    let method: RoutingMethod;
    if (row.values[node.split.attribute] !== null) {
      left = goesLeft(node.split, row);
      method = 'primary';
    } else {
      const surrogate = node.surrogates.find((item) => row.values[item.split.attribute] !== null);
      if (surrogate) {
        left = goesLeft(surrogate.split, row) === (surrogate.direction === 'left');
        method = 'surrogate';
      } else {
        left = node.defaultDirection === 'left';
        method = 'default';
      }
    }
    steps.push({ node, left, method });
    node = left ? node.left : node.right;
  }
}
export function predict(view: TreeView, row: Row): number {
  return route(view, row).prediction;
}
export function correctCount(view: TreeView, rows: Row[]): number {
  return rows.reduce((sum, row) => sum + Number(predict(view, row) === row.label), 0);
}
export function formatReal(value: number, digits = 4): string {
  const text = value.toFixed(digits);
  return Number(text) === 0 ? (0).toFixed(digits) : text;
}
export function ratio(numerator: number, denominator: number): string {
  return denominator === 0
    ? '0/0 -'
    : `${numerator}/${denominator} ${formatReal(numerator / denominator)}`;
}
export function reducedFraction(numerator: number, denominator: number, digits = 4): string {
  if (denominator === 0) return '- -';
  let a = Math.abs(numerator);
  let b = denominator;
  while (b !== 0) [a, b] = [b, a % b];
  return `${numerator / a}/${denominator / a} ${formatReal(numerator / denominator, digits)}`;
}
export function classificationLines(
  title: string,
  rows: Row[],
  predictions: number[],
  classes: string[],
): string[] {
  const matrix: number[][] = Array.from({ length: classes.length }, () =>
    Array(classes.length).fill(0),
  );
  let correct = 0;
  rows.forEach((row, i) => {
    matrix[row.label][predictions[i]]++;
    if (row.label === predictions[i]) correct++;
  });
  const lines = [
    `confusion ${title} correct ${correct}/${rows.length} accuracy ${reducedFraction(correct, rows.length)}`,
    `actual\\predicted ${classes.join(' ')}`,
  ];
  matrix.forEach((counts, i) => lines.push(`${classes[i]} ${counts.join(' ')}`));
  let macro = 0;
  let defined = 0;
  for (let k = 0; k < classes.length; k++) {
    const tp = matrix[k][k];
    let predicted = 0;
    let actual = 0;
    for (let j = 0; j < classes.length; j++) {
      predicted += matrix[j][k];
      actual += matrix[k][j];
    }
    lines.push(
      `class ${classes[k]} precision ${reducedFraction(tp, predicted)} recall ${reducedFraction(tp, actual)} f1 ${reducedFraction(2 * tp, predicted + actual)} support ${actual}`,
    );
    if (predicted + actual > 0) {
      macro += (2 * tp) / (predicted + actual);
      defined++;
    }
  }
  lines.push(`macro_f1 ${defined === 0 ? '-' : formatReal(macro / defined)}`);
  return lines;
}
