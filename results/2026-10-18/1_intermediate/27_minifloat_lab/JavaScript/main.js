const fs = require('node:fs');

const INVALID = 1, DIVBYZERO = 2, OVERFLOW = 4, UNDERFLOW = 8, INEXACT = 16;
const MODES = new Set(['RNE', 'RNA', 'RTZ', 'RUP', 'RDN']);
const TYPES = new Map([
  ['I8', [-128n, 127n]], ['U8', [0n, 255n]],
  ['I16', [-32768n, 32767n]], ['U16', [0n, 65535n]],
  ['I32', [-2147483648n, 2147483647n]], ['U32', [0n, 4294967295n]],
]);

class CommandError extends Error {}
function fail(message) { throw new CommandError(message); }

function flagsText(flags) {
  const names = ['invalid', 'divbyzero', 'overflow', 'underflow', 'inexact'];
  return 'flags=' + (names.filter((_, index) => flags & (1 << index)).join(',') || 'none');
}

function modeOf(word = 'RNE') {
  if (!MODES.has(word)) fail(`BAD MODE ${word}`);
  return word;
}

function gcd(a, b) {
  while (b !== 0n) [a, b] = [b, a % b];
  return a;
}

function scaled(numerator, denominator, exponent) {
  return exponent >= 0
    ? [numerator << BigInt(exponent), denominator]
    : [numerator, denominator << BigInt(-exponent)];
}

function integerSqrt(value) {
  if (value === 0n) return 0n;
  let root = 1n << BigInt((value.toString(2).length + 1) >> 1);
  while (true) {
    const next = (root + value / root) >> 1n;
    if (next >= root) return root;
    root = next;
  }
}

class Exact {
  constructor(numerator, exponent = 0, denominator = 1n, sign = 0) {
    this.n = numerator;
    this.e = exponent;
    this.d = denominator;
    this.sign = sign;
  }

  negated() { return new Exact(this.n, this.e, this.d, this.sign ^ 1); }

  log2Floor() {
    let result = this.n.toString(2).length - this.d.toString(2).length + this.e;
    const [n, d] = scaled(this.n, this.d, this.e - result);
    if (n < d) result--;
    return result;
  }

  fraction() {
    if (this.n === 0n) return '0';
    let [n, d] = scaled(this.n, this.d, this.e);
    const factor = gcd(n, d);
    n /= factor;
    d /= factor;
    return (this.sign ? '-' : '') + n + (d === 1n ? '' : `/${d}`);
  }

  decimal(keepZeroSign = false) {
    const [n, d] = scaled(this.n, this.d, this.e);
    let text = String(n / d);
    let remainder = n % d;
    if (remainder !== 0n) {
      text += '.';
      while (remainder !== 0n) {
        remainder *= 10n;
        text += remainder / d;
        remainder %= d;
      }
    }
    return (this.sign && (this.n !== 0n || keepZeroSign) ? '-' : '') + text;
  }
}

function exactProduct(a, b) {
  return new Exact(a.n * b.n, a.e + b.e, a.d * b.d, a.sign ^ b.sign);
}

function exactSum(terms, mode) {
  const nonzero = terms.filter(term => term.n !== 0n);
  if (nonzero.length === 0) {
    const sameSign = terms.every(term => term.sign === terms[0].sign);
    return new Exact(0n, 0, 1n, sameSign ? terms[0].sign : Number(mode === 'RDN'));
  }
  const exponent = Math.min(...nonzero.map(term => term.e));
  let numerator = 0n;
  for (const term of nonzero) {
    const aligned = term.n << BigInt(term.e - exponent);
    numerator += term.sign ? -aligned : aligned;
  }
  const sign = numerator < 0n ? 1 : numerator === 0n ? Number(mode === 'RDN') : 0;
  return new Exact(numerator < 0n ? -numerator : numerator, exponent, 1n, sign);
}

function increment(mode, sign, integer, inexact, halfway) {
  if (!inexact) return false;
  if (mode === 'RNE') return halfway > 0n || halfway === 0n && integer % 2n === 1n;
  if (mode === 'RNA') return halfway >= 0n;
  if (mode === 'RUP') return sign === 0;
  if (mode === 'RDN') return sign === 1;
  return false;
}

