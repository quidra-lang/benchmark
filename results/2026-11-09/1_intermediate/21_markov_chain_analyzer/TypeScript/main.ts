import {readFileSync} from "node:fs";

type Scalar = Fraction | bigint | number | string;

function absInt(n: bigint): bigint { return n < 0n ? -n : n; }
function gcd(a: bigint, b: bigint): bigint {
  a = absInt(a);
  b = absInt(b);
  while (b !== 0n) [a, b] = [b, a % b];
  return a;
}
function lcm(a: bigint, b: bigint): bigint { return a / gcd(a, b) * b; }

class Fraction {
  readonly n: bigint;
  readonly d: bigint;

  constructor(n: bigint | number | string, d: bigint | number | string = 1n) {
    n = BigInt(n);
    d = BigInt(d);
    if (d === 0n) throw Error("Zero denominator");
    if (d < 0n) [n, d] = [-n, -d];
    const factor = gcd(n, d);
    this.n = n / factor;
    this.d = d / factor;
  }
  static of(value: Scalar): Fraction { return value instanceof Fraction ? value : new Fraction(value); }
  add(other: Scalar): Fraction {
    other = Fraction.of(other);
    return new Fraction(this.n * other.d + other.n * this.d, this.d * other.d);
  }
  sub(other: Scalar): Fraction {
    other = Fraction.of(other);
    return new Fraction(this.n * other.d - other.n * this.d, this.d * other.d);
  }
  mul(other: Scalar): Fraction {
    other = Fraction.of(other);
    return new Fraction(this.n * other.n, this.d * other.d);
  }
  div(other: Scalar): Fraction {
    other = Fraction.of(other);
    return new Fraction(this.n * other.d, this.d * other.n);
  }
  cmp(other: Scalar): number {
    other = Fraction.of(other);
    const difference = this.n * other.d - other.n * this.d;
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
  }
  eq(other: Scalar): boolean { return this.cmp(other) === 0; }
  abs(): Fraction { return new Fraction(absInt(this.n), this.d); }
  neg(): Fraction { return new Fraction(-this.n, this.d); }
  toString(): string { return this.n + "/" + this.d; }
}
const ZERO = new Fraction(0n);
const ONE = new Fraction(1n);
const fractionText = (value: Scalar): string => Fraction.of(value).toString();
const answer = (flag: boolean): string => flag ? "yes" : "no";

function valueText(value: Scalar): string {
  value = Fraction.of(value);
  let whole = value.n / value.d;
  let remainder = value.n % value.d;
  if (remainder < 0n) {
    --whole;
    remainder += value.d;
  }
  const fraction = (remainder * 1000000n / value.d).toString().padStart(6, "0");
  return fractionText(value) + "(" + whole + "." + fraction + ")";
}
function timeText(value: Scalar | null): string { return value === null ? "inf" : valueText(value); }
function parseProbability(text: string): Fraction {
  const parts = text.split("/");
  const n = BigInt(parts[0]);
  const d = parts.length === 2 ? BigInt(parts[1]) : 1n;
  if (d === 0n || n > d) throw new CommandError("BAD PROBABILITY");
  return new Fraction(n, d);
}
function sum(values: Fraction[]): Fraction { return values.reduce((total, value) => total.add(value), ZERO); }
function delta(i: number, j: number): Fraction { return i === j ? ONE : ZERO; }
function identity(size: number): Fraction[][] {
  return Array.from({length: size}, (_, i) =>
    Array.from({length: size}, (_, j) => delta(i, j)));
}
function membership(size: number, states: number[]): boolean[] {
  const inside = Array(size).fill(false);
  for (const state of states) inside[state] = true;
  return inside;
}
function eliminate(rows: Fraction[][], size: number): Fraction[][] {
  for (let column = 0; column < size; ++column) {
    let pivotRow = column;
    while (rows[pivotRow][column].eq(ZERO)) ++pivotRow;
    [rows[column], rows[pivotRow]] = [rows[pivotRow], rows[column]];
    const pivot = rows[column][column];
    rows[column] = rows[column].map(value => value.div(pivot));
    for (let i = 0; i < size; ++i) {
      const factor = rows[i][column];
      if (i !== column && !factor.eq(ZERO)) {
        rows[i] = rows[i].map((value, j) => value.sub(factor.mul(rows[column][j])));
      }
    }
  }
  return rows.map(row => row.slice(size));
}
function igcd(a: number, b: number): number {
  a = Math.abs(a);
  b = Math.abs(b);
  while (b !== 0) [a, b] = [b, a % b];
  return a;
}

