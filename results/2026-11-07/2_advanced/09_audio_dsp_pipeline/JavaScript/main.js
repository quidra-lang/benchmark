const fs = require('node:fs');
const signals = require('./signals');
const effects = require('./effects');
const filters = require('./filters');
const dynamics = require('./dynamics');
const analysis = require('./analysis');
const { floorDiv, ceilDiv, rdiv } = signals;

const integer = (label, lower, upper) => ({ kind: 'integer', label, lower, upper });
const destination = { kind: 'name', label: 'dst' };
const source = { kind: 'signal', label: 'src' };
const variable = { kind: 'name', label: 'var' };
const metric = { kind: 'metric', label: 'metric' };
const arithmeticOperator = { kind: 'operator', label: 'op', choices: ['+', '-', '*', '/'] };
const comparisonOperator = { kind: 'operator', label: 'op', choices: ['eq', 'ne', 'lt', 'le', 'gt', 'ge'] };

function fixed(...arguments_) {
  return { accepts: count => count === arguments_.length, schema: () => arguments_ };
}

function repeated(prefix, group, minimum, maximum) {
  return {
    accepts: count => count >= prefix.length + minimum * group.length
      && count <= prefix.length + maximum * group.length && (count - prefix.length) % group.length === 0,
    schema: count => [...prefix, ...Array.from({ length: floorDiv(count - prefix.length, group.length) }, () => group).flat()],
  };
}

const amplitudeArguments = [destination, integer('rate', 1000, 48000), integer('count', 1, 20000),
  integer('pos', 0, values => values.count - 1), integer('amp', -32768, 32767)];
const commandTable = new Map([
  ['SET', { accepts: count => count === 2 || count === 4,
    schema: count => [variable, integer('value', -10000000, 10000000),
      ...(count === 4 ? [arithmeticOperator, integer('operand', -10000000, 10000000)] : [])] }],
  ['IMPULSE', fixed(...amplitudeArguments)],
  ['STEP', fixed(...amplitudeArguments)],
  ['NOISE', fixed(destination, integer('rate', 1000, 48000), integer('count', 1, 20000), integer('seed', 1, 2147483646))],
  ['GAIN', fixed(destination, source, integer('num', -65536, 65536), integer('den', 1, 65536))],
  ['MIX', repeated([destination, integer('den', 1, 65536)], [source, integer('weight', -65536, 65536)], 1, 8)],
  ['DELAY', fixed(destination, source, integer('samples', 0, 20000))],
  ['ECHO', fixed(destination, source, integer('delay', 1, 20000), integer('num', -65536, 65536),
    integer('den', 1, 65536), integer('tail', 0, 20000))],
  ['RESAMPLE', fixed(destination, source, integer('new_rate', 1000, 48000))],
  ['FADE', fixed(destination, source, integer('in', 0, values => values.length), integer('out', 0, values => values.length))],
  ['TRIM', fixed(destination, source, integer('start', 0, values => values.length - 1),
    integer('count', 1, values => values.length - values.start))],
  ['CONCAT', repeated([destination], [source], 2, 8)],
  ['FIR', repeated([destination, source, integer('divisor', 1, 1000000)], [integer('tap', -32768, 32767)], 1, 64)],
  ['BIQUAD', repeated([destination, source], ['b0', 'b1', 'b2', 'a1', 'a2'].map(label => integer(label, -65536, 65536)), 1, 4)],
  ['MOVAVG', fixed(destination, source, integer('width', 1, 1000))],
  ['DCBLOCK', fixed(destination, source, integer('num', 0, 65535), integer('den', values => values.num + 1, 65536))],
  ['NORMALIZE', fixed(destination, source, integer('target', 1, 32767))],
  ['GATE', fixed(destination, source, integer('threshold', 1, 32768), integer('hold', 0, 20000))],
  ['ENVELOPE', fixed(destination, source, integer('attack', 1, 32768), integer('release', 1, 32768))],
  ['COMPRESS', fixed(destination, source, integer('threshold', 1, 32767), integer('ratio_num', 1, 100),
    integer('ratio_den', 1, values => values.ratio_num), integer('attack', 1, 32768), integer('release', 1, 32768))],
  ['ANALYZE', fixed(source, integer('min_hz', 1, values => floorDiv(values.rate, 2) - 1),
    integer('max_hz', values => values.min_hz + 1, values => floorDiv(values.rate, 2)))],
  ['COMPARE', fixed(source, source)],
  ['EXPECT', fixed(source, metric, comparisonOperator, integer('value', -1000000000, 1000000000))],
  ['SEGMENTS', fixed(source, integer('threshold', 1, 32768), integer('gap', 1, 20000), integer('min_length', 1, 20000))],
  ['ONSETS', fixed(source, integer('attack', 1, 32768), integer('release', 1, 32768),
    integer('threshold', 1, 32767), integer('min_gap', 1, 20000))],
  ['PITCHTRACK', fixed(source, integer('frame', 16, values => values.length), integer('hop', 1, values => values.frame),
    integer('min_hz', 1, values => floorDiv(values.rate, 2) - 1),
    integer('max_hz', values => values.min_hz + 1, values => floorDiv(values.rate, 2)), integer('threshold', 0, 32767))],
  ['EXCERPT', fixed(source, integer('start', 0, values => values.length - 1), integer('count', 1, 1000))],
  ['PLOT', fixed(source, integer('start', 0, values => values.length - 1), integer('count', 1, values => values.length - values.start),
    integer('columns', 8, values => Math.min(120, values.count)), integer('half', 2, 20),
    integer('attack', 1, 32768), integer('release', 1, 32768))],
  ['METER', fixed(source, integer('block', 1, 20000))],
  ['HISTOGRAM', fixed(source, integer('bins', 2, 64))],
  ['TRACE', fixed(source)],
  ['SAVE', fixed(source)],
]);