function roundedUnits(value, exponent, mode) {
  const [n, d] = scaled(value.n, value.d, value.e - exponent);
  let integer = n / d;
  const remainder = n % d;
  const inexact = remainder !== 0n;
  if (increment(mode, value.sign, integer, inexact, 2n * remainder - d)) integer++;
  return { integer, inexact };
}

function roundedSqrtUnits(value, exponent, mode) {
  const [n, d] = scaled(value.n, value.d, value.e - 2 * exponent);
  let integer = integerSqrt(n / d);
  const inexact = integer * integer * d !== n;
  const twiceMidpoint = 2n * integer + 1n;
  const halfway = 4n * n - d * twiceMidpoint * twiceMidpoint;
  if (increment(mode, 0, integer, inexact, halfway)) integer++;
  return { integer, inexact };
}

class Format {
  constructor(name, e, m) {
    this.name = name;
    this.e = e;
    this.m = m;
    this.w = 1 + e + m;
    this.bias = (1 << (e - 1)) - 1;
    this.emin = 1 - this.bias;
    this.emax = this.bias;
    this.hidden = 1 << m;
    this.exponentMask = (1 << e) - 1;
    this.signBit = 1 << (e + m);
    this.infinity = this.exponentMask * this.hidden;
    this.nan = this.infinity + (this.hidden >> 1);
    this.maximum = this.infinity - 1;
  }

  fields(pattern) {
    const sign = pattern & this.signBit ? 1 : 0;
    const exponent = (pattern >> this.m) & this.exponentMask;
    const fraction = pattern & (this.hidden - 1);
    const q = (exponent === 0 ? this.emin : exponent - this.bias) - this.m;
    return { sign, exponent, fraction, q };
  }

  isNaN(pattern) { const f = this.fields(pattern); return f.exponent === this.exponentMask && f.fraction !== 0; }
  isSignaling(pattern) { return this.isNaN(pattern) && this.fields(pattern).fraction < (this.hidden >> 1); }
  isInfinity(pattern) { return (pattern & (this.signBit - 1)) === this.infinity; }
  isZero(pattern) { return (pattern & (this.signBit - 1)) === 0; }
  isFinite(pattern) { return this.fields(pattern).exponent !== this.exponentMask; }
  zero(sign) { return sign * this.signBit; }
  inf(sign) { return this.zero(sign) + this.infinity; }
  flip(pattern) { return pattern ^ this.signBit; }

  exact(pattern) {
    const f = this.fields(pattern);
    return new Exact(BigInt(f.exponent === 0 ? f.fraction : this.hidden + f.fraction), f.q, 1n, f.sign);
  }

  bits(pattern) {
    const f = this.fields(pattern);
    return `${f.sign}|${f.exponent.toString(2).padStart(this.e, '0')}|${f.fraction.toString(2).padStart(this.m, '0')}`;
  }

  hex(pattern) { return '0x' + pattern.toString(16).toUpperCase().padStart((this.w + 3) >> 2, '0'); }

  value(pattern) {
    if (this.isNaN(pattern)) return 'nan';
    if (this.isInfinity(pattern)) return this.fields(pattern).sign ? '-inf' : 'inf';
    return this.exact(pattern).decimal(true);
  }

  patternText(pattern) { return `${this.bits(pattern)} ${this.hex(pattern)} ${this.value(pattern)}`; }
  resultText(result) { return `${this.patternText(result.pattern)} ${flagsText(result.flags)}`; }

  overflow(sign, mode) {
    const infinity = mode === 'RNE' || mode === 'RNA' || mode === 'RUP' && sign === 0 || mode === 'RDN' && sign === 1;
    return { pattern: this.zero(sign) + (infinity ? this.infinity : this.maximum), flags: OVERFLOW | INEXACT };
  }

