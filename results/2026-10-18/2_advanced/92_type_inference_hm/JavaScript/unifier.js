'use strict';

let serial = 0;
const integer = {kind: 'int', args: []};
const boolean = {kind: 'bool', args: []};
const string = {kind: 'string', args: []};

function fresh() { return {kind: 'var', number: serial++, bound: null}; }
function list(element) { return {kind: 'list', args: [element]}; }
function pair(first, second) { return {kind: 'pair', args: [first, second]}; }
function fn(argument, result) { return {kind: 'function', args: [argument, result]}; }

function resolve(type) {
  if (type.kind !== 'var' || type.bound === null) return type;
  type.bound = resolve(type.bound);
  return type.bound;
}

function freeVariables(type, result = new Set()) {
  type = resolve(type);
  if (type.kind === 'var') result.add(type);
  else for (const argument of type.args) freeVariables(argument, result);
  return result;
}

function occurs(variable, type) {
  type = resolve(type);
  return type === variable || (type.kind !== 'var' && type.args.some(argument => occurs(variable, argument)));
}

function unify(expected, found) {
  function visit(first, second, component) {
    first = resolve(first);
    second = resolve(second);
    if (first === second) return null;
    if (first.kind === 'var') {
      if (occurs(first, second)) return {kind: 'occurs', variable: first, other: second, expected: first, found: second, component};
      first.bound = second;
      return null;
    }
    if (second.kind === 'var') {
      if (occurs(second, first)) return {kind: 'occurs', variable: second, other: first, expected: first, found: second, component};
      second.bound = first;
      return null;
    }
    if (first.kind !== second.kind) return {kind: 'mismatch', expected: first, found: second, component};
    for (let i = 0; i < first.args.length; i++) {
      const failure = visit(first.args[i], second.args[i], true);
      if (failure !== null) return failure;
    }
    return null;
  }
  return visit(expected, found, false);
}

function monomorphic(type) { return {type, quantified: new Set()}; }

function generalize(type, environment) {
  const free = new Set();
  for (const scheme of environment.values()) {
    for (const variable of freeVariables(scheme.type)) if (!scheme.quantified.has(variable)) free.add(variable);
  }
  const quantified = new Set([...freeVariables(type)].filter(variable => !free.has(variable)));
  return {type, quantified};
}

function instantiate(scheme) {
  const replacements = new Map();
  function copy(type) {
    type = resolve(type);
    if (type.kind === 'var') {
      if (!scheme.quantified.has(type)) return type;
      if (!replacements.has(type)) replacements.set(type, fresh());
      return replacements.get(type);
    }
    return {kind: type.kind, args: type.args.map(copy)};
  }
  return copy(scheme.type);
}

module.exports = {integer, boolean, string, fresh, list, pair, fn, resolve, freeVariables,
  occurs, unify, monomorphic, generalize, instantiate};