const generators = new Set(['IMPULSE', 'STEP', 'NOISE', 'GAIN', 'MIX', 'DELAY', 'ECHO', 'RESAMPLE',
  'FADE', 'TRIM', 'CONCAT', 'FIR', 'BIQUAD', 'MOVAVG', 'DCBLOCK', 'NORMALIZE', 'GATE', 'ENVELOPE', 'COMPRESS']);
const metricNames = new Set(['samples', 'peak', 'rms', 'sum', 'zero_crossings', 'clipped']);

class CommandError extends Error {}

function twoDecimals(value) {
  const integer_ = BigInt(value);
  return `${integer_ / 100n}.${String(integer_ % 100n).padStart(2, '0')}`;
}

function milliseconds(index, rate) {
  return floorDiv(index * 1000, rate);
}

function frequency(rate, lag) {
  return twoDecimals(rdiv(100 * rate, lag));
}

function compareNames(first, second) {
  return first < second ? -1 : first > second ? 1 : 0;
}

class Pipeline {
  constructor(inputs) {
    this.signals = new Map(inputs.map(signal => [signal.name, signal]));
    this.variables = new Map();
    this.measurements = new WeakMap();
    this.log = inputs.map(signal => `load ${signal.name} rate=${signal.rate} samples=${signal.samples.length} peak=${signals.peak(signal.samples)}`);
    this.analysis = ['signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz'];
    this.excerpts = [];
    this.waveforms = [];
    this.saved = [];
    this.steps = 0;
    this.errors = 0;
    this.passed = 0;
    this.failed = 0;
  }

  measure(signal) {
    if (!this.measurements.has(signal)) this.measurements.set(signal, analysis.measure(signal.samples));
    return this.measurements.get(signal);
  }

