'use strict';

const fs = require('node:fs');
const charset = require('./charset');
const formatter = require('./formatter');
const {BacktrackVM, TooManySteps} = require('./backtrack_vm');
const {PikeVM} = require('./pike_vm');

class PatternError extends Error {
  constructor(message, column) { super(message); this.column = column; }
}

function quantifier(character) {
  return character === '*' || character === '+' || character === '?' || character === '{';
}

class PatternParser {
  constructor(source) {
    this.source = source;
    this.index = 0;
    this.groups = 0;
    this.names = new Map();
    this.references = [];
  }

  peek() { return this.source[this.index]; }
  fail(message, column = this.index + 1) { throw new PatternError(message, column); }
  take(character) {
    if (this.peek() !== character) return false;
    this.index++;
    return true;
  }

  parse() {
    const root = this.alternation();
    if (this.index < this.source.length) this.fail('unmatched )');
    for (const reference of this.references) {
      if (reference.name !== undefined) {
        if (!this.names.has(reference.name)) this.fail('unknown group name', reference.column);
        reference.group = this.names.get(reference.name);
      } else if (reference.group > this.groups) this.fail('invalid group reference', reference.column);
    }
    return root;
  }

  alternation() {
    const alternatives = [this.concatenation()];
    while (this.take('|')) alternatives.push(this.concatenation());
    return alternatives.length === 1 ? alternatives[0] : {kind: 'alternation', elements: alternatives};
  }

  concatenation() {
    const elements = [];
    while (this.index < this.source.length && this.peek() !== '|' && this.peek() !== ')') elements.push(this.quantified());
    return elements.length === 1 ? elements[0] : {kind: 'concatenation', elements};
  }

  quantified() {
    if (quantifier(this.peek())) this.fail('nothing to repeat');
    const content = this.element();
    if (!quantifier(this.peek())) return content;
    if (content.kind === 'assertion' || content.kind === 'lookahead') this.fail('nothing to repeat');
    let minimum;
    let maximum;
    if (this.take('*')) { minimum = 0; maximum = null; }
    else if (this.take('+')) { minimum = 1; maximum = null; }
    else if (this.take('?')) { minimum = 0; maximum = 1; }
    else ({minimum, maximum} = this.bounds());
    const mode = this.take('?') ? 'lazy' : this.take('+') ? 'possessive' : 'greedy';
    if (quantifier(this.peek())) this.fail('nested quantifier');
    return {kind: 'repetition', content, minimum, maximum, mode};
  }

  bounds() {
    const column = ++this.index;
    const number = () => {
      const start = this.index;
      while (charset.digit(this.source.charCodeAt(this.index))) this.index++;
      if (this.index === start) this.fail('invalid quantifier', column);
      return Number(this.source.slice(start, this.index));
    };
    const minimum = number();
    let maximum = minimum;
    if (this.take(',')) maximum = this.peek() === '}' ? null : number();
    if (!this.take('}')) this.fail('invalid quantifier', column);
    if (minimum > 100 || (maximum !== null && maximum > 100)) this.fail('quantifier too large', column);
    if (maximum !== null && minimum > maximum) this.fail('quantifier range out of order', column);
    return {minimum, maximum};
  }

  element() {
    if (this.peek() === '(') return this.group();
    if (this.peek() === '[') return this.characterClass();
    if (this.peek() === '\\') return this.escape();
    const character = this.source[this.index++];
    if (character === '.') return {kind: 'any'};
    if (character === '^' || character === '$') return {kind: 'assertion', assertion: character === '^' ? 'BOL' : 'EOL'};
    return {kind: 'literal', character: character.charCodeAt(0)};
  }

  name() {
    const start = this.index;
    if (charset.letter(this.source.charCodeAt(this.index)) || this.peek() === '_') {
      this.index++;
      while (charset.word(this.source.charCodeAt(this.index))) this.index++;
    }
    if (this.index === start || this.peek() !== '>') this.fail('invalid group name');
    const name = this.source.slice(start, this.index);
    this.index++;
    return {name, column: start + 1};
  }

