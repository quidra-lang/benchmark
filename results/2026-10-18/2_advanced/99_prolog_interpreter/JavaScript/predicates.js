'use strict';

const terms = require('./terms');
const {identical} = require('./unify');

const indicators = [
  ['true', 0], ['fail', 0], ['false', 0], ['=', 2], ['\\=', 2], ['==', 2], ['\\==', 2],
  ['var', 1], ['nonvar', 1], ['atom', 1], ['number', 1], ['integer', 1], ['atomic', 1],
  ['compound', 1], ['callable', 1], ['is_list', 1], ['is', 2], ['=:=', 2], ['=\\=', 2],
  ['<', 2], ['>', 2], ['=<', 2], ['>=', 2], ['functor', 3], ['arg', 3], ['=..', 2],
  ['copy_term', 2], ['atom_length', 2], ['atom_chars', 2], ['write', 1], ['writeq', 1], ['nl', 0]
];
const keys = new Set(indicators.map(([name, count]) => terms.key(name, count)));
const arithmetic = new Set([['+', 2], ['-', 2], ['*', 2], ['//', 2], ['mod', 2], ['rem', 2],
  ['-', 1], ['abs', 1], ['min', 2], ['max', 2]].map(([name, count]) => terms.key(name, count)));

class BuiltinError extends Error {
  constructor(formal) { super('Prolog built-in error'); this.formal = formal; }
}

function fail(name, ...args) { throw new BuiltinError(terms.form(name, ...args)); }

function checkInteger(term) {
  term = terms.dereference(term);
  if (term.kind === 'variable') fail('instantiation_error');
  if (term.kind !== 'integer') fail('type_error', terms.atom('integer'), term);
  return term.value;
}

function checkAtom(term) {
  term = terms.dereference(term);
  if (term.kind === 'variable') fail('instantiation_error');
  if (term.kind !== 'atom') fail('type_error', terms.atom('atom'), term);
  return term.name;
}

function checkList(term) {
  const result = terms.listParts(term);
  if (result.tail.kind === 'variable') fail('instantiation_error');
  if (!result.proper) fail('type_error', terms.atom('list'), term);
  return result.elements;
}

function evaluate(term) {
  const pending = [{term}];
  const values = [];
  while (pending.length > 0) {
    const frame = pending.pop();
    if (frame.term !== undefined) {
      const current = terms.dereference(frame.term);
      if (current.kind === 'variable') fail('instantiation_error');
      if (current.kind === 'integer') { values.push(BigInt(current.value)); continue; }
      if (current.kind === 'atom' || !arithmetic.has(terms.predicateKey(current))) {
        fail('type_error', terms.atom('evaluable'), terms.predicateIndicator(current));
      }
      pending.push({name: current.name, count: current.args.length});
      for (let index = current.args.length - 1; index >= 0; index--) pending.push({term: current.args[index]});
      continue;
    }
    const args = values.splice(values.length - frame.count, frame.count);
    const [first, second] = args;
    let value;
    if (frame.name === '+') value = first + second;
    else if (frame.name === '-') value = frame.count === 1 ? -first : first - second;
    else if (frame.name === '*') value = first * second;
    else if (frame.name === 'abs') value = first < 0n ? -first : first;
    else if (frame.name === 'min') value = first < second ? first : second;
    else if (frame.name === 'max') value = first > second ? first : second;
    else {
      if (second === 0n) fail('evaluation_error', terms.atom('zero_divisor'));
      const quotient = first / second;
      const remainder = first % second;
      if (frame.name === '//') value = quotient;
      else if (frame.name === 'rem') value = remainder;
      else {
        const floor = remainder !== 0n && ((first < 0n) !== (second < 0n)) ? quotient - 1n : quotient;
        value = first - second * floor;
      }
    }
    if (value < -2147483648n || value > 2147483647n) fail('evaluation_error', terms.atom('int_overflow'));
    values.push(value);
  }
  return Number(values[0]);
}

