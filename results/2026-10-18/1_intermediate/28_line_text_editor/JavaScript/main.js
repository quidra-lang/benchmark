'use strict';

const fs = require('node:fs');

class EditorError extends Error {}
function fail(reason) { throw new EditorError(reason); }
const isDigit = ch => ch !== undefined && ch >= '0' && ch <= '9';

function delimited(source, start, delimiter) {
  let text = '';
  const replacement = [];
  for (let i = start; i < source.length; i++) {
    let ch = source[i];
    if (ch === '\\') {
      if (++i === source.length) fail('missing delimiter');
      ch = source[i];
      text += ch;
      replacement.push(ch);
    } else if (ch === delimiter) {
      return { text, replacement, raw: source.slice(start, i), next: i + 1 };
    } else {
      text += ch;
      replacement.push(ch === '&' ? null : ch);
    }
  }
  fail('missing delimiter');
}

function scanAddress(source) {
  const elements = [];
  let i = 0;
  while (i < source.length) {
    const ch = source[i];
    if (isDigit(ch) || ch === '+' || ch === '-') {
      const start = i++;
      while (isDigit(source[i])) i++;
      const word = source.slice(start, i);
      elements.push({ kind: isDigit(ch) ? 'number' : 'offset', word });
    } else if ('.$,;%'.includes(ch)) {
      elements.push({ kind: ch });
      i++;
    } else if (ch === "'") {
      elements.push({ kind: 'mark', word: source[i + 1] ?? '' });
      i += Math.min(2, source.length - i);
    } else if (ch === '/' || ch === '?') {
      const found = delimited(source, i + 1, ch);
      elements.push({ kind: ch, word: found.text });
      i = found.next;
    } else break;
  }
  return { elements, command: source.slice(i) };
}

function singleAddress(elements) {
  const bases = new Set(['number', '.', '$', 'mark', '/', '?']);
  return elements.length > 0 && elements.every((item, i) =>
    item.kind === 'offset' || i === 0 && bases.has(item.kind));
}

function addressForm(elements) {
  if (elements.length === 0) return { count: 0 };
  if (elements.length === 1 && elements[0].kind === '%') {
    return { count: 2, left: [{ kind: 'number', word: '1' }], separator: ',', right: [{ kind: '$' }] };
  }
  const separators = elements.flatMap((item, i) => ',;'.includes(item.kind) ? [i] : []);
  if (separators.length > 1) fail('bad address');
  if (separators.length === 0) {
    if (!singleAddress(elements)) fail('bad address');
    return { count: 1, left: elements };
  }
  const index = separators[0];
  const left = elements.slice(0, index), right = elements.slice(index + 1);
  if (left.length && !singleAddress(left) || right.length && !singleAddress(right)) fail('bad address');
  return { count: 2, left, right, separator: elements[index].kind };
}

function positiveArgument(argument) {
  if (argument === '') return null;
  if (!/^\d+$/.test(argument) || Number(argument) === 0) fail('invalid suffix');
  return Number(argument);
}

function printSuffix(argument) {
  if (!/^[pnl]?$/.test(argument)) fail('invalid suffix');
  return argument;
}

function fileName(argument) {
  if (!/^ [a-z0-9]{1,8}$/.test(argument)) fail('invalid file name');
  return argument.slice(1);
}

function parseSubstitution(argument) {
  let pattern = '', replacement = null, flags = argument;
  if (!/^[gpnl0-9]*$/.test(argument)) {
    const delimiter = argument[0];
    if (delimiter === ' ' || delimiter === '\\') fail('missing delimiter');
    const search = delimited(argument, 1, delimiter);
    const replace = delimited(argument, search.next, delimiter);
    pattern = search.text;
    replacement = replace.raw === '%' ? null : replace.replacement;
    flags = argument.slice(replace.next);
  }
  let global = false, suffix = '', count = 1, counted = false;
  for (let i = 0; i < flags.length;) {
    const ch = flags[i++];
    if (ch === 'g') {
      if (global) fail('invalid suffix');
      global = true;
    } else if ('pnl'.includes(ch)) {
      if (suffix !== '') fail('invalid suffix');
      suffix = ch;
    } else if (isDigit(ch)) {
      if (counted) fail('invalid suffix');
      const start = i - 1;
      while (isDigit(flags[i])) i++;
      count = Number(flags.slice(start, i));
      if (count === 0) fail('invalid suffix');
      counted = true;
    } else fail('invalid suffix');
  }
  return { kind: 's', pattern, replacement, global, suffix, count };
}

