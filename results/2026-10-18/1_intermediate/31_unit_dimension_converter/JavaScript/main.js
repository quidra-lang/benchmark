import { readFileSync } from 'node:fs';

class CommandError extends Error {}
function fail(message) { throw new CommandError(message); }
const abs = value => value < 0n ? -value : value;
function gcd(a, b) {
  a = abs(a);
  while (b !== 0n) [a, b] = [b, a % b];
  return a;
}

class Fraction {
  constructor(n, d = 1n) {
    if (d < 0n) { n = -n; d = -d; }
    const divisor = gcd(n, d);
    this.n = n / divisor;
    this.d = d / divisor;
  }
  add(b) { return new Fraction(this.n * b.d + b.n * this.d, this.d * b.d); }
  sub(b) { return new Fraction(this.n * b.d - b.n * this.d, this.d * b.d); }
  mul(b) { return new Fraction(this.n * b.n, this.d * b.d); }
  div(b) { return new Fraction(this.n * b.d, this.d * b.n); }
  neg() { return new Fraction(-this.n, this.d); }
  abs() { return this.n < 0n ? this.neg() : this; }
  compare(b) {
    const left = this.n * b.d, right = b.n * this.d;
    return left < right ? -1 : left > right ? 1 : 0;
  }
  pow(exponent) {
    const factor = exponent < 0n ? ONE.div(this) : this;
    let result = ONE;
    for (let i = 0n; i < abs(exponent); i++) result = result.mul(factor);
    return result;
  }
  toString() { return this.d === 1n ? `${this.n}` : `${this.n}/${this.d}`; }
  decimal() {
    const magnitude = abs(this.n);
    const whole = magnitude / this.d, tail = magnitude % this.d * 1_000_000n / this.d;
    return `${this.n < 0n ? '-' : ''}${whole}.${String(tail).padStart(6, '0')}`;
  }
  notation(unit) { return `${this} ${unit} (${this.decimal()})`; }
}
const ONE = new Fraction(1n), TEN = new Fraction(10n);

function numberValue(text) {
  if (!/^-?[0-9]+([./][0-9]+)?$/.test(text)) fail(`BAD NUMBER ${text}`);
  const negative = text.startsWith('-'), body = negative ? text.slice(1) : text;
  let value;
  if (body.includes('/')) {
    const [n, d] = body.split('/').map(BigInt);
    if (d === 0n) fail(`BAD NUMBER ${text}`);
    value = new Fraction(n, d);
  } else if (body.includes('.')) {
    const [whole, digits] = body.split('.');
    const scale = 10n ** BigInt(digits.length);
    value = new Fraction(BigInt(whole) * scale + BigInt(digits), scale);
  } else value = new Fraction(BigInt(body));
  return negative ? value.neg() : value;
}
function exponentValue(text) {
  const value = BigInt(text);
  if (value === 0n || value < -3n || value > 3n) fail(`BAD EXPONENT ${text}`);
  return value;
}
const FUNCTIONS = new Map([['abs', 1], ['sqrt', 1], ['min', 2], ['max', 2]]);
function checkName(name, variable = false) {
  if (!/^[A-Za-z]{1,12}$/.test(name) || (variable && FUNCTIONS.has(name))) fail(`BAD NAME ${name}`);
}

class Dimension {
  constructor(exponents = Array(7).fill(0n)) { this.exponents = exponents; }
  add(other) { return new Dimension(this.exponents.map((value, i) => value + other.exponents[i])); }
  sub(other) { return new Dimension(this.exponents.map((value, i) => value - other.exponents[i])); }
  scale(factor) { return new Dimension(this.exponents.map(value => value * factor)); }
  equals(other) { return this.exponents.every((value, i) => value === other.exponents[i]); }
  match(other) { if (!this.equals(other)) fail(`DIMENSION MISMATCH ${this} vs ${other}`); }
  toString() {
    const symbols = ['kg', 'm', 's', 'A', 'K', 'mol', 'cd'];
    return this.exponents.flatMap((value, i) => value === 0n ? [] : [value === 1n ? symbols[i] : `${symbols[i]}^${value}`]).join(' ') || '1';
  }
}
const dimension = (kg = 0n, m = 0n, s = 0n, a = 0n, k = 0n, mol = 0n, cd = 0n) =>
  new Dimension([kg, m, s, a, k, mol, cd]);
