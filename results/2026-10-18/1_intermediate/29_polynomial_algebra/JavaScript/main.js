import { readFileSync } from 'node:fs';

class CalculatorError extends Error {}
const fail = message => { throw new CalculatorError(message); };
const abs = value => value < 0n ? -value : value;
function gcd(a, b) {
  for (a = abs(a), b = abs(b); b !== 0n;) [a, b] = [b, a % b];
  return a;
}

class Fraction {
  constructor(numerator, denominator = 1n) {
    if (denominator < 0n) { numerator = -numerator; denominator = -denominator; }
    const divisor = gcd(numerator, denominator);
    this.n = numerator / divisor;
    this.d = denominator / divisor;
  }
  static parse(word) {
    const [numerator, denominator = '1'] = word.split('/');
    if (BigInt(denominator) === 0n) fail('ZERO DENOMINATOR');
    return new Fraction(BigInt(numerator), BigInt(denominator));
  }
  add(other) { return new Fraction(this.n * other.d + other.n * this.d, this.d * other.d); }
  sub(other) { return new Fraction(this.n * other.d - other.n * this.d, this.d * other.d); }
  mul(other) { return new Fraction(this.n * other.n, this.d * other.d); }
  div(other) { return new Fraction(this.n * other.d, this.d * other.n); }
  neg() { return new Fraction(-this.n, this.d); }
  abs() { return this.n < 0n ? this.neg() : this; }
  compare(other) {
    const left = this.n * other.d, right = other.n * this.d;
    return left < right ? -1 : left > right ? 1 : 0;
  }
  pow(exponent) {
    let result = ONE;
    for (let i = 0; i < exponent; i++) result = result.mul(this);
    return result;
  }
  toString() { return this.d === 1n ? String(this.n) : `${this.n}/${this.d}`; }
}

const integer = value => new Fraction(BigInt(value));
const ZERO = integer(0), ONE = integer(1), TWO = integer(2);