  arguments(definition, tokens) {
    const schema = definition.schema(tokens.length);
    const values = [];
    const context = { ingredients: [] };
    for (let index = 0; index < tokens.length; index += 1) {
      const token = tokens[index];
      const argument = schema[index];
      let value = token;
      if (argument.kind === 'name') {
        if (!/^[a-z][a-z0-9_]{0,15}$/.test(token)) throw new CommandError(`bad name ${token}`);
      } else if (argument.kind === 'signal') {
        if (!this.signals.has(token)) throw new CommandError(`unknown signal ${token}`);
        value = this.signals.get(token);
        if (context.ingredients.length === 0) {
          context.length = value.samples.length;
          context.rate = value.rate;
        }
        context.ingredients.push(value);
      } else if (argument.kind === 'metric') {
        if (!metricNames.has(token)) throw new CommandError(`unknown metric ${token}`);
      } else if (argument.kind === 'operator') {
        if (!argument.choices.includes(token)) throw new CommandError(`unknown operator ${token}`);
      } else {
        if (token.startsWith('$')) {
          if (!this.variables.has(token.slice(1))) throw new CommandError(`undefined variable ${token}`);
          value = this.variables.get(token.slice(1));
        } else {
          if (!/^(?:0|[1-9][0-9]{0,9}|-[1-9][0-9]{0,9})$/.test(token)) throw new CommandError(`bad integer ${token}`);
          value = Number(token);
        }
        const lower = typeof argument.lower === 'function' ? argument.lower(context) : argument.lower;
        const upper = typeof argument.upper === 'function' ? argument.upper(context) : argument.upper;
        if (value < lower || value > upper) throw new CommandError(`${argument.label} out of range`);
        context[argument.label] = value;
      }
      values.push(value);
    }
    return { values, context };
  }

  checks(command, values, context) {
    if (command === 'SET') {
      let result = values[1];
      if (values.length === 4) {
        const operator = values[2];
        const operand = values[3];
        if (operator === '/' && operand === 0) throw new CommandError('division by zero');
        if (operator === '+') result += operand;
        else if (operator === '-') result -= operand;
        else if (operator === '*') result *= operand;
        else result = floorDiv(result, operand);
        if (Math.abs(result) > 10000000) throw new CommandError('value out of range');
      }
      context.result = result;
    }
    if (command === 'MIX' || command === 'CONCAT' || command === 'COMPARE') {
      if (context.ingredients.some(signal => signal.rate !== context.rate)) throw new CommandError('rate mismatch');
    }
    if (command === 'ECHO' && Math.abs(values[3]) >= values[4]) throw new CommandError('unstable feedback');
    let length = 0;
    if (command === 'DELAY') length = context.length + values[2];
    else if (command === 'ECHO') length = context.length + values[5];
    else if (command === 'RESAMPLE') length = floorDiv((context.length - 1) * values[2], context.rate) + 1;
    else if (command === 'CONCAT') for (const signal of context.ingredients) length += signal.samples.length;
    if (length > 20000) throw new CommandError('result too long');
    if (command === 'ANALYZE' || command === 'PITCHTRACK') {
      context.low = ceilDiv(context.rate, context.max_hz);
      context.high = floorDiv(context.rate, context.min_hz);
      if (context.low > context.high) throw new CommandError('empty lag range');
      if (context.high >= (command === 'ANALYZE' ? context.length : context.frame)) {
        throw new CommandError(command === 'ANALYZE' ? 'signal too short' : 'frame too short');
      }
    }
  }