const DIMENSIONLESS = dimension();
class Quantity {
  constructor(value = ONE, dimension = DIMENSIONLESS) {
    this.value = value;
    this.dimension = dimension;
  }
}

const KINDS = new Map([
  ['dimensionless', DIMENSIONLESS], ['length', dimension(0n, 1n)], ['mass', dimension(1n)], ['time', dimension(0n, 0n, 1n)],
  ['current', dimension(0n, 0n, 0n, 1n)], ['temperature', dimension(0n, 0n, 0n, 0n, 1n)],
  ['amount', dimension(0n, 0n, 0n, 0n, 0n, 1n)], ['luminous_intensity', dimension(0n, 0n, 0n, 0n, 0n, 0n, 1n)],
  ['area', dimension(0n, 2n)], ['volume', dimension(0n, 3n)], ['speed', dimension(0n, 1n, -1n)],
  ['acceleration', dimension(0n, 1n, -2n)], ['density', dimension(1n, -3n)], ['momentum', dimension(1n, 1n, -1n)],
  ['force', dimension(1n, 1n, -2n)], ['energy', dimension(1n, 2n, -2n)], ['power', dimension(1n, 2n, -3n)],
  ['pressure', dimension(1n, -1n, -2n)], ['frequency', dimension(0n, 0n, -1n)], ['charge', dimension(0n, 0n, 1n, 1n)],
  ['voltage', dimension(1n, 2n, -3n, -1n)], ['resistance', dimension(1n, 2n, -3n, -2n)],
  ['conductance', dimension(-1n, -2n, 3n, 2n)], ['capacitance', dimension(-1n, -2n, 4n, 2n)],
  ['magnetic_flux', dimension(1n, 2n, -2n, -1n)], ['flux_density', dimension(1n, 0n, -2n, -1n)],
  ['inductance', dimension(1n, 2n, -2n, -2n)], ['illuminance', dimension(0n, -2n, 0n, 0n, 0n, 0n, 1n)],
  ['catalytic_activity', dimension(0n, 0n, -1n, 0n, 0n, 1n)],
]);
const kindName = value => [...KINDS].find(([, known]) => known.equals(value))?.[0] ?? '-';
const BUILTINS = [
  ['m',1n,1n,'length',true], ['g',1n,1000n,'mass',true], ['s',1n,1n,'time',true],
  ['A',1n,1n,'current',true], ['K',1n,1n,'temperature',true], ['mol',1n,1n,'amount',true],
  ['cd',1n,1n,'luminous_intensity',true], ['N',1n,1n,'force',true], ['J',1n,1n,'energy',true],
  ['W',1n,1n,'power',true], ['Pa',1n,1n,'pressure',true], ['Hz',1n,1n,'frequency',true],
  ['C',1n,1n,'charge',true], ['V',1n,1n,'voltage',true], ['ohm',1n,1n,'resistance',true],
  ['S',1n,1n,'conductance',true], ['F',1n,1n,'capacitance',true], ['Wb',1n,1n,'magnetic_flux',true],
  ['T',1n,1n,'flux_density',true], ['H',1n,1n,'inductance',true], ['lx',1n,1n,'illuminance',true],
  ['kat',1n,1n,'catalytic_activity',true], ['L',1n,1000n,'volume',true], ['t',1000n,1n,'mass',false],
  ['min',60n,1n,'time',false], ['h',3600n,1n,'time',false], ['day',86400n,1n,'time',false],
  ['in',127n,5000n,'length',false], ['ft',381n,1250n,'length',false], ['yd',1143n,1250n,'length',false],
  ['mi',201168n,125n,'length',false], ['nmi',1852n,1n,'length',false], ['ha',10000n,1n,'area',false],
  ['kn',463n,900n,'speed',false], ['bar',100000n,1n,'pressure',true], ['atm',101325n,1n,'pressure',false],
  ['Torr',20265n,152n,'pressure',false], ['cal',523n,125n,'energy',true], ['Wh',3600n,1n,'energy',true],
  ['Ah',3600n,1n,'charge',true], ['dC',1n,1n,'temperature',false], ['dF',5n,9n,'temperature',false],
].map(([symbol, n, d, kind, prefixable]) => ({ symbol, quantity: new Quantity(new Fraction(n, d), KINDS.get(kind)), prefixable }));
const PREFIXES = [
  ['G',9n], ['M',6n], ['k',3n], ['h',2n], ['da',1n], ['d',-1n], ['c',-2n], ['m',-3n], ['u',-6n], ['n',-9n],
].map(([symbol, exponent]) => [symbol, TEN.pow(exponent)]);