  group() {
    const column = ++this.index;
    let kind = 'capture';
    let name = null;
    if (this.take('?')) {
      const character = this.peek();
      if (character === ':') kind = 'noncapture';
      else if (character === '=') kind = 'positive';
      else if (character === '!') kind = 'negative';
      else if (character === '<') kind = 'named';
      else this.fail('invalid group', column);
      this.index++;
    }
    if (kind === 'named') {
      name = this.name();
      if (this.names.has(name.name)) this.fail('duplicate group name', name.column);
    }
    let group = null;
    if (kind === 'capture' || kind === 'named') {
      group = ++this.groups;
      if (name !== null) this.names.set(name.name, group);
    }
    const content = this.alternation();
    if (!this.take(')')) this.fail('missing )', column);
    if (kind === 'noncapture') return content;
    if (kind === 'positive' || kind === 'negative') return {kind: 'lookahead', positive: kind === 'positive', content};
    return {kind: 'group', group, content};
  }

  classItem() {
    const column = this.index + 1;
    const character = this.source[this.index++];
    if (character !== '\\') return {character: character.charCodeAt(0)};
    if (this.index === this.source.length) this.fail('trailing backslash', column);
    const escaped = this.source[this.index++];
    if ('dDwWsS'.includes(escaped)) {
      const {set, negated} = charset.shorthand(escaped);
      return {set: negated ? charset.complement(set) : set};
    }
    if (escaped === 'n' || escaped === 't') return {character: escaped === 'n' ? 10 : 9};
    if (charset.letter(escaped.charCodeAt(0)) || charset.digit(escaped.charCodeAt(0))) this.fail('invalid escape', column);
    return {character: escaped.charCodeAt(0)};
  }

  characterClass() {
    const column = ++this.index;
    const negated = this.take('^');
    if (this.peek() === ']') this.fail('empty class');
    const set = new Set();
    for (;;) {
      if (this.index === this.source.length) this.fail('missing ]', column);
      if (this.take(']')) break;
      const first = this.classItem();
      if (this.peek() === '-' && this.index + 1 < this.source.length && this.source[this.index + 1] !== ']') {
        const dash = ++this.index;
        if (first.set !== undefined) this.fail('invalid range', dash);
        const last = this.classItem();
        if (last.set !== undefined || first.character > last.character) this.fail('invalid range', dash);
        for (let code = first.character; code <= last.character; code++) set.add(code);
      } else if (first.set !== undefined) {
        for (const code of first.set) set.add(code);
      } else set.add(first.character);
    }
    return {kind: 'class', set, negated};
  }

  escape() {
    const column = ++this.index;
    if (this.index === this.source.length) this.fail('trailing backslash', column);
    const character = this.source[this.index++];
    if ('dDwWsS'.includes(character)) return {kind: 'class', ...charset.shorthand(character)};
    if (character === 'b' || character === 'B') return {kind: 'assertion', assertion: character === 'b' ? 'WORD' : 'NOTWORD'};
    if (character === 'n' || character === 't') return {kind: 'literal', character: character === 'n' ? 10 : 9};
    let reference;
    if (character >= '1' && character <= '9') {
      const start = this.index - 1;
      while (charset.digit(this.source.charCodeAt(this.index))) this.index++;
      reference = {kind: 'backreference', group: Number(this.source.slice(start, this.index)), column};
    } else if (character === 'k') {
      if (!this.take('<')) this.fail('invalid escape', column);
      reference = {kind: 'backreference', name: this.name().name, column};
    } else {
      const code = character.charCodeAt(0);
      if (charset.letter(code) || charset.digit(code)) this.fail('invalid escape', column);
      return {kind: 'literal', character: code};
    }
    this.references.push(reference);
    return reference;
  }
}