class CommandError extends Error {}

class Chain {
  readonly names: string[];
  readonly positions: Map<string, number>;
  matrix: Fraction[][];

  constructor(names: string[]) {
    this.names = [...names];
    this.positions = new Map<string, number>(names.map((name, i) => [name, i]));
    this.matrix = names.map(() => names.map(() => ZERO));
  }
  get size(): number { return this.names.length; }
  state(text: string): number {
    if (!this.positions.has(text)) throw new CommandError("UNKNOWN STATE " + text);
    return this.positions.get(text);
  }
  distinctStates(texts: string[]): number[] {
    const found = new Set();
    const states = [];
    for (const text of texts) {
      const state = this.state(text);
      if (found.has(state)) throw new CommandError("DUPLICATE STATE " + text);
      states.push(state);
      found.add(state);
    }
    return states;
  }
  labels(states: number[]): string[] { return states.map(i => this.names[i]); }
  rowSum(i: number): Fraction { return sum(this.matrix[i]); }
  blockSum(i: number, block: number[]): Fraction { return sum(block.map(j => this.matrix[i][j])); }
  edge(i: number, j: number): boolean { return this.matrix[i][j].cmp(ZERO) > 0; }
  absorbing(i: number): boolean { return this.matrix[i][i].eq(ONE); }
  advance(distribution: Fraction[]): Fraction[] {
    return this.names.map((_, j) => sum(distribution.map((prob, i) =>
      prob.mul(this.matrix[i][j]))));
  }
  reachable(start: number): boolean[] {
    const seen = Array(this.size).fill(false);
    const stack = [start];
    seen[start] = true;
    while (stack.length) {
      const i = stack.pop();
      for (let j = 0; j < this.size; ++j) {
        if (this.edge(i, j) && !seen[j]) {
          seen[j] = true;
          stack.push(j);
        }
      }
    }
    return seen;
  }
}

class CommunicatingClass {
  readonly number: number;
  readonly members: number[];
  readonly closed: boolean;
  readonly levels: number[];
  readonly period: number;

  constructor(chain: Chain, number: number, members: number[]) {
    this.number = number;
    this.members = members;
    const inside = membership(chain.size, members);
    this.closed = !members.some(i => chain.names.some((_, j) => chain.edge(i, j) && !inside[j]));
    this.levels = Array(chain.size).fill(-1);
    const queue = [members[0]];
    this.levels[members[0]] = 0;
    for (let head = 0; head < queue.length; ++head) {
      const u = queue[head];
      for (const v of members) {
        if (chain.edge(u, v) && this.levels[v] < 0) {
          this.levels[v] = this.levels[u] + 1;
          queue.push(v);
        }
      }
    }
    this.period = 0;
    for (const u of members) {
      for (const v of members) {
        if (chain.edge(u, v)) {
          this.period = igcd(this.period, this.levels[u] + 1 - this.levels[v]);
        }
      }
    }
  }
}

class Decomposition {
  readonly reach: boolean[][];
  readonly classes: CommunicatingClass[];
  readonly classOf: number[];

  constructor(chain: Chain) {
    this.reach = chain.names.map((_, i) => chain.reachable(i));
    this.classes = [];
    this.classOf = Array(chain.size).fill(-1);
    for (let i = 0; i < chain.size; ++i) {
      if (this.classOf[i] >= 0) continue;
      const members = chain.names.map((_, j) => j)
        .filter(j => this.reach[i][j] && this.reach[j][i]);
      for (const j of members) this.classOf[j] = this.classes.length;
      this.classes.push(new CommunicatingClass(chain, this.classes.length + 1, members));
    }
  }
  closedClasses(): CommunicatingClass[] { return this.classes.filter(item => item.closed); }
  containing(state: number): CommunicatingClass { return this.classes[this.classOf[state]]; }
  reaches(state: number, targets: boolean[]): boolean { return this.reach[state].some((found, i) => found && targets[i]); }
}

class Absorption {
  readonly transient: number[];
  readonly absorbing: number[];
  readonly fundamental: Fraction[][];
  readonly steps: Fraction[];
  readonly probabilities: Fraction[][];

