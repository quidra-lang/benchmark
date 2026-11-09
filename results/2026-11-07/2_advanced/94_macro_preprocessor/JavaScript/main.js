'use strict';

const fs = require('node:fs');
const {punct, copy, readBasic, lexDefinition, render} = require('./lexer');
const {builtins, checkName, parseDefinition, identical} = require('./definitions');
const {expressionValue} = require('./expression');
const {Expander} = require('./expander');
const {IncludeManager} = require('./include_manager');

const starts = new Set(['if', 'ifdef', 'ifndef']);
const conditionals = new Set([...starts, 'elif', 'elifdef', 'elifndef', 'else', 'endif']);
const resultKinds = [['taken', 'taken'], ['not taken', 'not_taken'], ['skipped', 'skipped'],
  ['not evaluated', 'not_evaluated'], ['closes', 'endif']];

class Preprocessor {
  constructor() {
    this.table = new Map();
    this.everDefined = new Set();
    this.poisoned = new Set();
    this.saved = new Map();
    this.history = [];
    this.diagnostics = [];
    this.diagnosticCounts = {error: 0, warning: 0};
    this.output = [];
    this.previous = null;
    this.tree = [];
    this.records = [];
    this.regions = [];
    this.recordCounts = {taken: 0, not_taken: 0, skipped: 0, not_evaluated: 0, endif: 0};
    this.includes = new IncludeManager();
    this.expander = new Expander(this.table, (position, kind, message) => this.diagnostic(position, kind, message));
  }

  position(context, physicalLine) {
    return {file: context.displayName, line: physicalLine + context.offset};
  }

  diagnostic(position, kind, message) {
    this.diagnostics.push(`${position.file}:${position.line}: ${kind}: ${message}`);
    this.diagnosticCounts[kind]++;
  }

  recordHistory(position, content) {
    this.history.push(`${position.file}:${position.line}: ${content}`);
  }

  unused(macro) {
    if (macro.mainFile && macro.expanded === 0 && macro.tested === 0) {
      this.diagnostic(macro.position, 'warning', `macro "${macro.name}" is not used`);
    }
  }

  define(operands, position, mainFile) {
    const macro = parseDefinition(operands, position, mainFile);
    const old = this.table.get(macro.name);
    if (old && identical(old, macro)) {
      this.recordHistory(position, `identical ${macro.signature()}`);
      return;
    }
    if (old) {
      this.unused(old);
      this.diagnostic(position, 'warning', `"${macro.name}" redefined (previous definition at ${old.position.file}:${old.position.line})`);
    }
    this.table.set(macro.name, macro);
    this.everDefined.add(macro.name);
    this.recordHistory(position, `${old ? 'redefine' : 'define'} ${macro.signature()}`);
  }

  undefine(operands, position) {
    const name = checkName(operands, 'undef');
    if (operands.length > 1) this.diagnostic(position, 'warning', 'extra tokens at end of #undef directive');
    const old = this.table.get(name);
    if (old) {
      this.unused(old);
      this.table.delete(name);
    }
    this.recordHistory(position, `undef ${name}${old ? '' : ' (not defined)'}`);
  }

  defined(name) {
    const macro = this.table.get(name);
    if (macro) {
      macro.tested++;
      return true;
    }
    return builtins.has(name) || name === '__has_include';
  }

  poison(tokens, context) {
    for (const token of tokens) {
      if (token.kind === 'identifier' && this.poisoned.has(token.spelling)) {
        this.diagnostic(this.position(context, token.line), 'error', `attempt to use poisoned "${token.spelling}"`);
      }
    }
  }

  separator(left, right) {
    return left === '/' && (right[0] === '/' || right[0] === '*')
      || readBasic(left + right).length !== left.length;
  }

  outputRendering(tokens) {
    let text = '';
    for (let index = 0; index < tokens.length; index++) {
      const token = tokens[index];
      if (index && (token.space || this.separator(tokens[index - 1].spelling, token.spelling))) text += ' ';
      text += token.spelling;
    }
    return text;
  }

  marker(file, line, flag = '') {
    this.output.push(`# ${line} "${file}"${flag ? ` ${flag}` : ''}`);
    this.previous = {file, line: line - 1};
  }