  generate(command, values, context, line) {
    const input = context.ingredients[0];
    let rate = input?.rate;
    let result;
    switch (command) {
      case 'IMPULSE':
        rate = values[1]; result = { samples: signals.impulse(values[2], values[3], values[4]) }; break;
      case 'STEP':
        rate = values[1]; result = { samples: signals.step(values[2], values[3], values[4]) }; break;
      case 'NOISE':
        rate = values[1]; result = { samples: signals.noise(values[2], values[3]) }; break;
      case 'GAIN': result = effects.gain(input.samples, values[2], values[3]); break;
      case 'MIX': {
        const weights = [];
        for (let index = 3; index < values.length; index += 2) weights.push(values[index]);
        result = effects.mix(context.ingredients.map(signal => signal.samples), weights, values[1]);
        break;
      }
      case 'DELAY': result = { samples: effects.delay(input.samples, values[2]) }; break;
      case 'ECHO': result = effects.echo(input.samples, values[2], values[3], values[4], values[5]); break;
      case 'RESAMPLE': rate = values[2]; result = { samples: effects.resample(input.samples, input.rate, rate) }; break;
      case 'FADE': result = { samples: effects.fade(input.samples, values[2], values[3]) }; break;
      case 'TRIM': result = { samples: input.samples.slice(values[2], values[2] + values[3]) }; break;
      case 'CONCAT': result = { samples: context.ingredients.flatMap(signal => signal.samples) }; break;
      case 'FIR': result = filters.fir(input.samples, values[2], values.slice(3)); break;
      case 'BIQUAD': result = filters.biquad(input.samples, values.slice(2)); break;
      case 'MOVAVG': result = { samples: filters.movingAverage(input.samples, values[2]) }; break;
      case 'DCBLOCK': result = filters.dcBlock(input.samples, values[2], values[3]); break;
      case 'NORMALIZE': result = dynamics.normalize(input.samples, values[2]); break;
      case 'GATE': result = dynamics.gate(input.samples, values[2], values[3]); break;
      case 'ENVELOPE': result = { samples: dynamics.envelope(input.samples, values[2], values[3]) }; break;
      case 'COMPRESS': result = dynamics.compress(input.samples, values[2], values[3], values[4], values[5], values[6]); break;
    }
    const signal = new signals.Signal(values[0], rate, result.samples, `line ${line} ${command}`, context.ingredients);
    this.signals.set(signal.name, signal);
    const measurements = this.measure(signal);
    const extras = [];
    for (const [field, label] of [['sections', 'sections'], ['clipped', 'clipped'], ['sourcePeak', 'source_peak'],
      ['muted', 'muted'], ['minGain', 'min_gain'], ['reduced', 'reduced']]) {
      if (result[field] !== undefined) extras.push(`${label}=${result[field]}`);
    }
    return `${signal.name} rate=${rate} samples=${signal.samples.length} peak=${measurements.peak} sum=${measurements.sum}`
      + (extras.length === 0 ? '' : ` ${extras.join(' ')}`);
  }

  analyze(signal, low, high) {
    const measured = this.measure(signal);
    const lag = analysis.pitchLag(signal.samples, low, high);
    this.analysis.push([signal.name, measured.peak, measured.rms, measured.zero_crossings, measured.clipped,
      analysis.crest(signal.samples, measured), lag ?? 'none', lag === null ? 'none' : frequency(signal.rate, lag)].join(','));
    return `${signal.name} lags=${low}-${high}`;
  }

  compare(first, second) {
    const length = Math.max(first.samples.length, second.samples.length);
    let differing = 0;
    let maximum = 0;
    let firstDifference = null;
    let energy = 0;
    for (let index = 0; index < length; index += 1) {
      const difference = (first.samples[index] ?? 0) - (second.samples[index] ?? 0);
      if (difference !== 0) {
        differing += 1;
        if (firstDifference === null) firstDifference = index;
      }
      maximum = Math.max(maximum, Math.abs(difference));
      energy += difference * difference;
    }
    return `${first.name} ${second.name} differing=${differing} max_diff=${maximum} first=${firstDifference ?? 'none'} error_energy=${energy}`;
  }

  expect(signal, metric, operator, expected) {
    const value = metric === 'samples' ? signal.samples.length : this.measure(signal)[metric];
    const predicates = { eq: value === expected, ne: value !== expected, lt: value < expected,
      le: value <= expected, gt: value > expected, ge: value >= expected };
    const passed = predicates[operator];
    if (passed) this.passed += 1;
    else this.failed += 1;
    return `${signal.name} ${metric}=${value} ${operator} ${expected} ${passed ? 'pass' : 'fail'}`;
  }

