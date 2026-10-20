import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import * as signals from './signals.ts';
import * as effects from './effects.ts';
import * as filters from './filters.ts';
import * as dynamics from './dynamics.ts';
import * as analysis from './analysis.ts';
import { Signal, ceilDiv, floorDiv, rdiv, type Generated } from './signals.ts';

interface Arguments {
  n: Record<string, number>; text: Record<string, string>; integers: number[]; ingredients: Signal[];
  length: number; rate: number; result: number; low: number; high: number;
}
type Bound = number | ((args: Arguments) => number);
type Argument = { kind: 'name' | 'signal' | 'metric'; label: string }
  | { kind: 'operator'; label: string; choices: string[] }
  | { kind: 'integer'; label: string; lower: Bound; upper: Bound };
interface Definition { accepts(count: number): boolean; schema(count: number): Argument[] }
interface Execution { details: string; following?: string[] }
const integer = (label: string, lower: Bound, upper: Bound): Argument => ({ kind: 'integer', label, lower, upper });
const destination: Argument = { kind: 'name', label: 'dst' }, source: Argument = { kind: 'signal', label: 'src' };
const variable: Argument = { kind: 'name', label: 'var' }, metric: Argument = { kind: 'metric', label: 'metric' };
const arithmeticOperator: Argument = { kind: 'operator', label: 'op', choices: ['+', '-', '*', '/'] };
const comparisonOperator: Argument = { kind: 'operator', label: 'op', choices: ['eq', 'ne', 'lt', 'le', 'gt', 'ge'] };
function fixed(...args: Argument[]): Definition { return { accepts: count => count === args.length, schema: () => args }; }
function repeated(prefix: Argument[], group: Argument[], minimum: number, maximum: number): Definition {
  return { accepts: count => count >= prefix.length + minimum * group.length && count <= prefix.length + maximum * group.length
    && (count - prefix.length) % group.length === 0,
  schema: count => [...prefix, ...Array.from({ length: floorDiv(count - prefix.length, group.length) }, () => group).flat()] };
}
const amplitudeArguments = [destination, integer('rate', 1000, 48000), integer('count', 1, 20000),
  integer('pos', 0, a => a.n.count - 1), integer('amp', -32768, 32767)];