class Polynomial {
  constructor(coefficients = []) {
    this.coefficients = coefficients.slice();
    while (this.coefficients.length && this.coefficients.at(-1).n === 0n) this.coefficients.pop();
  }
  static constant(value) { return new Polynomial([value]); }
  get degree() { return this.coefficients.length - 1; }
  get zero() { return this.degree < 0; }
  get leading() { return this.coefficients.at(-1); }
  coefficient(index) { return this.coefficients[index] ?? ZERO; }
  add(other) {
    return new Polynomial(Array.from({ length: Math.max(this.degree, other.degree) + 1 },
      (_, i) => this.coefficient(i).add(other.coefficient(i))));
  }
  sub(other) {
    return new Polynomial(Array.from({ length: Math.max(this.degree, other.degree) + 1 },
      (_, i) => this.coefficient(i).sub(other.coefficient(i))));
  }
  scale(value) { return new Polynomial(this.coefficients.map(coefficient => coefficient.mul(value))); }
  divideScalar(value) { return new Polynomial(this.coefficients.map(coefficient => coefficient.div(value))); }
  neg() { return new Polynomial(this.coefficients.map(coefficient => coefficient.neg())); }
  mul(other) {
    if (this.zero || other.zero) return new Polynomial();
    const result = Array(this.degree + other.degree + 1).fill(ZERO);
    for (let i = 0; i <= this.degree; i++) {
      for (let j = 0; j <= other.degree; j++) {
        result[i + j] = result[i + j].add(this.coefficients[i].mul(other.coefficients[j]));
      }
    }
    return new Polynomial(result);
  }
  pow(exponent) {
    if (exponent === 0) return UNIT;
    if (this.zero) return this;
    if (this.degree === 0 && this.leading.d === 1n && abs(this.leading.n) === 1n) {
      return Polynomial.constant(this.leading.n < 0n && exponent % 2 ? integer(-1) : ONE);
    }
    let result = UNIT;
    for (let i = 0; i < exponent; i++) result = result.mul(this);
    return result;
  }
  divide(other) {
    const remainder = this.coefficients.slice();
    const quotient = Array(Math.max(0, this.degree - other.degree + 1)).fill(ZERO);
    while (remainder.length && remainder.length >= other.coefficients.length) {
      const value = remainder.at(-1).div(other.leading);
      const shift = remainder.length - other.coefficients.length;
      quotient[shift] = value;
      for (let j = 0; j <= other.degree; j++) {
        remainder[shift + j] = remainder[shift + j].sub(value.mul(other.coefficients[j]));
      }
      while (remainder.length && remainder.at(-1).n === 0n) remainder.pop();
    }
    return [new Polynomial(quotient), new Polynomial(remainder)];
  }
  mod(other) { return this.divide(other)[1]; }
  monic() { return this.zero ? this : this.divideScalar(this.leading); }
  derivative(count = 1) {
    let result = this;
    for (let repetition = 0; repetition < count && !result.zero; repetition++) {
      result = new Polynomial(result.coefficients.slice(1).map((coefficient, i) => integer(i + 1).mul(coefficient)));
    }
    return result;
  }
  integral() {
    return new Polynomial([ZERO, ...this.coefficients.map((coefficient, i) => coefficient.div(integer(i + 1)))]);
  }
  evaluate(value) {
    let result = ZERO;
    for (let i = this.degree; i >= 0; i--) result = result.mul(value).add(this.coefficients[i]);
    return result;
  }
  compose(other) {
    let result = new Polynomial();
    for (let i = this.degree; i >= 0; i--) result = result.mul(other).add(Polynomial.constant(this.coefficients[i]));
    return result;
  }
  content() {
    let multiple = 1n, divisor = 0n;
    for (const coefficient of this.coefficients) {
      multiple = multiple * coefficient.d / gcd(multiple, coefficient.d);
      divisor = gcd(divisor, coefficient.n);
    }
    return new Fraction(this.leading.n < 0n ? -divisor : divisor, multiple);
  }
  primitive() { return this.divideScalar(this.content()); }
  notation(variable = 'x') {
    let result = '';
    for (let i = this.degree; i >= 0; i--) {
      const coefficient = this.coefficients[i];
      if (coefficient.n === 0n) continue;
      result += result === '' ? (coefficient.n < 0n ? '-' : '') : (coefficient.n < 0n ? ' - ' : ' + ');
      const magnitude = coefficient.abs();
      if (i === 0 || magnitude.compare(ONE) !== 0) result += magnitude;
      if (i > 0) result += variable + (i === 1 ? '' : `^${i}`);
    }
    return result || '0';
  }
}

const UNIT = Polynomial.constant(ONE), X = new Polynomial([ZERO, ONE]);
const linear = (constant, slope = ONE) => new Polynomial([constant, slope]);
const degreeLimit = condition => { if (condition) fail('DEGREE LIMIT'); };
const productLimit = (a, b) => degreeLimit(!a.zero && !b.zero && a.degree + b.degree > 30);
const compositionLimit = (a, b) => degreeLimit(a.degree >= 1 && b.degree >= 1 && a.degree * b.degree > 30);
const requireNonzero = polynomial => { if (polynomial.zero) fail('ZERO POLYNOMIAL'); };
const isOne = polynomial => polynomial.degree === 0 && polynomial.leading.compare(ONE) === 0;

function polynomialGcd(a, b) {
  while (!b.zero) [a, b] = [b, a.mod(b)];
  return a.monic();
}

function extendedGcd(a, b) {
  let s0 = UNIT, s1 = new Polynomial(), t0 = new Polynomial(), t1 = UNIT;
  while (!b.zero) {
    const [quotient, remainder] = a.divide(b);
    [a, b] = [b, remainder];
    [s0, s1] = [s1, s0.sub(quotient.mul(s1))];
    [t0, t1] = [t1, t0.sub(quotient.mul(t1))];
  }
  return a.zero ? [a, s0, t0] : [a.monic(), s0.divideScalar(a.leading), t0.divideScalar(a.leading)];
}

function divisors(number) {
  const result = [];
  for (let divisor = 1n; divisor * divisor <= number; divisor++) {
    if (number % divisor !== 0n) continue;
    result.push(divisor);
    if (divisor * divisor !== number) result.push(number / divisor);
  }
  return result;
}