  segments(signal, threshold, gap, minimum) {
    const intervals = [];
    let current = null;
    for (let index = 0; index < signal.samples.length; index += 1) {
      if (Math.abs(signal.samples[index]) < threshold) continue;
      if (current === null || index - current.end > gap) {
        current = { start: index, end: index };
        intervals.push(current);
      } else current.end = index;
    }
    const kept = intervals.filter(interval => interval.end - interval.start + 1 >= minimum);
    const following = kept.map((interval, index) => {
      const { start, end } = interval;
      const measured = analysis.measure(signal.samples.slice(start, end + 1));
      return `  segment ${index + 1} start=${start} end=${end} start_ms=${milliseconds(start, signal.rate)} `
        + `end_ms=${milliseconds(end, signal.rate)} peak=${measured.peak} rms=${measured.rms} crossings=${measured.zero_crossings}`;
    });
    return { details: `${signal.name} segments=${kept.length}`, following };
  }

  onsets(signal, attack, release, threshold, minimumGap) {
    const envelope = dynamics.envelope(signal.samples, attack, release);
    const onsets = [];
    for (let index = 0; index < envelope.length; index += 1) {
      if (envelope[index] >= threshold && (index === 0 || envelope[index - 1] < threshold)
          && (onsets.length === 0 || index - onsets.at(-1) >= minimumGap)) onsets.push(index);
    }
    let tempo = 'none';
    if (onsets.length >= 2) {
      const differences = onsets.slice(1).map((value, index) => value - onsets[index]);
      differences.sort((first, second) => first - second);
      const middle = differences[floorDiv(onsets.length - 2, 2)];
      tempo = twoDecimals(rdiv(6000 * signal.rate, middle));
    }
    const following = onsets.map((sample, index) => `  onset ${index + 1} sample=${sample} ms=${milliseconds(sample, signal.rate)} `
      + `interval=${index === 0 ? 'none' : sample - onsets[index - 1]}`);
    return { details: `${signal.name} onsets=${onsets.length} tempo=${tempo}`, following };
  }

  pitchTrack(signal, frame, hop, low, high, threshold) {
    const frames = [];
    for (let start = 0; start + frame <= signal.samples.length; start += hop) {
      const samples = signal.samples.slice(start, start + frame);
      const level = analysis.rms(samples);
      const lag = level < threshold ? null : analysis.pitchLag(samples, low, high);
      frames.push({ start, level, lag });
    }
    const voiced = frames.filter(entry => entry.lag !== null).length;
    this.waveforms.push(`PITCHTRACK ${signal.name} rate=${signal.rate} frame=${frame} hop=${hop} lags=${low}-${high} `
      + `threshold=${threshold} frames=${frames.length} voiced=${voiced}`);
    for (const entry of frames) {
      const scale = Array(41).fill(' ');
      let detail = `unvoiced rms=${entry.level}`;
      if (entry.lag !== null) {
        const position = high > low ? rdiv((high - entry.lag) * 40, high - low) : 0;
        scale[position] = 'o';
        detail = `lag=${entry.lag} hz=${frequency(signal.rate, entry.lag)} rms=${entry.level}`;
      }
      this.waveforms.push(`${String(milliseconds(entry.start, signal.rate)).padStart(6)} |${scale.join('')}| ${detail}`);
    }
    return `${signal.name} frames=${frames.length} voiced=${voiced}`;
  }

  excerpt(signal, start, requested) {
    const count = Math.min(requested, signal.samples.length - start);
    this.excerpts.push(`EXCERPT ${signal.name} rate=${signal.rate} samples=${signal.samples.length} start=${start} count=${count}`);
    for (let offset = 0; offset < count; offset += 8) {
      const group = signal.samples.slice(start + offset, start + Math.min(offset + 8, count));
      this.excerpts.push(`${String(start + offset).padStart(5)}:` + group.map(sample => ` ${String(sample).padStart(6)}`).join(''));
    }
    return `${signal.name} start=${start} count=${count}`;
  }

