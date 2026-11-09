import { readFileSync } from "node:fs";

class CommandError extends Error {}
function fail(message: string): never { throw new CommandError(message); }
const abs = (value: bigint): bigint => value < 0n ? -value : value;
function gcd(a: bigint, b: bigint): bigint {
  for (a = abs(a), b = abs(b); b !== 0n;) [a, b] = [b, a % b];
  return a;
}

class Fraction {
  readonly n: bigint;
  readonly d: bigint;

  constructor(n: bigint, d: bigint = 1n) {
    if (d < 0n) { n = -n; d = -d; }
    const divisor = gcd(n, d);
    this.n = n / divisor;
    this.d = d / divisor;
  }
  add(other: Fraction): Fraction { return new Fraction(this.n * other.d + other.n * this.d, this.d * other.d); }
  sub(other: Fraction): Fraction { return new Fraction(this.n * other.d - other.n * this.d, this.d * other.d); }
  mul(other: Fraction): Fraction { return new Fraction(this.n * other.n, this.d * other.d); }
  div(other: Fraction): Fraction { return new Fraction(this.n * other.d, this.d * other.n); }
  neg(): Fraction { return new Fraction(-this.n, this.d); }
  abs(): Fraction { return this.n < 0n ? this.neg() : this; }
  compare(other: Fraction): -1 | 0 | 1 {
    const a = this.n * other.d, b = other.n * this.d;
    return a < b ? -1 : a > b ? 1 : 0;
  }
  pow(exponent: bigint): Fraction {
    const factor = exponent < 0n ? ONE.div(this) : this;
    let result = ONE;
    for (let i = 0n; i < abs(exponent); i++) result = result.mul(factor);
    return result;
  }
  toString(): string { return this.d === 1n ? String(this.n) : `${this.n}/${this.d}`; }
  decimal(): string {
    const n = abs(this.n), whole = n / this.d, tail = (n % this.d) * 1_000_000n / this.d;
    return `${this.n < 0n ? "-" : ""}${whole}.${String(tail).padStart(6, "0")}`;
  }
  notation(unit: string): string { return `${this} ${unit} (${this.decimal()})`; }
}
const integer = (value: bigint): Fraction => new Fraction(value);
const ONE = integer(1n), TEN = integer(10n);

function numberValue(text: string): Fraction {
  if (!/^-?[0-9]+([./][0-9]+)?$/.test(text)) fail(`BAD NUMBER ${text}`);
  const negative = text.startsWith("-"), body = negative ? text.slice(1) : text;
  let value: Fraction;
  if (body.includes("/")) {
    const [n, d] = body.split("/");
    if (BigInt(d) === 0n) fail(`BAD NUMBER ${text}`);
    value = new Fraction(BigInt(n), BigInt(d));
  } else if (body.includes(".")) {
    const [whole, tail] = body.split(".");
    let scale = 1n;
    for (const _ of tail) scale *= 10n;
    value = new Fraction(BigInt(whole) * scale + BigInt(tail), scale);
  } else value = integer(BigInt(body));
  return negative ? value.neg() : value;
}
function checkedExponent(text: string): bigint {
  const value = BigInt(text);
  if (value === 0n || value < -3n || value > 3n) fail(`BAD EXPONENT ${text}`);
  return value;
}
function checkName(name: string, variable = false): void {
  if (!/^[A-Za-z]{1,12}$/.test(name) || (variable && ["abs", "sqrt", "min", "max"].includes(name))) {
    fail(`BAD NAME ${name}`);
  }
}