function parseCommand(source) {
  if (source === 'sort' || source.startsWith('sort ')) {
    const options = source === 'sort' ? '' : source.slice(5);
    if (source !== 'sort' && (!/^[ruin]+$/.test(options) || new Set(options).size !== options.length
        || options.includes('i') && options.includes('n'))) fail('invalid suffix');
    return { kind: 'sort', options };
  }
  const kind = source[0] ?? '', argument = source.slice(1);
  if (kind === '' || 'aicpnl=#yKhf'.includes(kind)) {
    if (argument !== '') fail('invalid suffix');
    return { kind };
  }
  if ('dxjJ'.includes(kind)) return { kind, suffix: printSuffix(argument) };
  if ('z><u'.includes(kind)) return { kind, amount: positiveArgument(argument) };
  if (kind === '~') {
    if (!/^[ul]?$/.test(argument)) fail('invalid suffix');
    return { kind, letterCase: argument };
  }
  if (kind === 'r') {
    return /^\d*$/.test(argument)
      ? { kind: 'redo', amount: positiveArgument(argument) }
      : { kind: 'read', name: fileName(argument) };
  }
  if (kind === 'w') return argument === '' ? { kind } : { kind: 'write', name: fileName(argument) };
  if (kind === 'W' || kind === 'e') return { kind, name: fileName(argument) };
  if (kind === 'k') {
    if (!/^[a-z]$/.test(argument)) fail('invalid mark');
    return { kind, mark: argument };
  }
  if (kind === 'm' || kind === 't') {
    const destination = scanAddress(argument);
    if (!singleAddress(destination.elements)) fail('invalid destination');
    return { kind, destination: destination.elements, suffix: printSuffix(destination.command) };
  }
  if (kind === 's') return parseSubstitution(argument);
  if (kind === 'g' || kind === 'v') {
    if (argument === '' || argument[0] === ' ' || argument[0] === '\\') fail('missing delimiter');
    const search = delimited(argument, 1, argument[0]);
    const subcommand = argument.slice(search.next) || 'p';
    if (!'pnldmtjJs><~aicx'.includes(subcommand[0]) || subcommand === 'sort' || subcommand.startsWith('sort ')) {
      fail('invalid global command');
    }
    return { kind, pattern: search.text, subcommand: parseCommand(subcommand) };
  }
  fail('unknown command');
}

function hasText(source) {
  try {
    const command = scanAddress(source).command;
    if (/^[aic]$/.test(command)) return true;
    if (!/^[gv]/.test(command) || command.length < 2 || command[1] === ' ' || command[1] === '\\') return false;
    const search = delimited(command, 2, command[1]);
    return /^[aic]$/.test(command.slice(search.next));
  } catch (error) {
    if (!(error instanceof EditorError)) throw error;
    return false;
  }
}

function addressKind(command) {
  if (['u', 'redo', 'h', 'K', 'f', 'e'].includes(command.kind)) return 0;
  if (['a', 'i', 'x', '=', 'read', 'k', 'z'].includes(command.kind)) return 1;
  return 2;
}

function modifying(command) {
  if (command.kind === 'g' || command.kind === 'v') return !['p', 'n', 'l'].includes(command.subcommand.kind);
  return ['a', 'i', 'c', 'd', 'x', 'j', 'J', 'm', 't', 's', '>', '<', '~', 'sort', 'read', 'e'].includes(command.kind);
}

function copyState(state) {
  // Line objects, history records, replacements and file contents are immutable.
  return { ...state, lines: state.lines.slice(), marks: new Map(state.marks), cut: state.cut.slice(),
    undo: state.undo.slice(), redo: state.redo.slice(), files: new Map(state.files) };
}

class Editor {
  constructor() {
    this.state = { lines: [], current: 0, marks: new Map(), cut: [], pattern: null, replacement: null,
      displayCount: 5, undo: [], redo: [], files: new Map(), nextId: 1 };
    this.output = [];
  }

  newLines(text) { return text.map(value => ({ id: this.state.nextId++, text: value })); }
  replace(position, count, inserted) {
    const lines = this.state.lines;
    this.state.lines = lines.slice(0, position).concat(inserted, lines.slice(position + count));
  }
  snapshot(command) { return { command, lines: this.state.lines.slice(), current: this.state.current }; }
  contents(a, b) { return this.state.lines.slice(a - 1, b).map(line => line.text); }
  emit(text) { this.output.push(text); }

  pattern(text) {
    if (text !== '') this.state.pattern = text;
    if (this.state.pattern === null) fail('no previous pattern');
    return this.state.pattern;
  }

