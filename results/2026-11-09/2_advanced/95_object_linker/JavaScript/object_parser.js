'use strict';

const fs = require('node:fs');

function readLines(filename) {
  return fs.readFileSync(filename, 'ascii').split('\n').slice(0, -1);
}

function belongs(name, prefix) {
  return name === prefix || name.startsWith(prefix + '.');
}

function isNobits(name) {
  return belongs(name, '.bss');
}

function isString(name) {
  return belongs(name, '.rodata.str');
}

class Section {
  constructor(object, name, alignment, size) {
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
    this.mergedPositions = new Map();
  }
}

class SymbolEntry {
  constructor(object, name, binding, kind, section = null, offset = 0, size = 0, alignment = 1) {
    Object.assign(this, {object, name, binding, kind, section, offset, size, alignment});
  }
}

class Relocation {
  constructor(section, offset, type, symbol, addend) {
    Object.assign(this, {section, offset, type, symbol, addend});
  }
}

class ObjectFile {
  constructor(name) {
    this.name = name;
    this.sections = [];
    this.sectionNames = new Map();
    this.symbols = [];
    this.symbolNames = new Map();
    this.comdats = [];
    this.relocations = [];
    this.rank = -1;
  }
}

function parseObject(lines, start, name) {
  const object = new ObjectFile(name);
  let current = null;
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
      bytes.copy(current.data, dataOffset);
      dataOffset += bytes.length;
    } else if (words[0] === 'comdat') {
      object.comdats.push({signature: words[1], sections: words.slice(2).map(section => object.sectionNames.get(section))});
    } else if (words[0] === 'symbol') {
      let symbol;
      if (words[3] === 'undef') symbol = new SymbolEntry(object, words[1], words[2], 'undef');
      else if (words[3] === 'common') {
        symbol = new SymbolEntry(object, words[1], words[2], 'common', null, 0, Number(words[4]), Number(words[5]));
      } else {
        symbol = new SymbolEntry(object, words[1], words[2], 'defined', object.sectionNames.get(words[3]), Number(words[4]));
      }
      object.symbols.push(symbol);
      object.symbolNames.set(symbol.name, symbol);
    } else if (words[0] === 'reloc') {
      const section = object.sectionNames.get(words[1]);
      const relocation = new Relocation(section, Number(words[2]), words[3], object.symbolNames.get(words[4]), Number(words[5]));
      section.relocations.push(relocation);
      object.relocations.push(relocation);
    }
  }
  return {object, next: index + 1};
}

function readObject(filename) {
  return parseObject(readLines('input/' + filename), 0, filename).object;
}

module.exports = {Section, SymbolEntry, Relocation, ObjectFile, readLines, belongs, isNobits, isString, parseObject, readObject};