function compile(root) {
  const program = [];
  const emit = (op, fields = {}) => { program.push({op, ...fields}); return program.length - 1; };
  function split(index, repeat, stop, mode) {
    program[index].x = mode === 'lazy' ? stop : repeat;
    program[index].y = mode === 'lazy' ? repeat : stop;
  }
  function repeat(node) {
    const {content, minimum, maximum, mode} = node;
    if (mode === 'possessive') {
      const look = emit('LOOK', {kind: 'ATOMIC'});
      repeat({...node, mode: 'greedy'});
      emit('MATCH');
      program[look].x = program.length;
    } else if (maximum === null && minimum === 0) {
      const head = emit('SPLIT');
      visit(content);
      emit('JMP', {x: head});
      split(head, head + 1, program.length, mode);
    } else if (maximum === null) {
      for (let index = 0; index < minimum - 1; index++) visit(content);
      const head = program.length;
      visit(content);
      const branch = emit('SPLIT');
      split(branch, head, program.length, mode);
    } else {
      for (let index = 0; index < minimum; index++) visit(content);
      const branches = [];
      for (let index = minimum; index < maximum; index++) {
        const branch = emit('SPLIT');
        branches.push(branch);
        visit(content);
      }
      for (const branch of branches) split(branch, branch + 1, program.length, mode);
    }
  }
  function visit(node) {
    switch (node.kind) {
      case 'literal': emit('CHAR', {character: node.character}); break;
      case 'any': emit('ANY'); break;
      case 'class': emit('CLASS', {set: node.set, negated: node.negated}); break;
      case 'assertion': emit('ASSERT', {assertion: node.assertion}); break;
      case 'backreference': emit('BACKREF', {group: node.group}); break;
      case 'group': emit('SAVE', {group: 2 * node.group}); visit(node.content); emit('SAVE', {group: 2 * node.group + 1}); break;
      case 'lookahead': {
        const look = emit('LOOK', {kind: node.positive ? 'AHEAD' : 'NOT'});
        visit(node.content);
        emit('MATCH');
        program[look].x = program.length;
        break;
      }
      case 'concatenation': for (const element of node.elements) visit(element); break;
      case 'alternation': {
        const jumps = [];
        for (let index = 0; index + 1 < node.elements.length; index++) {
          const branch = emit('SPLIT');
          program[branch].x = program.length;
          visit(node.elements[index]);
          jumps.push(emit('JMP'));
          program[branch].y = program.length;
        }
        visit(node.elements[node.elements.length - 1]);
        for (const jump of jumps) program[jump].x = program.length;
        break;
      }
      case 'repetition': repeat(node); break;
    }
  }
  emit('SAVE', {group: 0});
  visit(root);
  emit('SAVE', {group: 1});
  emit('MATCH');
  return program;
}

function properties(node, flags) {
  if (node.kind === 'assertion' || node.kind === 'lookahead') return {minimum: 0, maximum: 0, first: new Set(), nullable: true};
  if (node.kind === 'group') return properties(node.content, flags);
  if (node.kind === 'literal' || node.kind === 'any' || node.kind === 'class' || node.kind === 'backreference') {
    const first = new Set();
    for (let code = 0; code < 128; code++) {
      let present;
      if (node.kind === 'literal') present = charset.same(code, node.character, flags);
      else if (node.kind === 'any') present = flags.includes('s') || code !== 10;
      else if (node.kind === 'class') present = charset.classMatches(node.set, node.negated, code, flags);
      else present = true;
      if (present) first.add(code);
    }
    const reference = node.kind === 'backreference';
    return {minimum: reference ? 0 : 1, maximum: reference ? null : 1, first, nullable: reference};
  }
  if (node.kind === 'repetition') {
    const content = properties(node.content, flags);
    const maximum = content.maximum === 0 ? 0 : content.maximum === null || node.maximum === null ? null : node.maximum * content.maximum;
    return {minimum: node.minimum * content.minimum, maximum,
      first: node.maximum === 0 ? new Set() : content.first,
      nullable: node.maximum === 0 || node.minimum === 0 || content.nullable};
  }
  const elements = node.elements.map(element => properties(element, flags));
  const first = new Set();
  if (node.kind === 'concatenation') {
    let minimum = 0;
    let maximum = 0;
    let nullable = true;
    for (const element of elements) {
      minimum += element.minimum;
      maximum = maximum === null || element.maximum === null ? null : maximum + element.maximum;
      if (nullable) {
        for (const code of element.first) first.add(code);
        nullable = element.nullable;
      }
    }
    return {minimum, maximum, first, nullable};
  }
  let minimum = elements[0].minimum;
  let maximum = elements[0].maximum;
  let nullable = false;
  for (const element of elements) {
    minimum = Math.min(minimum, element.minimum);
    maximum = maximum === null || element.maximum === null ? null : Math.max(maximum, element.maximum);
    nullable ||= element.nullable;
    for (const code of element.first) first.add(code);
  }
  return {minimum, maximum, first, nullable};
}

function readLines(file) { return fs.readFileSync('input/' + file, 'ascii').split('\n').slice(0, -1); }

function decodeQuoted(source) {
  let result = '';
  const escapes = {n: '\n', t: '\t', '\\': '\\', '"': '"'};
  for (let index = 1; index + 1 < source.length; index++) {
    if (source[index] === '\\') result += escapes[source[++index]];
    else result += source[index];
  }
  return result;
}