  outputLine(context, physicalLine, text) {
    const position = this.position(context, physicalLine);
    if (this.previous.file === position.file && this.previous.line < position.line
        && position.line <= this.previous.line + 8) {
      for (let line = this.previous.line + 1; line < position.line; line++) this.output.push('');
    } else this.marker(position.file, position.line);
    this.output.push(text);
    this.previous = position;
    context.file.outputLines++;
  }

  flush(context) {
    this.poison(context.segment, context);
    const tokens = this.expander.expand(context.segment, context);
    context.segment = [];
    for (let start = 0; start < tokens.length;) {
      let end = start + 1;
      while (end < tokens.length && tokens[end].line === tokens[start].line) end++;
      this.outputLine(context, tokens[start].line, this.outputRendering(tokens.slice(start, end)));
      start = end;
    }
  }

  header(tokens, index = 0) {
    const token = tokens[index];
    let rendering;
    let end;
    if (token?.kind === 'string' || token?.kind === 'header') {
      rendering = token.spelling;
      end = index + 1;
    } else if (punct(token, '<')) {
      end = index + 1;
      while (end < tokens.length && !punct(tokens[end], '>')) end++;
      if (end === tokens.length) throw new Error('missing terminating > character');
      rendering = '<' + render(tokens.slice(index + 1, end)) + '>';
      end++;
    } else return null;
    return {rendering, end, name: rendering.slice(1, -1), quoted: rendering[0] === '"'};
  }

  replaceOperators(operands) {
    const result = [];
    for (let index = 0; index < operands.length; index++) {
      const token = operands[index];
      if (token.kind !== 'identifier' || !['defined', '__has_include'].includes(token.spelling)) {
        result.push(copy(token));
        continue;
      }
      let value;
      if (token.spelling === 'defined') {
        index++;
        const parenthesized = punct(operands[index], '(');
        if (parenthesized) index++;
        if (operands[index]?.kind !== 'identifier') throw new Error('operator "defined" requires an identifier');
        const name = operands[index].spelling;
        if (parenthesized && !punct(operands[++index], ')')) throw new Error('missing \')\' after "defined"');
        value = this.defined(name);
      } else {
        if (!punct(operands[++index], '(')) throw new Error('missing \'(\' after "__has_include"');
        const header = this.header(operands, index + 1);
        if (!header || !header.name) throw new Error('operator "__has_include" requires a header-name');
        index = header.end;
        if (!punct(operands[index], ')')) throw new Error('missing \')\' after "__has_include" operand');
        value = this.includes.search(header.name, header.quoted) !== null;
      }
      result.push({kind: 'number', spelling: value ? '1' : '0', line: token.line,
        space: token.space, hide: new Set()});
    }
    return result;
  }

  testCondition(context, logical) {
    const operands = logical.tokens.slice(2);
    const position = this.position(context, logical.tokens[0].line);
    this.poison(operands, context);
    let value = null;
    let expanded = null;
    const expression = logical.name === 'if' || logical.name === 'elif';
    try {
      if (expression) {
        const replaced = this.replaceOperators(operands);
        expanded = this.expander.expand(replaced, context);
        if (!expanded.length) throw new Error(`#${logical.name} with no expression`);
        value = expressionValue(expanded, message => this.diagnostic(position, 'warning', message));
      } else {
        if (!operands.length) throw new Error(`no macro name given in #${logical.name} directive`);
        if (operands[0].kind !== 'identifier') throw new Error('macro names must be identifiers');
        if (operands.length > 1) this.diagnostic(position, 'warning', `extra tokens at end of #${logical.name} directive`);
        value = Number(this.defined(operands[0].spelling));
        if (logical.name === 'ifndef' || logical.name === 'elifndef') value = 1 - value;
      }
    } catch (error) {
      this.diagnostic(position, 'error', error.message);
      value = null;
    }
    let description = value === null ? 'not taken (error)' : value !== 0 ? 'taken' : 'not taken';
    if (expression && value !== null) description += ` (value ${value})`;
    if (expanded !== null) description += ` [${this.outputRendering(expanded)}]`;
    return {taken: value !== null && value !== 0, description};
  }

  recordConditional(context, logical, depth, result) {
    const position = this.position(context, logical.tokens[0].line);
    const operands = logical.tokens.slice(2);
    const directive = `#${logical.name}${operands.length ? ` ${render(operands)}` : ''}`;
    this.records.push(`${position.file}:${position.line}: ${' '.repeat(2 * depth)}${directive} => ${result}`);
    for (const [prefix, key] of resultKinds) {
      if (result.startsWith(prefix)) {
        this.recordCounts[key]++;
        break;
      }
    }
  }