  plot(signal, start, count, columns, half, attack, release) {
    const rows = 2 * half + 1;
    const scale = Math.max(1, signals.peak(signal.samples.slice(start, start + count)));
    const envelope = dynamics.envelope(signal.samples, attack, release);
    const rowOf = value => rdiv((scale - value) * (rows - 1), 2 * scale);
    const spans = [];
    for (let column = 0; column < columns; column += 1) {
      const first = start + floorDiv(column * count, columns);
      const end = start + floorDiv((column + 1) * count, columns);
      let top = signal.samples[first];
      let bottom = top;
      let level = envelope[first];
      for (let index = first + 1; index < end; index += 1) {
        top = Math.max(top, signal.samples[index]);
        bottom = Math.min(bottom, signal.samples[index]);
        level = Math.max(level, envelope[index]);
      }
      level = Math.min(scale, level);
      spans.push({ top: rowOf(top), bottom: rowOf(bottom), upper: rowOf(level), lower: rowOf(-level) });
    }
    this.waveforms.push(`PLOT ${signal.name} rate=${signal.rate} start=${start} count=${count} columns=${columns} `
      + `rows=${rows} scale=${scale} attack=${attack} release=${release}`);
    for (let row = 0; row < rows; row += 1) {
      const label = row === 0 ? String(scale) : row === half ? '0' : row === rows - 1 ? String(-scale) : '';
      const characters = spans.map(span => row === span.upper || row === span.lower ? '*'
        : row >= span.top && row <= span.bottom ? '#' : row === half ? '-' : ' ');
      this.waveforms.push(`${label.padStart(6)} |${characters.join('')}|`);
    }
    this.waveforms.push('       +' + Array.from({ length: columns }, (_, column) => column % 10 === 0 ? '+' : '-').join('') + '+');
    const timeLine = [...'    ms'];
    for (let column = 0; column < columns; column += 10) {
      const text = String(milliseconds(start + floorDiv(column * count, columns), signal.rate));
      const position = 8 + column;
      while (timeLine.length < position) timeLine.push(' ');
      for (let digit = 0; digit < text.length; digit += 1) timeLine[position + digit] = text[digit];
    }
    this.waveforms.push(timeLine.join(''));
    return `${signal.name} start=${start} count=${count} columns=${columns} rows=${rows}`;
  }

  meter(signal, block) {
    const blocks = ceilDiv(signal.samples.length, block);
    this.waveforms.push(`METER ${signal.name} rate=${signal.rate} samples=${signal.samples.length} block=${block} blocks=${blocks}`);
    for (let index = 0; index < blocks; index += 1) {
      const samples = signal.samples.slice(index * block, Math.min((index + 1) * block, signal.samples.length));
      const measured = analysis.measure(samples);
      const peakLength = rdiv(measured.peak * 40, 32768);
      const rmsLength = rdiv(measured.rms * 40, 32768);
      const bar = Array.from({ length: 40 }, (_, position) => position < rmsLength ? '#' : position < peakLength ? '-' : ' ').join('');
      this.waveforms.push(`${String(milliseconds(index * block, signal.rate)).padStart(6)} |${bar}| `
        + `peak=${measured.peak} rms=${measured.rms} clipped=${measured.clipped}`);
    }
    return `${signal.name} block=${block}`;
  }

  histogram(signal, bins) {
    const counts = Array(bins).fill(0);
    for (const sample of signal.samples) counts[floorDiv((sample + 32768) * bins, 65536)] += 1;
    const maximum = Math.max(...counts);
    this.waveforms.push(`HISTOGRAM ${signal.name} rate=${signal.rate} samples=${signal.samples.length} bins=${bins} max=${maximum}`);
    for (let bin = 0; bin < bins; bin += 1) {
      const low = ceilDiv(bin * 65536, bins) - 32768;
      const high = ceilDiv((bin + 1) * 65536, bins) - 32769;
      this.waveforms.push(`${String(low).padStart(6)} ${String(high).padStart(6)} ${String(counts[bin]).padStart(5)} |`
        + '#'.repeat(rdiv(counts[bin] * 50, maximum)));
    }
    return `${signal.name} bins=${bins}`;
  }

