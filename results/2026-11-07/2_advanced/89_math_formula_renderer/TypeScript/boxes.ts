import { SYMBOL_COMMANDS } from './lexer.ts';
import type { FormulaNode, Glyph, Placement } from './types.ts';
export const LARGE_GLYPHS = new Map<string, string[]>([['\\sum', ['\\--', ' > ', '/--']], ['\\prod', ['___', '| |', '| |']], ['\\int', [' /', ' |', '/ ']]]);
const SYMBOL_TYPES = new Map<string, string>();
for (const [characters, type] of [['+-*', 'binary'], ['=<>:', 'relation'], ['([', 'open'], [')]!', 'close'], [',;', 'punctuation'], ['/.|\'', 'ordinary']]) {
  for (const character of characters) SYMBOL_TYPES.set(character, type);
}

export class Box {
  width: number;
  height: number;
  baseline: number;
  description: string;
  children: Placement[];
  strings: {text: string; x: number; y: number}[];
  constructor(width: number, height: number, baseline: number, description: string) {
    this.width = width; this.height = height; this.baseline = baseline; this.description = description;
    this.children = []; this.strings = [];
  }
  add(box: Box, x: number, y: number, role = ''): Box { this.children.push({ box, x, y, role }); return this; }
  draw(text: string, x = 0, y = 0): Box { this.strings.push({ text, x, y }); return this; }
}

export function atomType(node: Extract<FormulaNode,{kind:'atom'}>): string {
  if (node.atom === 'symbol') return SYMBOL_TYPES.get(node.value) || 'ordinary';
  if (node.atom === 'command') return SYMBOL_COMMANDS.get(node.value)!.type;
  return 'ordinary';
}

export function atomDisplay(node: Extract<FormulaNode,{kind:'atom'}>, references: Map<string,string>): string {
  if (node.atom === 'reference') return references.has(node.value) ? references.get(node.value)! : '(??)';
  if (node.atom === 'command') return SYMBOL_COMMANDS.get(node.value)!.display;
  return node.value;
}

export function delimiterGlyph(delimiter: string, height: number): Glyph {
  if (delimiter === '.') return { width: 0, lines: [] };
  if (height === 1) return { width: 1, lines: [delimiter.length === 1 ? delimiter : delimiter[1]] };
  if (delimiter === '[' || delimiter === ']' || delimiter === '|') return { width: 1, lines: Array(height).fill(delimiter) };
  const left = delimiter === '(' || delimiter === '\\{', lines = Array(height).fill('|');
  lines[0] = left ? '/' : '\\'; lines[height - 1] = left ? '\\' : '/';
  if (height >= 3 && (delimiter === '\\{' || delimiter === '\\}')) lines[Math.floor((height - 1) / 2)] = left ? '<' : '>';
  return { width: 1, lines };
}

export const center = (box: Box, width: number): number => Math.floor((width - box.width) / 2);