  closeSkipped(context, block, end) {
    const start = block.skipStart;
    if (start !== null && end >= start) {
      const count = end - start + 1;
      this.regions.push(`${context.displayName}:${start + context.offset}-${end + context.offset} lines=${count}`);
      context.file.skippedLines += count;
    }
    block.skipStart = null;
  }

  conditional(context, logical) {
    const stack = context.conditions;
    const position = this.position(context, logical.tokens[0].line);
    if (starts.has(logical.name)) {
      const block = {kind: logical.name, start: position, parentActive: !stack.length || stack.at(-1).active,
        chosen: false, active: false, elseSeen: false, skipStart: null};
      let result = 'skipped';
      if (block.parentActive) {
        const test = this.testCondition(context, logical);
        result = test.description;
        block.active = block.chosen = test.taken;
        if (!block.active) block.skipStart = logical.endLine + 1;
      }
      this.recordConditional(context, logical, stack.length, result);
      stack.push(block);
      return;
    }
    if (!stack.length) {
      this.diagnostic(position, 'error', `#${logical.name} without #if`);
      return;
    }
    const depth = stack.length - 1;
    const block = stack.at(-1);
    this.closeSkipped(context, block, logical.startLine - 1);
    let result;
    if (logical.name === 'endif') {
      stack.pop();
      if (block.parentActive && logical.tokens.length > 2) {
        this.diagnostic(position, 'warning', 'extra tokens at end of #endif directive');
      }
      result = `closes #${block.kind} at line ${block.start.line}`;
    } else {
      if (block.elseSeen) this.diagnostic(position, 'error', `#${logical.name} after #else`);
      if (logical.name === 'else') {
        if (block.parentActive && logical.tokens.length > 2) {
          this.diagnostic(position, 'warning', 'extra tokens at end of #else directive');
        }
        block.elseSeen = true;
        if (block.parentActive) {
          block.active = !block.chosen;
          block.chosen = true;
          result = block.active ? 'taken' : 'not taken';
        } else result = 'skipped';
      } else if (!block.parentActive) {
        block.active = false;
        result = 'skipped';
      } else if (block.chosen) {
        block.active = false;
        result = 'not evaluated';
      } else {
        const test = this.testCondition(context, logical);
        block.active = test.taken;
        if (test.taken) block.chosen = true;
        result = test.description;
      }
      if (block.parentActive && !block.active) block.skipStart = logical.endLine + 1;
    }
    this.recordConditional(context, logical, depth, result);
  }

  include(context, logical, operands, position) {
    let tokens = operands;
    let header = this.header(tokens);
    if (!header && tokens.length) {
      tokens = this.expander.expand(tokens, context);
      header = this.header(tokens);
    }
    if (!header) throw new Error('#include expects "FILENAME" or <FILENAME>');
    if (tokens.length > header.end) this.diagnostic(position, 'warning', 'extra tokens at end of #include directive');
    if (!header.name) throw new Error('empty filename in #include');
    const path = this.includes.search(header.name, header.quoted);
    const prefix = `${' '.repeat(2 * (context.depth + 1))}${logical.tokens[0].line}: `;
    if (path === null) {
      this.tree.push(`${prefix}${header.rendering} [not found]`);
      this.diagnostic(position, 'error', `cannot find include file ${header.rendering}`);
      return;
    }
    const file = this.includes.files.get(path);
    if (file && (file.once || file.guard && this.table.has(file.guard))) {
      this.tree.push(`${prefix}${path} [skipped: ${file.once ? 'pragma once' : `guard ${file.guard}`}]`);
      file.skipped++;
      return;
    }
    if (context.depth + 1 > 8) {
      this.tree.push(`${prefix}${path} [too deep]`);
      this.diagnostic(position, 'error', '#include nested too deeply');
      return;
    }
    this.tree.push(prefix + path);
    this.marker(path, 1, '1');
    this.processFile(path, context.depth + 1);
    this.marker(context.displayName, logical.endLine + 1 + context.offset, '2');
  }