type Exponents = readonly [bigint, bigint, bigint, bigint, bigint, bigint, bigint];
class Dimension {
  constructor(readonly exponents: Exponents) {}
  map(transform: (value: bigint, index: number) => bigint): Dimension {
    const a = this.exponents;
    return new Dimension([transform(a[0], 0), transform(a[1], 1), transform(a[2], 2), transform(a[3], 3),
      transform(a[4], 4), transform(a[5], 5), transform(a[6], 6)]);
  }
  add(other: Dimension): Dimension { return this.map((value, i) => value + other.exponents[i]); }
  sub(other: Dimension): Dimension { return this.map((value, i) => value - other.exponents[i]); }
  scale(multiplier: bigint): Dimension { return this.map(value => value * multiplier); }
  equals(other: Dimension): boolean { return this.exponents.every((value, i) => value === other.exponents[i]); }
  match(other: Dimension): void {
    if (!this.equals(other)) fail(`DIMENSION MISMATCH ${this} vs ${other}`);
  }
  toString(): string {
    const symbols = ["kg", "m", "s", "A", "K", "mol", "cd"];
    return this.exponents.flatMap((value, i) => value === 0n ? [] : [value === 1n ? symbols[i] : `${symbols[i]}^${value}`]).join(" ") || "1";
  }
}
const dim = (kg = 0n, m = 0n, s = 0n, a = 0n, k = 0n, mol = 0n, cd = 0n): Dimension =>
  new Dimension([kg, m, s, a, k, mol, cd]);
const DIMENSIONLESS = dim();
interface Quantity { readonly value: Fraction; readonly dimension: Dimension; }
const quantity = (value = ONE, dimension = DIMENSIONLESS): Quantity => ({ value, dimension });

const KINDS = [
  ["dimensionless", DIMENSIONLESS], ["length", dim(0n, 1n)], ["mass", dim(1n)], ["time", dim(0n, 0n, 1n)],
  ["current", dim(0n, 0n, 0n, 1n)], ["temperature", dim(0n, 0n, 0n, 0n, 1n)],
  ["amount", dim(0n, 0n, 0n, 0n, 0n, 1n)], ["luminous_intensity", dim(0n, 0n, 0n, 0n, 0n, 0n, 1n)],
  ["area", dim(0n, 2n)], ["volume", dim(0n, 3n)], ["speed", dim(0n, 1n, -1n)],
  ["acceleration", dim(0n, 1n, -2n)], ["density", dim(1n, -3n)], ["momentum", dim(1n, 1n, -1n)],
  ["force", dim(1n, 1n, -2n)], ["energy", dim(1n, 2n, -2n)], ["power", dim(1n, 2n, -3n)],
  ["pressure", dim(1n, -1n, -2n)], ["frequency", dim(0n, 0n, -1n)], ["charge", dim(0n, 0n, 1n, 1n)],
  ["voltage", dim(1n, 2n, -3n, -1n)], ["resistance", dim(1n, 2n, -3n, -2n)],
  ["conductance", dim(-1n, -2n, 3n, 2n)], ["capacitance", dim(-1n, -2n, 4n, 2n)],
  ["magnetic_flux", dim(1n, 2n, -2n, -1n)], ["flux_density", dim(1n, 0n, -2n, -1n)],
  ["inductance", dim(1n, 2n, -2n, -2n)], ["illuminance", dim(0n, -2n, 0n, 0n, 0n, 0n, 1n)],
  ["catalytic_activity", dim(0n, 0n, -1n, 0n, 0n, 1n)],
] as const;
type KindName = typeof KINDS[number][0];
const kindDimension = (name: string): Dimension | null => KINDS.find(([label]) => label === name)?.[1] ?? null;
const kindName = (dimension: Dimension): KindName | "-" => KINDS.find(([, known]) => known.equals(dimension))?.[0] ?? "-";