function readPatterns() {
  const patterns = new Map();
  for (const line of readLines('patterns.txt')) {
    const first = line.indexOf(' ');
    const second = line.indexOf(' ', first + 1);
    const pattern = {name: line.slice(0, first), flags: line.slice(first + 1, second), source: line.slice(second + 1), error: null};
    const parser = new PatternParser(pattern.source);
    try {
      const root = parser.parse();
      pattern.groups = parser.groups;
      pattern.names = parser.names;
      pattern.program = compile(root);
      pattern.properties = properties(root, pattern.flags);
      pattern.pike = pattern.program.every(instruction => instruction.op !== 'BACKREF' && instruction.op !== 'LOOK');
    } catch (error) {
      if (!(error instanceof PatternError)) throw error;
      pattern.error = {message: error.message, column: error.column};
    }
    patterns.set(pattern.name, pattern);
  }
  return patterns;
}

function templateParts(template, pattern) {
  const parts = [];
  let literal = '';
  let index = 0;
  while (index < template.length) {
    if (template[index] !== '$') { literal += template[index++]; continue; }
    if (template[index + 1] === '$') { literal += '$'; index += 2; continue; }
    if (literal !== '') { parts.push(literal); literal = ''; }
    let group;
    if (charset.digit(template.charCodeAt(index + 1))) {
      group = Number(template[index + 1]);
      index += 2;
    } else if (template[index + 1] === '{') {
      const end = template.indexOf('}', index + 2);
      if (end === -1) return null;
      const name = template.slice(index + 2, end);
      let numeric = name.length > 0;
      for (let at = 0; at < name.length; at++) if (!charset.digit(name.charCodeAt(at))) numeric = false;
      if (numeric) group = Number(name);
      else if (pattern.names.has(name)) group = pattern.names.get(name);
      else return null;
      index = end + 1;
    } else return null;
    if (group > pattern.groups) return null;
    parts.push(group);
  }
  if (literal !== '') parts.push(literal);
  return parts;
}

function setGroup(captures, group) { return captures[2 * group] !== null && captures[2 * group + 1] !== null; }
function captured(text, captures, group) { return text.slice(captures[2 * group], captures[2 * group + 1]); }

function expand(parts, text, captures) {
  return parts.map(part => typeof part === 'string' ? part : setGroup(captures, part) ? captured(text, captures, part) : '').join('');
}

function sequence(vm, command, text) {
  if (command.kind === 'MATCH' || command.kind === 'SEARCH' || (command.kind === 'REPLACE' && command.mode === 'FIRST')) {
    const match = vm.search(0, command.kind === 'MATCH');
    return match === null ? [] : [match];
  }
  const matches = [];
  let start = 0;
  while (start <= text.length) {
    const match = vm.search(start, false);
    if (match === null) break;
    matches.push(match);
    start = match[1] > match[0] ? match[1] : match[1] + 1;
  }
  return matches;
}

function runEngines(pattern, text, command) {
  const backtrack = new BacktrackVM(pattern, text);
  let first = null;
  let aborted = false;
  try { first = sequence(backtrack, command, text); }
  catch (error) {
    if (!(error instanceof TooManySteps)) throw error;
    aborted = true;
  }
  const steps = [['backtrack', backtrack.steps]];
  if (!pattern.pike) return {steps, matches: first, label: 'backtrack', failure: aborted ? 'TOO_MANY_STEPS' : null};
  const pike = new PikeVM(pattern, text);
  const second = sequence(pike, command, text);
  steps.push(['pike', pike.steps]);
  if (aborted) return {steps, matches: second, label: 'pike (backtrack: TOO_MANY_STEPS)', failure: null};
  const equal = first.length === second.length && first.every((match, index) =>
    match.length === second[index].length && match.every((value, group) => value === second[index][group]));
  return {steps, matches: first, label: 'both', failure: equal ? null : 'MISMATCH'};
}

function appendMatch(lines, pattern, text, captures) {
  for (let group = 0; group <= pattern.groups; group++) {
    const label = group === 0 ? 'match' : 'group ' + group;
    const span = setGroup(captures, group) ? `${captures[2 * group]}-${captures[2 * group + 1]} ${formatter.quote(captured(text, captures, group))}` : '-';
    lines.push(label + ' ' + span);
  }
}