class Database {
  units = [...BUILTINS];
  variables = new Map();

  resolve(name) {
    const exact = this.units.find(unit => unit.symbol === name);
    if (exact) return exact.quantity;
    for (const [prefix, factor] of PREFIXES) {
      if (!name.startsWith(prefix)) continue;
      const unit = BUILTINS.find(item => item.prefixable && item.symbol === name.slice(prefix.length));
      if (unit) return new Quantity(factor.mul(unit.quantity.value), unit.quantity.dimension);
    }
    return null;
  }
  simplified(dimension) {
    return this.units.find(unit => unit.quantity.value.compare(ONE) === 0 && unit.quantity.dimension.equals(dimension))?.symbol ?? String(dimension);
  }
  selected(dimension) {
    return this.units.filter(unit => unit.quantity.dimension.equals(dimension)).sort((a, b) =>
      a.quantity.value.compare(b.quantity.value) || (a.symbol < b.symbol ? -1 : a.symbol > b.symbol ? 1 : 0));
  }
}

const letter = c => c !== undefined && ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'));
const digit = c => c !== undefined && c >= '0' && c <= '9';

class Parser {
  tokens = [];
  position = 0;

  constructor(source, quantityMode) {
    this.source = source;
    for (let i = 0; i < source.length;) {
      const start = i, character = source[i++];
      let kind = 'invalid';
      if (letter(character)) {
        kind = 'name';
        while (letter(source[i])) i++;
      } else if (digit(character)) {
        kind = 'number';
        while (digit(source[i])) i++;
        if (quantityMode && source[i] === '.' && digit(source[i + 1])) {
          i++;
          while (digit(source[i])) i++;
        }
      } else if (quantityMode && character === '[') {
        const closing = source.indexOf(']', i);
        if (closing > i) { kind = 'unit'; i = closing + 1; }
      } else if ((quantityMode ? '+-*/^(),' : '*/^()-').includes(character)) kind = 'symbol';
      this.tokens.push({ kind, text: source.slice(start, i), position: start + 1 });
    }
    this.tokens.push({ kind: 'end', text: '', position: source.length + 1 });
  }
  get current() { return this.tokens[this.position]; }
  syntax() { fail(`SYNTAX ${this.source} AT ${this.current.kind === 'end' ? 'END' : this.current.position}`); }
  advance() { return this.tokens[this.position++]; }
  take(text) {
    if (this.current.text !== text) return false;
    this.position++;
    return true;
  }
  expect(text) { if (!this.take(text)) this.syntax(); }
  exponent() {
    const sign = this.take('-') ? '-' : '';
    if (this.current.kind !== 'number' || this.current.text.includes('.')) this.syntax();
    return sign + this.advance().text;
  }
  unitTerm() {
    let node;
    if (this.current.kind === 'name') node = { kind: 'name', name: this.advance().text };
    else if (this.current.kind === 'number' && this.current.text[0] !== '0') node = { kind: 'number', value: BigInt(this.advance().text) };
    else if (this.take('(')) { node = this.unitExpression(); this.expect(')'); }
    else this.syntax();
    return this.take('^') ? { kind: 'power', child: node, exponent: this.exponent() } : node;
  }
  unitExpression() {
    const terms = [{ operation: '*', node: this.unitTerm() }];
    while (this.current.text === '*' || this.current.text === '/') {
      const operation = this.advance().text;
      terms.push({ operation, node: this.unitTerm() });
    }
    return { kind: 'product', terms };
  }
  unit() {
    const node = this.unitExpression();
    if (this.current.kind !== 'end') this.syntax();
    return node;
  }
  primary() {
    const token = this.current;
    let node;
    if (token.kind === 'number') {
      this.advance();
      const unit = this.current.kind === 'unit' ? this.advance().text.slice(1, -1) : null;
      node = { kind: 'literal', number: token.text, unit };
    } else if (token.kind === 'unit') {
      this.advance();
      node = { kind: 'literal', number: '1', unit: token.text.slice(1, -1) };
    } else if (token.kind === 'name') {
      this.advance();
      if (this.take('(')) {
        const args = [this.expression()];
        while (this.take(',')) args.push(this.expression());
        this.expect(')');
        node = { kind: 'call', name: token.text, args };
      } else node = { kind: 'variable', name: token.text };
    } else if (this.take('(')) { node = this.expression(); this.expect(')'); }
    else this.syntax();
    return this.take('^') ? { kind: 'power', child: node, exponent: this.exponent() } : node;
  }
  unary() { return this.take('-') ? { kind: 'negative', child: this.unary() } : this.primary(); }
  product() {
    let node = this.unary();
    while (this.current.text === '*' || this.current.text === '/') {
      const operation = this.advance().text;
      node = { kind: 'binary', operation, left: node, right: this.unary() };
    }
    return node;
  }
  expression() {
    let node = this.product();
    while (this.current.text === '+' || this.current.text === '-') {
      const operation = this.advance().text;
      node = { kind: 'binary', operation, left: node, right: this.product() };
    }
    return node;
  }
  quantity() {
    const node = this.expression();
    if (this.current.kind !== 'end') this.syntax();
    return node;
  }
}