  address(elements) {
    const state = this.state, last = state.lines.length;
    let value = state.current, firstOffset = 0;
    const base = elements[0];
    if (base.kind !== 'offset') {
      firstOffset = 1;
      if (base.kind === 'number') value = Number(base.word);
      else if (base.kind === '.') value = state.current;
      else if (base.kind === '$') value = last;
      else if (base.kind === 'mark') {
        if (!/^[a-z]$/.test(base.word)) fail('invalid mark');
        value = state.lines.findIndex(line => line.id === state.marks.get(base.word)) + 1;
        if (value === 0) fail('mark not set');
      } else {
        const pattern = this.pattern(base.word);
        value = 0;
        for (let step = 1; step <= last; step++) {
          const pivot = state.current === 0 && base.kind === '?' ? last + 1 : state.current;
          const index = base.kind === '/' ? (pivot + step - 1) % last : (pivot - step - 1 + last) % last;
          if (state.lines[index].text.includes(pattern)) { value = index + 1; break; }
        }
        if (value === 0) fail('no match');
      }
    }
    for (const offset of elements.slice(firstOffset)) {
      const magnitude = offset.word.length === 1 ? 1 : Number(offset.word.slice(1));
      value += offset.word[0] === '+' ? magnitude : -magnitude;
    }
    return value;
  }

  addresses(form) {
    if (form.count === 0) return [];
    if (form.count === 1) return [this.address(form.left)];
    const left = form.left.length ? this.address(form.left) : form.separator === ',' ? 1 : this.state.current;
    if (form.separator === ';') {
      if (left < 0 || left > this.state.lines.length) fail('address out of range');
      this.state.current = left;
    }
    return [left, form.right.length ? this.address(form.right) : this.state.lines.length];
  }

  range(command, values) {
    const state = this.state, last = state.lines.length, kind = command.kind;
    const category = addressKind(command);
    if (category === 0) return [0, 0];
    if (category === 1) {
      const fallback = ['=', 'read'].includes(kind) ? last : state.current + (kind === 'z' ? 1 : 0);
      const a = values.length ? values[0] : fallback;
      const minimum = kind === 'k' || kind === 'z' ? 1 : 0;
      if (a < minimum || a > last) fail('address out of range');
      return [a, a];
    }
    let a, b;
    if (values.length) [a, b] = [values[0], values.at(-1)];
    else if (['w', 'write', 'W', '#'].includes(kind)) return [1, last];
    else if (['g', 'v', 'sort'].includes(kind)) [a, b] = [1, last];
    else [a, b] = [state.current, state.current + (kind === 'j' || kind === 'J' ? 1 : 0)];
    if (a < 1 || b < 1 || a > last || b > last) fail('address out of range');
    if (a > b || a === b && (kind === 'j' || kind === 'J')) fail('invalid range');
    return [a, b];
  }

  print(number, form) {
    const text = this.state.lines[number - 1].text;
    if (form === 'p') this.emit(text);
    else if (form === 'n') this.emit(`${String(number).padStart(3, ' ')} ${text}`);
    else {
      let escaped = text.replaceAll('\\', '\\\\') + '$';
      while (escaped.length > 40) {
        this.emit(escaped.slice(0, 39) + '\\');
        escaped = escaped.slice(39);
      }
      this.emit(escaped);
    }
  }

  suffix(command) {
    if (command.suffix && this.state.current > 0) this.print(this.state.current, command.suffix);
  }

  substitute(command, a, b, insideGlobal) {
    const state = this.state, pattern = this.pattern(command.pattern);
    const replacement = command.replacement ?? state.replacement;
    if (replacement === null) fail('no previous substitution');
    state.replacement = replacement;
    const expanded = replacement.map(part => part === null ? pattern : part).join('');
    let changed = 0;
    for (let i = a - 1; i < b; i++) {
      const line = state.lines[i];
      let position = 0, occurrence = 0, result = '', substituted = false;
      for (;;) {
        const found = line.text.indexOf(pattern, position);
        if (found < 0) break;
        occurrence++;
        const replace = occurrence === command.count || command.global && occurrence > command.count;
        result += line.text.slice(position, found) + (replace ? expanded : pattern);
        substituted ||= replace;
        position = found + pattern.length;
      }
      if (!substituted) continue;
      result += line.text.slice(position);
      if (result.length > 80) fail('line too long');
      if (result === '' || result.endsWith(' ')) fail('bad line');
      state.lines[i] = { id: line.id, text: result };
      state.current = i + 1;
      changed++;
    }
    if (changed === 0 && !insideGlobal) fail('no match');
    if (changed > 0) this.suffix(command);
    return changed;
  }

