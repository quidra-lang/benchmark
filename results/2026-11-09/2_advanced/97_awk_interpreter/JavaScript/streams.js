'use strict';

const fs = require('node:fs');
const { fail } = require('./builtins');
const validName = name => name !== '' && name[0] !== '.' && !/[^A-Za-z0-9._-]/.test(name);
const readLines = name => {
  const text = fs.readFileSync('input/' + name, 'ascii'); return text === '' ? [] : text.split('\n').slice(0, -1);
};

function argumentsList(lines) {
  const options = [], operands = [];
  const assignment = text => { const equal = text.indexOf('='); return { kind: 'assignment', name: text.slice(0, equal), value: text.slice(equal + 1) }; };
  for (const line of lines) {
    if (line.startsWith('-F ')) options.push({ name: 'FS', value: line.slice(3) });
    else if (line.startsWith('-v ')) options.push(assignment(line.slice(3)));
    else if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(line)) operands.push(assignment(line));
    else operands.push({ kind: 'file', name: line, records: 0 });
  }
  return { options, operands };
}

class Streams {
  constructor() { this.stdout = { content: '', writes: 0 }; this.outputs = new Map(); this.inputs = new Map(); }
  write(content, name = null, operator = null, position = null) {
    let output = this.stdout;
    if (name !== null) {
      if (!validName(name) || name === 'stdout.txt' || name === 'stats.txt') fail(position, 'invalid output file name');
      if (!this.outputs.has(name)) this.outputs.set(name, { content: '', writes: 0, open: false });
      output = this.outputs.get(name);
      if (!output.open) { if (operator === '>') output.content = ''; output.open = true; }
    }
    output.content += content; output.writes++;
  }
  getline(name) {
    if (!this.inputs.has(name)) this.inputs.set(name, { open: false, opened: false, reads: 0, lines: [], index: 0 });
    const input = this.inputs.get(name);
    if (!input.open) {
      if (!validName(name) || !fs.existsSync('input/' + name)) return { status: -1 };
      input.lines = readLines(name); input.index = 0; input.open = true; input.opened = true;
    }
    if (input.index === input.lines.length) return { status: 0 };
    input.reads++; return { status: 1, line: input.lines[input.index++] };
  }
  close(name) {
    let closed = false;
    for (const collection of [this.outputs, this.inputs]) {
      const stream = collection.get(name);
      if (stream !== undefined && stream.open) { stream.open = false; closed = true; }
    }
    return closed ? 0 : -1;
  }
  save() {
    fs.mkdirSync('output', { recursive: true }); fs.writeFileSync('output/stdout.txt', this.stdout.content, 'ascii');
    for (const [name, output] of this.outputs) fs.writeFileSync('output/' + name, output.content, 'ascii');
  }
}

module.exports = { argumentsList, validName, readLines, Streams };