interface Definition { readonly value: Fraction; readonly expression: string; }
interface Unit {
  readonly symbol: string;
  readonly quantity: Quantity;
  readonly prefixable: boolean;
  readonly definition: Definition | null;
}
type BuiltinRow = readonly [symbol: string, numerator: bigint, denominator: bigint, kind: KindName, prefixable: boolean];
const BUILTINS: readonly BuiltinRow[] = [
  ["m",1n,1n,"length",true], ["g",1n,1000n,"mass",true], ["s",1n,1n,"time",true],
  ["A",1n,1n,"current",true], ["K",1n,1n,"temperature",true], ["mol",1n,1n,"amount",true],
  ["cd",1n,1n,"luminous_intensity",true], ["N",1n,1n,"force",true], ["J",1n,1n,"energy",true],
  ["W",1n,1n,"power",true], ["Pa",1n,1n,"pressure",true], ["Hz",1n,1n,"frequency",true],
  ["C",1n,1n,"charge",true], ["V",1n,1n,"voltage",true], ["ohm",1n,1n,"resistance",true],
  ["S",1n,1n,"conductance",true], ["F",1n,1n,"capacitance",true], ["Wb",1n,1n,"magnetic_flux",true],
  ["T",1n,1n,"flux_density",true], ["H",1n,1n,"inductance",true], ["lx",1n,1n,"illuminance",true],
  ["kat",1n,1n,"catalytic_activity",true], ["L",1n,1000n,"volume",true], ["t",1000n,1n,"mass",false],
  ["min",60n,1n,"time",false], ["h",3600n,1n,"time",false], ["day",86400n,1n,"time",false],
  ["in",127n,5000n,"length",false], ["ft",381n,1250n,"length",false], ["yd",1143n,1250n,"length",false],
  ["mi",201168n,125n,"length",false], ["nmi",1852n,1n,"length",false], ["ha",10000n,1n,"area",false],
  ["kn",463n,900n,"speed",false], ["bar",100000n,1n,"pressure",true], ["atm",101325n,1n,"pressure",false],
  ["Torr",20265n,152n,"pressure",false], ["cal",523n,125n,"energy",true], ["Wh",3600n,1n,"energy",true],
  ["Ah",3600n,1n,"charge",true], ["dC",1n,1n,"temperature",false], ["dF",5n,9n,"temperature",false],
];
const PREFIXES: readonly (readonly [string, Fraction])[] = [
  ["G",integer(1_000_000_000n)], ["M",integer(1_000_000n)], ["k",integer(1000n)], ["h",integer(100n)],
  ["da",integer(10n)], ["d",new Fraction(1n,10n)], ["c",new Fraction(1n,100n)],
  ["m",new Fraction(1n,1000n)], ["u",new Fraction(1n,1_000_000n)], ["n",new Fraction(1n,1_000_000_000n)],
];
class Database {
  readonly units: Unit[] = BUILTINS.map(([symbol, n, d, kind, prefixable]) => ({
    symbol, quantity: quantity(new Fraction(n, d), kindDimension(kind)!), prefixable, definition: null,
  }));
  readonly variables = new Map<string, Quantity>();

  resolve(name: string): Quantity | null {
    const exact = this.units.find(unit => unit.symbol === name);
    if (exact) return exact.quantity;
    for (const [prefix, factor] of PREFIXES) {
      if (!name.startsWith(prefix)) continue;
      const suffix = name.slice(prefix.length);
      const unit = this.units.slice(0, BUILTINS.length).find(item => item.prefixable && item.symbol === suffix);
      if (unit) return quantity(factor.mul(unit.quantity.value), unit.quantity.dimension);
    }
    return null;
  }
  simplified(dimension: Dimension): string {
    return this.units.find(unit => unit.quantity.value.compare(ONE) === 0 && unit.quantity.dimension.equals(dimension))?.symbol ?? String(dimension);
  }
  selected(dimension: Dimension): Unit[] {
    return this.units.filter(unit => unit.quantity.dimension.equals(dimension)).sort((a, b) =>
      a.quantity.value.compare(b.quantity.value) || (a.symbol < b.symbol ? -1 : a.symbol > b.symbol ? 1 : 0));
  }
}

type TokenKind = "name" | "number" | "unit" | "symbol" | "invalid" | "end";
interface Token { readonly kind: TokenKind; readonly text: string; readonly position: number; }
type UnitExpr =
  | { readonly kind: "name"; readonly name: string }
  | { readonly kind: "number"; readonly value: bigint }
  | { readonly kind: "power"; readonly child: UnitExpr; readonly exponent: string }
  | { readonly kind: "product"; readonly terms: readonly UnitTerm[] };
interface UnitTerm { readonly operation: "*" | "/"; readonly node: UnitExpr; }
type QuantityExpr =
  | { readonly kind: "literal"; readonly number: string; readonly unit: string | null }
  | { readonly kind: "variable"; readonly name: string }
  | { readonly kind: "negative"; readonly child: QuantityExpr }
  | { readonly kind: "power"; readonly child: QuantityExpr; readonly exponent: string }
  | { readonly kind: "binary"; readonly operation: "+" | "-" | "*" | "/"; readonly left: QuantityExpr; readonly right: QuantityExpr }
  | { readonly kind: "call"; readonly name: string; readonly arguments: readonly QuantityExpr[] };
