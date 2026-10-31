export interface TypeVariable {
  kind: 'var';
  number: number;
  bound: Type | null;
}

export interface TypeConstructor {
  kind: 'int' | 'bool' | 'string' | 'list' | 'pair' | 'function';
  args: Type[];
}

export type Type = TypeVariable | TypeConstructor;

export interface Scheme {
  type: Type;
  quantified: Set<TypeVariable>;
}

export interface UnifyFailure {
  kind: 'occurs' | 'mismatch';
  expected: Type;
  found: Type;
  component: boolean;
  variable?: TypeVariable;
  other?: Type;
}

let serial = 0;
const integer: TypeConstructor = {kind: 'int', args: []};
const boolean: TypeConstructor = {kind: 'bool', args: []};
const string: TypeConstructor = {kind: 'string', args: []};

function fresh(): TypeVariable { return {kind: 'var', number: serial++, bound: null}; }
function list(element: Type): TypeConstructor { return {kind: 'list', args: [element]}; }
function pair(first: Type, second: Type): TypeConstructor { return {kind: 'pair', args: [first, second]}; }
function fn(argument: Type, result: Type): TypeConstructor { return {kind: 'function', args: [argument, result]}; }

function resolve(type: Type): Type {
  if (type.kind !== 'var' || type.bound === null) return type;
  type.bound = resolve(type.bound);
  return type.bound;
}

function freeVariables(type: Type, result: Set<TypeVariable> = new Set()): Set<TypeVariable> {
  type = resolve(type);
  if (type.kind === 'var') result.add(type);
  else for (const argument of type.args) freeVariables(argument, result);
  return result;
}

function occurs(variable: TypeVariable, type: Type): boolean {
  type = resolve(type);
  return type === variable || (type.kind !== 'var' && type.args.some(argument => occurs(variable, argument)));
}

function unify(expected: Type, found: Type): UnifyFailure | null {
  function visit(first: Type, second: Type, component: boolean): UnifyFailure | null {
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

function monomorphic(type: Type): Scheme { return {type, quantified: new Set<TypeVariable>()}; }

function generalize(type: Type, environment: Map<string, Scheme>): Scheme {
  const free = new Set<TypeVariable>();
  for (const scheme of environment.values()) {
    for (const variable of freeVariables(scheme.type)) if (!scheme.quantified.has(variable)) free.add(variable);
  }
  const quantified = new Set<TypeVariable>([...freeVariables(type)].filter(variable => !free.has(variable)));
  return {type, quantified};
}

function instantiate(scheme: Scheme): Type {
  const replacements = new Map<TypeVariable, TypeVariable>();
  function copy(type: Type): Type {
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

export {integer, boolean, string, fresh, list, pair, fn, resolve, freeVariables,
  occurs, unify, monomorphic, generalize, instantiate};