  constructor(chain: Chain) {
    this.transient = chain.names.map((_, i) => i).filter(i => !chain.absorbing(i));
    this.absorbing = chain.names.map((_, i) => i).filter(i => chain.absorbing(i));
    const count = this.transient.length;
    const rows = this.transient.map((i, r) =>
      this.transient.map(j => delta(i, j).sub(chain.matrix[i][j]))
        .concat(Array.from({length: count}, (_, c) => delta(r, c))));
    this.fundamental = eliminate(rows, count);
    this.steps = this.fundamental.map(row => sum(row));
    this.probabilities = this.fundamental.map(row =>
      this.absorbing.map(a => sum(row.map((rho, k) =>
        rho.mul(chain.matrix[this.transient[k]][a])))));
  }
  variance(i: number): Fraction {
    const total = sum(this.fundamental[i].map((value, j) =>
      value.mul(2).sub(delta(i, j)).mul(this.steps[j])));
    return total.sub(this.steps[i].mul(this.steps[i]));
  }
}

function stationaryDistribution(chain: Chain, members: number[]): Fraction[] {
  const n = members.length;
  const rows = [];
  for (let r = 0; r < n - 1; ++r) {
    const coefficients = members.map((member, k) =>
      chain.matrix[member][members[r]].sub(delta(k, r)));
    rows.push(coefficients.concat([ZERO]));
  }
  rows.push(Array(n + 1).fill(ONE));
  return eliminate(rows, n).map(row => row[0]);
}
function irreducibleDistribution(chain: Chain, decomposition: Decomposition): Fraction[] {
  if (decomposition.classes.length > 1) throw new CommandError("NOT IRREDUCIBLE");
  return stationaryDistribution(chain, decomposition.classes[0].members);
}
function solveRestricted(chain: Chain, states: number[], constants: Fraction[]): Fraction[] {
  const rows = states.map((i, k) =>
    states.map(j => delta(i, j).sub(chain.matrix[i][j])).concat([constants[k]]));
  return eliminate(rows, states.length).map(row => row[0]);
}
function hittingProbabilities(chain: Chain, decomposition: Decomposition, targets: boolean[]): Fraction[] {
  const probabilities = chain.names.map((_, i) => targets[i] ? ONE : ZERO);
  const remaining = chain.names.map((_, i) => i)
    .filter(i => !targets[i] && decomposition.reaches(i, targets));
  if (remaining.length) {
    const constants = remaining.map(i => sum(chain.names.map((_, j) =>
      targets[j] ? chain.matrix[i][j] : ZERO)));
    const values = solveRestricted(chain, remaining, constants);
    remaining.forEach((i, k) => { probabilities[i] = values[k]; });
  }
  return probabilities;
}
function hittingTimes(chain: Chain, targets: boolean[], probabilities: Fraction[]): (Fraction | null)[] {
  const times = chain.names.map((_, i) => targets[i] ? ZERO : null);
  const certain = chain.names.map((_, i) => i)
    .filter(i => !targets[i] && probabilities[i].eq(ONE));
  if (certain.length) {
    const values = solveRestricted(chain, certain, certain.map(() => ONE));
    certain.forEach((i, k) => { times[i] = values[k]; });
  }
  return times;
}
function regularExponent(chain: Chain): number | null {
  const n = chain.size;
  const edges = chain.names.map((_, i) => chain.names.map((_, j) => chain.edge(i, j)));
  let power = edges;
  for (let exponent = 1; exponent < (n - 1) * (n - 1) + 2; ++exponent) {
    if (power.every(row => row.every(Boolean))) return exponent;
    power = power.map((row, i) => row.map((_, j) =>
      chain.names.some((__, k) => power[i][k] && edges[k][j])));
  }
  return null;
}

class MarkovAnalyzer {
  readonly chains: Map<string, Chain>;
  readonly output: string[];