function rationalRoots(a) {
  let remaining = a.primitive(), zeros = 0;
  while (remaining.coefficient(0).n === 0n) {
    remaining = new Polynomial(remaining.coefficients.slice(1));
    zeros++;
  }
  const candidates = [];
  for (const numerator of divisors(abs(remaining.coefficient(0).n))) {
    for (const denominator of divisors(remaining.leading.n)) {
      if (gcd(numerator, denominator) === 1n) {
        const root = new Fraction(numerator, denominator);
        candidates.push(root, root.neg());
      }
    }
  }
  candidates.sort((a, b) => a.compare(b));
  const roots = [];
  for (const root of candidates) {
    let multiplicity = 0;
    const factor = linear(new Fraction(-root.n), new Fraction(root.d));
    while (remaining.degree >= 1 && remaining.evaluate(root).n === 0n) {
      remaining = remaining.divide(factor)[0];
      multiplicity++;
    }
    if (multiplicity) roots.push({ root, multiplicity });
  }
  if (zeros) roots.push({ root: ZERO, multiplicity: zeros });
  roots.sort((a, b) => a.root.compare(b.root));
  return { roots, remaining };
}

function squareFreePart(a) {
  return a.degree < 1 ? a : a.divide(polynomialGcd(a, a.derivative()))[0];
}

function sturmSequence(a) {
  const first = squareFreePart(a), sequence = [first];
  let previous = first, current = first.derivative();
  while (!current.zero) {
    sequence.push(current);
    [previous, current] = [current, previous.mod(current).neg()];
  }
  return sequence;
}

function signChanges(signs) {
  let previous = 0, changes = 0;
  for (const sign of signs) {
    if (sign === 0) continue;
    if (previous !== 0 && previous !== sign) changes++;
    previous = sign;
  }
  return changes;
}

function variations(sequence, endpoint) {
  return signChanges(sequence.map(polynomial => {
    if (endpoint === 'inf') return polynomial.leading.compare(ZERO);
    if (endpoint === '-inf') return polynomial.leading.compare(ZERO) * (polynomial.degree % 2 ? -1 : 1);
    return polynomial.evaluate(endpoint).compare(ZERO);
  }));
}

function compareEndpoints(a, b) {
  if (a === b) return 0;
  if (a === '-inf' || b === 'inf') return -1;
  if (a === 'inf' || b === '-inf') return 1;
  return a.compare(b);
}

function isolate(a, precision) {
  const sequence = sturmSequence(a), first = sequence[0];
  let maximum = ZERO;
  for (let i = 0; i < first.degree; i++) {
    const ratio = first.coefficients[i].div(first.leading).abs();
    if (ratio.compare(maximum) > 0) maximum = ratio;
  }
  const bound = ONE.add(maximum), width = new Fraction(1n, 1n << BigInt(precision)), intervals = [];
  const count = (left, right) => variations(sequence, left) - variations(sequence, right);
  function examine(left, right) {
    const roots = count(left, right);
    if (roots >= 2) {
      const middle = left.add(right).div(TWO);
      examine(left, middle);
      examine(middle, right);
    } else if (roots === 1) {
      while (right.sub(left).compare(width) > 0) {
        const middle = left.add(right).div(TWO);
        if (count(left, middle) >= 1) right = middle;
        else left = middle;
      }
      intervals.push(`(${left}, ${right}]`);
    }
  }
  examine(bound.neg(), bound);
  return intervals;
}

function resultant(a, b) {
  let result = ONE;
  while (b.degree >= 1) {
    const remainder = a.mod(b);
    if (remainder.zero) return ZERO;
    result = result.mul(b.leading.pow(a.degree - remainder.degree));
    if (a.degree * b.degree % 2) result = result.neg();
    [a, b] = [b, remainder];
  }
  return result.mul(b.coefficient(0).pow(a.degree));
}