const commandTable = new Map<string, Definition>([
  ['SET', { accepts: count => count === 2 || count === 4, schema: count => [variable, integer('value', -10000000, 10000000),
    ...(count === 4 ? [arithmeticOperator, integer('operand', -10000000, 10000000)] : [])] }],
  ['IMPULSE', fixed(...amplitudeArguments)], ['STEP', fixed(...amplitudeArguments)],
  ['NOISE', fixed(destination, integer('rate', 1000, 48000), integer('count', 1, 20000), integer('seed', 1, 2147483646))],
  ['GAIN', fixed(destination, source, integer('num', -65536, 65536), integer('den', 1, 65536))],
  ['MIX', repeated([destination, integer('den', 1, 65536)], [source, integer('weight', -65536, 65536)], 1, 8)],
  ['DELAY', fixed(destination, source, integer('samples', 0, 20000))],
  ['ECHO', fixed(destination, source, integer('delay', 1, 20000), integer('num', -65536, 65536), integer('den', 1, 65536), integer('tail', 0, 20000))],
  ['RESAMPLE', fixed(destination, source, integer('new_rate', 1000, 48000))],
  ['FADE', fixed(destination, source, integer('in', 0, a => a.length), integer('out', 0, a => a.length))],
  ['TRIM', fixed(destination, source, integer('start', 0, a => a.length - 1), integer('count', 1, a => a.length - a.n.start))],
  ['CONCAT', repeated([destination], [source], 2, 8)],
  ['FIR', repeated([destination, source, integer('divisor', 1, 1000000)], [integer('tap', -32768, 32767)], 1, 64)],
  ['BIQUAD', repeated([destination, source], ['b0', 'b1', 'b2', 'a1', 'a2'].map(label => integer(label, -65536, 65536)), 1, 4)],
  ['MOVAVG', fixed(destination, source, integer('width', 1, 1000))],
  ['DCBLOCK', fixed(destination, source, integer('num', 0, 65535), integer('den', a => a.n.num + 1, 65536))],
  ['NORMALIZE', fixed(destination, source, integer('target', 1, 32767))],
  ['GATE', fixed(destination, source, integer('threshold', 1, 32768), integer('hold', 0, 20000))],
  ['ENVELOPE', fixed(destination, source, integer('attack', 1, 32768), integer('release', 1, 32768))],
  ['COMPRESS', fixed(destination, source, integer('threshold', 1, 32767), integer('ratio_num', 1, 100),
    integer('ratio_den', 1, a => a.n.ratio_num), integer('attack', 1, 32768), integer('release', 1, 32768))],
  ['ANALYZE', fixed(source, integer('min_hz', 1, a => floorDiv(a.rate, 2) - 1), integer('max_hz', a => a.n.min_hz + 1, a => floorDiv(a.rate, 2)))],
  ['COMPARE', fixed(source, source)], ['EXPECT', fixed(source, metric, comparisonOperator, integer('value', -1000000000, 1000000000))],
  ['SEGMENTS', fixed(source, integer('threshold', 1, 32768), integer('gap', 1, 20000), integer('min_length', 1, 20000))],
  ['ONSETS', fixed(source, integer('attack', 1, 32768), integer('release', 1, 32768), integer('threshold', 1, 32767), integer('min_gap', 1, 20000))],
  ['PITCHTRACK', fixed(source, integer('frame', 16, a => a.length), integer('hop', 1, a => a.n.frame),
    integer('min_hz', 1, a => floorDiv(a.rate, 2) - 1), integer('max_hz', a => a.n.min_hz + 1, a => floorDiv(a.rate, 2)), integer('threshold', 0, 32767))],
  ['EXCERPT', fixed(source, integer('start', 0, a => a.length - 1), integer('count', 1, 1000))],
  ['PLOT', fixed(source, integer('start', 0, a => a.length - 1), integer('count', 1, a => a.length - a.n.start),
    integer('columns', 8, a => Math.min(120, a.n.count)), integer('half', 2, 20), integer('attack', 1, 32768), integer('release', 1, 32768))],
  ['METER', fixed(source, integer('block', 1, 20000))], ['HISTOGRAM', fixed(source, integer('bins', 2, 64))],
  ['TRACE', fixed(source)], ['SAVE', fixed(source)],
]);
const generators = new Set(['IMPULSE', 'STEP', 'NOISE', 'GAIN', 'MIX', 'DELAY', 'ECHO', 'RESAMPLE', 'FADE', 'TRIM',
  'CONCAT', 'FIR', 'BIQUAD', 'MOVAVG', 'DCBLOCK', 'NORMALIZE', 'GATE', 'ENVELOPE', 'COMPRESS']);
const metricNames = new Set(['samples', 'peak', 'rms', 'sum', 'zero_crossings', 'clipped']);
class CommandError extends Error {}
const twoDecimals = (value: number) => `${floorDiv(value, 100)}.${String(signals.mod(value, 100)).padStart(2, '0')}`;
const milliseconds = (index: number, rate: number) => floorDiv(index * 1000, rate);
const frequency = (rate: number, lag: number) => twoDecimals(rdiv(100 * rate, lag));

