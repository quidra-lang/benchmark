import * as fs from 'node:fs';
import {tokenize} from './lexer.ts';
import {Parser, ParseError, operators} from './parser.ts';
import * as types from './unifier.ts';
import {Inferencer, InferenceError} from './inference.ts';
import {Evaluator, RuntimeError, builtin} from './evaluator.ts';

function positionOrder(first, second) {
  return first.line - second.line || first.column - second.column;
}

function quote(value) {
  const escapes = {'\\': '\\\\', '"': '\\"', '\n': '\\n', '\t': '\\t'};
  return '"' + value.replace(/[\\"\n\t]/g, character => escapes[character]) + '"';
}

function printValue(value) {
  const pieces = [];
  const pending: Array<{value?: any; text?: string}> = [{value}];
  while (pending.length > 0) {
    const part = pending.pop();
    if (Object.hasOwn(part, 'text')) { pieces.push(part.text); continue; }
    const current = part.value;
    if (typeof current === 'string') pieces.push(quote(current));
    else if (typeof current !== 'object') pieces.push(String(current));
    else if (Array.isArray(current)) {
      pending.push({text: ']'});
      for (let i = current.length - 1; i >= 0; i--) {
        pending.push({value: current[i]});
        if (i > 0) pending.push({text: '; '});
      }
      pending.push({text: '['});
    } else if (current.kind === 'pair') {
      pending.push({text: ')'}, {value: current.second}, {text: ', '}, {value: current.first}, {text: '('});
    } else pieces.push('<fun>');
  }
  return pieces.join('');
}

function printType(type, names = new Map(), quantified = null) {
  function render(value) {
    if (value.kind === 'variable') return value.name;
    value = types.resolve(value);
    if (value.kind === 'var') {
      if (!names.has(value)) names.set(value, names.size);
      const index = names.get(value);
      const prefix = quantified !== null && !quantified.has(value) ? "'_" : "'";
      return prefix + String.fromCharCode(97 + index % 26) + (index < 26 ? '' : Math.floor(index / 26));
    }
    if (value.args.length === 0) return value.kind;
    const wrap = (component, kinds) => {
      const text = render(component);
      return kinds.includes(types.resolve(component).kind) ? '(' + text + ')' : text;
    };
    if (value.kind === 'list') return wrap(value.args[0], ['pair', 'function']) + ' list';
    if (value.kind === 'pair') return wrap(value.args[0], ['pair', 'function']) + ' * ' + wrap(value.args[1], ['pair', 'function']);
    return wrap(value.args[0], ['function']) + ' -> ' + render(value.args[1]);
  }
  return render(type);
}

function editDistance(first, second) {
  let previous = Array.from({length: second.length + 1}, (_, i) => i);
  for (let i = 0; i < first.length; i++) {
    const current = [i + 1];
    for (let j = 0; j < second.length; j++) {
      current.push(Math.min(current[j] + 1, previous[j + 1] + 1, previous[j] + (first[i] === second[j] ? 0 : 1)));
    }
    previous = current;
  }
  return previous[second.length];
}

function typeErrorMessage(error) {
  const names = new Map();
  const show = type => printType(type, names);
  if (error.reason === 'check') {
    let message = `expected ${show(error.expected)} but found ${show(error.found)}`;
    const failure = error.failure;
    if (failure.kind === 'occurs') message += ` (infinite type ${show(failure.variable)} = ${show(failure.other)})`;
    else if (failure.component) message += ` (${show(failure.expected)} vs ${show(failure.found)})`;
    return message;
  }
  if (error.reason === 'function') return `expected a function but found ${show(error.found)}`;
  if (error.reason === 'patternDuplicate') return `variable '${error.name}' is bound twice in this pattern`;
  if (error.reason === 'letDuplicate') return `variable '${error.name}' is bound twice in this let`;
  if (error.reason === 'recFunction') return `'${error.name}' in let rec must be a function`;
  if (error.reason === 'signature') return `'${error.name}' has type ${show(error.inferred)} but its signature is ${show(error.declared)}`;
  let candidate = null;
  let distance = 3;
  for (const name of error.candidates) {
    const found = editDistance(error.name, name);
    if (found < error.name.length && (found < distance || (found === distance && (candidate === null || name < candidate)))) {
      distance = found;
      candidate = name;
    }
  }
  return `unbound variable '${error.name}'` + (candidate === null || distance > 2 ? '' : ` (did you mean '${candidate}'?)`);
}

function signatureType(expression, variables = new Map()) {
  if (expression.kind === 'variable') {
    if (!variables.has(expression.name)) variables.set(expression.name, types.fresh());
    return variables.get(expression.name);
  }
  return {kind: expression.kind, args: expression.args.map(argument => signatureType(argument, variables))};
}

function equalRigid(first, second) {
  if (first === second) return true;
  if (first.kind !== second.kind || first.kind === 'var') return false;
  return first.args.every((argument, index) => equalRigid(argument, second.args[index]));
}

function acceptsSignature(inferred, declared, assignments = new Map()) {
  inferred = types.resolve(inferred);
  if (inferred.kind === 'var') {
    if (assignments.has(inferred)) return equalRigid(assignments.get(inferred), declared);
    assignments.set(inferred, declared);
    return true;
  }
  return inferred.kind === declared.kind && inferred.args.every((argument, index) => acceptsSignature(argument, declared.args[index], assignments));
}

function checkSignatures(group, signatures, environment) {
  for (let i = 0; i < group.bindings.length; i++) {
    if (signatures[i] === null) continue;
    const binding = group.bindings[i];
    const declared = signatureType(signatures[i].type);
    if (!acceptsSignature(binding.scheme.type, declared)) {
      throw new InferenceError('signature', binding.position,
        {name: binding.name, inferred: binding.scheme.type, declared});
    }
    binding.scheme = {type: declared, quantified: types.freeVariables(declared)};
    environment.set(binding.name, binding.scheme);
  }
}

function initialEnvironments() {
  const typeEnvironment = new Map();
  const valueEnvironment = new Map();
  function add(name, type, apply) {
    typeEnvironment.set(name, {type, quantified: types.freeVariables(type)});
    valueEnvironment.set(name, builtin(name, apply));
  }
  let first = types.fresh();
  let second = types.fresh();
  add('fst', types.fn(types.pair(first, second), first), value => value.first);
  first = types.fresh();
  second = types.fresh();
  add('snd', types.fn(types.pair(first, second), second), value => value.second);
  add('not', types.fn(types.boolean, types.boolean), value => !value);
  add('string_of_int', types.fn(types.integer, types.string), value => String(value));
  add('failwith', types.fn(types.string, types.fresh()), (value, position) => {
    throw new RuntimeError(position, 'failure ' + printValue(value));
  });
  return {typeEnvironment, valueEnvironment};
}

function leadingFunctions(expression) {
  const parameters = [];
  while (expression.kind === 'fun') {
    parameters.push(expression.parameter.name);
    expression = expression.body;
  }
  return {parameters, body: expression};
}

function formatPattern(pattern) {
  if (pattern.kind === 'name') return pattern.name;
  if (pattern.kind === 'wildcard') return '_';
  if (pattern.kind === 'pair') return '(' + formatPattern(pattern.first) + ', ' + formatPattern(pattern.second) + ')';
  if (pattern.kind === 'list') return '[' + pattern.elements.map(formatPattern).join('; ') + ']';
  if (pattern.kind === 'cons') {
    let first = formatPattern(pattern.first);
    if (pattern.first.kind === 'cons') first = '(' + first + ')';
    return first + ' :: ' + formatPattern(pattern.second);
  }
  return printValue(pattern.value);
}

function endsWithMatch(expression) {
  if (expression.kind === 'match') return true;
  if (expression.kind === 'let' || expression.kind === 'fun') return endsWithMatch(expression.body);
  return expression.kind === 'if' && endsWithMatch(expression.no);
}

function formatBinding(binding) {
  const {parameters, body} = leadingFunctions(binding.expression);
  return [binding.name, ...parameters, '=', formatExpression(body)].join(' ');
}

function formatGroup(group) {
  return (group.recursive ? 'let rec ' : 'let ') + group.bindings.map(formatBinding).join(' and ');
}

function formatExpression(expression, required = 0) {
  let text;
  let strength = 9;
  switch (expression.kind) {
    case 'int': case 'bool': case 'string': text = printValue(expression.value); break;
    case 'name': text = expression.name; break;
    case 'fun': {
      const {parameters, body} = leadingFunctions(expression);
      strength = 0;
      text = 'fun ' + parameters.join(' ') + ' -> ' + formatExpression(body);
      break;
    }
    case 'application':
      strength = 8;
      text = formatExpression(expression.fn, 8) + ' ' + formatExpression(expression.argument, 9);
      break;
    case 'binary': {
      const [precedence, rightAssociative] = operators.get(expression.operator);
      strength = precedence;
      text = formatExpression(expression.left, precedence + (rightAssociative ? 1 : 0)) + ' ' + expression.operator + ' ' +
        formatExpression(expression.right, precedence + (rightAssociative ? 0 : 1));
      break;
    }
    case 'unary': strength = 7; text = '-' + formatExpression(expression.expression, 7); break;
    case 'if':
      strength = 0;
      text = 'if ' + formatExpression(expression.condition) + ' then ' + formatExpression(expression.yes) + ' else ' + formatExpression(expression.no);
      break;
    case 'pair': text = '(' + formatExpression(expression.first) + ', ' + formatExpression(expression.second) + ')'; break;
    case 'list': text = '[' + expression.elements.map(value => formatExpression(value)).join('; ') + ']'; break;
    case 'let': strength = 0; text = formatGroup(expression.group) + ' in ' + formatExpression(expression.body); break;
    case 'match':
      strength = 0;
      text = 'match ' + formatExpression(expression.matched) + ' with ' + expression.arms.map((arm, index) => {
        let body = formatExpression(arm.expression);
        if (index + 1 < expression.arms.length && endsWithMatch(arm.expression)) body = '(' + body + ')';
        return formatPattern(arm.pattern) + ' -> ' + body;
      }).join(' | ');
      break;
  }
  return strength < required ? '(' + text + ')' : text;
}

function formatItem(item) {
  if (item.kind === 'signature') return `val ${item.name} : ${printType(item.type)};;`;
  return (item.kind === 'declaration' ? formatGroup(item.group) : formatExpression(item.expression)) + ';;';
}

const wildcard = {tag: '_', args: []};

function patternTree(pattern) {
  if (pattern.kind === 'name' || pattern.kind === 'wildcard') return wildcard;
  if (pattern.kind === 'pair' || pattern.kind === 'cons') {
    return {tag: pattern.kind, args: [patternTree(pattern.first), patternTree(pattern.second)]};
  }
  if (pattern.kind === 'list') {
    let result = {tag: 'nil', args: []};
    for (let i = pattern.elements.length - 1; i >= 0; i--) result = {tag: 'cons', args: [patternTree(pattern.elements[i]), result]};
    return result;
  }
  return {tag: pattern.kind + ':' + String(pattern.value), args: []};
}

function constructors(type) {
  type = types.resolve(type);
  if (type.kind === 'bool') return ['bool:false', 'bool:true'];
  if (type.kind === 'list') return ['nil', 'cons'];
  if (type.kind === 'pair') return ['pair'];
  return null;
}

function constructorArguments(type, tag) {
  type = types.resolve(type);
  if (tag === 'pair') return type.args;
  if (tag === 'cons') return [type.args[0], type];
  return [];
}

function specialize(matrix, tag, arity) {
  const result = [];
  for (const row of matrix) {
    if (row[0].tag === tag) result.push(row[0].args.concat(row.slice(1)));
    else if (row[0].tag === '_') result.push(Array(arity).fill(wildcard).concat(row.slice(1)));
  }
  return result;
}

function useful(matrix, vector, columnTypes) {
  const pending = [{matrix, vector, columnTypes}];
  while (pending.length > 0) {
    const state = pending.pop();
    if (state.matrix.length === 0) return true;
    if (state.vector.length === 0 || state.matrix.some(row => row.every(pattern => pattern.tag === '_'))) continue;
    const [head, ...tail] = state.vector;
    const [type, ...otherTypes] = state.columnTypes;
    if (head.tag !== '_') {
      pending.push({matrix: specialize(state.matrix, head.tag, head.args.length), vector: head.args.concat(tail),
        columnTypes: constructorArguments(type, head.tag).concat(otherTypes)});
      continue;
    }
    const possible = constructors(type);
    const present = new Set(state.matrix.map(row => row[0].tag));
    if (possible !== null && possible.every(tag => present.has(tag))) {
      for (const tag of possible) {
        const arguments_ = constructorArguments(type, tag);
        pending.push({matrix: specialize(state.matrix, tag, arguments_.length),
          vector: Array(arguments_.length).fill(wildcard).concat(tail), columnTypes: arguments_.concat(otherTypes)});
      }
    } else {
      pending.push({matrix: state.matrix.filter(row => row[0].tag === '_').map(row => row.slice(1)),
        vector: tail, columnTypes: otherTypes});
    }
  }
  return false;
}

function matchWarnings(expression, warnings) {
  const matrix = [];
  const columnTypes = [expression.matched.type];
  for (let index = 0; index < expression.arms.length; index++) {
    const arm = expression.arms[index];
    const pattern = patternTree(arm.pattern);
    if (index > 0 && !useful(matrix, [pattern], columnTypes)) {
      warnings.push({position: arm.pattern.position, priority: 2, message: 'this match case is unused'});
    }
    matrix.push([pattern]);
  }
  if (useful(matrix, [wildcard], columnTypes)) {
    warnings.push({position: expression.position, priority: 1, message: 'this match is not exhaustive'});
  }
}

function recursionClass(binding, group) {
  let references = 0;
  let allTail = true;
  function reference(expression, tail) {
    if (expression.target?.group !== group) return;
    references++;
    if (!tail) allTail = false;
  }
  function visit(expression, tail) {
    switch (expression.kind) {
      case 'name': reference(expression, false); break;
      case 'application': {
        const arguments_ = [];
        let head = expression;
        while (head.kind === 'application') { arguments_.push(head.argument); head = head.fn; }
        if (head.kind === 'name') reference(head, tail);
        else visit(head, false);
        for (let i = arguments_.length - 1; i >= 0; i--) visit(arguments_[i], false);
        break;
      }
      case 'fun': visit(expression.body, false); break;
      case 'unary': visit(expression.expression, false); break;
      case 'binary':
        visit(expression.left, false);
        visit(expression.right, tail && (expression.operator === '&&' || expression.operator === '||'));
        break;
      case 'if': visit(expression.condition, false); visit(expression.yes, tail); visit(expression.no, tail); break;
      case 'pair': visit(expression.first, false); visit(expression.second, false); break;
      case 'list': for (const element of expression.elements) visit(element, false); break;
      case 'match':
        visit(expression.matched, false);
        for (const arm of expression.arms) visit(arm.expression, tail);
        break;
      case 'let':
        for (const local of expression.group.bindings) visit(local.expression, false);
        visit(expression.body, tail);
        break;
    }
  }
  visit(leadingFunctions(binding.expression).body, true);
  return references === 0 ? null : allTail ? 'tail recursive' : 'recursive';
}

function staticChecks(item, environment) {
  const warnings = [];
  const binders = [];
  const groups = [];
  function binder(name, position, excluded, group = null) {
    const result = {name, position, excluded, group, used: 0};
    binders.push(result);
    return result;
  }
  function patternBindings(pattern, scope) {
    if (pattern.kind === 'name') scope.set(pattern.name, binder(pattern.name, pattern.position, false));
    else if (pattern.kind === 'pair' || pattern.kind === 'cons') {
      patternBindings(pattern.first, scope);
      patternBindings(pattern.second, scope);
    } else if (pattern.kind === 'list') for (const element of pattern.elements) patternBindings(element, scope);
  }
  function groupScope(group, scope, topLevel) {
    const extended = new Map(scope);
    const members = group.bindings.map(binding => binder(binding.name, binding.position, topLevel, group));
    group.bindings.forEach((binding, i) => extended.set(binding.name, members[i]));
    for (const binding of group.bindings) visit(binding.expression, group.recursive ? extended : scope);
    group.usedRec = members.some(member => member.used > 0);
    groups.push(group);
    return extended;
  }
  function visit(expression, scope) {
    switch (expression.kind) {
      case 'name':
        expression.target = scope.get(expression.name);
        expression.target.used++;
        break;
      case 'fun': {
        const extended = new Map(scope);
        const parameter = expression.parameter;
        if (parameter.name !== '_') extended.set(parameter.name, binder(parameter.name, parameter.position, false));
        visit(expression.body, extended);
        break;
      }
      case 'application': visit(expression.fn, scope); visit(expression.argument, scope); break;
      case 'binary': visit(expression.left, scope); visit(expression.right, scope); break;
      case 'unary': visit(expression.expression, scope); break;
      case 'if': visit(expression.condition, scope); visit(expression.yes, scope); visit(expression.no, scope); break;
      case 'pair': visit(expression.first, scope); visit(expression.second, scope); break;
      case 'list': for (const element of expression.elements) visit(element, scope); break;
      case 'let': visit(expression.body, groupScope(expression.group, scope, false)); break;
      case 'match':
        visit(expression.matched, scope);
        matchWarnings(expression, warnings);
        for (const arm of expression.arms) {
          const extended = new Map(scope);
          patternBindings(arm.pattern, extended);
          visit(arm.expression, extended);
        }
        break;
    }
  }
  const scope = new Map([...environment.keys()].map(name => [name, {name, used: 0, group: null}]));
  if (item.kind === 'declaration') groupScope(item.group, scope, true);
  else visit(item.expression, scope);
  for (const group of groups) {
    if (!group.recursive) continue;
    if (!group.usedRec) warnings.push({position: group.recPosition, priority: 3, message: 'unused rec flag'});
    for (const binding of group.bindings) binding.classification = recursionClass(binding, group);
  }
  for (const name of binders) {
    if (!name.excluded && !name.name.startsWith('_') && name.used === 0) {
      warnings.push({position: name.position, priority: 4, message: `unused variable '${name.name}'`});
    }
  }
  warnings.sort((first, second) => positionOrder(first.position, second.position) || first.priority - second.priority);
  return warnings;
}

function classification(binding) {
  return binding.classification ? ' (' + binding.classification + ')' : '';
}

function appendTypes(lines, item, inferencer) {
  if (item.kind === 'declaration') {
    for (const binding of item.group.bindings) lines.push(`${binding.name} : ${printType(binding.scheme.type)}${classification(binding)}`);
  } else lines.push('- : ' + printType(item.expression.type));
  inferencer.locals.sort((first, second) => positionOrder(first.position, second.position));
  for (const binding of inferencer.locals) {
    const {line, column} = binding.position;
    lines.push(`  ${binding.name} (${line}:${column}) : ${printType(binding.scheme.type, new Map(), binding.scheme.quantified)}${classification(binding)}`);
  }
}

function report(lines, sources, statistics, position, kind, message) {
  const key = {warning: 'warnings', 'syntax error': 'syntax', 'type error': 'type', 'runtime error': 'runtime'}[kind];
  statistics[key]++;
  lines.push(`${position.file}:${position.line}:${position.column}: ${kind}: ${message}`);
  const source = sources.get(position.file).lines;
  if (position.line <= source.length) {
    lines.push('    ' + source[position.line - 1]);
    lines.push(' '.repeat(position.column + 3) + '^');
  }
}

function syntaxMessage(token) {
  if (token.kind === 'invalid') return token.message;
  return token.kind === 'eof' ? 'unexpected end of file' : `unexpected '${token.text}'`;
}

function recover(parser) {
  while (parser.current().kind !== 'eof' && parser.current().text !== ';;') parser.index++;
  if (parser.current().text === ';;') parser.index++;
}

function main() {
  const fileNames = ['prelude.ml', 'program.ml'];
  const sources = new Map(fileNames.map(name => {
    const text = fs.readFileSync('input/' + name, 'ascii');
    return [name, {text, lines: text === '' ? [] : text.slice(0, -1).split('\n')}];
  }));
  const outputs = {'types.txt': [], 'values.txt': [], 'errors.txt': [], 'formatted.ml': []};
  const summaries = [];
  let {typeEnvironment, valueEnvironment} = initialEnvironments();
  for (const file of fileNames) {
    const statistics = {items: 0, bindings: 0, syntax: 0, type: 0, runtime: 0, warnings: 0, calls: 0};
    const emit = (position, kind, message) => report(outputs['errors.txt'], sources, statistics, position, kind, message);
    const parser = new Parser(tokenize(sources.get(file).text, file));
    const evaluator = new Evaluator();
    const pending = new Map();
    outputs['types.txt'].push(`== ${file} ==`);
    outputs['values.txt'].push(`== ${file} ==`);
    outputs['formatted.ml'].push(`(* ${file} *)`);
    while (parser.current().kind !== 'eof') {
      statistics.items++;
      let item;
      try { item = parser.item(); }
      catch (error) {
        if (!(error instanceof ParseError)) throw error;
        emit(error.token.position, 'syntax error', syntaxMessage(error.token));
        recover(parser);
        continue;
      }
      outputs['formatted.ml'].push(formatItem(item));
      if (item.kind === 'signature') {
        const old = pending.get(item.name);
        if (old !== undefined) emit(old.position, 'warning', `signature for '${item.name}' is never used`);
        pending.set(item.name, item);
        continue;
      }
      const signatures = item.kind === 'declaration' ? item.group.bindings.map(binding => {
        const signature = pending.get(binding.name) ?? null;
        pending.delete(binding.name);
        return signature;
      }) : [];
      const inferencer = new Inferencer();
      let newTypes;
      try {
        if (item.kind === 'declaration') {
          newTypes = inferencer.group(item.group, typeEnvironment, true);
          checkSignatures(item.group, signatures, newTypes);
        } else inferencer.expression(item.expression, typeEnvironment);
      } catch (error) {
        if (!(error instanceof InferenceError)) throw error;
        emit(error.position, 'type error', typeErrorMessage(error));
        continue;
      }
      const warnings = staticChecks(item, typeEnvironment);
      appendTypes(outputs['types.txt'], item, inferencer);
      for (const warning of warnings) emit(warning.position, 'warning', warning.message);
      try {
        if (item.kind === 'declaration') {
          const newValues = evaluator.group(item.group, valueEnvironment);
          for (const binding of item.group.bindings) outputs['values.txt'].push(`${binding.name} = ${printValue(newValues.get(binding.name))}`);
          typeEnvironment = newTypes;
          valueEnvironment = newValues;
          statistics.bindings += item.group.bindings.length;
        } else outputs['values.txt'].push('- = ' + printValue(evaluator.expression(item.expression, valueEnvironment)));
      } catch (error) {
        if (!(error instanceof RuntimeError)) throw error;
        emit(error.position, 'runtime error', error.message);
      }
    }
    const remaining = [...pending.values()].sort((first, second) => positionOrder(first.position, second.position));
    for (const signature of remaining) emit(signature.position, 'warning', `signature for '${signature.name}' is never used`);
    statistics.calls = evaluator.calls;
    summaries.push(`${file}: ` + Object.entries(statistics).map(([name, value]) => `${name}=${value}`).join(' '));
  }
  outputs['errors.txt'].push('== summary ==', ...summaries);
  fs.mkdirSync('output', {recursive: true});
  for (const [file, lines] of Object.entries(outputs)) fs.writeFileSync('output/' + file, lines.join('\n') + '\n', 'ascii');
}

main();