const letter = (c: string | undefined): boolean => c !== undefined && ((c >= "A" && c <= "Z") || (c >= "a" && c <= "z"));
const digit = (c: string | undefined): boolean => c !== undefined && c >= "0" && c <= "9";

class Parser {
  private readonly tokens: Token[] = [];
  private position = 0;

  constructor(private readonly source: string, quantityMode: boolean) {
    for (let i = 0; i < source.length;) {
      const start = i, character = source[i++];
      let kind: TokenKind = "invalid";
      if (letter(character)) {
        kind = "name";
        while (letter(source[i])) i++;
      } else if (digit(character)) {
        kind = "number";
        while (digit(source[i])) i++;
        if (quantityMode && source[i] === "." && digit(source[i + 1])) {
          i++;
          while (digit(source[i])) i++;
        }
      } else if (quantityMode && character === "[") {
        const closing = source.indexOf("]", i);
        if (closing > i) { kind = "unit"; i = closing + 1; }
      } else if ((quantityMode ? "+-*/^()," : "*/^()-").includes(character)) kind = "symbol";
      this.tokens.push({ kind, text: source.slice(start, i), position: start + 1 });
    }
    this.tokens.push({ kind: "end", text: "", position: source.length + 1 });
  }
  private get current(): Token { return this.tokens[this.position]; }
  private syntax(): never { fail(`SYNTAX ${this.source} AT ${this.current.kind === "end" ? "END" : this.current.position}`); }
  private advance(): Token { return this.tokens[this.position++]; }
  private take(text: string): boolean {
    if (this.current.text !== text) return false;
    this.position++;
    return true;
  }
  private expect(text: string): void { if (!this.take(text)) this.syntax(); }
  private exponent(): string {
    const sign = this.take("-") ? "-" : "";
    if (this.current.kind !== "number" || this.current.text.includes(".")) this.syntax();
    return sign + this.advance().text;
  }
  private unitTerm(): UnitExpr {
    let result: UnitExpr;
    if (this.current.kind === "name") result = { kind: "name", name: this.advance().text };
    else if (this.current.kind === "number" && this.current.text[0] !== "0") result = { kind: "number", value: BigInt(this.advance().text) };
    else if (this.take("(")) { result = this.unitExpression(); this.expect(")"); }
    else this.syntax();
    return this.take("^") ? { kind: "power", child: result, exponent: this.exponent() } : result;
  }
  private unitExpression(): UnitExpr {
    const terms: UnitTerm[] = [{ operation: "*", node: this.unitTerm() }];
    while (this.current.text === "*" || this.current.text === "/") {
      const operation = this.current.text;
      this.advance();
      terms.push({ operation, node: this.unitTerm() });
    }
    return { kind: "product", terms };
  }
  unit(): UnitExpr {
    const result = this.unitExpression();
    if (this.current.kind !== "end") this.syntax();
    return result;
  }
  private primary(): QuantityExpr {
    let result: QuantityExpr;
    const token = this.current;
    if (token.kind === "number") {
      this.advance();
      const unit = this.current.kind === "unit" ? this.advance().text.slice(1, -1) : null;
      result = { kind: "literal", number: token.text, unit };
    } else if (token.kind === "unit") {
      this.advance();
      result = { kind: "literal", number: "1", unit: token.text.slice(1, -1) };
    } else if (token.kind === "name") {
      this.advance();
      if (this.take("(")) {
        const arguments_: QuantityExpr[] = [this.expression()];
        while (this.take(",")) arguments_.push(this.expression());
        this.expect(")");
        result = { kind: "call", name: token.text, arguments: arguments_ };
      } else result = { kind: "variable", name: token.text };
    } else if (this.take("(")) { result = this.expression(); this.expect(")"); }
    else this.syntax();
    return this.take("^") ? { kind: "power", child: result, exponent: this.exponent() } : result;
  }
  private unary(): QuantityExpr { return this.take("-") ? { kind: "negative", child: this.unary() } : this.primary(); }
  private product(): QuantityExpr {
    let result = this.unary();
    while (this.current.text === "*" || this.current.text === "/") {
      const operation = this.current.text;
      this.advance();
      result = { kind: "binary", operation, left: result, right: this.unary() };
    }
    return result;
  }
  private expression(): QuantityExpr {
    let result = this.product();
    while (this.current.text === "+" || this.current.text === "-") {
      const operation = this.current.text;
      this.advance();
      result = { kind: "binary", operation, left: result, right: this.product() };
    }
    return result;
  }
  quantity(): QuantityExpr {
    const result = this.expression();
    if (this.current.kind !== "end") this.syntax();
    return result;
  }
}