function appendResult(lines, pattern, text, command, result) {
  if (result.failure !== null) { lines.push(result.failure); return; }
  lines.push('engine ' + result.label);
  const matches = result.matches;
  if (command.kind === 'MATCH' || command.kind === 'SEARCH') {
    if (matches.length === 0) lines.push('no match');
    else appendMatch(lines, pattern, text, matches[0]);
  } else if (command.kind === 'FINDALL') {
    lines.push('matches ' + matches.length);
    for (const match of matches) appendMatch(lines, pattern, text, match);
  } else if (command.kind === 'REPLACE') {
    const pieces = [];
    let previous = 0;
    for (const match of matches) {
      pieces.push(text.slice(previous, match[0]), expand(command.template, text, match));
      previous = match[1];
    }
    pieces.push(text.slice(previous));
    lines.push('replacements ' + matches.length, 'result ' + formatter.quote(pieces.join('')));
  } else {
    lines.push('pieces ' + (matches.length + 1));
    lines.push('piece ' + formatter.quote(text.slice(0, matches.length === 0 ? text.length : matches[0][0])));
    for (let index = 0; index < matches.length; index++) {
      const match = matches[index];
      for (let group = 1; group <= pattern.groups; group++) {
        lines.push(`group ${group} ` + (setGroup(match, group) ? formatter.quote(captured(text, match, group)) : '-'));
      }
      const end = index + 1 < matches.length ? matches[index + 1][0] : text.length;
      lines.push('piece ' + formatter.quote(text.slice(match[1], end)));
    }
  }
}

function appendProgram(lines, pattern) {
  const properties_ = pattern.properties;
  const names = [...pattern.names].map(([name, group]) => `${name}:${group}`).join(',') || '-';
  const first = properties_.first.size === 0 ? '-' : formatter.setNotation(properties_.first);
  const maximum = properties_.maximum === null ? 'inf' : properties_.maximum;
  lines.push('=== ' + pattern.name);
  lines.push(`flags=${pattern.flags} groups=${pattern.groups} names=${names} length=${properties_.minimum}..${maximum} ` +
    `first=${first} pike=${pattern.pike ? 'yes' : 'no'} size=${pattern.program.length}`);
  pattern.program.forEach((instruction, index) => lines.push(index + ' ' + formatter.instruction(instruction)));
}

function main() {
  const patterns = readPatterns();
  const subjects = new Map(readLines('subjects.txt').map(line => {
    const space = line.indexOf(' ');
    return [line.slice(0, space), decodeQuoted(line.slice(space + 1))];
  }));
  const outputs = {'results.txt': [], 'programs.txt': [], 'steps.csv': ['command,engine,steps'], 'errors.txt': []};
  for (const pattern of patterns.values()) {
    if (pattern.error === null) continue;
    outputs['errors.txt'].push(`${pattern.name}: ${pattern.error.message} at column ${pattern.error.column}`,
      '  ' + pattern.source, ' '.repeat(pattern.error.column + 1) + '^');
  }
  const commands = readLines('commands.txt');
  for (let index = 0; index < commands.length; index++) {
    const line = commands[index];
    const words = line.split(' ');
    const command = {kind: words[0], mode: words[0] === 'REPLACE' ? words[1] : null};
    const pattern = patterns.get(words[command.kind === 'REPLACE' ? 2 : 1]);
    outputs['results.txt'].push(`#${index + 1} ${line}`);
    if (pattern.error !== null) { outputs['results.txt'].push('invalid pattern'); continue; }
    if (command.kind === 'LIST') {
      outputs['results.txt'].push('instructions ' + pattern.program.length);
      appendProgram(outputs['programs.txt'], pattern);
      continue;
    }
    const text = subjects.get(words[command.kind === 'REPLACE' ? 3 : 2]);
    if (command.kind === 'REPLACE') {
      let space = -1;
      for (let count = 0; count < 4; count++) space = line.indexOf(' ', space + 1);
      command.template = templateParts(decodeQuoted(line.slice(space + 1)), pattern);
      if (command.template === null) { outputs['results.txt'].push('invalid template'); continue; }
    }
    const result = runEngines(pattern, text, command);
    for (const [engine, steps] of result.steps) outputs['steps.csv'].push(`${index + 1},${engine},${steps}`);
    appendResult(outputs['results.txt'], pattern, text, command, result);
  }
  if (outputs['programs.txt'].length === 0) outputs['programs.txt'].push('no programs');
  if (outputs['errors.txt'].length === 0) outputs['errors.txt'].push('no errors');
  fs.mkdirSync('output', {recursive: true});
  for (const [file, lines] of Object.entries(outputs)) fs.writeFileSync('output/' + file, lines.join('\n') + '\n', 'ascii');
}

main();