  trace(signal) {
    const following = [];
    function visit(current, depth) {
      following.push(`${' '.repeat(2 * depth)}${current.name} <- ${current.origin}`);
      for (const ingredient of current.ingredients) visit(ingredient, depth + 1);
    }
    visit(signal, 1);
    return { details: signal.name, following };
  }

  execute(command, values, context, line) {
    if (generators.has(command)) return { details: this.generate(command, values, context, line) };
    let details;
    switch (command) {
      case 'SET':
        this.variables.set(values[0], context.result);
        details = `${values[0]}=${context.result}`;
        break;
      case 'ANALYZE': details = this.analyze(values[0], context.low, context.high); break;
      case 'COMPARE': details = this.compare(values[0], values[1]); break;
      case 'EXPECT': details = this.expect(values[0], values[1], values[2], values[3]); break;
      case 'SEGMENTS': return this.segments(values[0], values[1], values[2], values[3]);
      case 'ONSETS': return this.onsets(values[0], values[1], values[2], values[3], values[4]);
      case 'PITCHTRACK': details = this.pitchTrack(values[0], values[1], values[2], context.low, context.high, values[5]); break;
      case 'EXCERPT': details = this.excerpt(values[0], values[1], values[2]); break;
      case 'PLOT': details = this.plot(values[0], values[1], values[2], values[3], values[4], values[5], values[6]); break;
      case 'METER': details = this.meter(values[0], values[1]); break;
      case 'HISTOGRAM': details = this.histogram(values[0], values[1]); break;
      case 'TRACE': return this.trace(values[0]);
      case 'SAVE':
        this.saved.push(...signals.formatSignal(values[0]));
        details = `${values[0].name} samples=${values[0].samples.length}`;
        break;
    }
    return { details };
  }

  process(text, line) {
    if (text === '' || text.startsWith('#')) return;
    const [command, ...tokens] = text.split(' ');
    try {
      const definition = commandTable.get(command);
      if (definition === undefined) throw new CommandError(`unknown command ${command}`);
      if (!definition.accepts(tokens.length)) throw new CommandError('wrong number of arguments');
      const { values, context } = this.arguments(definition, tokens);
      this.checks(command, values, context);
      const result = this.execute(command, values, context, line);
      this.steps += 1;
      this.log.push(`line ${line}: ${command} ${result.details}`);
      if (result.following !== undefined) this.log.push(...result.following);
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      this.errors += 1;
      this.log.push(`line ${line}: error: ${error.message}`);
    }
  }

  finish() {
    for (const name of [...this.signals.keys()].sort(compareNames)) {
      const signal = this.signals.get(name);
      const measured = this.measure(signal);
      this.log.push(`signal ${name} rate=${signal.rate} samples=${signal.samples.length} peak=${measured.peak} rms=${measured.rms}`);
    }
    this.log.push(`summary steps=${this.steps} errors=${this.errors} signals=${this.signals.size} passed=${this.passed} failed=${this.failed}`);
    fs.mkdirSync('output', { recursive: true });
    for (const [name, lines] of [['log.txt', this.log], ['analysis.csv', this.analysis], ['excerpts.txt', this.excerpts],
      ['waveforms.txt', this.waveforms], ['signals_out.txt', this.saved]]) {
      fs.writeFileSync(`output/${name}`, lines.length === 0 ? '' : `${lines.join('\n')}\n`, 'ascii');
    }
  }
}

function main() {
  const pipeline = new Pipeline(signals.readSignals('input/signals.txt'));
  const text = fs.readFileSync('input/pipeline.txt', 'ascii');
  const lines = text === '' ? [] : text.slice(0, -1).split('\n');
  lines.forEach((line, index) => pipeline.process(line, index + 1));
  pipeline.finish();
}

if (require.main === module) main();