  finishRound(sign, t, exponent, units, unbounded, mode) {
    const hidden = BigInt(this.hidden);
    let n = units.integer;
    if (n === 2n * hidden) {
      n = hidden;
      exponent++;
    }
    if (exponent > this.emax - this.m) return this.overflow(sign, mode);
    const magnitude = n >= hidden
      ? (exponent + this.m + this.bias) * this.hidden + Number(n - hidden)
      : Number(n);
    let flags = units.inexact ? INEXACT : 0;
    if (units.inexact && t < this.emin && (t < this.emin - 1 || unbounded().integer < 2n * hidden)) {
      flags |= UNDERFLOW;
    }
    return { pattern: this.zero(sign) + magnitude, flags };
  }

  round(value, mode) {
    if (value.n === 0n) return { pattern: this.zero(value.sign), flags: 0 };
    const t = value.log2Floor();
    if (t > this.emax) return this.overflow(value.sign, mode);
    const exponent = Math.max(t, this.emin) - this.m;
    return this.finishRound(value.sign, t, exponent, roundedUnits(value, exponent, mode),
      () => roundedUnits(value, t - this.m, mode), mode);
  }

  sqrt(value, mode) {
    const log = value.log2Floor();
    const t = log >= 0 ? log >> 1 : -((-log + 1) >> 1);
    const exponent = Math.max(t, this.emin) - this.m;
    return this.finishRound(0, t, exponent, roundedSqrtUnits(value, exponent, mode),
      () => roundedSqrtUnits(value, t - this.m, mode), mode);
  }
}

function parseReal(word) {
  if (word === 'nan' || word === 'inf' || word === '-inf') return { special: word };
  if (word.startsWith('0b') || word.startsWith('0x')) fail(`BAD OPERAND ${word}`);
  const sign = word.startsWith('-') ? 1 : 0;
  const body = sign ? word.slice(1) : word;
  if (body.includes('/')) {
    const [p, q] = body.split('/').map(BigInt);
    if (q === 0n) fail(`BAD OPERAND ${word}`);
    return { exact: new Exact(p, 0, q, sign) };
  }
  const [whole, fraction = ''] = body.split('.');
  return { exact: new Exact(BigInt(whole + fraction), 0, 10n ** BigInt(fraction.length), sign) };
}

function encoded(format, real, mode) {
  if (real.special === 'nan') return { pattern: format.nan, flags: 0 };
  if (real.special) return { pattern: format.inf(Number(real.special === '-inf')), flags: 0 };
  return format.round(real.exact, mode);
}

function operand(format, word) {
  if (word.startsWith('0b')) {
    if (word.length - 2 !== format.w) fail(`BAD OPERAND ${word}`);
    return Number(BigInt(word));
  }
  if (word.startsWith('0x')) {
    const pattern = Number(BigInt(word));
    if (word.length - 2 !== ((format.w + 3) >> 2) || pattern >= (1 << format.w)) fail(`BAD OPERAND ${word}`);
    return pattern;
  }
  return encoded(format, parseReal(word), 'RNE').pattern;
}

function operation(format, command, inputs, mode) {
  if (command === 'SUB') return operation(format, 'ADD', [inputs[0], format.flip(inputs[1])], mode);
  if (inputs.some(pattern => format.isNaN(pattern))) {
    return { pattern: format.nan, flags: inputs.some(pattern => format.isSignaling(pattern)) ? INVALID : 0 };
  }
  const [a, b, c] = inputs;
  const result = (pattern, flags = 0) => ({ pattern, flags });
  const invalid = () => result(format.nan, INVALID);
  const aSign = format.fields(a).sign;
  if (command === 'SQRT') {
    if (format.isZero(a)) return result(a);
    if (aSign) return invalid();
    if (format.isInfinity(a)) return result(a);
    return format.sqrt(format.exact(a), mode);
  }
  const sigma = aSign ^ format.fields(b).sign;
  if (command === 'ADD') {
    if (format.isInfinity(a) && format.isInfinity(b) && sigma) return invalid();
    if (format.isInfinity(a)) return result(a);
    if (format.isInfinity(b)) return result(b);
    return format.round(exactSum([format.exact(a), format.exact(b)], mode), mode);
  }
  if (command === 'MUL') {
    if (format.isInfinity(a) || format.isInfinity(b)) {
      return format.isZero(a) || format.isZero(b) ? invalid() : result(format.inf(sigma));
    }
    if (format.isZero(a) || format.isZero(b)) return result(format.zero(sigma));
    return format.round(exactProduct(format.exact(a), format.exact(b)), mode);
  }
  if (command === 'DIV') {
    if (format.isInfinity(a)) return format.isInfinity(b) ? invalid() : result(format.inf(sigma));
    if (format.isInfinity(b)) return result(format.zero(sigma));
    if (format.isZero(b)) return format.isZero(a) ? invalid() : result(format.inf(sigma), DIVBYZERO);
    if (format.isZero(a)) return result(format.zero(sigma));
    const x = format.exact(a), y = format.exact(b);
    return format.round(new Exact(x.n * y.d, x.e - y.e, x.d * y.n, sigma), mode);
  }
  if (format.isInfinity(a) || format.isInfinity(b)) {
    if (format.isZero(a) || format.isZero(b) || format.isInfinity(c) && format.fields(c).sign !== sigma) return invalid();
    return result(format.inf(sigma));
  }
  if (format.isInfinity(c)) return result(c);
  return format.round(exactSum([exactProduct(format.exact(a), format.exact(b)), format.exact(c)], mode), mode);
}