function validateUnit(database, node) {
  switch (node.kind) {
    case 'name': if (!database.resolve(node.name)) fail(`UNKNOWN UNIT ${node.name}`); break;
    case 'power': validateUnit(database, node.child); exponentValue(node.exponent); break;
    case 'product': for (const term of node.terms) validateUnit(database, term.node); break;
  }
}
function evaluateUnit(database, node) {
  switch (node.kind) {
    case 'name': return database.resolve(node.name);
    case 'number': return new Quantity(new Fraction(node.value));
    case 'power': {
      const value = evaluateUnit(database, node.child), exponent = BigInt(node.exponent);
      return new Quantity(value.value.pow(exponent), value.dimension.scale(exponent));
    }
    case 'product': {
      let result = new Quantity();
      for (const term of node.terms) {
        const right = evaluateUnit(database, term.node);
        result = term.operation === '*' ? new Quantity(result.value.mul(right.value), result.dimension.add(right.dimension)) :
          new Quantity(result.value.div(right.value), result.dimension.sub(right.dimension));
      }
      return result;
    }
  }
}
function parseUnit(database, text) {
  const tree = new Parser(text, false).unit();
  validateUnit(database, tree);
  return tree;
}
const unitValue = (database, text) => evaluateUnit(database, parseUnit(database, text));

