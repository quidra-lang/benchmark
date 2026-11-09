'use strict';

function integer(value) { return {kind: 'integer', value}; }
function atom(name) { return {kind: 'atom', name}; }
function variable() { return {kind: 'variable', binding: null}; }
function compound(name, args) { return {kind: 'compound', name, args}; }
const empty = atom('[]');

function dereference(term) {
  while (term.kind === 'variable' && term.binding !== null) term = term.binding;
  return term;
}

function callable(term) {
  term = dereference(term);
  return term.kind === 'atom' || term.kind === 'compound';
}

function arity(term) {
  term = dereference(term);
  return term.kind === 'compound' ? term.args.length : 0;
}

function key(name, count) { return JSON.stringify([name, count]); }
function predicateKey(term) { term = dereference(term); return key(term.name, arity(term)); }
function indicator(name, count) { return compound('/', [atom(name), integer(count)]); }
function predicateIndicator(term) { term = dereference(term); return indicator(term.name, arity(term)); }
function form(name, ...args) { return args.length === 0 ? atom(name) : compound(name, args); }
function error(formal, name, count) { return compound('error', [formal, indicator(name, count)]); }

function list(elements, tail = empty) {
  for (let index = elements.length - 1; index >= 0; index--) tail = compound('.', [elements[index], tail]);
  return tail;
}

function listParts(term) {
  const elements = [];
  term = dereference(term);
  while (term.kind === 'compound' && term.name === '.' && term.args.length === 2) {
    elements.push(term.args[0]);
    term = dereference(term.args[1]);
  }
  return {elements, tail: term, proper: term.kind === 'atom' && term.name === '[]'};
}

function copy(term, variables = new Map(), compounds = new Map()) {
  term = dereference(term);
  if (term.kind === 'variable') {
    if (!variables.has(term)) variables.set(term, variable());
    return variables.get(term);
  }
  if (term.kind !== 'compound') return term;
  if (compounds.has(term)) return compounds.get(term);
  const result = compound(term.name, []);
  compounds.set(term, result);
  result.args = term.args.map(argument => copy(argument, variables, compounds));
  return result;
}

function* variables(term) {
  const pending = [term];
  while (pending.length > 0) {
    const current = dereference(pending.pop());
    if (current.kind === 'variable') yield current;
    else if (current.kind === 'compound') {
      for (let index = current.args.length - 1; index >= 0; index--) pending.push(current.args[index]);
    }
  }
}

module.exports = {integer, atom, variable, compound, empty, dereference, callable, arity, key,
  predicateKey, indicator, predicateIndicator, form, error, list, listParts, copy, variables};