function interpolate(values) {
  const xs = values.filter((_, i) => i % 2 === 0), differences = values.filter((_, i) => i % 2 === 1);
  for (let j = 1; j < xs.length; j++) {
    if (xs.slice(0, j).some(x => x.compare(xs[j]) === 0)) fail(`DUPLICATE X ${xs[j]}`);
  }
  for (let j = 1; j < xs.length; j++) {
    for (let i = xs.length - 1; i >= j; i--) {
      differences[i] = differences[i].sub(differences[i - 1]).div(xs[i].sub(xs[i - j]));
    }
  }
  let result = new Polynomial();
  for (let i = xs.length - 1; i >= 0; i--) result = result.mul(linear(xs[i].neg())).add(Polynomial.constant(differences[i]));
  return result;
}

function special(kind, order) {
  if (!['chebyshev', 'chebyshev2', 'legendre', 'hermite', 'laguerre'].includes(kind)) fail(`UNKNOWN KIND ${kind}`);
  degreeLimit(order > 30);
  if (order === 0) return UNIT;
  let previous = UNIT;
  let current = kind === 'laguerre' ? linear(ONE, integer(-1))
    : kind === 'chebyshev2' || kind === 'hermite' ? X.scale(TWO) : X;
  for (let j = 1; j < order; j++) {
    let next;
    if (kind === 'chebyshev' || kind === 'chebyshev2') next = X.scale(TWO).mul(current).sub(previous);
    else if (kind === 'hermite') next = X.scale(TWO).mul(current).sub(previous.scale(integer(2 * j)));
    else {
      const multiplier = kind === 'legendre' ? X.scale(integer(2 * j + 1)) : linear(integer(2 * j + 1), integer(-1));
      next = multiplier.mul(current).sub(previous.scale(integer(j))).scale(new Fraction(1n, BigInt(j + 1)));
    }
    [previous, current] = [current, next];
  }
  return current;
}

// Build a complete syntax tree before looking up names or performing arithmetic.
class ExpressionParser {
  constructor(source) {
    this.tokens = [];
    const pattern = /[0-9]+|[A-Z][A-Z0-9]*|[^ ]/g;
    for (const match of source.matchAll(pattern)) {
      const word = match[0];
      const kind = /^[0-9]/.test(word) ? 'number' : /^[A-Z]/.test(word) ? 'name' : word;
      this.tokens.push({ kind, word, position: match.index + 1 });
    }
    this.tokens.push({ kind: 'end' });
    this.position = 0;
  }
  get token() { return this.tokens[this.position]; }
  take(kind) {
    if (this.token.kind !== kind) return false;
    this.position++;
    return true;
  }
  syntaxError() { fail(`SYNTAX AT ${this.token.kind === 'end' ? 'END' : this.token.position}`); }
  expect(kind) { if (!this.take(kind)) this.syntaxError(); }
  parse() {
    const result = this.expression();
    if (this.token.kind !== 'end') this.syntaxError();
    return result;
  }
  expression() {
    const negative = this.take('-');
    let result = this.term();
    if (negative) result = { kind: 'neg', operand: result };
    while (this.token.kind === '+' || this.token.kind === '-') {
      const kind = this.token.kind;
      this.position++;
      result = { kind, left: result, right: this.term() };
    }
    return result;
  }
  term() {
    let result = this.factor();
    while (['*', '/', 'x', 'name', '('].includes(this.token.kind)) {
      let kind = '*';
      if (this.token.kind === '*' || this.token.kind === '/') {
        kind = this.token.kind;
        this.position++;
      }
      result = { kind, left: result, right: this.factor() };
    }
    return result;
  }
  factor() {
    let result = this.primary();
    if (this.take('^')) {
      if (this.token.kind !== 'number') this.syntaxError();
      const exponent = Number(this.token.word);
      this.position++;
      result = { kind: 'pow', operand: result, exponent };
    }
    return result;
  }
  primary() {
    const token = this.token;
    if (this.take('number')) return { kind: 'number', value: new Fraction(BigInt(token.word)) };
    if (this.take('x')) return { kind: 'x' };
    if (this.take('name')) {
      let derivatives = 0;
      while (this.take("'")) derivatives++;
      const reference = { kind: 'name', name: token.word, derivatives };
      if (!this.take('(')) return reference;
      const argument = this.expression();
      this.expect(')');
      return { kind: 'call', left: reference, right: argument };
    }
    if (this.take('(')) {
      const result = this.expression();
      this.expect(')');
      return result;
    }
    return this.syntaxError();
  }
}