function reduceUnit(node) {
  switch (node.kind) {
    case 'name': return { coefficient: ONE, names: new Map([[node.name, 1n]]) };
    case 'number': return { coefficient: new Fraction(node.value), names: new Map() };
    case 'power': {
      const value = reduceUnit(node.child), exponent = BigInt(node.exponent);
      return { coefficient: value.coefficient.pow(exponent), names: new Map([...value.names].map(([name, power]) => [name, power * exponent])) };
    }
    case 'product': {
      let coefficient = ONE;
      const names = new Map();
      for (const term of node.terms) {
        const right = reduceUnit(term.node), multiply = term.operation === '*';
        coefficient = multiply ? coefficient.mul(right.coefficient) : coefficient.div(right.coefficient);
        for (const [name, power] of right.names) names.set(name, (names.get(name) ?? 0n) + (multiply ? power : -power));
      }
      return { coefficient, names };
    }
  }
}
function reducedText(tree) {
  const value = reduceUnit(tree), parts = value.coefficient.compare(ONE) === 0 ? [] : [String(value.coefficient)];
  for (const [name, power] of value.names) if (power !== 0n) parts.push(power === 1n ? name : `${name}^${power}`);
  return parts.join(' ') || '1';
}
function integerSqrt(value) {
  if (value < 2n) return value;
  let current = value, next = (value + 1n) / 2n;
  while (next < current) { current = next; next = (current + value / current) / 2n; }
  return current;
}
function evaluateQuantity(database, node) {
  switch (node.kind) {
    case 'literal': {
      const unit = node.unit === null ? new Quantity() : unitValue(database, node.unit);
      return new Quantity(numberValue(node.number).mul(unit.value), unit.dimension);
    }
    case 'variable': {
      const value = database.variables.get(node.name);
      if (!value) fail(`UNKNOWN VARIABLE ${node.name}`);
      return value;
    }
    case 'negative': {
      const value = evaluateQuantity(database, node.child);
      return new Quantity(value.value.neg(), value.dimension);
    }
    case 'power': {
      const value = evaluateQuantity(database, node.child), exponent = exponentValue(node.exponent);
      if (value.value.n === 0n && exponent < 0n) fail('DIVISION BY ZERO');
      return new Quantity(value.value.pow(exponent), value.dimension.scale(exponent));
    }
    case 'binary': {
      const left = evaluateQuantity(database, node.left), right = evaluateQuantity(database, node.right);
      if (node.operation === '+' || node.operation === '-') {
        left.dimension.match(right.dimension);
        return new Quantity(node.operation === '+' ? left.value.add(right.value) : left.value.sub(right.value), left.dimension);
      }
      if (node.operation === '*') return new Quantity(left.value.mul(right.value), left.dimension.add(right.dimension));
      if (right.value.n === 0n) fail('DIVISION BY ZERO');
      return new Quantity(left.value.div(right.value), left.dimension.sub(right.dimension));
    }
    case 'call': {
      if (!FUNCTIONS.has(node.name)) fail(`UNKNOWN FUNCTION ${node.name}`);
      if (node.args.length !== FUNCTIONS.get(node.name)) fail(`BAD ARGUMENTS ${node.name}`);
      const first = evaluateQuantity(database, node.args[0]);
      if (node.name === 'abs') return new Quantity(first.value.abs(), first.dimension);
      if (node.name === 'sqrt') {
        if (first.value.n < 0n) fail('NEGATIVE ROOT');
        if (first.dimension.exponents.some(value => value % 2n !== 0n)) fail(`ODD DIMENSION ${first.dimension}`);
        const n = integerSqrt(first.value.n), d = integerSqrt(first.value.d);
        if (n * n !== first.value.n || d * d !== first.value.d) fail('NOT EXACT');
        return new Quantity(new Fraction(n, d), new Dimension(first.dimension.exponents.map(value => value / 2n)));
      }
      const second = evaluateQuantity(database, node.args[1]);
      first.dimension.match(second.dimension);
      const comparison = first.value.compare(second.value);
      return (node.name === 'min' ? comparison <= 0 : comparison >= 0) ? first : second;
    }
  }
}
const quantityValue = (database, text) => evaluateQuantity(database, new Parser(text, true).quantity());