  constructor() {
    this.chains = new Map<string, Chain>();
    this.output = [];
  }
  emit(...parts: unknown[]): void { this.output.push(parts.map(String).join(" ")); }
  display(names: string[], matrix: Fraction[][], label = "ROW"): void {
    this.emit("STATES", ...names);
    names.forEach((name, i) => this.emit(label, name, ...matrix[i].map(fractionText)));
  }
  requireChain(name: string): Chain {
    if (!this.chains.has(name)) throw new CommandError("UNKNOWN CHAIN " + name);
    return this.chains.get(name);
  }
  requireStochastic(name: string): Chain {
    const chain = this.requireChain(name);
    for (let i = 0; i < chain.size; ++i) {
      if (!chain.rowSum(i).eq(ONE)) {
        throw new CommandError("NOT STOCHASTIC " + chain.names[i]);
      }
    }
    return chain;
  }
  createChain(a: string[]) {
    const name = a[0], names = a.slice(1);
    if (names.length > 10) throw new CommandError("TOO MANY STATES");
    const seen = new Set();
    for (const state of names) {
      if (seen.has(state)) throw new CommandError("DUPLICATE STATE " + state);
      seen.add(state);
    }
    this.chains.set(name, new Chain(names));
    this.emit("CHAIN", name, "states=" + names.length);
  }
  setProbability(a: string[]) {
    const [name, source, target, text] = a;
    const chain = this.requireChain(name);
    const i = chain.state(source);
    const j = chain.state(target);
    const value = parseProbability(text);
    chain.matrix[i][j] = value;
    this.emit("P", name, source, target, fractionText(value),
              "rowsum=" + fractionText(chain.rowSum(i)));
  }
  setRow(a: string[]) {
    const [name, source, ...texts] = a;
    const chain = this.requireChain(name);
    const i = chain.state(source);
    if (texts.length !== chain.size) throw new CommandError("BAD LENGTH");
    const values = texts.map(parseProbability);
    chain.matrix[i] = values;
    this.emit("ROW", name, source, "rowsum=" + fractionText(chain.rowSum(i)));
  }
  show(a: string[]) {
    const chain = this.requireChain(a[0]);
    this.emit("MATRIX", a[0], "states=" + chain.size);
    this.display(chain.names, chain.matrix);
  }
  check(a: string[]) {
    const chain = this.requireChain(a[0]);
    const bad = chain.names.map((_, i) => i).filter(i => !chain.rowSum(i).eq(ONE));
    if (!bad.length) {
      this.emit("CHECK", a[0], "ok");
      return;
    }
    this.emit("CHECK", a[0], "bad=" + bad.length);
    for (const i of bad) {
      this.emit("BADROW", chain.names[i], "sum=" + fractionText(chain.rowSum(i)));
    }
  }
  build(a: string[]) {
    const name = a[0], order = Number(a[1]), tokens = a.slice(2);
    if (order !== 1 && order !== 2) throw new CommandError("BAD ORDER");
    if (tokens.length <= order) throw new CommandError("TOO FEW TOKENS");
    const observations = order === 1 ? tokens :
      tokens.slice(0, -1).map((token, i) => token + "." + tokens[i + 1]);
    const names = [...new Set(observations)];
    if (names.length > 10) throw new CommandError("TOO MANY STATES");
    const chain = new Chain(names);
    const counts = names.map(() => names.map(() => 0));
    for (let i = 0; i < observations.length - 1; ++i) {
      counts[chain.positions.get(observations[i])][chain.positions.get(observations[i + 1])]++;
    }
    this.emit("BUILD", name, "order=" + order, "states=" + names.length,
              "transitions=" + (observations.length - 1));
    for (let i = 0; i < chain.size; ++i) {
      const total = counts[i].reduce((x, y) => x + y, 0);
      if (total === 0) {
        chain.matrix[i][i] = ONE;
        this.emit("FROM", names[i], "total=0", "absorbing");
        continue;
      }
      const parts = [];
      for (let j = 0; j < chain.size; ++j) {
        if (counts[i][j] > 0) {
          chain.matrix[i][j] = new Fraction(counts[i][j], total);
          parts.push(names[j] + ":" + counts[i][j]);
        }
      }
      this.emit("FROM", names[i], "total=" + total, ...parts);
    }
    this.chains.set(name, chain);
  }
  gambler(a: string[]) {
    const name = a[0], goal = Number(a[1]), start = Number(a[2]);
    if (goal === 0 || goal > 9) throw new CommandError("BAD SIZE");
    if (start > goal) throw new CommandError("BAD START");
    const probability = parseProbability(a[3]);
    if (probability.eq(ZERO) || probability.eq(ONE))
      throw new CommandError("BAD PROBABILITY");
    const chain = new Chain(Array.from({length: goal + 1}, (_, i) => "s" + i));
    chain.matrix[0][0] = ONE;
    chain.matrix[goal][goal] = ONE;
    for (let i = 1; i < goal; ++i) {
      chain.matrix[i][i + 1] = probability;
      chain.matrix[i][i - 1] = ONE.sub(probability);
    }
    this.chains.set(name, chain);
    const absorption = new Absorption(chain);
    const ruin = [ONE, ...absorption.probabilities.map(row => row[0]), ZERO];
    const duration = [ZERO, ...absorption.steps, ZERO];
    this.emit("GAMBLER", name, "g=" + goal, "p=" + fractionText(probability),
              "start=s" + start, "ruin=" + valueText(ruin[start]),
              "duration=" + valueText(duration[start]));
    for (let i = 0; i <= goal; ++i) {
      this.emit("CAPITAL", "s" + i, "ruin=" + valueText(ruin[i]),
                "win=" + valueText(ONE.sub(ruin[i])), "duration=" + valueText(duration[i]));
    }
  }
  classes(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const decomposition = new Decomposition(chain);
    this.emit("CLASSES", a[0], "count=" + decomposition.classes.length);
    for (const item of decomposition.classes) {
      this.emit("CLASS", item.number, item.closed ? "RECURRENT" : "TRANSIENT",
                "period=" + item.period, "size=" + item.members.length,
                ...chain.labels(item.members));
      if (item.period < 2) continue;
      for (let remainder = 0; remainder < item.period; ++remainder) {
        const states = item.members.filter(i => item.levels[i] % item.period === remainder);
        this.emit("CYCLIC", remainder, ...chain.labels(states));
      }
    }
  }
  classify(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const decomposition = new Decomposition(chain);
    const absorbing = chain.names.map((_, i) => chain.absorbing(i));
    const count = absorbing.filter(Boolean).length;
    const absorbingChain = count > 0 &&
      chain.names.every((_, i) => decomposition.reaches(i, absorbing));
    const exponent = regularExponent(chain);
    this.emit("CLASSIFY", a[0], "absorbing_states=" + count,
              "absorbing=" + answer(absorbingChain),
              "ergodic=" + answer(decomposition.classes.length === 1),
              "regular=" + answer(exponent !== null),
              "exponent=" + (exponent === null ? "-" : exponent));
  }
  step(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const initial = a[1], steps = Number(a[2]);
    let distribution;
    if (/^[0-9]/.test(initial)) {
      const texts = initial.split(",");
      if (texts.length !== chain.size) throw new CommandError("BAD LENGTH");
      distribution = texts.map(parseProbability);
      if (!sum(distribution).eq(ONE)) throw new CommandError("BAD DISTRIBUTION");
    } else {
      const state = chain.state(initial);
      distribution = chain.names.map((_, i) => delta(state, i));
    }
    for (let k = 0; k < steps; ++k) distribution = chain.advance(distribution);
    this.emit("STEP", a[0], "k=" + steps);
    chain.names.forEach((name, i) => this.emit("PROB", name, valueText(distribution[i])));
  }
  power(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const steps = Number(a[1]);
    let matrix = identity(chain.size);
    for (let k = 0; k < steps; ++k) matrix = matrix.map(row => chain.advance(row));
    this.emit("POWER", a[0], "k=" + steps);
    this.display(chain.names, matrix);
  }
  stationary(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const closed = new Decomposition(chain).closedClasses();
    this.emit("STATIONARY", a[0], "count=" + closed.length);
    closed.forEach((item, index) => {
      this.emit("DIST", index + 1, "class=" + item.number, "size=" + item.members.length);
      const distribution = stationaryDistribution(chain, item.members);
      item.members.forEach((i, k) => this.emit("PI", chain.names[i], valueText(distribution[k])));
    });
  }
  recurrence(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const state = chain.state(a[1]);
    const item = new Decomposition(chain).containing(state);
    if (!item.closed) throw new CommandError("TRANSIENT STATE " + a[1]);
    const distribution = stationaryDistribution(chain, item.members);
    const rho = distribution[item.members.indexOf(state)];
    this.emit("RECURRENCE", a[0], a[1], "pi=" + valueText(rho),
              "mean=" + valueText(ONE.div(rho)), "period=" + item.period);
  }
  absorb(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const flags = chain.names.map((_, i) => chain.absorbing(i));
    if (!flags.some(Boolean)) throw new CommandError("NO ABSORBING STATE");
    const decomposition = new Decomposition(chain);
    for (let i = 0; i < chain.size; ++i) {
      if (!flags[i] && !decomposition.reaches(i, flags))
        throw new CommandError("NOT ABSORBING " + chain.names[i]);
    }
    const absorption = new Absorption(chain);
    const transientNames = chain.labels(absorption.transient);
    this.emit("ABSORB", a[0], "transient=" + absorption.transient.length,
              "absorbing=" + absorption.absorbing.length);
    if (!absorption.transient.length) return;
    this.emit("TRANSIENT", ...transientNames);
    this.emit("ABSORBING", ...chain.labels(absorption.absorbing));
    transientNames.forEach((name, i) => this.emit(
      "N", name, ...absorption.fundamental[i].map(fractionText)));
    transientNames.forEach((name, i) => this.emit(
      "STEPS", name, "mean=" + valueText(absorption.steps[i]),
      "var=" + valueText(absorption.variance(i))));
    transientNames.forEach((name, i) => this.emit(
      "B", name, ...absorption.probabilities[i].map(fractionText)));
  }
  hitting(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const targets = membership(chain.size, chain.distinctStates(a.slice(1)));
    const probabilities = hittingProbabilities(chain, new Decomposition(chain), targets);
    const times = hittingTimes(chain, targets, probabilities);
    const names = chain.names.filter((_, i) => targets[i]);
    this.emit("HITTING", a[0], "targets=" + names.join(","));
    chain.names.forEach((name, i) => this.emit(
      "HIT", name, "prob=" + valueText(probabilities[i]),
      "time=" + timeText(times[i])));
  }
  passage(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const decomposition = new Decomposition(chain);
    const pi = irreducibleDistribution(chain, decomposition);
    const times = chain.names.map(() => chain.names.map(() => ZERO));
    for (let j = 0; j < chain.size; ++j) {
      const targets = membership(chain.size, [j]);
      const probabilities = hittingProbabilities(chain, decomposition, targets);
      const column = hittingTimes(chain, targets, probabilities);
      for (let i = 0; i < chain.size; ++i) {
        times[i][j] = i === j ? ONE.div(pi[j]) : column[i];
      }
    }
    const kemeny = sum(pi.slice(1).map((rho, j) => rho.mul(times[0][j + 1])));
    this.emit("PASSAGE", a[0], "kemeny=" + valueText(kemeny));
    this.display(chain.names, times, "M");
  }
  firstPassage(a: string[]) {
    const [name, source, target, text] = a;
    const chain = this.requireStochastic(name);
    const x = chain.state(source), y = chain.state(target);
    const steps = Number(text);
    if (steps === 0) throw new CommandError("BAD STEPS");
    let current = chain.names.map((_, i) => chain.matrix[i][y]);
    const first = [current[x]];
    for (let t = 1; t < steps; ++t) {
      current = chain.names.map((_, i) => sum(
        chain.names.map((__, j) => j !== y ?
          chain.matrix[i][j].mul(current[j]) : ZERO)));
      first.push(current[x]);
    }
    this.emit("FIRSTPASSAGE", name, source, target, "k=" + steps,
              "total=" + valueText(sum(first)));
    let cumulative = ZERO;
    first.forEach((value, i) => {
      cumulative = cumulative.add(value);
      this.emit("FP", i + 1, valueText(value), "cum=" + valueText(cumulative));
    });
  }
  pathProbability(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const path = a.slice(1).map(name => chain.state(name));
    let probability = ONE, zeroAt = null;
    for (let t = 1; t < path.length; ++t) {
      probability = probability.mul(chain.matrix[path[t - 1]][path[t]]);
      if (zeroAt === null && probability.eq(ZERO)) zeroAt = t;
    }
    const parts = ["PATHPROB", a[0], "steps=" + (path.length - 1),
                   "prob=" + valueText(probability)];
    if (zeroAt !== null) parts.push("zero_at=" + zeroAt);
    this.emit(...parts);
  }
  mostLikely(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const start = chain.state(a[1]), steps = Number(a[2]);
    if (steps === 0) throw new CommandError("BAD STEPS");
    const best = Array.from({length: steps + 1}, () => Array(chain.size).fill(ONE));
    for (let t = steps - 1; t >= 0; --t) {
      best[t] = chain.names.map((_, i) =>
        chain.names.map((__, j) => chain.matrix[i][j].mul(best[t + 1][j]))
          .reduce((a, b) => a.cmp(b) >= 0 ? a : b));
    }
    const path = [start];
    for (let t = 0; t < steps; ++t) {
      const current = path[path.length - 1];
      const next = chain.names.findIndex((_, j) =>
        chain.matrix[current][j].mul(best[t + 1][j]).eq(best[t][current]));
      path.push(next);
    }
    this.emit("MOSTLIKELY", a[0], a[1], "k=" + steps,
              "prob=" + valueText(best[0][start]));
    this.emit("PATH", ...chain.labels(path));
  }
  reversible(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const pi = irreducibleDistribution(chain, new Decomposition(chain));
    const violations = [];
    for (let i = 0; i < chain.size; ++i) {
      for (let j = i + 1; j < chain.size; ++j) {
        const forward = pi[i].mul(chain.matrix[i][j]);
        const backward = pi[j].mul(chain.matrix[j][i]);
        if (!forward.eq(backward)) violations.push([i, j, forward, backward]);
      }
    }
    if (!violations.length) {
      this.emit("REVERSIBLE", a[0], "yes");
      return;
    }
    this.emit("REVERSIBLE", a[0], "no", "violations=" + violations.length);
    for (const [i, j, forward, backward] of violations) {
      this.emit("VIOLATION", chain.names[i], chain.names[j],
                valueText(forward), valueText(backward));
    }
  }
  reverse(a: string[]) {
    const [name, reversedName] = a;
    const chain = this.requireStochastic(name);
    const pi = irreducibleDistribution(chain, new Decomposition(chain));
    const reversed = new Chain(chain.names);
    for (let i = 0; i < chain.size; ++i) {
      for (let j = 0; j < chain.size; ++j) {
        reversed.matrix[i][j] = pi[j].mul(chain.matrix[j][i]).div(pi[i]);
      }
    }
    this.chains.set(reversedName, reversed);
    const same = reversed.matrix.every((row, i) =>
      row.every((value, j) => value.eq(chain.matrix[i][j])));
    this.emit("REVERSE", name, reversedName, "reversible=" + answer(same));
    this.display(reversed.names, reversed.matrix);
  }
  mixing(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const steps = Number(a[1]);
    if (steps === 0) throw new CommandError("BAD STEPS");
    const epsilon = parseProbability(a[2]);
    const pi = irreducibleDistribution(chain, new Decomposition(chain));
    let matrix = identity(chain.size), mixingTime = null;
    const lines = [];
    for (let t = 1; t <= steps; ++t) {
      matrix = matrix.map(row => chain.advance(row));
      const distances = matrix.map(row => sum(row.map((value, j) =>
        value.sub(pi[j]).abs())).div(2));
      const largest = distances.reduce((a, b) => a.cmp(b) >= 0 ? a : b);
      const worst = distances.findIndex(distance => distance.eq(largest));
      if (mixingTime === null && largest.cmp(epsilon) <= 0) mixingTime = t;
      lines.push([t, largest, chain.names[worst]]);
    }
    this.emit("MIXING", a[0], "k=" + steps, "eps=" + fractionText(epsilon),
              "time=" + (mixingTime === null ? "none" : mixingTime));
    for (const [t, value, name] of lines) {
      this.emit("TV", t, valueText(value), "from=" + name);
    }
  }
  lump(a: string[]) {
    const [name, lumpedName, partition] = a;
    const chain = this.requireStochastic(name);
    const seen = Array(chain.size).fill(false);
    const blocks = [];
    for (const group of partition.split("|")) {
      const block = [];
      for (const text of group.split(",")) {
        const state = chain.state(text);
        if (seen[state]) throw new CommandError("BAD PARTITION");
        seen[state] = true;
        block.push(state);
      }
      block.sort((a, b) => a - b);
      blocks.push(block);
    }
    if (!seen.every(Boolean)) throw new CommandError("BAD PARTITION");
    blocks.sort((a, b) => a[0] - b[0]);
    for (const block of blocks) {
      const representative = block[0];
      for (const target of blocks) {
        const expected = chain.blockSum(representative, target);
        for (const i of block) {
          const actual = chain.blockSum(i, target);
          if (!actual.eq(expected)) {
            this.emit("LUMP", name, "not", "lumpable",
                      "block=" + chain.names[representative],
                      "target=" + chain.names[target[0]],
                      chain.names[representative] + "=" + valueText(expected),
                      chain.names[i] + "=" + valueText(actual));
            return;
          }
        }
      }
    }
    const lumped = new Chain(blocks.map(block => chain.names[block[0]]));
    lumped.matrix = blocks.map(block => blocks.map(target =>
      chain.blockSum(block[0], target)));
    this.chains.set(lumpedName, lumped);
    this.emit("LUMP", name, lumpedName, "blocks=" + blocks.length);
    this.display(lumped.names, lumped.matrix);
  }
  reward(a: string[]) {
    const chain = this.requireStochastic(a[0]);
    const texts = a.slice(2);
    if (texts.length !== chain.size) throw new CommandError("BAD LENGTH");
    const gamma = parseProbability(a[1]);
    if (gamma.eq(ONE)) throw new CommandError("BAD DISCOUNT");
    const rewards = texts.map(text => new Fraction(BigInt(text)));
    const matrix = chain.names.map((_, i) =>
      chain.names.map((__, j) => delta(i, j).sub(gamma.mul(chain.matrix[i][j])))
        .concat([rewards[i]]));
    const values = eliminate(matrix, chain.size).map(row => row[0]);
    const decomposition = new Decomposition(chain);
    const gains = chain.names.map(() => ZERO);
    for (const item of decomposition.closedClasses()) {
      const distribution = stationaryDistribution(chain, item.members);
      const gain = sum(distribution.map((rho, j) => rho.mul(rewards[item.members[j]])));
      const targets = membership(chain.size, item.members);
      const probabilities = hittingProbabilities(chain, decomposition, targets);
      for (let i = 0; i < chain.size; ++i) {
        gains[i] = gains[i].add(probabilities[i].mul(gain));
      }
    }
    this.emit("REWARD", a[0], "gamma=" + fractionText(gamma));
    chain.names.forEach((name, i) => this.emit(
      "VALUE", name, "discounted=" + valueText(values[i]),
      "gain=" + valueText(gains[i])));
  }
  restrict(a: string[]) {
    const [name, restrictedName, ...texts] = a;
    const chain = this.requireStochastic(name);
    const inside = membership(chain.size, chain.distinctStates(texts));
    for (let i = 0; i < chain.size; ++i) {
      if (inside[i] && chain.names.some((_, j) => chain.edge(i, j) && !inside[j]))
        throw new CommandError("NOT CLOSED " + chain.names[i]);
    }
    const members = chain.names.map((_, i) => i).filter(i => inside[i]);
    const restricted = new Chain(chain.labels(members));
    restricted.matrix = members.map(i => members.map(j => chain.matrix[i][j]));
    this.chains.set(restrictedName, restricted);
    this.emit("RESTRICT", name, restrictedName, "states=" + members.length);
    this.display(restricted.names, restricted.matrix);
  }
  simulate(a: string[]) {
    const [name, source] = a;
    const chain = this.requireStochastic(name);
    const start = chain.state(source);
    const steps = Number(a[2]), seed = Number(a[3]);
    if (steps === 0) throw new CommandError("BAD STEPS");
    if (seed === 0 || seed >= 2147483647) throw new CommandError("BAD SEED");
    let random = seed;
    const path = [start];
    for (let t = 0; t < steps; ++t) {
      const row = chain.matrix[path[path.length - 1]];
      const common = row.map(value => value.d).reduce(lcm);
      random = 48271 * random % 2147483647;
      const threshold = BigInt(random) % common;
      let cumulative = ZERO;
      for (let j = 0; j < chain.size; ++j) {
        cumulative = cumulative.add(row[j]);
        if (cumulative.n * common > threshold * cumulative.d) {
          path.push(j);
          break;
        }
      }
    }
    this.emit("SIMULATE", name, source, "steps=" + steps, "seed=" + seed,
              "end=" + chain.names[path[path.length - 1]]);
    this.emit("PATH", ...chain.labels(path));
    chain.names.forEach((state, i) => this.emit(
      "VISIT", state, path.filter(value => value === i).length));
  }
  execute(line: string): void {
    const [command, ...args] = line.split(" ");
    const handlers = {
      CHAIN: this.createChain, P: this.setProbability, ROW: this.setRow,
      SHOW: this.show, CHECK: this.check, BUILD: this.build,
      GAMBLER: this.gambler, CLASSES: this.classes, CLASSIFY: this.classify,
      STEP: this.step, POWER: this.power, STATIONARY: this.stationary,
      RECURRENCE: this.recurrence, ABSORB: this.absorb, HITTING: this.hitting,
      PASSAGE: this.passage, FIRSTPASSAGE: this.firstPassage,
      PATHPROB: this.pathProbability, MOSTLIKELY: this.mostLikely,
      REVERSIBLE: this.reversible, REVERSE: this.reverse, MIXING: this.mixing,
      LUMP: this.lump, REWARD: this.reward, RESTRICT: this.restrict,
      SIMULATE: this.simulate
    };
    try {
      handlers[command].call(this, args);
    } catch (error) {
      if (error instanceof CommandError) {
        this.emit("ERROR", error.message);
      } else {
        throw error;
      }
    }
  }
}

const lines = readFileSync(0, "utf8").trimEnd().split("\n");
const count = Number(lines[0]);
const analyzer = new MarkovAnalyzer();
for (let i = 1; i <= count; ++i) analyzer.execute(lines[i]);
process.stdout.write(analyzer.output.join("\n") + "\n");
