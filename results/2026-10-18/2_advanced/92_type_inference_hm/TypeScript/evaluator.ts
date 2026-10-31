class RuntimeError extends Error {
  declare position: any;
  constructor(position, message) { super(message); this.position = position; }
}

function closure(expression, environment) {
  return {kind: 'closure', parameter: expression.parameter, body: expression.body, environment};
}

function builtin(name, apply) { return {kind: 'builtin', name, apply}; }

function integer(value, position) {
  if (value < -2147483648n || value > 2147483647n) throw new RuntimeError(position, 'integer overflow');
  return Number(value);
}

function compare(first, second, position) {
  const pending = [[first, second]];
  while (pending.length > 0) {
    const [left, right] = pending.pop();
    if (typeof left !== 'object') {
      if (left < right) return -1;
      if (left > right) return 1;
    } else if (Array.isArray(left)) {
      pending.push([left.length, right.length]);
      for (let i = Math.min(left.length, right.length) - 1; i >= 0; i--) pending.push([left[i], right[i]]);
    } else if (left.kind === 'pair') {
      pending.push([left.second, right.second], [left.first, right.first]);
    } else throw new RuntimeError(position, 'functional value compared');
  }
  return 0;
}

function binary(operator, left, right, position) {
  if (operator === '+') return integer(BigInt(left) + BigInt(right), position);
  if (operator === '-') return integer(BigInt(left) - BigInt(right), position);
  if (operator === '*') return integer(BigInt(left) * BigInt(right), position);
  if (operator === '/' || operator === 'mod') {
    if (right === 0) throw new RuntimeError(position, 'division by zero');
    return integer(operator === '/' ? BigInt(left) / BigInt(right) : BigInt(left) % BigInt(right), position);
  }
  if (operator === '^') return left + right;
  if (operator === '::') return [left, ...right];
  if (operator === '&&' || operator === '||') return right;
  const order = compare(left, right, position);
  if (operator === '=') return order === 0;
  if (operator === '<>') return order !== 0;
  if (operator === '<') return order < 0;
  if (operator === '>') return order > 0;
  if (operator === '<=') return order <= 0;
  return order >= 0;
}

function match(pattern, value) {
  const bindings = new Map();
  const pending = [[pattern, value]];
  while (pending.length > 0) {
    const [current, found] = pending.pop();
    switch (current.kind) {
      case 'wildcard': break;
      case 'name': bindings.set(current.name, found); break;
      case 'int': case 'bool': case 'string':
        if (current.value !== found) return null;
        break;
      case 'pair':
        pending.push([current.second, found.second], [current.first, found.first]);
        break;
      case 'cons':
        if (found.length === 0) return null;
        pending.push([current.second, found.slice(1)], [current.first, found[0]]);
        break;
      case 'list':
        if (current.elements.length !== found.length) return null;
        for (let i = found.length - 1; i >= 0; i--) pending.push([current.elements[i], found[i]]);
        break;
    }
  }
  return bindings;
}

function recursiveGroup(group, environment) {
  const scope = new Map(environment);
  for (const binding of group.bindings) scope.set(binding.name, closure(binding.expression, scope));
  return scope;
}

class Evaluator {
  declare calls: any;
  constructor() { this.calls = 0; }

  group(group, environment) {
    if (group.recursive) return recursiveGroup(group, environment);
    const values = group.bindings.map(binding => this.expression(binding.expression, environment));
    const scope = new Map(environment);
    group.bindings.forEach((binding, i) => scope.set(binding.name, values[i]));
    return scope;
  }