  global(command, a, b, text) {
    const state = this.state, pattern = this.pattern(command.pattern);
    const selected = state.lines.slice(a - 1, b)
      .filter(line => line.text.includes(pattern) === (command.kind === 'g')).map(line => line.id);
    if (selected.length === 0) fail('no match');
    let changed = 0;
    for (const id of selected) {
      const index = state.lines.findIndex(line => line.id === id);
      if (index < 0) continue;
      state.current = index + 1;
      const [start, end] = this.range(command.subcommand, []);
      changed += this.execute(command.subcommand, start, end, text, true);
    }
    if (command.subcommand.kind === 's' && changed === 0) fail('no match');
  }

  execute(command, a, b, text, insideGlobal = false) {
    const state = this.state, kind = command.kind;
    if (kind === 's') return this.substitute(command, a, b, insideGlobal);
    if (kind === 'g' || kind === 'v') this.global(command, a, b, text);
    else if (kind === '' || ['p', 'n', 'l'].includes(kind)) {
      for (let i = kind === '' ? b : a; i <= b; i++) this.print(i, kind || 'p');
      state.current = b;
    } else if (kind === 'z') {
      if (command.amount !== null) state.displayCount = command.amount;
      const end = Math.min(a + state.displayCount - 1, state.lines.length);
      for (let i = a; i <= end; i++) this.print(i, 'p');
      state.current = end;
    } else if (kind === '=') this.emit(String(a));
    else if (kind === '#') {
      const contents = this.contents(a, b);
      const words = contents.reduce((n, line) => n + line.split(' ').filter(Boolean).length, 0);
      const chars = contents.reduce((n, line) => n + line.length, 0);
      this.emit(`count lines=${contents.length} words=${words} chars=${chars}`);
    } else if (kind === 'w') {
      const contents = this.contents(a, b);
      for (const line of contents) this.emit(line);
      this.emit(`lines=${contents.length} bytes=${contents.reduce((n, line) => n + line.length + 1, 0)}`);
    } else if (kind === 'a' || kind === 'i') {
      const position = kind === 'a' ? a : Math.max(a, 1) - 1;
      this.replace(position, 0, this.newLines(text));
      state.current = position + text.length;
    } else if (kind === 'c' || kind === 'd') {
      state.cut = this.contents(a, b);
      const inserted = kind === 'c' ? this.newLines(text) : [];
      this.replace(a - 1, b - a + 1, inserted);
      state.current = inserted.length ? a + inserted.length - 1 : Math.min(a, state.lines.length);
      this.suffix(command);
    } else if (kind === 'y') state.cut = this.contents(a, b);
    else if (kind === 'x') {
      if (state.cut.length === 0) fail('nothing to put');
      this.replace(a, 0, this.newLines(state.cut));
      state.current = a + state.cut.length;
      this.suffix(command);
    } else if (kind === 'm' || kind === 't') {
      const destination = this.address(command.destination), count = b - a + 1;
      if (destination < 0 || destination > state.lines.length) fail('address out of range');
      if (kind === 'm') {
        if (a <= destination && destination < b) fail('invalid destination');
        const moved = state.lines.splice(a - 1, count);
        const position = destination < a ? destination : destination - count;
        this.replace(position, 0, moved);
        state.current = position + count;
      } else {
        const copied = this.newLines(this.contents(a, b));
        this.replace(destination, 0, copied);
        state.current = destination + count;
      }
      this.suffix(command);
    } else if (kind === 'j' || kind === 'J') {
      const contents = this.contents(a, b);
      const joined = kind === 'j' ? contents.join('') : contents.map((line, i) => i ? line.replace(/^ +/, '') : line).join(' ');
      if (joined.length > 80) fail('line too long');
      state.lines.splice(a - 1, b - a + 1, { id: state.lines[a - 1].id, text: joined });
      state.current = a;
      this.suffix(command);
    } else if (kind === '>' || kind === '<' || kind === '~') {
      const width = command.amount ?? 4;
      for (let i = a - 1; i < b; i++) {
        const line = state.lines[i];
        let value = line.text;
        if (kind === '>') {
          if (value.length + width > 80) fail('line too long');
          value = ' '.repeat(width) + value;
        } else if (kind === '<') value = value.slice(Math.min(width, /^ */.exec(value)[0].length));
        else value = value.replace(/[A-Za-z]/g, ch => command.letterCase === 'u' ? ch.toUpperCase()
          : command.letterCase === 'l' ? ch.toLowerCase() : ch === ch.toUpperCase() ? ch.toLowerCase() : ch.toUpperCase());
        state.lines[i] = { id: line.id, text: value };
      }
      state.current = b;
    } else if (kind === 'sort') {
      const options = command.options;
      const key = line => options.includes('n') ? Number(/^-?\d+/.exec(line.text)?.[0] ?? 0)
        : options.includes('i') ? line.text.toLowerCase() : line.text;
      const direction = options.includes('r') ? -1 : 1;
      let sorted = state.lines.slice(a - 1, b).map(line => ({ line, key: key(line) }));
      sorted.sort((x, y) => direction * (x.key < y.key ? -1 : x.key > y.key ? 1 : 0));
      if (options.includes('u')) sorted = sorted.filter((item, i, all) => i === 0 || item.key !== all[i - 1].key);
      this.replace(a - 1, b - a + 1, sorted.map(item => item.line));
      state.current = a + sorted.length - 1;
    } else if (kind === 'k') state.marks.set(command.mark, state.lines[a - 1].id);
    else if (kind === 'K') {
      const marks = [...state.marks].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).flatMap(([name, id]) => {
        const index = state.lines.findIndex(line => line.id === id);
        return index < 0 ? [] : [`${name}=${index + 1}`];
      });
      this.emit('marks ' + (marks.join(' ') || 'none'));
    } else if (kind === 'u' || kind === 'redo') {
      const source = kind === 'u' ? state.undo : state.redo;
      const target = kind === 'u' ? state.redo : state.undo;
      const count = command.amount ?? 1;
      if (source.length < count) fail(kind === 'u' ? 'nothing to undo' : 'nothing to redo');
      for (let i = 0; i < count; i++) {
        const record = source.pop();
        target.push(this.snapshot(record.command));
        state.lines = record.lines.slice();
        state.current = record.current;
      }
    } else if (kind === 'h') {
      this.emit(`history undo=${state.undo.length} redo=${state.redo.length}`);
      for (const [name, history] of [['undo', state.undo], ['redo', state.redo]]) {
        for (let i = history.length - 1; i >= 0; i--) this.emit(`${name} ${history.length - i}: ${history[i].command}`);
      }
    } else if (['write', 'W', 'read', 'e'].includes(kind)) {
      let file = state.files.get(command.name);
      if (kind === 'write' || kind === 'W') {
        file = (kind === 'W' ? file ?? [] : []).concat(this.contents(a, b));
        state.files.set(command.name, file);
      } else {
        if (file === undefined) fail('no such file');
        const inserted = this.newLines(file);
        if (kind === 'e') { state.lines = inserted; state.current = inserted.length; }
        else { this.replace(a, 0, inserted); state.current = a + inserted.length; }
      }
      this.emit(`file ${command.name} lines=${file.length} bytes=${file.reduce((n, line) => n + line.length + 1, 0)}`);
    } else if (kind === 'f') {
      const files = [...state.files.keys()].sort().map(name => `${name}=${state.files.get(name).length}`);
      this.emit('files ' + (files.join(' ') || 'none'));
    }
    return 0;
  }

  process(source, text) {
    const previous = this.state;
    const before = this.snapshot(source);
    this.state = copyState(previous);
    this.output = [];
    try {
      const split = scanAddress(source);
      const form = addressForm(split.elements);
      const command = parseCommand(split.command);
      const category = addressKind(command);
      if (category === 0 && form.count > 0) fail('unexpected address');
      if (category === 1 && form.count > 1) fail('too many addresses');
      const [a, b] = this.range(command, this.addresses(form));
      this.execute(command, a, b, text);
      if (this.state.lines.length > 200) fail('buffer full');
      if (modifying(command)) {
        this.state.undo.push(before);
        this.state.redo = [];
      }
      return this.output;
    } catch (error) {
      this.state = previous;
      if (!(error instanceof EditorError)) throw error;
      return ['? ' + error.message];
    }
  }
}

const input = fs.readFileSync(0, 'utf8').split('\n');
const editor = new Editor(), output = [];
for (let i = 0; input[i] !== 'Q'; i++) {
  const command = input[i], text = [];
  if (hasText(command)) {
    while (input[++i] !== '.') text.push(input[i]);
  }
  output.push(...editor.process(command, text));
}
if (output.length) process.stdout.write(output.join('\n') + '\n');
