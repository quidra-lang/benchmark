import {punct} from './lexer.ts';
const precedence = new Map([
  ['||', 1], ['&&', 2], ['|', 3], ['^', 4], ['&', 5], ['==', 6], ['!=', 6],
  ['<', 7], ['>', 7], ['<=', 7], ['>=', 7], ['<<', 8], ['>>', 8],
  ['+', 9], ['-', 9], ['*', 10], ['/', 10], ['%', 10],
]);

function complete(generator) {
  const stack = [generator];
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

function integerConstant(spelling) {
  let digits = spelling;
  for (const suffix of ['ll', 'LL', 'l', 'L']) {
    if (digits.length > suffix.length && digits.endsWith(suffix)) {
      digits = digits.slice(0, -suffix.length);
      break;
    }
  }
  if (/^0[xX][0-9a-fA-F]+$/.test(digits)) return Number(digits);
  if (/^0[0-7]*$/.test(digits)) return Number.parseInt(digits, 8);
  if (/^[1-9][0-9]*$/.test(digits)) return Number(digits);
  throw new Error(`invalid integer constant "${spelling}"`);
}

function characterConstant(spelling) {
  const body = spelling.slice(1, -1);
  if (body.length === 1 && body !== "'" && body !== '\\') return body.charCodeAt(0);
  const escapes = new Map([['n', 10], ['t', 9], ['\\', 92], ["'", 39], ['"', 34], ['0', 0]]);
  if (body.length === 2 && body[0] === '\\' && escapes.has(body[1])) return escapes.get(body[1]);
  throw new Error(`invalid character constant ${spelling}`);
}

class Parser {
  declare index: any;
  declare tokens: any;
  constructor(tokens) {
    this.tokens = tokens;
    this.index = 0;
  }

  *expression() {
    const condition = yield this.binary(1);
    if (!punct(this.tokens[this.index], '?')) return condition;
    this.index++;
    const yes = yield this.expression();
    if (!punct(this.tokens[this.index], ':')) throw new Error("'?' without following ':'");
    this.index++;
    const no = yield this.expression();
    return {kind: 'conditional', condition, yes, no};
  }

  *binary(minimum) {
    let left = yield this.unary();
    for (;;) {
      const token = this.tokens[this.index];
      const level = token?.kind === 'punctuator' ? precedence.get(token.spelling) : undefined;
      if (level === undefined || level < minimum) return left;
      this.index++;
      const right = yield this.binary(level + 1);
      left = {kind: 'binary', operator: token.spelling, left, right};
    }
  }

  *unary() {
    const token = this.tokens[this.index];
    if (!token) throw new Error('expected value at end of expression');
    this.index++;
    if (token.kind === 'punctuator' && ['+', '-', '!', '~'].includes(token.spelling)) {
      const operand = yield this.unary();
      return {kind: 'unary', operator: token.spelling, operand};
    }
    if (token.kind === 'number') return {kind: 'constant', value: integerConstant(token.spelling)};
    if (token.kind === 'character') return {kind: 'constant', value: characterConstant(token.spelling)};
    if (token.kind === 'identifier') return {kind: 'identifier', name: token.spelling};
    if (punct(token, '(')) {
      const inside = yield this.expression();
      if (!punct(this.tokens[this.index], ')')) throw new Error("missing ')' in expression");
      this.index++;
      return inside;
    }
    throw new Error(`expected value before "${token.spelling}"`);
  }

  parse() {
    const tree = complete(this.expression());
    if (this.index < this.tokens.length) {
      throw new Error(`missing binary operator before "${this.tokens[this.index].spelling}"`);
    }
    return tree;
  }
}

function *evaluate(tree, warning) {
  if (tree.kind === 'constant') return tree.value;
  if (tree.kind === 'identifier') {
    warning(`identifier "${tree.name}" evaluates to 0`);
    return 0;
  }
  if (tree.kind === 'conditional') {
    const value = yield evaluate(tree.condition, warning);
    return yield evaluate(value !== 0 ? tree.yes : tree.no, warning);
  }
  if (tree.kind === 'unary') {
    const value = yield evaluate(tree.operand, warning);
    switch (tree.operator) {
      case '+': return value;
      case '-': return -value;
      case '!': return Number(value === 0);
      case '~': return -value - 1;
    }
  }
  const left = yield evaluate(tree.left, warning);
  if (tree.operator === '&&' && left === 0) return 0;
  if (tree.operator === '||' && left !== 0) return 1;
  const right = yield evaluate(tree.right, warning);
  switch (tree.operator) {
    case '&&': case '||': return Number(right !== 0);
    case '*': return left * right;
    case '+': return left + right;
    case '-': return left - right;
    case '/': case '%': {
      if (right === 0) throw new Error('division by zero in #if');
      const quotient = Number(BigInt(left) / BigInt(right));
      return tree.operator === '/' ? quotient : left - right * quotient;
    }
    case '<<': return left * 2 ** right;
    case '>>': return Math.floor(left / 2 ** right);
    case '&': return left & right;
    case '|': return left | right;
    case '^': return left ^ right;
    case '==': return Number(left === right);
    case '!=': return Number(left !== right);
    case '<': return Number(left < right);
    case '>': return Number(left > right);
    case '<=': return Number(left <= right);
    case '>=': return Number(left >= right);
  }
}

function expressionValue(tokens, warning) {
  return complete(evaluate(new Parser(tokens).parse(), warning));
}

export {expressionValue};