function execute(goal, machine) {
  const args = goal.kind === 'compound' ? goal.args : [];
  const values = args.map(terms.dereference);
  const unify = (first, second) => machine.trail.unify(first, second);
  const [first, second, third] = values;
  switch (goal.name) {
    case 'true': return true;
    case 'fail': case 'false': return false;
    case '=': return unify(args[0], args[1]);
    case '\\=': {
      const mark = machine.trail.mark();
      const result = unify(args[0], args[1]);
      machine.trail.undo(mark);
      return !result;
    }
    case '==': return identical(args[0], args[1]);
    case '\\==': return !identical(args[0], args[1]);
    case 'var': return first.kind === 'variable';
    case 'nonvar': return first.kind !== 'variable';
    case 'atom': return first.kind === 'atom';
    case 'number': case 'integer': return first.kind === 'integer';
    case 'atomic': return first.kind === 'atom' || first.kind === 'integer';
    case 'compound': return first.kind === 'compound';
    case 'callable': return terms.callable(first);
    case 'is_list': return terms.listParts(first).proper;
    case 'is': return unify(args[0], terms.integer(evaluate(args[1])));
    case '=:=': case '=\\=': case '<': case '>': case '=<': case '>=': {
      const left = evaluate(args[0]);
      const right = evaluate(args[1]);
      if (goal.name === '=:=') return left === right;
      if (goal.name === '=\\=') return left !== right;
      if (goal.name === '<') return left < right;
      if (goal.name === '>') return left > right;
      if (goal.name === '=<') return left <= right;
      return left >= right;
    }
    case 'functor': {
      if (first.kind !== 'variable') {
        const name = first.kind === 'compound' ? terms.atom(first.name) : first;
        return unify(args[1], name) && unify(args[2], terms.integer(terms.arity(first)));
      }
      if (second.kind === 'variable' || third.kind === 'variable') fail('instantiation_error');
      if (second.kind === 'compound') fail('type_error', terms.atom('atomic'), second);
      if (third.kind !== 'integer') fail('type_error', terms.atom('integer'), third);
      if (third.value < 0) fail('domain_error', terms.atom('not_less_than_zero'), third);
      if (third.value > 255) fail('representation_error', terms.atom('max_arity'));
      if (third.value === 0) return unify(args[0], args[1]);
      if (second.kind === 'integer') fail('type_error', terms.atom('atom'), second);
      return unify(args[0], terms.compound(second.name, Array.from({length: third.value}, () => terms.variable())));
    }
    case 'arg':
      if (first.kind === 'variable' || second.kind === 'variable') fail('instantiation_error');
      if (first.kind !== 'integer') fail('type_error', terms.atom('integer'), first);
      if (second.kind !== 'compound') fail('type_error', terms.atom('compound'), second);
      return first.value >= 1 && first.value <= second.args.length && unify(second.args[first.value - 1], args[2]);
    case '=..': {
      if (first.kind !== 'variable') {
        const elements = first.kind === 'compound' ? [terms.atom(first.name), ...first.args] : [first];
        return unify(terms.list(elements), args[1]);
      }
      const elements = checkList(args[1]);
      if (elements.length === 0) fail('domain_error', terms.atom('non_empty_list'), terms.empty);
      const head = terms.dereference(elements[0]);
      if (head.kind === 'variable') fail('instantiation_error');
      if (elements.length === 1) {
        if (head.kind === 'compound') fail('type_error', terms.atom('atomic'), head);
        return unify(args[0], head);
      }
      if (head.kind !== 'atom') fail('type_error', terms.atom('atom'), head);
      if (elements.length - 1 > 255) fail('representation_error', terms.atom('max_arity'));
      return unify(args[0], terms.compound(head.name, elements.slice(1)));
    }
    case 'copy_term': return unify(terms.copy(args[0]), args[1]);
    case 'atom_length': {
      const name = checkAtom(args[0]);
      if (second.kind !== 'variable' && second.kind !== 'integer') fail('type_error', terms.atom('integer'), second);
      return unify(terms.integer(name.length), args[1]);
    }
    case 'atom_chars': {
      if (first.kind !== 'variable') {
        const name = checkAtom(args[0]);
        return unify(args[1], terms.list(Array.from(name, character => terms.atom(character))));
      }
      const elements = checkList(args[1]);
      let name = '';
      for (const element of elements) {
        const value = terms.dereference(element);
        if (value.kind === 'variable') fail('instantiation_error');
        if (value.kind !== 'atom' || value.name.length !== 1) fail('type_error', terms.atom('character'), value);
        name += value.name;
      }
      return unify(args[0], terms.atom(name));
    }
    case 'write': case 'writeq': machine.write(args[0], goal.name === 'writeq'); return true;
    case 'nl': machine.output.push('\n'); return true;
  }
}

module.exports = {indicators, keys, BuiltinError, fail, checkInteger, checkAtom, checkList, evaluate, execute};