function nextUp(format, pattern) {
  if (pattern === format.infinity) return pattern;
  if (format.isZero(pattern)) return 1;
  return pattern + (format.fields(pattern).sign ? -1 : 1);
}

function difference(format, pattern, exact) {
  if (!format.isFinite(pattern)) return format.value(pattern);
  return exactSum([format.exact(pattern), exact.negated()], 'RNE').fraction();
}

const relation = (a, b) => a < b ? 'LT' : a > b ? 'GT' : 'EQ';

class Laboratory {
  constructor() {
    this.formats = new Map([['HALF', new Format('HALF', 5, 10)], ['E5M2', new Format('E5M2', 5, 2)], ['E4M3', new Format('E4M3', 4, 3)]]);
    this.output = [];
  }

  emit(line) { this.output.push(line); }

  format(name) {
    if (!this.formats.has(name)) fail(`UNKNOWN FORMAT ${name}`);
    return this.formats.get(name);
  }

  summary(format, mode, patterns, pattern, flags) {
    const exact = exactSum(patterns.map(pattern => format.exact(pattern)), mode);
    this.emit(`RESULT ${format.resultText({ pattern, flags })}`);
    this.emit(`EXACT ${exact.decimal()}`);
    this.emit(`ROUNDED ${format.resultText(format.round(exact, mode))}`);
    this.emit(`DIFF ${difference(format, pattern, exact)}`);
  }

  summation(command, format, mode, patterns) {
    if (patterns.some(pattern => !format.isFinite(pattern))) fail('NOT FINITE');
    this.emit(`${command} ${format.name} ${mode} count=${patterns.length}`);
    let sum = patterns[0], compensation = 0, flags = 0;
    for (let i = 1; i < patterns.length; i++) {
      if (command === 'SUM') {
        const added = operation(format, 'ADD', [sum, patterns[i]], mode);
        sum = added.pattern;
        flags |= added.flags;
        this.emit(`PARTIAL ${i + 1} ${format.resultText(added)}`);
      } else {
        const y = operation(format, 'SUB', [patterns[i], compensation], mode);
        const t = operation(format, 'ADD', [sum, y.pattern], mode);
        const d = operation(format, 'SUB', [t.pattern, sum], mode);
        const c = operation(format, 'SUB', [d.pattern, y.pattern], mode);
        sum = t.pattern;
        compensation = c.pattern;
        const stepFlags = y.flags | t.flags | d.flags | c.flags;
        flags |= stepFlags;
        this.emit(`KSTEP ${i + 1} sum=${format.value(sum)} comp=${format.value(compensation)} ${flagsText(stepFlags)}`);
      }
    }
    this.summary(format, mode, patterns, sum, flags);
  }