function validateUnit(database: Database, node: UnitExpr): void {
  switch (node.kind) {
    case "name": if (!database.resolve(node.name)) fail(`UNKNOWN UNIT ${node.name}`); break;
    case "power": validateUnit(database, node.child); checkedExponent(node.exponent); break;
    case "product": for (const term of node.terms) validateUnit(database, term.node); break;
    case "number": break;
  }
}
function evaluateUnit(database: Database, node: UnitExpr): Quantity {
  switch (node.kind) {
    case "name": return database.resolve(node.name)!;
    case "number": return quantity(integer(node.value));
    case "power": {
      const value = evaluateUnit(database, node.child), exponent = BigInt(node.exponent);
      return quantity(value.value.pow(exponent), value.dimension.scale(exponent));
    }
    case "product": {
      let result = quantity();
      for (const term of node.terms) {
        const right = evaluateUnit(database, term.node);
        result = term.operation === "*" ? quantity(result.value.mul(right.value), result.dimension.add(right.dimension)) :
          quantity(result.value.div(right.value), result.dimension.sub(right.dimension));
      }
      return result;
    }
  }
}
function parseUnit(database: Database, source: string): UnitExpr {
  const tree = new Parser(source, false).unit();
  validateUnit(database, tree);
  return tree;
}
const unitValue = (database: Database, source: string): Quantity => evaluateUnit(database, parseUnit(database, source));

