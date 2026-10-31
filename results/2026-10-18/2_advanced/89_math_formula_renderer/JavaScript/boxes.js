'use strict';

const { SYMBOL_COMMANDS } = require('./lexer');
const LARGE_GLYPHS = new Map([['\\sum', ['\\--', ' > ', '/--']], ['\\prod', ['___', '| |', '| |']], ['\\int', [' /', ' |', '/ ']]]);
const SYMBOL_TYPES = new Map();
for (const [characters, type] of [['+-*', 'binary'], ['=<>:', 'relation'], ['([', 'open'], [')]!', 'close'], [',;', 'punctuation'], ['/.|\'', 'ordinary']]) {
  for (const character of characters) SYMBOL_TYPES.set(character, type);
}

class Box {
  constructor(width, height, baseline, description) {
    this.width = width; this.height = height; this.baseline = baseline; this.description = description;
    this.children = []; this.strings = [];
  }
  add(box, x, y, role = '') { this.children.push({ box, x, y, role }); return this; }
  draw(text, x = 0, y = 0) { this.strings.push({ text, x, y }); return this; }
}

function atomType(node) {
  if (node.atom === 'symbol') return SYMBOL_TYPES.get(node.value);
  if (node.atom === 'command') return SYMBOL_COMMANDS.get(node.value).type;
  return 'ordinary';
}

function atomDisplay(node, references) {
  if (node.atom === 'reference') return references.has(node.value) ? references.get(node.value) : '(??)';
  if (node.atom === 'command') return SYMBOL_COMMANDS.get(node.value).display;
  return node.value;
}

function delimiterGlyph(delimiter, height) {
  if (delimiter === '.') return { width: 0, lines: [] };
  if (height === 1) return { width: 1, lines: [delimiter.length === 1 ? delimiter : delimiter[1]] };
  if (delimiter === '[' || delimiter === ']' || delimiter === '|') return { width: 1, lines: Array(height).fill(delimiter) };
  const left = delimiter === '(' || delimiter === '\\{', lines = Array(height).fill('|');
  lines[0] = left ? '/' : '\\'; lines[height - 1] = left ? '\\' : '/';
  if (height >= 3 && (delimiter === '\\{' || delimiter === '\\}')) lines[Math.floor((height - 1) / 2)] = left ? '<' : '>';
  return { width: 1, lines };
}

const center = (box, width) => Math.floor((width - box.width) / 2);
module.exports = { Box, LARGE_GLYPHS, atomType, atomDisplay, delimiterGlyph, center };