  dot(format, mode, a, b) {
    if (a.length !== b.length) fail('LENGTH MISMATCH');
    if ([...a, ...b].some(pattern => !format.isFinite(pattern))) fail('NOT FINITE');
    let naive = operation(format, 'MUL', [a[0], b[0]], mode);
    let chained = { ...naive };
    for (let i = 1; i < a.length; i++) {
      const product = operation(format, 'MUL', [a[i], b[i]], mode);
      const added = operation(format, 'ADD', [naive.pattern, product.pattern], mode);
      naive = { pattern: added.pattern, flags: naive.flags | product.flags | added.flags };
      const fused = operation(format, 'FMA', [a[i], b[i], chained.pattern], mode);
      chained = { pattern: fused.pattern, flags: chained.flags | fused.flags };
    }
    const exact = exactSum(a.map((pattern, i) => exactProduct(format.exact(pattern), format.exact(b[i]))), mode);
    this.emit(`DOT ${format.name} ${mode} n=${a.length}`);
    this.emit(`NAIVE ${format.resultText(naive)}`);
    this.emit(`CHAINED ${format.resultText(chained)}`);
    this.emit(`EXACT ${exact.decimal()}`);
    this.emit(`FUSED ${format.resultText(format.round(exact, mode))}`);
    this.emit(`DIFF naive=${difference(format, naive.pattern, exact)} chained=${difference(format, chained.pattern, exact)}`);
  }

  table(format) {
    if (format.w > 8) fail('TABLE TOO LARGE');
    const count = format.infinity;
    this.emit(`TABLE ${format.name} count=${count}`);
    for (let pattern = 0; pattern < count; pattern++) {
      const gap = pattern === count - 1 ? '-'
        : exactSum([format.exact(pattern + 1), format.exact(pattern).negated()], 'RNE').decimal();
      this.emit(`ENTRY ${pattern} ${format.patternText(pattern)} gap=${gap}`);
    }
    this.emit(`MAX ${format.patternText(format.maximum)}`);
    this.emit(`MINNORMAL ${format.patternText(format.hidden)}`);
    this.emit(`MINSUBNORMAL ${format.patternText(1)}`);
    this.emit(`EPSILON ${new Exact(1n, -format.m).decimal()}`);
    this.emit(`PATTERNS finite=${2 * count} infinite=2 nan=${2 * (format.hidden - 1)} total=${1 << format.w}`);
  }