  lineDirective(context, logical, operands) {
    const decimal = token => token?.kind === 'number' && /^[0-9]+$/.test(token.spelling);
    if (!decimal(operands[0])) operands = this.expander.expand(operands, context);
    if (operands.length < 1 || operands.length > 2 || !decimal(operands[0])
        || operands.length === 2 && operands[1].kind !== 'string') throw new Error('invalid #line directive');
    const line = Number(operands[0].spelling);
    if (line < 1 || line > 2147483647) throw new Error('line number out of range');
    context.offset = line - (logical.endLine + 1);
    if (operands.length === 2) context.displayName = operands[1].spelling.slice(1, -1);
  }

  pragma(context, logical, operands, position) {
    const first = operands[0];
    if (first?.kind === 'identifier' && first.spelling === 'once') {
      if (operands.length > 1) this.diagnostic(position, 'warning', 'extra tokens at end of #pragma once directive');
      if (context.depth === 0) this.diagnostic(position, 'warning', '#pragma once in main file');
      context.file.once = true;
    } else if (first?.spelling === 'GCC' && operands[1]?.spelling === 'poison') {
      if (operands.slice(2).some(token => token.kind !== 'identifier')) throw new Error('invalid #pragma GCC poison directive');
      for (const token of operands.slice(2)) {
        if (this.table.has(token.spelling)) this.diagnostic(position, 'warning', `poisoning existing macro "${token.spelling}"`);
        this.poisoned.add(token.spelling);
      }
    } else if (first?.kind === 'identifier' && ['push_macro', 'pop_macro'].includes(first.spelling)) {
      if (operands.length !== 4 || !punct(operands[1], '(') || operands[2].kind !== 'string'
          || !punct(operands[3], ')')) throw new Error(`invalid #pragma ${first.spelling} directive`);
      const name = operands[2].spelling.slice(1, -1);
      if (!this.saved.has(name)) this.saved.set(name, []);
      const stack = this.saved.get(name);
      if (first.spelling === 'push_macro') {
        stack.push(this.table.get(name) ?? null);
        this.recordHistory(position, `push ${name}`);
      } else if (!stack.length) this.diagnostic(position, 'warning', `no matching push_macro for "${name}"`);
      else {
        const macro = stack.pop();
        if (macro) this.table.set(name, macro);
        else this.table.delete(name);
        this.recordHistory(position, `pop ${name}${macro ? '' : ' (undefined)'}`);
      }
    } else this.outputLine(context, logical.tokens[0].line, `#pragma${operands.length ? ` ${render(operands)}` : ''}`);
  }

  directive(context, logical) {
    if (logical.tokens.length === 1) return;
    const operands = logical.tokens.slice(2);
    const position = this.position(context, logical.tokens[0].line);
    if (!(logical.name === 'pragma' && operands[0]?.spelling === 'GCC' && operands[1]?.spelling === 'poison')) {
      this.poison(operands, context);
    }
    try {
      switch (logical.name) {
        case 'define': this.define(operands, position, context.depth === 0); break;
        case 'undef': this.undefine(operands, position); break;
        case 'include': this.include(context, logical, operands, position); break;
        case 'line': this.lineDirective(context, logical, operands); break;
        case 'error': case 'warning':
          this.diagnostic(position, logical.name, `#${logical.name}${operands.length ? ` ${render(operands)}` : ''}`);
          break;
        case 'pragma': this.pragma(context, logical, operands, position); break;
        default: this.diagnostic(position, 'error', `invalid preprocessing directive #${logical.tokens[1].spelling}`);
      }
    } catch (error) {
      this.diagnostic(position, 'error', error.message);
    }
  }

  processFile(path, depth) {
    const file = this.includes.enter(path);
    const context = {file, depth, displayName: path, offset: 0, conditions: [], segment: []};
    for (const logical of file.lines) {
      if (conditionals.has(logical.name)) {
        this.flush(context);
        this.conditional(context, logical);
      } else if (context.conditions.length && !context.conditions.at(-1).active) continue;
      else if (punct(logical.tokens[0], '#')) {
        this.flush(context);
        this.directive(context, logical);
      } else {
        for (const token of logical.tokens) context.segment.push(copy(token));
      }
    }
    this.flush(context);
    for (const block of context.conditions) this.closeSkipped(context, block, file.physicalLines);
    for (const block of context.conditions) this.diagnostic(block.start, 'error', `unterminated #${block.kind}`);
  }