function evaluateExpression(node, lookup) {
  if (node.kind === 'number') return Polynomial.constant(node.value);
  if (node.kind === 'x') return X;
  if (node.kind === 'name') return lookup(node.name).derivative(node.derivatives);
  if (node.kind === 'neg') return evaluateExpression(node.operand, lookup).neg();
  if (node.kind === 'pow') {
    const value = evaluateExpression(node.operand, lookup);
    degreeLimit(!value.zero && value.degree * node.exponent > 30);
    return value.pow(node.exponent);
  }
  const left = evaluateExpression(node.left, lookup), right = evaluateExpression(node.right, lookup);
  if (node.kind === '+') return left.add(right);
  if (node.kind === '-') return left.sub(right);
  if (node.kind === '*') { productLimit(left, right); return left.mul(right); }
  if (node.kind === 'call') { compositionLimit(left, right); return left.compose(right); }
  if (right.zero) fail('DIVISION BY ZERO');
  if (right.degree > 0) fail('NONCONSTANT DIVISOR');
  return left.divideScalar(right.leading);
}

const REFERENCES = {
  PRINT: [1], DELETE: [1], DEGREE: [1], ADD: [2, 3], SUB: [2, 3], MUL: [2, 3], POW: [2],
  DIV: [3, 4], GCD: [2, 3], XGCD: [4, 5], LCM: [2, 3], INVMOD: [2, 3], CRT: [2, 3, 4, 5],
  MODPOW: [2, 4], DERIV: [2], INTEG: [2], AREA: [1], TANGENT: [2], TAYLOR: [1], COMPOSE: [2, 3],
  EVAL: [1], ROOTS: [1], FACTOR: [1], SQFREE: [1], DESCARTES: [1], STURM: [1], ISOLATE: [1],
  RESULTANT: [1, 2], DISCRIM: [1], POWERSUM: [1],
};

class Calculator {
  polynomials = new Map();

  lookup(name) {
    const polynomial = this.polynomials.get(name);
    if (polynomial === undefined) fail(`UNKNOWN ${name}`);
    return polynomial;
  }