  command(line) {
    const words = line.split(' ');
    const command = words[0];
    if (command === 'FORMAT') {
      const name = words[1], e = Number(words[2]), m = Number(words[3]);
      if (this.formats.has(name)) fail(`FORMAT EXISTS ${name}`);
      if (e < 2 || e > 5 || m < 1 || m > 10) fail('BAD FORMAT');
      const format = new Format(name, e, m);
      this.formats.set(name, format);
      this.emit(`FORMAT ${name} e=${e} m=${m} bits=${format.w} bias=${format.bias} emin=${format.emin} emax=${format.emax}`);
      return;
    }

    const format = this.format(words[1]);
    const name = format.name;
    if (command === 'ENCODE') {
      const real = parseReal(words[2]);
      const mode = modeOf(words[3]);
      const value = real.special ?? real.exact.fraction();
      this.emit(`ENCODE ${name} ${mode} ${value} ${format.resultText(encoded(format, real, mode))}`);
    } else if (command === 'CONVERT') {
      const target = this.format(words[2]);
      const a = operand(format, words[3]);
      const mode = modeOf(words[4]);
      let result;
      if (format.isNaN(a)) result = { pattern: target.nan, flags: format.isSignaling(a) ? INVALID : 0 };
      else if (format.isInfinity(a)) result = { pattern: target.inf(format.fields(a).sign), flags: 0 };
      else result = target.round(format.exact(a), mode);
      this.emit(`CONVERT ${name} ${target.name} ${mode} ${target.resultText(result)}`);
    } else if (command === 'SUM' || command === 'KAHAN' || command === 'DOT') {
      const mode = modeOf(words[2]);
      if (command === 'DOT') {
        const separator = words.indexOf('|');
        const a = words.slice(3, separator).map(word => operand(format, word));
        const b = words.slice(separator + 1).map(word => operand(format, word));
        this.dot(format, mode, a, b);
      } else {
        const patterns = words.slice(3).map(word => operand(format, word));
        this.summation(command, format, mode, patterns);
      }
    } else if (command === 'TABLE') this.table(format);
    else if (['ADD', 'SUB', 'MUL', 'DIV', 'SQRT', 'FMA'].includes(command)) {
      const count = command === 'SQRT' ? 1 : command === 'FMA' ? 3 : 2;
      const patterns = words.slice(2, 2 + count).map(word => operand(format, word));
      const mode = modeOf(words[2 + count]);
      this.emit(`${command} ${name} ${mode} ${format.resultText(operation(format, command, patterns, mode))}`);
    } else {
      const a = operand(format, words[2]);
      const fields = format.fields(a);
      if (command === 'DECODE') {
        const classification = format.isNaN(a) ? format.isSignaling(a) ? 'snan' : 'qnan'
          : format.isInfinity(a) ? 'infinity' : format.isZero(a) ? 'zero' : fields.exponent === 0 ? 'subnormal' : 'normal';
        this.emit(`DECODE ${name} ${format.bits(a)} ${format.hex(a)} ${classification} sign=${fields.sign}`);
        let line = `FIELDS exponent=${fields.exponent} fraction=${fields.fraction}`;
        if (format.isFinite(a)) {
          line += ` unbiased=${fields.q + format.m} significand=${fields.exponent === 0 ? 0 : 1}.${fields.fraction.toString(2).padStart(format.m, '0')}`;
          this.emit(line);
          this.emit(`VALUE ${format.exact(a).fraction()} ${format.value(a)}`);
        } else {
          if (format.isNaN(a)) line += ` payload=${fields.fraction % (format.hidden >> 1)}`;
          this.emit(line);
        }
      } else if (command === 'COMPARE') {
        const b = operand(format, words[3]);
        const key = pattern => format.fields(pattern).sign ? -(pattern - format.signBit) - 1 : pattern;
        const order = relation(key(a), key(b));
        const numeric = format.isNaN(a) || format.isNaN(b) ? 'UN'
          : format.isZero(a) && format.isZero(b) ? 'EQ' : order;
        const flags = format.isSignaling(a) || format.isSignaling(b) ? INVALID : 0;
        this.emit(`COMPARE ${name} ${format.hex(a)} ${format.hex(b)} ${numeric} total=${order} ${flagsText(flags)}`);
      } else if (command === 'TOINT') {
        const type = words[3];
        if (!TYPES.has(type)) fail(`BAD TYPE ${type}`);
        const mode = modeOf(words[4]);
        const prefix = `TOINT ${name} ${type} ${mode}`;
        if (!format.isFinite(a)) this.emit(`${prefix} invalid flags=invalid`);
        else {
          const units = roundedUnits(format.exact(a), 0, mode);
          const integer = fields.sign ? -units.integer : units.integer;
          const [minimum, maximum] = TYPES.get(type);
          if (integer < minimum || integer > maximum) this.emit(`${prefix} invalid flags=invalid`);
          else this.emit(`${prefix} ${integer} ${flagsText(units.inexact ? INEXACT : 0)}`);
        }
      } else {
        let result;
        if (format.isNaN(a)) result = { pattern: format.nan, flags: format.isSignaling(a) ? INVALID : 0 };
        else if (command === 'NEXTUP') result = { pattern: nextUp(format, a), flags: 0 };
        else if (command === 'NEXTDOWN') result = { pattern: format.flip(nextUp(format, format.flip(a))), flags: 0 };
        else {
          const pattern = format.isInfinity(a) ? format.infinity : format.round(new Exact(1n, fields.q), 'RNE').pattern;
          result = { pattern, flags: 0 };
        }
        this.emit(`${command} ${name} ${format.resultText(result)}`);
      }
    }
  }
}

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/);
const commandCount = Number(lines[0]);
const lab = new Laboratory();
for (let i = 1; i <= commandCount; i++) {
  try {
    lab.command(lines[i]);
  } catch (error) {
    if (!(error instanceof CommandError)) throw error;
    lab.emit(`ERROR ${error.message}`);
  }
}
process.stdout.write(lab.output.join('\n') + '\n');