  expression(expression, environment) {
    const frames = [];
    let current = expression;
    let scope = environment;
    let evaluating = true;
    let value;
    for (;;) {
      if (evaluating) {
        switch (current.kind) {
          case 'int': case 'bool': case 'string': value = current.value; break;
          case 'name': value = scope.get(current.name); break;
          case 'fun': value = closure(current, scope); break;
          case 'application':
            frames.push({kind: 'applicationFunction', argument: current.argument, environment: scope, position: current.position});
            current = current.fn;
            continue;
          case 'binary':
            frames.push({kind: 'binaryLeft', expression: current, environment: scope});
            current = current.left;
            continue;
          case 'unary':
            frames.push({kind: 'unary', position: current.operatorPosition});
            current = current.expression;
            continue;
          case 'if':
            frames.push({kind: 'if', expression: current, environment: scope});
            current = current.condition;
            continue;
          case 'pair':
            frames.push({kind: 'pairFirst', second: current.second, environment: scope});
            current = current.first;
            continue;
          case 'list':
            if (current.elements.length === 0) { value = []; break; }
            frames.push({kind: 'list', elements: current.elements, values: [], environment: scope});
            current = current.elements[0];
            continue;
          case 'match':
            frames.push({kind: 'match', expression: current, environment: scope});
            current = current.matched;
            continue;
          case 'let':
            if (current.group.recursive) {
              scope = recursiveGroup(current.group, scope);
              current = current.body;
            } else {
              frames.push({kind: 'let', expression: current, values: [], environment: scope});
              current = current.group.bindings[0].expression;
            }
            continue;
        }
        evaluating = false;
      }
      if (frames.length === 0) return value;
      const frame = frames.pop();
      switch (frame.kind) {
        case 'applicationFunction':
          frames.push({kind: 'applicationArgument', fn: value, position: frame.position});
          current = frame.argument;
          scope = frame.environment;
          evaluating = true;
          break;
        case 'applicationArgument':
          this.calls++;
          if (frame.fn.kind === 'builtin') value = frame.fn.apply(value, frame.position);
          else {
            scope = new Map(frame.fn.environment);
            if (frame.fn.parameter.name !== '_') scope.set(frame.fn.parameter.name, value);
            current = frame.fn.body;
            evaluating = true;
          }
          break;
        case 'binaryLeft': {
          const operator = frame.expression.operator;
          if ((operator === '&&' && value === false) || (operator === '||' && value === true)) break;
          frames.push({kind: 'binaryRight', expression: frame.expression, first: value});
          current = frame.expression.right;
          scope = frame.environment;
          evaluating = true;
          break;
        }
        case 'binaryRight':
          value = binary(frame.expression.operator, frame.first, value, frame.expression.operatorPosition);
          break;
        case 'unary': value = integer(-BigInt(value), frame.position); break;
        case 'if':
          current = value ? frame.expression.yes : frame.expression.no;
          scope = frame.environment;
          evaluating = true;
          break;
        case 'pairFirst':
          frames.push({kind: 'pairSecond', first: value});
          current = frame.second;
          scope = frame.environment;
          evaluating = true;
          break;
        case 'pairSecond': value = {kind: 'pair', first: frame.first, second: value}; break;
        case 'list':
          frame.values.push(value);
          if (frame.values.length === frame.elements.length) value = frame.values;
          else {
            frames.push(frame);
            current = frame.elements[frame.values.length];
            scope = frame.environment;
            evaluating = true;
          }
          break;
        case 'match': {
          let selected = null;
          for (const arm of frame.expression.arms) {
            const bindings = match(arm.pattern, value);
            if (bindings !== null) { selected = {arm, bindings}; break; }
          }
          if (selected === null) throw new RuntimeError(frame.expression.position, 'match failure');
          scope = new Map(frame.environment);
          for (const [name, found] of selected.bindings) scope.set(name, found);
          current = selected.arm.expression;
          evaluating = true;
          break;
        }
        case 'let': {
          frame.values.push(value);
          const bindings = frame.expression.group.bindings;
          if (frame.values.length < bindings.length) {
            frames.push(frame);
            current = bindings[frame.values.length].expression;
            scope = frame.environment;
          } else {
            scope = new Map(frame.environment);
            bindings.forEach((binding, i) => scope.set(binding.name, frame.values[i]));
            current = frame.expression.body;
          }
          evaluating = true;
          break;
        }
      }
    }
  }
}

export {RuntimeError, Evaluator, builtin};
