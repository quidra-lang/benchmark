import * as types from './unifier.ts';
import type {Position} from './lexer.ts';
import type {Binding} from './parser.ts';

type Node = {kind: string; position: Position; [key: string]: any};
type BindingGroup = {bindings: Binding[]; recursive: boolean};

class InferenceError extends Error {
  [key: string]: any;
  declare position: Position;
  declare reason: string;
  constructor(reason: string, position: Position, details: Record<string, unknown> = {}) {
    super(reason);
    Object.assign(this, {reason, position}, details);
  }
}

function check(expected: types.Type, found: types.Type, position: Position): void {
  const failure = types.unify(expected, found);
  if (failure !== null) throw new InferenceError('check', position, {expected, found, failure});
}

function operatorType(operator: string): [types.Type, types.Type, types.Type] {
  if (['+', '-', '*', '/', 'mod'].includes(operator)) return [types.integer, types.integer, types.integer];
  if (operator === '^') return [types.string, types.string, types.string];
  if (operator === '&&' || operator === '||') return [types.boolean, types.boolean, types.boolean];
  const variable = types.fresh();
  if (operator === '::') return [variable, types.list(variable), types.list(variable)];
  return [variable, variable, types.boolean];
}

class Inferencer {
  declare locals: Binding[];
  constructor() { this.locals = []; }

  expression(expression: Node, environment: Map<string, types.Scheme>): types.Type {
    let type;
    switch (expression.kind) {
      case 'int': type = types.integer; break;
      case 'string': type = types.string; break;
      case 'bool': type = types.boolean; break;
      case 'name': {
        const scheme = environment.get(expression.name);
        if (scheme === undefined) throw new InferenceError('unbound', expression.position,
          {name: expression.name, candidates: [...environment.keys()]});
        type = types.instantiate(scheme);
        break;
      }
      case 'fun': {
        const parameter = types.fresh();
        const scope = new Map(environment);
        if (expression.parameter.name !== '_') scope.set(expression.parameter.name, types.monomorphic(parameter));
        type = types.fn(parameter, this.expression(expression.body, scope));
        break;
      }
      case 'application': {
        let callable = types.resolve(this.expression(expression.fn, environment));
        if (callable.kind === 'var') {
          const functionType = types.fn(types.fresh(), types.fresh());
          callable.bound = functionType;
          callable = functionType;
        }
        if (callable.kind !== 'function') throw new InferenceError('function', expression.fn.position, {found: callable});
        check(callable.args[0], this.expression(expression.argument, environment), expression.argument.position);
        type = callable.args[1];
        break;
      }
      case 'binary': {
        const [first, second, result] = operatorType(expression.operator);
        check(first, this.expression(expression.left, environment), expression.left.position);
        check(second, this.expression(expression.right, environment), expression.right.position);
        type = result;
        break;
      }
      case 'unary':
        check(types.integer, this.expression(expression.expression, environment), expression.expression.position);
        type = types.integer;
        break;
      case 'if': {
        check(types.boolean, this.expression(expression.condition, environment), expression.condition.position);
        const yes = this.expression(expression.yes, environment);
        const no = this.expression(expression.no, environment);
        check(yes, no, expression.no.position);
        type = yes;
        break;
      }
      case 'pair': {
        const first = this.expression(expression.first, environment);
        const second = this.expression(expression.second, environment);
        type = types.pair(first, second);
        break;
      }
      case 'list': {
        const element = types.fresh();
        for (const value of expression.elements) check(element, this.expression(value, environment), value.position);
        type = types.list(element);
        break;
      }
      case 'match': {
        const matched = this.expression(expression.matched, environment);
        const result = types.fresh();
        for (const arm of expression.arms) {
          const bindings = new Map();
          const pattern = this.pattern(arm.pattern, bindings);
          check(matched, pattern, arm.pattern.position);
          const scope = new Map(environment);
          for (const [name, value] of bindings) scope.set(name, types.monomorphic(value));
          check(result, this.expression(arm.expression, scope), arm.expression.position);
        }
        type = result;
        break;
      }
      case 'let': type = this.expression(expression.body, this.group(expression.group, environment, false)); break;
    }
    expression.type = type;
    return type;
  }

  pattern(pattern: Node, bindings: Map<string, types.Type>): types.Type {
    let type;
    switch (pattern.kind) {
      case 'wildcard': type = types.fresh(); break;
      case 'name':
        if (bindings.has(pattern.name)) throw new InferenceError('patternDuplicate', pattern.position, {name: pattern.name});
        type = types.fresh();
        bindings.set(pattern.name, type);
        break;
      case 'int': type = types.integer; break;
      case 'string': type = types.string; break;
      case 'bool': type = types.boolean; break;
      case 'pair': {
        const first = this.pattern(pattern.first, bindings);
        const second = this.pattern(pattern.second, bindings);
        type = types.pair(first, second);
        break;
      }
      case 'cons': {
        const element = types.fresh();
        check(element, this.pattern(pattern.first, bindings), pattern.first.position);
        const list = types.list(element);
        check(list, this.pattern(pattern.second, bindings), pattern.second.position);
        type = list;
        break;
      }
      case 'list': {
        const element = types.fresh();
        for (const value of pattern.elements) check(element, this.pattern(value, bindings), value.position);
        type = types.list(element);
        break;
      }
    }
    pattern.type = type;
    return type;
  }

  group(group: BindingGroup, environment: Map<string, types.Scheme>, topLevel: boolean): Map<string, types.Scheme> {
    const names = new Set();
    for (const binding of group.bindings) {
      if (names.has(binding.name)) throw new InferenceError('letDuplicate', binding.position, {name: binding.name});
      names.add(binding.name);
      if (group.recursive && binding.expression.kind !== 'fun') throw new InferenceError('recFunction', binding.position, {name: binding.name});
    }
    let inferred;
    if (group.recursive) {
      inferred = group.bindings.map(() => types.fresh());
      const scope = new Map(environment);
      group.bindings.forEach((binding, i) => scope.set(binding.name, types.monomorphic(inferred[i])));
      for (let i = 0; i < group.bindings.length; i++) {
        const binding = group.bindings[i];
        check(inferred[i], this.expression(binding.expression, scope), binding.position);
      }
    } else inferred = group.bindings.map(binding => this.expression(binding.expression, environment));
    const result = new Map(environment);
    for (let i = 0; i < group.bindings.length; i++) {
      const binding = group.bindings[i];
      binding.scheme = types.generalize(inferred[i], environment);
      result.set(binding.name, binding.scheme);
      if (!topLevel) this.locals.push(binding);
    }
    return result;
  }
}

export {Inferencer, InferenceError, check};