  execute(source) {
    const words = source.split(' '), command = words[0], name = words[1];
    const pending = [], output = [];
    const store = (name, polynomial) => {
      pending.push([name, polynomial]);
      output.push(`${name} = ${polynomial.notation()}`);
    };
    if (command === 'DEF') {
      const expression = source.slice(command.length + name.length + 2);
      const syntax = new ExpressionParser(expression).parse();
      store(name, evaluateExpression(syntax, name => this.lookup(name)));
    } else {
      if (command === 'DIV' && words[1] === words[2]
          || command === 'XGCD' && new Set(words.slice(1, 4)).size < 3) fail('SAME NAME');
      const [a, b, c, d] = (REFERENCES[command] ?? []).map(index => this.lookup(words[index]));
      let literalWords = [];
      if (command === 'AREA' || command === 'STURM') literalWords = words.slice(2, 4);
      else if (command === 'TANGENT') literalWords = words.slice(3, 4);
      else if (command === 'TAYLOR') literalWords = words.slice(2, 3);
      else if (command === 'EVAL' || command === 'INTERP') literalWords = words.slice(2);
      const values = literalWords.map(word => word === '-inf' || word === 'inf' ? word : Fraction.parse(word));
      switch (command) {
        case 'PRINT': output.push(`${name} = ${a.notation()}`); break;
        case 'DELETE': this.polynomials.delete(name); output.push(`deleted ${name}`); break;
        case 'LIST':
          for (const name of [...this.polynomials.keys()].sort()) output.push(`${name} = ${this.lookup(name).notation()}`);
          if (output.length === 0) output.push('no polynomials');
          break;
        case 'DEGREE': output.push(`deg(${name}) = ${a.zero ? '-inf' : a.degree}`); break;
        case 'ADD': store(name, a.add(b)); break;
        case 'SUB': store(name, a.sub(b)); break;
        case 'MUL': productLimit(a, b); store(name, a.mul(b)); break;
        case 'POW': {
          const exponent = Number(words[3]);
          degreeLimit(!a.zero && a.degree * exponent > 30);
          store(name, a.pow(exponent));
          break;
        }
        case 'DIV': {
          if (b.zero) fail('DIVISION BY ZERO');
          const [quotient, remainder] = a.divide(b);
          store(name, quotient); store(words[2], remainder);
          break;
        }
        case 'GCD': store(name, polynomialGcd(a, b)); break;
        case 'XGCD': extendedGcd(a, b).forEach((value, i) => store(words[i + 1], value)); break;
        case 'LCM': {
          if (a.zero || b.zero) store(name, new Polynomial());
          else {
            const common = polynomialGcd(a, b);
            degreeLimit(a.degree + b.degree - common.degree > 30);
            store(name, a.divide(common)[0].mul(b).monic());
          }
          break;
        }
        case 'INVMOD': {
          if (b.zero) fail('DIVISION BY ZERO');
          if (b.degree === 0) fail('DEGREE TOO LOW');
          const [common, inverse] = extendedGcd(a, b);
          if (!isOne(common)) fail('NOT COPRIME');
          store(name, inverse.mod(b));
          break;
        }
        case 'CRT': {
          if (b.zero || d.zero) fail('DIVISION BY ZERO');
          degreeLimit(b.degree + d.degree > 30);
          const [common, inverse] = extendedGcd(b, d);
          if (!isOne(common)) fail('NOT COPRIME');
          const first = a.mod(b), second = c.mod(d), correction = second.sub(first).mul(inverse).mod(d);
          store(name, first.add(b.mul(correction)));
          break;
        }
        case 'MODPOW': {
          if (b.zero) fail('DIVISION BY ZERO');
          degreeLimit(2 * b.degree - 2 > 30);
          let result = UNIT.mod(b), base = a.mod(b), exponent = Number(words[3]);
          while (exponent > 0) {
            if (exponent % 2) result = result.mul(base).mod(b);
            exponent = Math.floor(exponent / 2);
            if (exponent) base = base.mul(base).mod(b);
          }
          store(name, result);
          break;
        }
        case 'DERIV': store(name, a.derivative(Number(words[3]))); break;
        case 'INTEG': degreeLimit(!a.zero && a.degree + 1 > 30); store(name, a.integral()); break;
        case 'AREA': {
          const integral = a.integral(), [u, v] = values;
          output.push(`integral(${name}, ${u}, ${v}) = ${integral.evaluate(v).sub(integral.evaluate(u))}`);
          break;
        }
        case 'TANGENT': {
          const point = values[0], value = a.evaluate(point), slope = a.derivative().evaluate(point);
          store(name, linear(value.sub(slope.mul(point)), slope));
          break;
        }
        case 'TAYLOR': {
          const point = values[0];
          const variable = point.n === 0n ? 'x' : point.n > 0n ? `(x - ${point})` : `(x + ${point.neg()})`;
          output.push(`taylor(${name}, ${point}) = ${a.compose(linear(point)).notation(variable)}`);
          break;
        }
        case 'COMPOSE': compositionLimit(a, b); store(name, a.compose(b)); break;
        case 'EVAL': for (const point of values) output.push(`${name}(${point}) = ${a.evaluate(point)}`); break;
        case 'ROOTS': case 'FACTOR': {
          requireNonzero(a);
          const { roots, remaining } = rationalRoots(a);
          if (command === 'ROOTS') {
            output.push(`roots(${name}) = ` + (roots.map(({ root, multiplicity }) => `${root} (${multiplicity})`).join(', ') || 'none'));
          } else {
            let result = `factor(${name}) = ${a.content()}`;
            for (const { root, multiplicity } of roots) {
              const factor = root.n === 0n ? 'x' : `(${linear(new Fraction(-root.n), new Fraction(root.d)).notation()})`;
              result += ` * ${factor}` + (multiplicity > 1 ? `^${multiplicity}` : '');
            }
            if (remaining.degree >= 1) result += ` * (${remaining.notation()})`;
            output.push(result);
          }
          break;
        }
        case 'SQFREE': {
          requireNonzero(a);
          let result = `sqfree(${name}) = ${a.content()}`;
          if (a.degree >= 1) {
            const monic = a.monic();
            let common = polynomialGcd(monic, monic.derivative()), remaining = monic.divide(common)[0];
            for (let multiplicity = 1; remaining.degree >= 1; multiplicity++) {
              const shared = polynomialGcd(remaining, common), factor = remaining.divide(shared)[0];
              if (factor.degree >= 1) {
                const notation = factor.primitive().notation();
                result += ' * ' + (notation === 'x' ? 'x' : `(${notation})`) + (multiplicity > 1 ? `^${multiplicity}` : '');
              }
              common = common.divide(shared)[0];
              remaining = shared;
            }
          }
          output.push(result);
          break;
        }
        case 'DESCARTES': {
          requireNonzero(a);
          const signs = a.coefficients.map(coefficient => coefficient.compare(ZERO));
          const positive = signChanges(signs.toReversed());
          const negative = signChanges(signs.map((sign, i) => i % 2 ? -sign : sign).reverse());
          output.push(`descartes(${name}) = positive ${positive}, negative ${negative}`);
          break;
        }
        case 'STURM': {
          requireNonzero(a);
          const [u, v] = values;
          if (compareEndpoints(u, v) >= 0) fail('BAD INTERVAL');
          const sequence = sturmSequence(a);
          output.push(`sturm(${name}, ${u}, ${v}) = ${variations(sequence, u) - variations(sequence, v)}`);
          break;
        }
        case 'ISOLATE': {
          requireNonzero(a);
          const precision = Number(words[2]), intervals = isolate(a, precision);
          output.push(`isolate(${name}, ${precision}) = ${intervals.join(', ') || 'none'}`);
          break;
        }
        case 'RESULTANT':
          requireNonzero(a); requireNonzero(b);
          output.push(`res(${name}, ${words[2]}) = ${resultant(a, b)}`);
          break;
        case 'DISCRIM': {
          requireNonzero(a);
          if (a.degree === 0) fail('DEGREE TOO LOW');
          let discriminant = resultant(a, a.derivative()).div(a.leading);
          if (a.degree * (a.degree - 1) / 2 % 2) discriminant = discriminant.neg();
          output.push(`disc(${name}) = ${discriminant}`);
          break;
        }
        case 'POWERSUM': {
          requireNonzero(a);
          if (a.degree === 0) fail('DEGREE TOO LOW');
          const monic = a.monic(), sums = [ZERO], count = Number(words[2]);
          for (let j = 1; j <= count; j++) {
            let sum = j <= a.degree ? integer(j).mul(monic.coefficient(a.degree - j)) : ZERO;
            for (let i = 1; i <= Math.min(j - 1, a.degree); i++) sum = sum.add(monic.coefficient(a.degree - i).mul(sums[j - i]));
            sums.push(sum.neg());
          }
          output.push(`powersum(${name}) = ${sums.slice(1).join(', ')}`);
          break;
        }
        case 'INTERP': store(name, interpolate(values)); break;
        case 'SPECIAL': store(name, special(words[2], Number(words[3]))); break;
      }
    }
    for (const [name, polynomial] of pending) this.polynomials.set(name, polynomial);
    return output;
  }
}

const input = readFileSync(0, 'utf8').trimEnd().split('\n');
const calculator = new Calculator(), output = [];
for (let i = 1; i <= Number(input[0]); i++) {
  try { output.push(...calculator.execute(input[i])); }
  catch (error) {
    if (!(error instanceof CalculatorError)) throw error;
    output.push('ERROR ' + error.message);
  }
}
process.stdout.write(output.join('\n') + '\n');