interface Reduced { readonly coefficient: Fraction; readonly names: ReadonlyMap<string, bigint>; }
function reduceUnit(node: UnitExpr): Reduced {
  switch (node.kind) {
    case "name": return { coefficient: ONE, names: new Map([[node.name, 1n]]) };
    case "number": return { coefficient: integer(node.value), names: new Map() };
    case "power": {
      const result = reduceUnit(node.child), exponent = BigInt(node.exponent);
      return { coefficient: result.coefficient.pow(exponent), names: new Map([...result.names].map(([name, power]) => [name, power * exponent])) };
    }
    case "product": {
      let coefficient = ONE;
      const names = new Map<string, bigint>();
      for (const term of node.terms) {
        const right = reduceUnit(term.node), multiply = term.operation === "*";
        coefficient = multiply ? coefficient.mul(right.coefficient) : coefficient.div(right.coefficient);
        for (const [name, power] of right.names) names.set(name, (names.get(name) ?? 0n) + (multiply ? power : -power));
      }
      return { coefficient, names };
    }
  }
}
function reducedText(tree: UnitExpr): string {
  const result = reduceUnit(tree), parts = result.coefficient.compare(ONE) === 0 ? [] : [String(result.coefficient)];
  for (const [name, power] of result.names) if (power !== 0n) parts.push(power === 1n ? name : `${name}^${power}`);
  return parts.join(" ") || "1";
}
function integerSqrt(value: bigint): bigint {
  if (value < 2n) return value;
  let current = value, next = (value + 1n) / 2n;
  while (next < current) { current = next; next = (current + value / current) / 2n; }
  return current;
}
function evaluateQuantity(database: Database, node: QuantityExpr): Quantity {
  switch (node.kind) {
    case "literal": {
      if (node.unit === null) return quantity(numberValue(node.number));
      const unit = unitValue(database, node.unit);
      return quantity(numberValue(node.number).mul(unit.value), unit.dimension);
    }
    case "variable": {
      const value = database.variables.get(node.name);
      if (!value) fail(`UNKNOWN VARIABLE ${node.name}`);
      return value;
    }
    case "negative": {
      const value = evaluateQuantity(database, node.child);
      return quantity(value.value.neg(), value.dimension);
    }
    case "power": {
      const value = evaluateQuantity(database, node.child), exponent = checkedExponent(node.exponent);
      if (value.value.n === 0n && exponent < 0n) fail("DIVISION BY ZERO");
      return quantity(value.value.pow(exponent), value.dimension.scale(exponent));
    }
    case "binary": {
      const left = evaluateQuantity(database, node.left), right = evaluateQuantity(database, node.right);
      if (node.operation === "+" || node.operation === "-") {
        left.dimension.match(right.dimension);
        return quantity(node.operation === "+" ? left.value.add(right.value) : left.value.sub(right.value), left.dimension);
      }
      if (node.operation === "*") return quantity(left.value.mul(right.value), left.dimension.add(right.dimension));
      if (right.value.n === 0n) fail("DIVISION BY ZERO");
      return quantity(left.value.div(right.value), left.dimension.sub(right.dimension));
    }
    case "call": {
      if (!["abs", "sqrt", "min", "max"].includes(node.name)) fail(`UNKNOWN FUNCTION ${node.name}`);
      const arity = node.name === "abs" || node.name === "sqrt" ? 1 : 2;
      if (node.arguments.length !== arity) fail(`BAD ARGUMENTS ${node.name}`);
      const first = evaluateQuantity(database, node.arguments[0]);
      if (node.name === "abs") return quantity(first.value.abs(), first.dimension);
      if (node.name === "sqrt") {
        if (first.value.n < 0n) fail("NEGATIVE ROOT");
        if (first.dimension.exponents.some(value => value % 2n !== 0n)) fail(`ODD DIMENSION ${first.dimension}`);
        const n = integerSqrt(first.value.n), d = integerSqrt(first.value.d);
        if (n * n !== first.value.n || d * d !== first.value.d) fail("NOT EXACT");
        return quantity(new Fraction(n, d), first.dimension.map(value => value / 2n));
      }
      const second = evaluateQuantity(database, node.arguments[1]);
      first.dimension.match(second.dimension);
      const comparison = first.value.compare(second.value);
      return (node.name === "min" ? comparison <= 0 : comparison >= 0) ? first : second;
    }
  }
}
const quantityValue = (database: Database, source: string): Quantity => evaluateQuantity(database, new Parser(source, true).quantity());

const COMMANDS = ["DEFINE", "UNDEF", "DEFS", "CONVERT", "INVERT", "DIM", "REDUCE", "SIMPLIFY",
  "ADD", "SUB", "MUL", "DIV", "TEMP", "COMPARE", "LIST", "TABLE", "AUTO", "SPLIT", "LET", "EVAL", "VARS"] as const;
type CommandName = typeof COMMANDS[number];
const isCommand = (name: string): name is CommandName => COMMANDS.some(command => command === name);