  dependencies() {
    const lines = [];
    let current = 'main.o:';
    let hasPath = false;
    for (const path of this.includes.order) {
      if (current.length + 1 + path.length > 76 && hasPath) {
        lines.push(current + ' \\');
        current = ' ';
        hasPath = false;
      }
      current += ' ' + path;
      hasPath = true;
    }
    lines.push(current);
    return lines;
  }

  includeReport() {
    const lines = ['main.c', ...this.tree, '', '== files =='];
    for (const path of [...this.includes.files.keys()].sort()) {
      const file = this.includes.files.get(path);
      lines.push(`${path} entered=${file.entered} skipped=${file.skipped} lines=${file.physicalLines}`
        + ` output_lines=${file.outputLines} skipped_lines=${file.skippedLines} guard=${file.guard ?? '-'} once=${file.once ? 'yes' : 'no'}`);
    }
    return [...lines, '', ...this.dependencies()];
  }

  macroReport() {
    const names = [...this.table.keys()].sort();
    const references = new Map();
    for (const name of names) {
      const macro = this.table.get(name);
      const found = new Set();
      for (const token of macro.replacement) {
        if (token.kind === 'identifier' && this.table.has(token.spelling)
            && !macro.parameters?.includes(token.spelling)) found.add(token.spelling);
      }
      references.set(name, [...found].sort());
    }
    const recursive = name => {
      const pending = [...references.get(name)];
      const seen = new Set();
      while (pending.length) {
        const current = pending.pop();
        if (current === name) return true;
        if (seen.has(current)) continue;
        seen.add(current);
        for (const next of references.get(current)) pending.push(next);
      }
      return false;
    };
    const lines = ['== history ==', ...this.history, '', '== table =='];
    let objectLike = 0;
    for (const name of names) {
      const macro = this.table.get(name);
      if (macro.parameters === null) objectLike++;
      lines.push(`#define ${macro.signature()}${macro.replacement.length ? ` ${render(macro.replacement)}` : ''}`);
      lines.push(`  at ${macro.position.file}:${macro.position.line} expanded=${macro.expanded} tested=${macro.tested} recursive=${recursive(name) ? 'yes' : 'no'}`);
      lines.push(['  refs:', ...references.get(name)].join(' '));
    }
    const undefinedNames = [...this.everDefined].filter(name => !this.table.has(name)).sort();
    lines.push('', `macros=${names.length} object_like=${objectLike} function_like=${names.length - objectLike}`);
    lines.push(['undefined:', ...undefinedNames].join(' '));
    const uses = this.expander.uses;
    lines.push(`builtins: __COUNTER__=${uses.get('__COUNTER__')} __FILE__=${uses.get('__FILE__')} __LINE__=${uses.get('__LINE__')}`);
    return lines;
  }

  conditionalReport() {
    const count = this.recordCounts;
    const totals = `directives=${this.records.length} taken=${count.taken} not_taken=${count.not_taken}`
      + ` skipped=${count.skipped} not_evaluated=${count.not_evaluated} endif=${count.endif} regions=${this.regions.length}`;
    return [...this.records, '', '== skipped regions ==', ...this.regions, '', totals];
  }

  run() {
    const lines = fs.readFileSync('input/defines.txt', 'utf8').split('\n');
    for (let index = 0; index < lines.length; index++) {
      if (lines[index] === '') continue;
      const equal = lines[index].indexOf('=');
      const text = equal < 0 ? lines[index] + ' 1'
        : lines[index].slice(0, equal) + ' ' + lines[index].slice(equal + 1);
      const position = {file: 'defines.txt', line: index + 1};
      try {
        this.define(lexDefinition(text), position, false);
      } catch (error) {
        this.diagnostic(position, 'error', error.message);
      }
    }
    this.marker('main.c', 1);
    this.processFile('main.c', 0);
    for (const name of [...this.table.keys()].sort()) this.unused(this.table.get(name));
    const counts = this.diagnosticCounts;
    const reports = new Map([
      ['preprocessed.txt', this.output], ['includes.txt', this.includeReport()],
      ['macros.txt', this.macroReport()], ['conditionals.txt', this.conditionalReport()],
      ['diagnostics.txt', [...this.diagnostics, `errors=${counts.error} warnings=${counts.warning}`]],
    ]);
    fs.mkdirSync('output', {recursive: true});
    for (const [name, content] of reports) fs.writeFileSync(`output/${name}`, content.join('\n') + '\n');
  }
}

new Preprocessor().run();
