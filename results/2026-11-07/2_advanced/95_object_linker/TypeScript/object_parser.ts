import { readFileSync } from 'node:fs';
import { Buffer } from 'node:buffer';
import type { OutputSection } from './layout.ts';
import type { Merged, ComdatGroup } from './types.ts';

export function readLines(filename: string): string[] {
  return readFileSync(filename, 'ascii').split('\n').slice(0, -1);
}

export function belongs(name: string, prefix: string): boolean {
  return name === prefix || name.startsWith(prefix + '.');
}

export function isNobits(name: string): boolean {
  return belongs(name, '.bss');
}

export function isString(name: string): boolean {
  return belongs(name, '.rodata.str');
}

export class Section {
  kind: 'section' = 'section';
  object: ObjectFile;
  name: string;
  alignment: number;
  size: number;
  nobits: boolean;
  string: boolean;
  data: Buffer;
  relocations: Relocation[];
  discarded: string | null;
  output: OutputSection | null;
  live: boolean;
  address: number;
  merged: Merged | null;
  mergedPositions: Map<number, number>;
  constructor(object: ObjectFile, name: string, alignment: number, size: number) {
    this.kind = 'section';
    this.object = object;
    this.name = name;
    this.alignment = alignment;
    this.size = size;
    this.nobits = isNobits(name);
    this.string = isString(name);
    this.data = Buffer.alloc(this.nobits ? 0 : size);
    this.relocations = [];
    this.discarded = null;
    this.output = null;
    this.live = false;
    this.address = 0;
    this.merged = null;
    this.mergedPositions = new Map<number, number>();
  }
}

export class SymbolEntry {
  object: ObjectFile;
  name: string;
  binding: string;
  kind: 'defined' | 'common' | 'undef';
  section: Section | null;
  offset: number;
  size: number;
  alignment: number;
  constructor(object: ObjectFile, name: string, binding: string, kind: 'defined'|'common'|'undef',
    section: Section | null = null, offset = 0, size = 0, alignment = 1) {
    this.object = object; this.name = name; this.binding = binding; this.kind = kind;
    this.section = section; this.offset = offset; this.size = size; this.alignment = alignment;
  }
}

export class Relocation {
  section: Section;
  offset: number;
  type: string;
  symbol: SymbolEntry;
  addend: number;
  constructor(section: Section, offset: number, type: string, symbol: SymbolEntry, addend: number) {
    this.section = section; this.offset = offset; this.type = type; this.symbol = symbol; this.addend = addend;
  }
}

export class ObjectFile {
  name: string;
  sections: Section[];
  sectionNames: Map<string, Section>;
  symbols: SymbolEntry[];
  symbolNames: Map<string, SymbolEntry>;
  comdats: ComdatGroup[];
  relocations: Relocation[];
  rank: number;
  constructor(name: string) {
    this.name = name;
    this.sections = [];
    this.sectionNames = new Map<string, Section>();
    this.symbols = [];
    this.symbolNames = new Map<string, SymbolEntry>();
    this.comdats = [];
    this.relocations = [];
    this.rank = -1;
  }
}

export function parseObject(lines: string[], start: number, name: string): {object:ObjectFile;next:number} {
  const object = new ObjectFile(name);
  let current: Section | null = null;
  let dataOffset = 0;
  let index = start;
  for (; index < lines.length; index++) {
    const words = lines[index].split(' ');
    if (words[0] === 'end') break;
    if (words[0] === 'section') {
      current = new Section(object, words[1], Number(words[2]), Number(words[3]));
      object.sections.push(current);
      object.sectionNames.set(current.name, current);
      dataOffset = 0;
    } else if (words[0] === 'data') {
      const bytes = Buffer.from(words[1], 'hex');
      bytes.copy(current!.data, dataOffset);
      dataOffset += bytes.length;
    } else if (words[0] === 'comdat') {
      object.comdats.push({signature: words[1], sections: words.slice(2).map(section => object.sectionNames.get(section)!)});
    } else if (words[0] === 'symbol') {
      let symbol;
      if (words[3] === 'undef') symbol = new SymbolEntry(object, words[1], words[2], 'undef');
      else if (words[3] === 'common') {
        symbol = new SymbolEntry(object, words[1], words[2], 'common', null, 0, Number(words[4]), Number(words[5]));
      } else {
        symbol = new SymbolEntry(object, words[1], words[2], 'defined', object.sectionNames.get(words[3])!, Number(words[4]));
      }
      object.symbols.push(symbol);
      object.symbolNames.set(symbol.name, symbol);
    } else if (words[0] === 'reloc') {
      const section = object.sectionNames.get(words[1])!;
      const relocation = new Relocation(section, Number(words[2]), words[3], object.symbolNames.get(words[4])!, Number(words[5]));
      section.relocations.push(relocation);
      object.relocations.push(relocation);
    }
  }
  return {object, next: index + 1};
}

export function readObject(filename: string): ObjectFile {
  return parseObject(readLines('input/' + filename), 0, filename).object;
}