function execute(database: Database, line: string): string[] {
  const words = line.split(" "), command = words[0];
  if (!isCommand(command)) fail(`UNKNOWN COMMAND ${command}`);
  switch (command) {
    case "DEFINE": {
      const name = words[1];
      checkName(name);
      const value = numberValue(words[3]), unit = unitValue(database, words[4]);
      if (kindDimension(name) || database.resolve(name)) fail(`NAME TAKEN ${name}`);
      if (value.n <= 0n) fail(`NOT POSITIVE ${words[3]}`);
      const result = quantity(value.mul(unit.value), unit.dimension);
      database.units.push({ symbol: name, quantity: result, prefixable: false, definition: { value, expression: words[4] } });
      return [`DEFINE ${name} factor=${result.value} dim=${result.dimension} kind=${kindName(result.dimension)}`];
    }
    case "UNDEF": {
      const index = database.units.findIndex(unit => unit.symbol === words[1]);
      if (index < 0) fail(`NOT DEFINED ${words[1]}`);
      if (index < BUILTINS.length) fail(`BUILTIN UNIT ${words[1]}`);
      database.units.splice(index, 1);
      return [`UNDEF ${words[1]}`];
    }
    case "DEFS": return [`DEFS count=${database.units.length - BUILTINS.length}`, ...database.units.slice(BUILTINS.length).map(unit =>
      `DEF ${unit.symbol} = ${unit.definition!.value} ${unit.definition!.expression} factor=${unit.quantity.value} dim=${unit.quantity.dimension}`)];
    case "CONVERT": case "INVERT": {
      const value = numberValue(words[1]), source = unitValue(database, words[2]), target = unitValue(database, words[4]);
      if (command === "INVERT") {
        if (source.dimension.equals(DIMENSIONLESS) || !source.dimension.add(target.dimension).equals(DIMENSIONLESS)) {
          fail(`NOT RECIPROCAL ${source.dimension} vs ${target.dimension}`);
        }
        if (value.n === 0n) fail("DIVISION BY ZERO");
      } else source.dimension.match(target.dimension);
      let result = value.mul(source.value);
      if (command === "INVERT") result = ONE.div(result);
      return [`${command} ${value} ${words[2]} = ${result.div(target.value).notation(words[4])}`];
    }
    case "DIM": case "REDUCE": case "SIMPLIFY": {
      const tree = parseUnit(database, words[1]), unit = evaluateUnit(database, tree);
      const result = command === "DIM" ? `${unit.dimension} factor=${unit.value} kind=${kindName(unit.dimension)}` :
        command === "REDUCE" ? reducedText(tree) : unit.value.notation(database.simplified(unit.dimension));
      return [`${command} ${words[1]} = ${result}`];
    }
    case "ADD": case "SUB": case "MUL": case "DIV": case "COMPARE": {
      const a = numberValue(words[1]), first = unitValue(database, words[2]);
      const b = numberValue(words[3]), second = unitValue(database, words[4]);
      const hasTarget = words.length === 7, target = hasTarget ? unitValue(database, words[6]) : first;
      const prefix = `${command} ${a} ${words[2]}`, suffix = `${b} ${words[4]}`;
      if (command === "ADD" || command === "SUB" || command === "COMPARE") {
        first.dimension.match(second.dimension);
        if (hasTarget) first.dimension.match(target.dimension);
        const left = a.mul(first.value), right = b.mul(second.value);
        if (command === "COMPARE") {
          const relation = ["<", "=", ">"][left.compare(right) + 1];
          return [`${prefix} ${relation} ${suffix} ratio=${right.n === 0n ? "undefined" : left.div(right)}`];
        }
        const add = command === "ADD", result = add ? left.add(right) : left.sub(right);
        return [`${prefix} ${add ? "+" : "-"} ${suffix} = ${result.div(target.value).notation(hasTarget ? words[6] : words[2])}`];
      }
      const multiply = command === "MUL", dimension = multiply ? first.dimension.add(second.dimension) : first.dimension.sub(second.dimension);
      if (!multiply && b.n === 0n) fail("DIVISION BY ZERO");
      if (hasTarget) dimension.match(target.dimension);
      const raw = multiply ? a.mul(b) : a.div(b), left = a.mul(first.value), right = b.mul(second.value);
      const coherent = multiply ? left.mul(right) : left.div(right), operation = multiply ? "*" : "/";
      const heading = `${prefix} ${operation} ${suffix} =`;
      if (hasTarget) return [`${heading} ${coherent.div(target.value).notation(words[6])}`];
      const rightUnit = !multiply && /[*/]/.test(words[4]) ? `(${words[4]})` : words[4];
      return [`${heading} ${raw} ${words[2]}${operation}${rightUnit} = ${coherent.notation(database.simplified(dimension))}`];
    }
    case "TEMP": {
      const value = numberValue(words[1]);
      for (const scale of [words[2], words[4]]) if (!["C", "F", "K", "R"].includes(scale)) fail(`UNKNOWN SCALE ${scale}`);
      const celsius = new Fraction(5463n, 20n), fahrenheit = new Fraction(45967n, 100n);
      const kelvin = words[2] === "C" ? value.add(celsius) : words[2] === "F" ? value.add(fahrenheit).mul(integer(5n)).div(integer(9n)) :
        words[2] === "R" ? value.mul(integer(5n)).div(integer(9n)) : value;
      if (kelvin.n < 0n) fail("BELOW ABSOLUTE ZERO");
      const result = words[4] === "C" ? kelvin.sub(celsius) : words[4] === "F" ? kelvin.mul(integer(9n)).div(integer(5n)).sub(fahrenheit) :
        words[4] === "R" ? kelvin.mul(integer(9n)).div(integer(5n)) : kelvin;
      return [`TEMP ${value} ${words[2]} = ${result.notation(words[4])}`];
    }
    case "LIST": {
      const dimension = kindDimension(words[1]) ?? unitValue(database, words[1]).dimension;
      const selected = database.selected(dimension);
      return [`LIST ${words[1]} dim=${dimension} kind=${kindName(dimension)} count=${selected.length}`,
        ...selected.map(unit => `UNIT ${unit.symbol} factor=${unit.quantity.value} origin=${unit.definition ? "user" : "builtin"} prefix=${unit.prefixable ? "yes" : "no"}`)];
    }
    case "TABLE": {
      const value = numberValue(words[1]), unit = unitValue(database, words[2]), selected = database.selected(unit.dimension);
      return [`TABLE ${value} ${words[2]} dim=${unit.dimension} count=${selected.length}`,
        ...selected.map(item => `ROW ${value.mul(unit.value).div(item.quantity.value).notation(item.symbol)}`)];
    }
    case "AUTO": {
      const value = numberValue(words[1]), unit = unitValue(database, words[2]);
      const reference = database.units.slice(0, BUILTINS.length).find(item => item.prefixable && item.quantity.dimension.equals(unit.dimension));
      if (!reference) fail(`NO PREFIXABLE UNIT ${unit.dimension}`);
      const scaled = value.mul(unit.value).div(reference.quantity.value), magnitude = scaled.abs();
      let exponent = 0n;
      if (magnitude.compare(ONE) >= 0) {
        while (exponent < 9n && magnitude.compare(TEN.pow(exponent + 3n)) >= 0) exponent += 3n;
      } else if (magnitude.n > 0n) {
        while (exponent > -9n && magnitude.compare(TEN.pow(exponent)) < 0) exponent -= 3n;
      }
      const prefix = ["n", "u", "m", "", "k", "M", "G"][Number((exponent + 9n) / 3n)];
      return [`AUTO ${value} ${words[2]} = ${scaled.div(TEN.pow(exponent)).notation(prefix + reference.symbol)}`];
    }
    case "SPLIT": {
      const value = numberValue(words[1]), unit = unitValue(database, words[2]);
      const parts = words[4].split(","), targets = parts.map(part => unitValue(database, part));
      if (value.n < 0n) fail("NEGATIVE VALUE");
      for (const target of targets) unit.dimension.match(target.dimension);
      for (let i = 0; i + 1 < targets.length; i++) if (targets[i].value.compare(targets[i + 1].value) <= 0) fail("UNIT ORDER");
      let remaining = value.mul(unit.value);
      const pieces: string[] = [];
      for (let i = 0; i + 1 < targets.length; i++) {
        const quotient = remaining.div(targets[i].value), whole = quotient.n / quotient.d;
        remaining = remaining.sub(integer(whole).mul(targets[i].value));
        pieces.push(`${whole} ${parts[i]}`);
      }
      pieces.push(remaining.div(targets.at(-1)!.value).notation(parts.at(-1)!));
      return [`SPLIT ${value} ${words[2]} = ${pieces.join(" ")}`];
    }
    case "LET": {
      checkName(words[1], true);
      const value = quantityValue(database, words[3]);
      database.variables.set(words[1], value);
      return [`LET ${words[1]} = ${value.value.notation(database.simplified(value.dimension))}`];
    }
    case "EVAL": {
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
    case "VARS": return [`VARS count=${database.variables.size}`, ...[...database.variables.keys()].sort().map(name => {
      const value = database.variables.get(name)!;
      return `VAR ${name} = ${value.value.notation(database.simplified(value.dimension))}`;
    })];
  }
}

const lines = readFileSync(0, "utf8").split(/\r?\n/), commandCount = Number(lines[0]);
const database = new Database(), output: string[] = [];
for (let i = 1; i <= commandCount; i++) {
  try { output.push(...execute(database, lines[i])); }
  catch (error) {
    if (!(error instanceof CommandError)) throw error;
    output.push(`ERROR ${error.message}`);
  }
}
process.stdout.write(output.join("\n") + "\n");
