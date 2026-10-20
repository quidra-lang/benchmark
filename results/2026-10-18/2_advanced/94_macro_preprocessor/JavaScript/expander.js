'use strict';

const {copy, punct, singleToken} = require('./lexer');
const {builtins} = require('./definitions');

function intersection(left, right) {
  return new Set([...left].filter(name => right.has(name)));
}

class Expander {
  constructor(table, diagnostic) {
    this.table = table;
    this.diagnostic = diagnostic;
    this.counter = 0;
    this.uses = new Map([...builtins].map(name => [name, 0]));
  }

  error(context, token, message) {
    this.diagnostic({file: context.displayName, line: token.line + context.offset}, 'error', message);
  }

  builtin(token, context) {
    this.uses.set(token.spelling, this.uses.get(token.spelling) + 1);
    let spelling;
    if (token.spelling === '__LINE__') spelling = String(token.line + context.offset);
    else if (token.spelling === '__FILE__') spelling = `"${context.displayName}"`;
    else spelling = String(this.counter++);
    return {kind: token.spelling === '__FILE__' ? 'string' : 'number', spelling,
      line: token.line, space: token.space, hide: new Set()};
  }

  collect(input, macro, token, context) {
    const argumentsList = [[]];
    const separators = [];
    let depth = 0;
    let closingIndex = -1;
    for (let index = input.length - 2; index >= 0; index--) {
      const current = input[index];
      if (depth === 0 && punct(current, ')')) {
        closingIndex = index;
        break;
      }
      if (depth === 0 && punct(current, ',')) {
        separators.push(copy(current));
        argumentsList.push([]);
      } else {
        if (punct(current, '(')) depth++;
        if (punct(current, ')')) depth--;
        argumentsList.at(-1).push(copy(current));
      }
    }
    let message;
    const count = argumentsList.length;
    const required = macro.parameters.length - Number(macro.variadic);
    if (closingIndex < 0) message = `unterminated argument list invoking macro "${macro.name}"`;
    else if (!macro.variadic && required === 0 && (count !== 1 || argumentsList[0].length)) {
      message = `macro "${macro.name}" passed ${count} arguments, but takes just 0`;
    } else if (count < required) {
      message = `macro "${macro.name}" requires ${required} arguments, but only ${count} given`;
    } else if (count > required && !macro.variadic) {
      message = `macro "${macro.name}" passed ${count} arguments, but takes just ${required}`;
    }
    if (message) {
      this.error(context, token, message);
      return null;
    }
    const raw = new Map();
    for (let index = 0; index < required; index++) raw.set(macro.parameters[index], argumentsList[index]);
    if (macro.variadic) {
      const rest = [];
      for (let index = required; index < argumentsList.length; index++) {
        if (index > required) rest.push(copy(separators[index - 1]));
        for (const item of argumentsList[index]) rest.push(copy(item));
      }
      raw.set('__VA_ARGS__', rest);
    }
    const closing = copy(input[closingIndex]);
    input.length = closingIndex;
    return {raw, closing};
  }

  stringize(raw, hash) {
    let spelling = '"';
    for (let index = 0; index < raw.length; index++) {
      const token = raw[index];
      if (index && token.space) spelling += ' ';
      spelling += token.kind === 'string' || token.kind === 'character'
        ? token.spelling.replaceAll('\\', '\\\\').replaceAll('"', '\\"') : token.spelling;
    }
    return {kind: 'string', spelling: spelling + '"', line: hash.line, space: hash.space, hide: new Set()};
  }

  paste(left, right, token, context) {
    if (left.kind === 'placemarker') return [{...copy(right), space: left.space}];
    if (right.kind === 'placemarker') return [copy(left)];
    const spelling = left.spelling + right.spelling;
    const kind = singleToken(spelling);
    if (kind) return [{kind, spelling, line: left.line, space: left.space,
      hide: intersection(left.hide, right.hide)}];
    this.error(context, token, `pasting "${left.spelling}" and "${right.spelling}" does not give a valid preprocessing token`);
    return [copy(left), {...copy(right), space: false}];
  }

  *substitute(macro, raw, token, hide, context) {
    const items = [];
    const expanded = new Map();
    const replacement = macro.replacement;
    for (let index = 0; index < replacement.length; index++) {
      const current = replacement[index];
      if (macro.parameters !== null && punct(current, '#')) {
        items.push([this.stringize(raw.get(replacement[++index].spelling), current)]);
      } else if (punct(current, '##')) items.push({paste: copy(current)});
      else if (current.kind === 'identifier' && raw.has(current.spelling)) {
        const name = current.spelling;
        let argument;
        if (punct(replacement[index - 1], '##') || punct(replacement[index + 1], '##')) {
          argument = raw.get(name);
        } else {
          if (!expanded.has(name)) expanded.set(name, yield this.scan(raw.get(name), context));
          argument = expanded.get(name);
        }
        const sequence = argument.map(copy);
        if (sequence.length) sequence[0].space = current.space;
        else sequence.push({kind: 'placemarker', spelling: '', line: current.line,
          space: current.space, hide: new Set()});
        items.push(sequence);
      } else items.push([copy(current)]);
    }
    const joined = [];
    for (let index = 0; index < items.length; index++) {
      const item = items[index];
      if (!item.paste) {
        for (const current of item) joined.push(copy(current));
      } else {
        const left = joined.pop();
        const next = items[++index];
        const right = next.paste ? [copy(next.paste)] : next;
        for (const current of this.paste(left, right[0], token, context)) joined.push(current);
        for (let offset = 1; offset < right.length; offset++) joined.push(copy(right[offset]));
      }
    }
    const result = [];
    let separated = false;
    for (const current of joined) {
      if (current.kind === 'placemarker') separated ||= current.space;
      else {
        const next = copy(current);
        next.line = token.line;
        next.space ||= separated;
        for (const name of hide) next.hide.add(name);
        result.push(next);
        separated = false;
      }
    }
    if (result.length) result[0].space = token.space;
    return result;
  }

  *scan(sequence, context) {
    const input = sequence.map(copy).reverse();
    const result = [];
    while (input.length) {
      const token = input.pop();
      if (token.kind !== 'identifier' || token.hide.has(token.spelling)) {
        result.push(token);
        continue;
      }
      if (builtins.has(token.spelling)) {
        result.push(this.builtin(token, context));
        continue;
      }
      const macro = this.table.get(token.spelling);
      if (!macro || macro.parameters !== null && !punct(input.at(-1), '(')) {
        result.push(token);
        continue;
      }
      let hide = new Set(token.hide);
      let raw = new Map();
      if (macro.parameters !== null) {
        const collected = this.collect(input, macro, token, context);
        if (!collected) {
          result.push(token);
          continue;
        }
        raw = collected.raw;
        hide = intersection(token.hide, collected.closing.hide);
      }
      hide.add(macro.name);
      const replacement = yield this.substitute(macro, raw, token, hide, context);
      macro.expanded++;
      if (!replacement.length && token.space && input.length) input.at(-1).space = true;
      for (let index = replacement.length - 1; index >= 0; index--) input.push(replacement[index]);
    }
    return result;
  }

  expand(tokens, context) {
    const stack = [this.scan(tokens, context)];
    let value;
    while (stack.length) {
      const step = stack.at(-1).next(value);
      if (step.done) {
        stack.pop();
        value = step.value;
      } else {
        stack.push(step.value);
        value = undefined;
      }
    }
    return value;
  }
}

module.exports = {Expander};