class Pipeline {
  private signals: Map<string, Signal>;
  private variables = new Map<string, number>();
  private measurements = new WeakMap<Signal, analysis.Measurements>();
  private log: string[];
  private analysisLines = ['signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz'];
  private excerpts: string[] = [];
  private waveforms: string[] = [];
  private saved: string[] = [];
  private steps = 0; private errors = 0; private passed = 0; private failed = 0;
  constructor(inputs: Signal[]) {
    this.signals = new Map(inputs.map(signal => [signal.name, signal]));
    this.log = inputs.map(s => `load ${s.name} rate=${s.rate} samples=${s.samples.length} peak=${signals.peak(s.samples)}`);
  }
  private measure(signal: Signal): analysis.Measurements {
    let measured = this.measurements.get(signal);
    if (!measured) { measured = analysis.measure(signal.samples); this.measurements.set(signal, measured); } return measured;
  }
  private arguments(definition: Definition, tokens: string[]): Arguments {
    const schema = definition.schema(tokens.length);
    const a: Arguments = { n: {}, text: {}, integers: [], ingredients: [], length: 0, rate: 0, result: 0, low: 0, high: 0 };
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i], argument = schema[i];
      if (argument.kind === 'integer') {
        let value: number;
        if (token.startsWith('$')) {
          const variable = this.variables.get(token.slice(1));
          if (variable === undefined) throw new CommandError(`undefined variable ${token}`); value = variable;
        } else {
          if (!/^(?:0|[1-9][0-9]{0,9}|-[1-9][0-9]{0,9})$/.test(token)) throw new CommandError(`bad integer ${token}`);
          value = Number(token);
        }
        const lower = typeof argument.lower === 'function' ? argument.lower(a) : argument.lower;
        const upper = typeof argument.upper === 'function' ? argument.upper(a) : argument.upper;
        if (value < lower || value > upper) throw new CommandError(`${argument.label} out of range`);
        a.n[argument.label] = value; a.integers.push(value);
      } else if (argument.kind === 'signal') {
        const signal = this.signals.get(token); if (!signal) throw new CommandError(`unknown signal ${token}`);
        if (!a.ingredients.length) { a.length = signal.samples.length; a.rate = signal.rate; } a.ingredients.push(signal);
      } else {
        if (argument.kind === 'name' && !/^[a-z][a-z0-9_]{0,15}$/.test(token)) throw new CommandError(`bad name ${token}`);
        if (argument.kind === 'metric' && !metricNames.has(token)) throw new CommandError(`unknown metric ${token}`);
        if (argument.kind === 'operator' && !argument.choices.includes(token)) throw new CommandError(`unknown operator ${token}`);
        a.text[argument.label] = token;
      }
    }
    return a;
  }
  private checks(command: string, a: Arguments): void {
    const n = a.n;
    if (command === 'SET') {
      let result = n.value;
      if (a.integers.length === 2) {
        const op = a.text.op, operand = n.operand;
        if (op === '/' && operand === 0) throw new CommandError('division by zero');
        if (op === '+') result += operand; else if (op === '-') result -= operand;
        else if (op === '*') result *= operand; else result = floorDiv(result, operand);
        if (Math.abs(result) > 10000000) throw new CommandError('value out of range');
      }
      a.result = result;
    }
    if (['MIX', 'CONCAT', 'COMPARE'].includes(command) && a.ingredients.some(s => s.rate !== a.rate)) throw new CommandError('rate mismatch');
    if (command === 'ECHO' && Math.abs(n.num) >= n.den) throw new CommandError('unstable feedback');
    let length = 0;
    if (command === 'DELAY') length = a.length + n.samples;
    else if (command === 'ECHO') length = a.length + n.tail;
    else if (command === 'RESAMPLE') length = floorDiv((a.length - 1) * n.new_rate, a.rate) + 1;
    else if (command === 'CONCAT') for (const s of a.ingredients) length += s.samples.length;
    if (length > 20000) throw new CommandError('result too long');
    if (command === 'ANALYZE' || command === 'PITCHTRACK') {
      a.low = ceilDiv(a.rate, n.max_hz); a.high = floorDiv(a.rate, n.min_hz);
      if (a.low > a.high) throw new CommandError('empty lag range');
      if (a.high >= (command === 'ANALYZE' ? a.length : n.frame)) throw new CommandError(command === 'ANALYZE' ? 'signal too short' : 'frame too short');
    }
  }
  private generate(command: string, a: Arguments, line: number): string {
    const input = a.ingredients[0], n = a.n; let rate = a.rate, result: Generated;
    switch (command) {
      case 'IMPULSE': rate = n.rate; result = { samples: signals.impulse(n.count, n.pos, n.amp) }; break;
      case 'STEP': rate = n.rate; result = { samples: signals.step(n.count, n.pos, n.amp) }; break;
      case 'NOISE': rate = n.rate; result = { samples: signals.noise(n.count, n.seed) }; break;
      case 'GAIN': result = effects.gain(input.samples, n.num, n.den); break;
      case 'MIX': result = effects.mix(a.ingredients.map(s => s.samples), a.integers.slice(1), n.den); break;
      case 'DELAY': result = { samples: effects.delay(input.samples, n.samples) }; break;
      case 'ECHO': result = effects.echo(input.samples, n.delay, n.num, n.den, n.tail); break;
      case 'RESAMPLE': rate = n.new_rate; result = { samples: effects.resample(input.samples, input.rate, rate) }; break;
      case 'FADE': result = { samples: effects.fade(input.samples, n.in, n.out) }; break;
      case 'TRIM': result = { samples: input.samples.slice(n.start, n.start + n.count) }; break;
      case 'CONCAT': result = { samples: a.ingredients.flatMap(s => [...s.samples]) }; break;
      case 'FIR': result = filters.fir(input.samples, n.divisor, a.integers.slice(1)); break;
      case 'BIQUAD': result = filters.biquad(input.samples, a.integers); break;
      case 'MOVAVG': result = { samples: filters.movingAverage(input.samples, n.width) }; break;
      case 'DCBLOCK': result = filters.dcBlock(input.samples, n.num, n.den); break;
      case 'NORMALIZE': result = dynamics.normalize(input.samples, n.target); break;
      case 'GATE': result = dynamics.gate(input.samples, n.threshold, n.hold); break;
      case 'ENVELOPE': result = { samples: dynamics.envelope(input.samples, n.attack, n.release) }; break;
      case 'COMPRESS': result = dynamics.compress(input.samples, n.threshold, n.ratio_num, n.ratio_den, n.attack, n.release); break;
      default: throw new Error(`unhandled generator ${command}`);
    }
    const signal = new Signal(a.text.dst, rate, result.samples, `line ${line} ${command}`, a.ingredients);
    this.signals.set(signal.name, signal);
    const measured = this.measure(signal), extras: string[] = [];
    const fields: [keyof Omit<Generated, 'samples'>, string][] = [['sections', 'sections'], ['clipped', 'clipped'], ['sourcePeak', 'source_peak'], ['muted', 'muted'], ['minGain', 'min_gain'], ['reduced', 'reduced']];
    for (const [field, label] of fields) if (result[field] !== undefined) extras.push(`${label}=${result[field]}`);
    return `${signal.name} rate=${rate} samples=${signal.samples.length} peak=${measured.peak} sum=${measured.sum}` + (extras.length ? ` ${extras.join(' ')}` : '');
  }
  private analyze(signal: Signal, low: number, high: number): string {
    const m = this.measure(signal), lag = analysis.pitchLag(signal.samples, low, high);
    this.analysisLines.push([signal.name, m.peak, m.rms, m.zero_crossings, m.clipped, analysis.crest(signal.samples, m), lag ?? 'none', lag === null ? 'none' : frequency(signal.rate, lag)].join(','));
    return `${signal.name} lags=${low}-${high}`;
  }
  private compare(first: Signal, second: Signal): string {
    const length = Math.max(first.samples.length, second.samples.length); let differing = 0, maximum = 0, energy = 0, firstDifference: number | null = null;
    for (let i = 0; i < length; i++) {
      const d = (first.samples[i] ?? 0) - (second.samples[i] ?? 0);
      if (d !== 0) { differing++; if (firstDifference === null) firstDifference = i; }
      maximum = Math.max(maximum, Math.abs(d)); energy += d * d;
    }
    return `${first.name} ${second.name} differing=${differing} max_diff=${maximum} first=${firstDifference ?? 'none'} error_energy=${energy}`;
  }
  private expect(signal: Signal, metric: string, op: string, expected: number): string {
    const m = this.measure(signal);
    let value: number;
    switch (metric) {
      case 'samples': value = signal.samples.length; break;
      case 'peak': value = m.peak; break; case 'rms': value = m.rms; break;
      case 'sum': value = m.sum; break; case 'zero_crossings': value = m.zero_crossings; break;
      case 'clipped': value = m.clipped; break; default: throw new Error(`unhandled metric ${metric}`);
    }
    const comparisons: Record<string, boolean> = { eq: value === expected, ne: value !== expected, lt: value < expected, le: value <= expected, gt: value > expected, ge: value >= expected };
    const passed = comparisons[op]; if (passed) this.passed++; else this.failed++;
    return `${signal.name} ${metric}=${value} ${op} ${expected} ${passed ? 'pass' : 'fail'}`;
  }
  private segments(signal: Signal, threshold: number, gap: number, minimum: number): Execution {
    const intervals: { start: number; end: number }[] = []; let current: { start: number; end: number } | null = null;
    for (let i = 0; i < signal.samples.length; i++) {
      if (Math.abs(signal.samples[i]) < threshold) continue;
      if (current === null || i - current.end > gap) { current = { start: i, end: i }; intervals.push(current); } else current.end = i;
    }
    const kept = intervals.filter(({ start, end }) => end - start + 1 >= minimum);
    const following = kept.map(({ start, end }, i) => {
      const m = analysis.measure(signal.samples.slice(start, end + 1));
      return `  segment ${i + 1} start=${start} end=${end} start_ms=${milliseconds(start, signal.rate)} end_ms=${milliseconds(end, signal.rate)} peak=${m.peak} rms=${m.rms} crossings=${m.zero_crossings}`;
    });
    return { details: `${signal.name} segments=${kept.length}`, following };
  }
  private onsets(signal: Signal, attack: number, release: number, threshold: number, minimumGap: number): Execution {
    const env = dynamics.envelope(signal.samples, attack, release), onsets: number[] = [];
    for (let n = 0; n < env.length; n++) if (env[n] >= threshold && (n === 0 || env[n - 1] < threshold)
      && (!onsets.length || n - onsets[onsets.length - 1] >= minimumGap)) onsets.push(n);
    let tempo = 'none';
    if (onsets.length >= 2) {
      const differences = onsets.slice(1).map((n, i) => n - onsets[i]).sort((a, b) => a - b);
      tempo = twoDecimals(rdiv(6000 * signal.rate, differences[floorDiv(onsets.length - 2, 2)]));
    }
    const following = onsets.map((n, i) => `  onset ${i + 1} sample=${n} ms=${milliseconds(n, signal.rate)} interval=${i === 0 ? 'none' : n - onsets[i - 1]}`);
    return { details: `${signal.name} onsets=${onsets.length} tempo=${tempo}`, following };
  }
  private pitchTrack(signal: Signal, frame: number, hop: number, low: number, high: number, threshold: number): string {
    const frames: { start: number; level: number; lag: number | null }[] = [];
    for (let start = 0; start + frame <= signal.samples.length; start += hop) {
      const samples = signal.samples.slice(start, start + frame), level = analysis.rms(samples);
      frames.push({ start, level, lag: level < threshold ? null : analysis.pitchLag(samples, low, high) });
    }
    const voiced = frames.filter(entry => entry.lag !== null).length;
    this.waveforms.push(`PITCHTRACK ${signal.name} rate=${signal.rate} frame=${frame} hop=${hop} lags=${low}-${high} threshold=${threshold} frames=${frames.length} voiced=${voiced}`);
    for (const { start, level, lag } of frames) {
      const scale = Array<string>(41).fill(' '); let detail = `unvoiced rms=${level}`;
      if (lag !== null) { scale[high > low ? rdiv((high - lag) * 40, high - low) : 0] = 'o'; detail = `lag=${lag} hz=${frequency(signal.rate, lag)} rms=${level}`; }
      this.waveforms.push(`${String(milliseconds(start, signal.rate)).padStart(6)} |${scale.join('')}| ${detail}`);
    }
    return `${signal.name} frames=${frames.length} voiced=${voiced}`;
  }
  private excerpt(signal: Signal, start: number, requested: number): string {
    const count = Math.min(requested, signal.samples.length - start);
    this.excerpts.push(`EXCERPT ${signal.name} rate=${signal.rate} samples=${signal.samples.length} start=${start} count=${count}`);
    for (let offset = 0; offset < count; offset += 8) this.excerpts.push(`${String(start + offset).padStart(5)}:`
      + signal.samples.slice(start + offset, start + Math.min(offset + 8, count)).map(x => ` ${String(x).padStart(6)}`).join(''));
    return `${signal.name} start=${start} count=${count}`;
  }
  private plot(signal: Signal, start: number, count: number, columns: number, half: number, attack: number, release: number): string {
    const rows = 2 * half + 1, scale = Math.max(1, signals.peak(signal.samples.slice(start, start + count))), env = dynamics.envelope(signal.samples, attack, release);
    const rowOf = (v: number) => rdiv((scale - v) * (rows - 1), 2 * scale);
    const spans: { top: number; bottom: number; upper: number; lower: number }[] = [];
    for (let c = 0; c < columns; c++) {
      const first = start + floorDiv(c * count, columns), end = start + floorDiv((c + 1) * count, columns);
      let top = signal.samples[first], bottom = top, level = env[first];
      for (let i = first + 1; i < end; i++) { top = Math.max(top, signal.samples[i]); bottom = Math.min(bottom, signal.samples[i]); level = Math.max(level, env[i]); }
      level = Math.min(scale, level); spans.push({ top: rowOf(top), bottom: rowOf(bottom), upper: rowOf(level), lower: rowOf(-level) });
    }
    this.waveforms.push(`PLOT ${signal.name} rate=${signal.rate} start=${start} count=${count} columns=${columns} rows=${rows} scale=${scale} attack=${attack} release=${release}`);
    for (let r = 0; r < rows; r++) {
      const label = r === 0 ? String(scale) : r === half ? '0' : r === rows - 1 ? String(-scale) : '';
      const text = spans.map(s => r === s.upper || r === s.lower ? '*' : s.top <= r && r <= s.bottom ? '#' : r === half ? '-' : ' ').join('');
      this.waveforms.push(`${label.padStart(6)} |${text}|`);
    }
    this.waveforms.push('       +' + Array.from({ length: columns }, (_, c) => c % 10 === 0 ? '+' : '-').join('') + '+');
    const timeLine = [...'    ms'];
    for (let c = 0; c < columns; c += 10) {
      const text = String(milliseconds(start + floorDiv(c * count, columns), signal.rate)), position = 8 + c;
      while (timeLine.length < position) timeLine.push(' ');
      for (let i = 0; i < text.length; i++) timeLine[position + i] = text[i];
    }
    this.waveforms.push(timeLine.join('')); return `${signal.name} start=${start} count=${count} columns=${columns} rows=${rows}`;
  }
  private meter(signal: Signal, block: number): string {
    const blocks = ceilDiv(signal.samples.length, block);
    this.waveforms.push(`METER ${signal.name} rate=${signal.rate} samples=${signal.samples.length} block=${block} blocks=${blocks}`);
    for (let b = 0; b < blocks; b++) {
      const m = analysis.measure(signal.samples.slice(b * block, Math.min((b + 1) * block, signal.samples.length))), np = rdiv(m.peak * 40, 32768), nq = rdiv(m.rms * 40, 32768);
      const bar = Array.from({ length: 40 }, (_, j) => j < nq ? '#' : j < np ? '-' : ' ').join('');
      this.waveforms.push(`${String(milliseconds(b * block, signal.rate)).padStart(6)} |${bar}| peak=${m.peak} rms=${m.rms} clipped=${m.clipped}`);
    }
    return `${signal.name} block=${block}`;
  }
  private histogram(signal: Signal, bins: number): string {
    const counts = Array<number>(bins).fill(0);
    for (const x of signal.samples) counts[floorDiv((x + 32768) * bins, 65536)]++;
    const maximum = Math.max(...counts);
    this.waveforms.push(`HISTOGRAM ${signal.name} rate=${signal.rate} samples=${signal.samples.length} bins=${bins} max=${maximum}`);
    for (let b = 0; b < bins; b++) {
      const low = ceilDiv(b * 65536, bins) - 32768, high = ceilDiv((b + 1) * 65536, bins) - 32769;
      this.waveforms.push(`${String(low).padStart(6)} ${String(high).padStart(6)} ${String(counts[b]).padStart(5)} |` + '#'.repeat(rdiv(counts[b] * 50, maximum)));
    }
    return `${signal.name} bins=${bins}`;
  }
  private trace(signal: Signal): Execution {
    const following: string[] = [];
    function visit(s: Signal, depth: number): void { following.push(`${' '.repeat(2 * depth)}${s.name} <- ${s.origin}`); for (const ingredient of s.ingredients) visit(ingredient, depth + 1); }
    visit(signal, 1); return { details: signal.name, following };
  }
  private execute(command: string, a: Arguments, line: number): Execution {
    if (generators.has(command)) return { details: this.generate(command, a, line) };
    const n = a.n, s = a.ingredients[0]; let details: string;
    switch (command) {
      case 'SET': this.variables.set(a.text.var, a.result); details = `${a.text.var}=${a.result}`; break;
      case 'ANALYZE': details = this.analyze(s, a.low, a.high); break;
      case 'COMPARE': details = this.compare(s, a.ingredients[1]); break;
      case 'EXPECT': details = this.expect(s, a.text.metric, a.text.op, n.value); break;
      case 'SEGMENTS': return this.segments(s, n.threshold, n.gap, n.min_length);
      case 'ONSETS': return this.onsets(s, n.attack, n.release, n.threshold, n.min_gap);
      case 'PITCHTRACK': details = this.pitchTrack(s, n.frame, n.hop, a.low, a.high, n.threshold); break;
      case 'EXCERPT': details = this.excerpt(s, n.start, n.count); break;
      case 'PLOT': details = this.plot(s, n.start, n.count, n.columns, n.half, n.attack, n.release); break;
      case 'METER': details = this.meter(s, n.block); break;
      case 'HISTOGRAM': details = this.histogram(s, n.bins); break;
      case 'TRACE': return this.trace(s);
      case 'SAVE': this.saved.push(...signals.formatSignal(s)); details = `${s.name} samples=${s.samples.length}`; break;
      default: throw new Error(`unhandled command ${command}`);
    }
    return { details };
  }
  process(text: string, line: number): void {
    if (text === '' || text.startsWith('#')) return;
    const [command, ...tokens] = text.split(' ');
    try {
      const definition = commandTable.get(command);
      if (!definition) throw new CommandError(`unknown command ${command}`);
      if (!definition.accepts(tokens.length)) throw new CommandError('wrong number of arguments');
      const args = this.arguments(definition, tokens); this.checks(command, args);
      const result = this.execute(command, args, line); this.steps++;
      this.log.push(`line ${line}: ${command} ${result.details}`); if (result.following) this.log.push(...result.following);
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      this.errors++; this.log.push(`line ${line}: error: ${error.message}`);
    }
  }
  finish(): void {
    for (const name of [...this.signals.keys()].sort()) {
      const s = this.signals.get(name)!, m = this.measure(s);
      this.log.push(`signal ${name} rate=${s.rate} samples=${s.samples.length} peak=${m.peak} rms=${m.rms}`);
    }
    this.log.push(`summary steps=${this.steps} errors=${this.errors} signals=${this.signals.size} passed=${this.passed} failed=${this.failed}`);
    mkdirSync('output', { recursive: true });
    const files: [string, string[]][] = [['log.txt', this.log], ['analysis.csv', this.analysisLines], ['excerpts.txt', this.excerpts], ['waveforms.txt', this.waveforms], ['signals_out.txt', this.saved]];
    for (const [name, lines] of files) writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
  }
}
function main(): void {
  const pipeline = new Pipeline(signals.readSignals('input/signals.txt')), text = readFileSync('input/pipeline.txt', 'ascii');
  const lines = text === '' ? [] : text.slice(0, -1).split('\n');
  lines.forEach((line, i) => pipeline.process(line, i + 1)); pipeline.finish();
}
main();