function execute(database, line) {
  const words = line.split(' '), command = words[0];
  switch (command) {
    case 'DEFINE': {
      const name = words[1];
      checkName(name);
      const value = numberValue(words[3]), unit = unitValue(database, words[4]);
      if (KINDS.has(name) || database.resolve(name)) fail(`NAME TAKEN ${name}`);
      if (value.n <= 0n) fail(`NOT POSITIVE ${words[3]}`);
      const result = new Quantity(value.mul(unit.value), unit.dimension);
      database.units.push({ symbol: name, quantity: result, prefixable: false, definition: { value, expression: words[4] } });
      return [`DEFINE ${name} factor=${result.value} dim=${result.dimension} kind=${kindName(result.dimension)}`];
    }
    case 'UNDEF': {
      const index = database.units.findIndex(unit => unit.symbol === words[1]);
      if (index < 0) fail(`NOT DEFINED ${words[1]}`);
      if (index < BUILTINS.length) fail(`BUILTIN UNIT ${words[1]}`);
      database.units.splice(index, 1);
      return [`UNDEF ${words[1]}`];
    }
    case 'DEFS': return [`DEFS count=${database.units.length - BUILTINS.length}`, ...database.units.slice(BUILTINS.length).map(unit =>
      `DEF ${unit.symbol} = ${unit.definition.value} ${unit.definition.expression} factor=${unit.quantity.value} dim=${unit.quantity.dimension}`)];
    case 'CONVERT': case 'INVERT': {
      const value = numberValue(words[1]), source = unitValue(database, words[2]), target = unitValue(database, words[4]);
      if (command === 'INVERT') {
        if (source.dimension.equals(DIMENSIONLESS) || !source.dimension.add(target.dimension).equals(DIMENSIONLESS)) {
          fail(`NOT RECIPROCAL ${source.dimension} vs ${target.dimension}`);
        }
        if (value.n === 0n) fail('DIVISION BY ZERO');
      } else source.dimension.match(target.dimension);
      let result = value.mul(source.value);
      if (command === 'INVERT') result = ONE.div(result);
      return [`${command} ${value} ${words[2]} = ${result.div(target.value).notation(words[4])}`];
    }
    case 'DIM': case 'REDUCE': case 'SIMPLIFY': {
      const tree = parseUnit(database, words[1]), unit = evaluateUnit(database, tree);
      const result = command === 'DIM' ? `${unit.dimension} factor=${unit.value} kind=${kindName(unit.dimension)}` :
        command === 'REDUCE' ? reducedText(tree) : unit.value.notation(database.simplified(unit.dimension));
      return [`${command} ${words[1]} = ${result}`];
    }
    case 'ADD': case 'SUB': case 'MUL': case 'DIV': case 'COMPARE': {
      const a = numberValue(words[1]), first = unitValue(database, words[2]);
      const b = numberValue(words[3]), second = unitValue(database, words[4]);
      const hasTarget = words.length === 7, target = hasTarget ? unitValue(database, words[6]) : first;
      const heading = `${command} ${a} ${words[2]}`, suffix = `${b} ${words[4]}`;
      if (command === 'ADD' || command === 'SUB' || command === 'COMPARE') {
        first.dimension.match(second.dimension);
        if (hasTarget) first.dimension.match(target.dimension);
        const left = a.mul(first.value), right = b.mul(second.value);
        if (command === 'COMPARE') {
          const relation = ['<', '=', '>'][left.compare(right) + 1];
          return [`${heading} ${relation} ${suffix} ratio=${right.n === 0n ? 'undefined' : left.div(right)}`];
        }
        const add = command === 'ADD', result = add ? left.add(right) : left.sub(right);
        return [`${heading} ${add ? '+' : '-'} ${suffix} = ${result.div(target.value).notation(hasTarget ? words[6] : words[2])}`];
      }
      const multiply = command === 'MUL', dimension = multiply ? first.dimension.add(second.dimension) : first.dimension.sub(second.dimension);
      if (!multiply && b.n === 0n) fail('DIVISION BY ZERO');
      if (hasTarget) dimension.match(target.dimension);
      const raw = multiply ? a.mul(b) : a.div(b), left = a.mul(first.value), right = b.mul(second.value);
      const coherent = multiply ? left.mul(right) : left.div(right), operation = multiply ? '*' : '/';
      const prefix = `${heading} ${operation} ${suffix} =`;
      if (hasTarget) return [`${prefix} ${coherent.div(target.value).notation(words[6])}`];
      const rightUnit = !multiply && /[*/]/.test(words[4]) ? `(${words[4]})` : words[4];
      return [`${prefix} ${raw} ${words[2]}${operation}${rightUnit} = ${coherent.notation(database.simplified(dimension))}`];
    }
    case 'TEMP': {
      const value = numberValue(words[1]);
      for (const scale of [words[2], words[4]]) if (!['C', 'F', 'K', 'R'].includes(scale)) fail(`UNKNOWN SCALE ${scale}`);
      const celsius = new Fraction(5463n, 20n), fahrenheit = new Fraction(45967n, 100n);
      const kelvin = words[2] === 'C' ? value.add(celsius) : words[2] === 'F' ? value.add(fahrenheit).mul(new Fraction(5n, 9n)) :
        words[2] === 'R' ? value.mul(new Fraction(5n, 9n)) : value;
      if (kelvin.n < 0n) fail('BELOW ABSOLUTE ZERO');
      const result = words[4] === 'C' ? kelvin.sub(celsius) : words[4] === 'F' ? kelvin.mul(new Fraction(9n, 5n)).sub(fahrenheit) :
        words[4] === 'R' ? kelvin.mul(new Fraction(9n, 5n)) : kelvin;
      return [`TEMP ${value} ${words[2]} = ${result.notation(words[4])}`];
    }
    case 'LIST': {
      const dimension = KINDS.get(words[1]) ?? unitValue(database, words[1]).dimension;
      const units = database.selected(dimension);
      return [`LIST ${words[1]} dim=${dimension} kind=${kindName(dimension)} count=${units.length}`,
        ...units.map(unit => `UNIT ${unit.symbol} factor=${unit.quantity.value} origin=${unit.definition ? 'user' : 'builtin'} prefix=${unit.prefixable ? 'yes' : 'no'}`)];
    }
    case 'TABLE': {
      const value = numberValue(words[1]), unit = unitValue(database, words[2]), units = database.selected(unit.dimension);
      return [`TABLE ${value} ${words[2]} dim=${unit.dimension} count=${units.length}`,
        ...units.map(item => `ROW ${value.mul(unit.value).div(item.quantity.value).notation(item.symbol)}`)];
    }
    case 'AUTO': {
      const value = numberValue(words[1]), unit = unitValue(database, words[2]);
      const reference = BUILTINS.find(item => item.prefixable && item.quantity.dimension.equals(unit.dimension));
      if (!reference) fail(`NO PREFIXABLE UNIT ${unit.dimension}`);
      const scaled = value.mul(unit.value).div(reference.quantity.value), magnitude = scaled.abs();
      let exponent = 0n;
      if (magnitude.compare(ONE) >= 0) {
        while (exponent < 9n && magnitude.compare(TEN.pow(exponent + 3n)) >= 0) exponent += 3n;
      } else if (magnitude.n > 0n) {
        while (exponent > -9n && magnitude.compare(TEN.pow(exponent)) < 0) exponent -= 3n;
      }
      const prefix = ['n', 'u', 'm', '', 'k', 'M', 'G'][Number((exponent + 9n) / 3n)];
      return [`AUTO ${value} ${words[2]} = ${scaled.div(TEN.pow(exponent)).notation(prefix + reference.symbol)}`];
    }
    case 'SPLIT': {
      const value = numberValue(words[1]), unit = unitValue(database, words[2]);
      const parts = words[4].split(','), targets = parts.map(part => unitValue(database, part));
      if (value.n < 0n) fail('NEGATIVE VALUE');
      for (const target of targets) unit.dimension.match(target.dimension);
      for (let i = 0; i + 1 < targets.length; i++) if (targets[i].value.compare(targets[i + 1].value) <= 0) fail('UNIT ORDER');
      let remaining = value.mul(unit.value);
      const pieces = [];
      for (let i = 0; i + 1 < targets.length; i++) {
        const quotient = remaining.div(targets[i].value), whole = quotient.n / quotient.d;
        remaining = remaining.sub(new Fraction(whole).mul(targets[i].value));
        pieces.push(`${whole} ${parts[i]}`);
      }
      pieces.push(remaining.div(targets.at(-1).value).notation(parts.at(-1)));
      return [`SPLIT ${value} ${words[2]} = ${pieces.join(' ')}`];
    }
    case 'LET': {
      checkName(words[1], true);
      const value = quantityValue(database, words[3]);
      database.variables.set(words[1], value);
      return [`LET ${words[1]} = ${value.value.notation(database.simplified(value.dimension))}`];
    }
    case 'EVAL': {
      const value = quantityValue(database, words[1]);
      let result = value.value, label = database.simplified(value.dimension);
      if (words.length === 4) {
        const target = unitValue(database, words[3]);
        value.dimension.match(target.dimension);
        result = result.div(target.value);
        label = words[3];
      }
      return [`EVAL ${words[1]} = ${result.notation(label)}`];
    }
    case 'VARS': return [`VARS count=${database.variables.size}`, ...[...database.variables.keys()].sort().map(name => {
      const value = database.variables.get(name);
      return `VAR ${name} = ${value.value.notation(database.simplified(value.dimension))}`;
    })];
    default: fail(`UNKNOWN COMMAND ${command}`);
  }
}

const lines = readFileSync(0, 'utf8').split(/\r?\n/), count = Number(lines[0]);
const database = new Database(), output = [];
for (let i = 1; i <= count; i++) {
  try { output.push(...execute(database, lines[i])); }
  catch (error) {
    if (!(error instanceof CommandError)) throw error;
    output.push(`ERROR ${error.message}`);
  }
}
process.stdout.write(output.join('\n') + '\n');
