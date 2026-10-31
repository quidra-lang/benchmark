import { GREEK } from './lexer.ts';
import { Box, atomType } from './boxes.ts';
import type { FormulaNode, Params } from './types.ts';

export function types(node: FormulaNode): [string,string] {
  if (node.kind === 'atom') { const type = atomType(node); return [type, type]; }
  if (node.kind === 'delim') return ['open', 'close'];
  if (node.kind === 'script' || node.kind === 'overset' || node.kind === 'underset') return types(node.base);
  return ['ordinary', 'ordinary'];
}

export function word(node: FormulaNode): boolean {
  if (node.kind === 'script') return word(node.base);
  return node.kind === 'atom' && node.atom === 'command' && (GREEK.has(node.value.slice(1)) || node.value === '\\infty');
}

export function alphanumeric(node: FormulaNode): boolean {
  if (word(node)) return true;
  if (node.kind === 'atom') return node.atom === 'identifier' || node.atom === 'number';
  if (node.kind === 'script') return alphanumeric(node.base);
  return node.kind === 'accent' && ['overline', 'hat', 'vec', 'dot', 'tilde'].includes(node.name) && alphanumeric(node.body);
}

const TYPE_ORDER = ['ordinary', 'operator', 'binary', 'relation', 'open', 'close', 'punctuation'];
const SPACE_TABLE: (string | number | null)[][] = [
  [0, 1, 'B', 'R', 0, 0, 0], [1, 1, null, 'R', 0, 0, 0],
  ['B', 'B', null, null, 'B', null, null], ['R', 'R', null, 0, 'R', 0, 0],
  [0, 0, null, 0, 0, 0, 0], [0, 1, 'B', 'R', 0, 0, 0], ['P', 'P', null, 'P', 'P', 'P', 'P'],
];

export function spacing(elements: FormulaNode[], style: string, params: Params): {types: [string,string][]; gaps: number[]} {
  const converted = elements.map(types), gaps: number[] = [];
  for (let i = 0; i < converted.length; i++) {
    if (converted[i][0] === 'binary' && (i === 0 || ['binary', 'operator', 'relation', 'open', 'punctuation'].includes(converted[i - 1][1]))) {
      converted[i] = ['ordinary', 'ordinary'];
    }
    if (i > 0 && ['relation', 'close', 'punctuation'].includes(converted[i][0]) && converted[i - 1][1] === 'binary') {
      converted[i - 1] = ['ordinary', 'ordinary'];
    }
  }
  if (converted.length && converted[converted.length - 1][1] === 'binary') converted[converted.length - 1] = ['ordinary', 'ordinary'];
  const widths: Record<string, number> = { B: style === 'script' ? 0 : params.bin_space, R: style === 'script' ? 0 : params.rel_space, P: style === 'script' ? 0 : params.punct_space };
  for (let i = 0; i + 1 < elements.length; i++) {
    if (alphanumeric(elements[i]) && alphanumeric(elements[i + 1]) && (word(elements[i]) || word(elements[i + 1]))) gaps.push(1);
    else {
      const value = SPACE_TABLE[TYPE_ORDER.indexOf(converted[i][1])][TYPE_ORDER.indexOf(converted[i + 1][0])];
      gaps.push(typeof value === 'number' ? value : widths[value as string]);
    }
  }
  return { types: converted, gaps };
}

export function rowBox(elements: Box[], gaps: number[], description = 'row', roles: string[] = []): Box {
  const ascent = Math.max(0, ...elements.map(box => box.baseline));
  const descent = Math.max(0, ...elements.map(box => box.height - 1 - box.baseline));
  const result = new Box(0, ascent + descent + 1, ascent, description);
  elements.forEach((box, i) => {
    result.add(box, result.width, ascent - box.baseline, roles[i] || '');
    result.width += box.width;
    if (i < elements.length - 1) result.width += gaps[i];
  });
  return result;
}

