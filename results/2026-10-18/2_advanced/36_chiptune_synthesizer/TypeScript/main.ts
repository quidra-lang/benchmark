import { mkdirSync, writeFileSync } from 'node:fs';
import { readSong, noteName, EFFECTS } from './song_parser.ts';
import type { Song, Settings, Cell, Effect, EffectName } from './song_parser.ts';
import { frequency, transpose, oscillation, envelope } from './instruments.ts';
import type { EnvelopeState } from './instruments.ts';
import { samplesPerTick, nextRow, reachableRows } from './sequencer.ts';
import { generate, fadeOut } from './mixer.ts';
import type { Oscillator } from './mixer.ts';
import { hex1, hex2, adler32, statistics, hexDump } from './report.ts';

const KEY_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const KEY_WEIGHTS = [
  [64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29],
  [64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32],
];
const clamp = (value: number, low: number, high: number) => Math.min(high, Math.max(low, value));
const pad = (value: string | number, width: number) => String(value).padStart(width, ' ');
const address = (position: number, row: number) => hex2(position) + ':' + hex2(row);
interface NoteRecord {
  serial: number;
  channel: number;
  position: number;
  row: number;
  instrument: number;
  note: number;
  start: number;
  length: number;
  release: number | null;
  reason: 'next' | 'cut' | 'end';
}
interface Channel extends Oscillator, EnvelopeState {
  note: number | null;
  base: number;
  target: number;
  portamento: number;
  slide: number;
  detune: number;
  vibratoSpeed: number;
  vibratoDepth: number;
  vibratoPosition: number;
  tremoloSpeed: number;
  tremoloDepth: number;
  tremoloPosition: number;
  volume: number;
  envelope: number;
  outputFrequency: number;
  outputVolume: number;
  effect: Effect | null;
  cell: Cell | null;
  activeRecord: NoteRecord | null;
  counters: { notes: number; retriggers: number; cuts: number; active: number; audible: number };
}
interface RowRecord {
  position: number;
  pattern: number;
  row: number;
  start: number;
  speed: number;
  tempo: number;
  notes: (number | null)[];
}
type Ending =
  | { reason: 'finished' | 'limit' }
  | { reason: 'stop'; position: number; row: number }
  | { reason: 'loop'; position: number; row: number; start: number };

function newChannel(): Channel {
  return {
    instrument: null,
    note: null,
    base: 0,
    target: 0,
    portamento: 0,
    slide: 0,
    detune: 0,
    vibratoSpeed: 0,
    vibratoDepth: 0,
    vibratoPosition: 0,
    tremoloSpeed: 0,
    tremoloDepth: 0,
    tremoloPosition: 0,
    volume: 15,
    mode: 0,
    phase: 0,
    register: 1,
    age: 0,
    keyedOff: false,
    offAge: 0,
    offEnvelope: 0,
    envelope: 0,
    outputFrequency: 0,
    outputVolume: 0,
    amplitude: 0,
    increment: 0,
    effect: null,
    cell: null,
    sounding: false,
    activeRecord: null,
    counters: { notes: 0, retriggers: 0, cuts: 0, active: 0, audible: 0 },
  };
}
function keyOff(channel: Channel): void {
  channel.offAge = channel.age;
  channel.offEnvelope = channel.envelope;
  channel.keyedOff = true;
}
function computeOutput(channel: Channel, tick: number, rate: number): void {
  channel.sounding = channel.note !== null;
  if (!channel.sounding) return;
  const effect = channel.effect;
  const instrument = channel.instrument!;
  let semitones = 0;
  if (effect?.name === '0') semitones = tick % 3 === 1 ? effect.x : tick % 3 === 2 ? effect.y : 0;
  if (instrument.arpeggio) {
    semitones += instrument.arpeggio[channel.age % instrument.arpeggio.length];
  }
  let output = transpose(channel.base, semitones) + channel.detune;
  if (effect?.name === '4' || effect?.name === '6') {
    output += oscillation(channel.vibratoPosition, channel.vibratoDepth, 4);
  }
  if (instrument.vibrato) {
    const [delay, speed, depth] = instrument.vibrato;
    if (channel.age >= delay) output += oscillation(((channel.age - delay) * speed) % 64, depth, 4);
  }
  channel.outputFrequency = clamp(output, 1000, 50 * rate);
  channel.envelope = envelope(instrument, channel);
  channel.outputVolume =
    effect?.name === '7'
      ? clamp(
          channel.volume + oscillation(channel.tremoloPosition, channel.tremoloDepth, 255),
          0,
          15,
        )
      : channel.volume;
  channel.amplitude = channel.envelope * channel.outputVolume;
  channel.increment = Math.floor((channel.outputFrequency * 65536) / (100 * rate));
}
function approach(channel: Channel, step: number): void {
  channel.base =
    channel.base < channel.target
      ? Math.min(channel.base + step, channel.target)
      : Math.max(channel.base - step, channel.target);
}

class Player {
  readonly channels = Array.from({ length: 4 }, newChannel);
  readonly samples: number[] = [];
  readonly lanes = Array.from({ length: 4 }, (): number[] => []);
  readonly records: NoteRecord[] = [];
  readonly warnings: string[] = [];
  readonly rows: RowRecord[] = [];
  readonly log: string[] = [];
  readonly visits = new Map<string, { count: number; start: number }>();
  readonly effectCounts = new Map<EffectName, number>();
  readonly instrumentTicks: Map<number, number>;
  speed: number;
  tempo: number;
  position = 0;
  row = 0;
  ticks = 0;
  clipped = 0;
  delay = 0;
  ending: Ending | null = null;
  constructor(
    readonly song: Song,
    readonly settings: Settings,
  ) {
    this.speed = song.speed;
    this.tempo = song.tempo;
    this.instrumentTicks = new Map([...song.instruments.keys()].map((number) => [number, 0]));
  }
  warn(channel: number, message: string): void {
    this.warnings.push(`warning ${address(this.position, this.row)} ch${channel + 1} ${message}`);
  }
  closeRecord(channel: Channel, reason: NoteRecord['reason']): void {
    if (!channel.activeRecord) return;
    channel.activeRecord.length = this.samples.length - channel.activeRecord.start;
    channel.activeRecord.reason = reason;
    channel.activeRecord = null;
  }
  noteOn(channel: Channel, index: number, note: number): void {
    this.closeRecord(channel, 'next');
    channel.note = note;
    channel.base = channel.target = frequency(note);
    channel.phase = channel.age = channel.vibratoPosition = channel.tremoloPosition = 0;
    channel.keyedOff = false;
    const record: NoteRecord = {
      serial: this.records.length + 1,
      channel: index,
      position: this.position,
      row: this.row,
      instrument: channel.instrument!.number,
      note,
      start: this.samples.length,
      length: 0,
      release: null,
      reason: 'end',
    };
    this.records.push(record);
    channel.activeRecord = record;
    channel.counters.notes++;
  }
  cellContent(channel: Channel, index: number, portamento: boolean): void {
    const cell = channel.cell!;
    if (cell.instrument !== null) {
      const instrument = this.song.instruments.get(cell.instrument);
      if (!instrument) this.warn(index, 'undefined instrument ' + hex2(cell.instrument));
      else {
        channel.instrument = instrument;
        channel.volume = 15;
        channel.mode = instrument.mode;
      }
    }
    if (cell.volume !== null) channel.volume = cell.volume;
    if (cell.note === 'OFF') {
      if (channel.note !== null && !channel.keyedOff) {
        keyOff(channel);
        channel.activeRecord!.release = this.samples.length - channel.activeRecord!.start;
      } else this.warn(index, 'key off without note');
    } else if (cell.note !== null) {
      if (!channel.instrument) this.warn(index, 'note without instrument');
      else if (portamento && channel.note !== null) {
        channel.target = frequency(cell.note);
        channel.note = cell.note;
      } else {
        if (portamento) this.warn(index, 'portamento without note');
        this.noteOn(channel, index, cell.note);
      }
    }
  }
  tickZero(channel: Channel, index: number): void {
    const effect = channel.effect;
    if (!effect) return;
    const { name, argument, x, y } = effect;
    switch (name) {
      case '3':
        if (argument > 0) channel.portamento = argument;
        break;
      case '4':
        if (x > 0) channel.vibratoSpeed = x;
        if (y > 0) channel.vibratoDepth = y;
        break;
      case '7':
        if (x > 0) channel.tremoloSpeed = x;
        if (y > 0) channel.tremoloDepth = y;
        break;
      case 'C':
        channel.volume = Math.min(argument, 15);
        break;
      case 'E1':
        channel.base = clamp(channel.base + 10 * argument, 1000, 50 * this.song.rate);
        break;
      case 'E2':
        channel.base = clamp(channel.base - 10 * argument, 1000, 50 * this.song.rate);
        break;
      case 'EA':
        channel.volume = Math.min(channel.volume + argument, 15);
        break;
      case 'EB':
        channel.volume = Math.max(channel.volume - argument, 0);
        break;
      case 'EE':
        this.delay = argument;
        break;
      case 'F':
        if (argument >= 1 && argument <= 31) this.speed = argument;
        else if (argument >= 32) this.tempo = argument;
        break;
      case 'P':
        channel.detune = argument - 128;
        break;
      case 'Q':
      case 'R':
        if (channel.note === null) this.warn(index, 'slide without note');
        else {
          channel.note =
            name === 'Q' ? Math.min(channel.note + y, 95) : Math.max(channel.note - y, 12);
          channel.target = frequency(channel.note);
          channel.slide = 2 * x + 1;
        }
        break;
      case 'V': {
        const wave = channel.instrument?.wave;
        if ((wave === 'PULSE' && argument <= 3) || (wave === 'NOISE' && argument <= 1)) {
          channel.mode = argument;
        } else this.warn(index, 'invalid mode ' + hex2(argument));
        break;
      }
    }
  }
  startRow(cells: Cell[]): number {
    this.delay = 0;
    for (let i = 0; i < 4; i++) {
      const channel = this.channels[i];
      channel.cell = cells[i];
      channel.effect = cells[i].effect;
      channel.slide = 0;
      const effect = channel.effect;
      if (effect) this.effectCounts.set(effect.name, (this.effectCounts.get(effect.name) ?? 0) + 1);
      if (!(effect?.name === 'ED' && effect.argument >= 1)) {
        this.cellContent(channel, i, effect?.name === '3' || effect?.name === '5');
      }
      this.tickZero(channel, i);
    }
    const ticks = this.speed * (1 + this.delay);
    this.channels.forEach((channel, i) => {
      const effect = channel.effect;
      if (effect?.name === 'EC' && effect.argument >= ticks) this.warn(i, 'cut beyond row');
      if (effect?.name === 'ED' && effect.argument >= ticks) this.warn(i, 'delay beyond row');
    });
    return ticks;
  }
  tickEffect(channel: Channel): void {
    const effect = channel.effect;
    if (!effect) return;
    const { name, argument, x, y } = effect;
    if (name === '1') channel.base = clamp(channel.base + 10 * argument, 1000, 50 * this.song.rate);
    else if (name === '2') {
      channel.base = clamp(channel.base - 10 * argument, 1000, 50 * this.song.rate);
    } else if (name === '3' || name === '5') approach(channel, 10 * channel.portamento);
    else if ((name === 'Q' || name === 'R') && channel.slide !== 0) {
      approach(channel, 10 * channel.slide);
    }
    if (name === '5' || name === '6' || name === 'A') {
      channel.volume = clamp(channel.volume + x - y, 0, 15);
    }
  }
  processTick(tick: number): void {
    this.channels.forEach((channel, i) => {
      if (channel.note !== null && channel.age >= 1 && channel.instrument!.sweep !== 0) {
        channel.base = clamp(
          channel.base + 10 * channel.instrument!.sweep,
          1000,
          50 * this.song.rate,
        );
      }
      if (tick >= 1) this.tickEffect(channel);
      const effect = channel.effect;
      if (effect?.name === 'ED' && effect.argument >= 1 && tick === effect.argument) {
        this.cellContent(channel, i, false);
      }
      if (
        effect?.name === 'E9' &&
        effect.argument >= 1 &&
        tick >= 1 &&
        tick % effect.argument === 0 &&
        channel.note !== null
      ) {
        channel.phase = channel.age = 0;
        channel.keyedOff = false;
        channel.counters.retriggers++;
      }
      if (effect?.name === 'EC' && tick === effect.argument && channel.note !== null) {
        this.closeRecord(channel, 'cut');
        channel.note = null;
        channel.counters.cuts++;
      }
      computeOutput(channel, tick, this.song.rate);
      if (channel.sounding) {
        channel.counters.active++;
        if (channel.amplitude > 0) channel.counters.audible++;
        const number = channel.instrument!.number;
        this.instrumentTicks.set(number, this.instrumentTicks.get(number)! + 1);
      }
    });
  }
  rowLine(record: RowRecord): string {
    const channels = this.channels.map((c) => {
      const effect = c.effect?.text ?? '...';
      return c.note === null
        ? `--- --       - - ${hex1(c.volume)} ${effect}`
        : `${noteName(c.note)} ${hex2(c.instrument!.number)} ${pad(c.outputFrequency, 7)} ${hex1(c.envelope)} ${hex1(c.outputVolume)} ${effect}`;
    });
    return `${hex2(record.position)} ${hex2(record.pattern)} ${hex2(record.row)} ${pad(record.start, 7)} ${pad(record.speed, 2)} ${pad(record.tempo, 3)} | ${channels.join(' | ')}`;
  }
  tickLine(tick: number): string {
    const channels = this.channels.map((c) =>
      c.sounding
        ? `${pad(c.outputFrequency, 7)} ${pad(c.increment, 5)} ${hex1(c.envelope)}${hex1(c.outputVolume)}`
        : '      -     - --',
    );
    return `  tick ${pad(tick, 3)} ${pad(this.samples.length, 7)} | ${channels.join(' | ')}`;
  }
  play(): void {
    while (this.ending === null) {
      const pattern = this.song.order[this.position];
      const cells = this.song.patterns.get(pattern)![this.row];
      const rowTicks = this.startRow(cells);
      const record: RowRecord = {
        position: this.position,
        pattern,
        row: this.row,
        start: this.samples.length,
        speed: this.speed,
        tempo: this.tempo,
        notes: [],
      };
      this.rows.push(record);
      const key = this.position + ',' + this.row;
      if (!this.visits.has(key)) this.visits.set(key, { count: 0, start: record.start });
      this.visits.get(key)!.count++;
      const perTick = samplesPerTick(this.song.rate, this.tempo);
      for (let tick = 0; tick < rowTicks; tick++) {
        this.processTick(tick);
        if (tick === 0) {
          record.notes = this.channels.map((c) => c.note);
          this.log.push(this.rowLine(record));
        }
        if (this.settings.traces.has(key)) this.log.push(this.tickLine(tick));
        this.clipped += generate(
          this.channels,
          Math.min(perTick, this.settings.maximum - this.samples.length),
          this.song.gain,
          this.settings.mute,
          this.samples,
          this.lanes,
        );
        this.ticks++;
        for (const c of this.channels) {
          if (c.note !== null) c.age++;
          if (c.effect?.name === '4' || c.effect?.name === '6') {
            c.vibratoPosition = (c.vibratoPosition + c.vibratoSpeed) % 64;
          }
          if (c.effect?.name === '7') c.tremoloPosition = (c.tremoloPosition + c.tremoloSpeed) % 64;
        }
        if (this.samples.length === this.settings.maximum) {
          this.ending = { reason: 'limit' };
          break;
        }
      }
      if (this.ending !== null) break;
      const next = nextRow(this.song, this.position, this.row);
      if (next.reason !== 'next') this.ending = next;
      else {
        const visit = this.visits.get(next.position + ',' + next.row);
        if (visit && visit.count >= this.settings.loops) {
          this.ending = {
            reason: 'loop',
            position: next.position,
            row: next.row,
            start: visit.start,
          };
        } else {
          this.position = next.position;
          this.row = next.row;
        }
      }
    }
    for (const channel of this.channels) this.closeRecord(channel, 'end');
    if (
      (this.ending.reason === 'limit' || this.ending.reason === 'loop') &&
      this.settings.fade > 0
    ) {
      fadeOut(this.samples, this.settings.fade);
    }
  }
}

function noteRange(records: NoteRecord[]): string {
  if (!records.length) return 'none';
  let low = 95;
  let high = 12;
  for (const r of records) {
    low = Math.min(low, r.note);
    high = Math.max(high, r.note);
  }
  return noteName(low) + '..' + noteName(high);
}
function noteLines(player: Player): string[] {
  return player.records.map((r) => {
    const lane = player.lanes[r.channel];
    let peak = 0;
    let cycles = 0;
    for (let i = r.start; i < r.start + r.length; i++) {
      peak = Math.max(peak, Math.abs(lane[i]));
      if (i > r.start && lane[i - 1] < 0 && lane[i] >= 0) cycles++;
    }
    return `${pad(r.serial, 4)} ch=${r.channel + 1} at=${address(r.position, r.row)} ins=${hex2(r.instrument)} note=${noteName(r.note)} start=${r.start} length=${r.length} release=${r.release ?? '-'} end=${r.reason} peak=${peak} cycles=${cycles}`;
  });
}
function rollLines(player: Player): string[] {
  const { start, rows: count } = player.settings.roll;
  const rows = player.rows.slice(start, start + count);
  const pitches = [...new Set(rows.flatMap((r) => r.notes.filter((n) => n !== null)))].sort(
    (a, b) => b - a,
  );
  const lines = [`ROLL start=${start} rows=${rows.length} pitches=${pitches.length}`];
  for (const pitch of pitches) {
    const columns = rows.map((r) => {
      const channels = r.notes
        .map((note, i) => (note === pitch ? String(i + 1) : ''))
        .filter(Boolean);
      return channels.length === 0 ? ' ' : channels.length === 1 ? channels[0] : '*';
    });
    lines.push(`${noteName(pitch)} |${columns.join('')}|`);
  }
  lines.push('    +' + rows.map((_, i) => (i % 16 === 0 ? '+' : '-')).join('') + '+');
  return lines;
}
function statsLines(player: Player): string[] {
  const { song, samples, rows, records } = player;
  const ending = player.ending!;
  const instruments = [...song.instruments.values()].sort((a, b) => a.number - b.number);
  const patterns = [...song.patterns.keys()].sort((a, b) => a - b);
  const mix = statistics(samples);
  const end =
    ending.reason === 'stop' || ending.reason === 'loop'
      ? `${ending.reason} order=${hex2(ending.position)} row=${hex2(ending.row)}`
      : ending.reason;
  const lines = [
    `title=${song.title}`,
    `rate=${song.rate}`,
    `samples=${samples.length}`,
    `duration_ms=${Math.floor((samples.length * 1000) / song.rate)}`,
    `end=${end}`,
    `loop_start=${ending.reason === 'loop' ? ending.start : '-'}`,
    `loop_length=${ending.reason === 'loop' ? samples.length - ending.start : '-'}`,
    `rows=${rows.length}`,
    `ticks=${player.ticks}`,
    `clipped=${player.clipped}`,
    `peak=${mix.peak}`,
    `min=${mix.minimum}`,
    `max=${mix.maximum}`,
    `rms=${mix.rms}`,
    `zero_crossings=${mix.crossings}`,
    `adler32=${adler32(samples)}`,
  ];
  lines.push(
    'path ' +
      rows
        .filter((r, i) => i === 0 || rows[i - 1].position !== r.position)
        .map((r) => hex2(r.position))
        .join(' '),
  );
  rows.forEach((r, i) => {
    if (i === 0 || r.speed !== rows[i - 1].speed || r.tempo !== rows[i - 1].tempo) {
      lines.push(
        `timing sample=${r.start} order=${hex2(r.position)} row=${hex2(r.row)} speed=${r.speed} tempo=${r.tempo}`,
      );
    }
  });
  player.channels.forEach((c, i) => {
    const { notes, retriggers, cuts, active, audible } = c.counters;
    const lane = statistics(player.lanes[i], 0);
    lines.push(
      `channel ${i + 1} notes=${notes} retriggers=${retriggers} cuts=${cuts} active=${active} audible=${audible} peak=${lane.peak} rms=${lane.rms}`,
    );
  });
  for (const instrument of instruments) {
    const selected = records.filter((r) => r.instrument === instrument.number);
    const average = selected.length
      ? Math.floor(selected.reduce((s, r) => s + r.length, 0) / selected.length)
      : '-';
    lines.push(
      `instrument ${hex2(instrument.number)} ${instrument.name} ${instrument.wave} notes=${selected.length} ticks=${player.instrumentTicks.get(instrument.number)} range=${noteRange(selected)} average=${average}`,
    );
  }
  for (const pattern of patterns) {
    const contents = song.patterns.get(pattern)!;
    const populated = contents.filter((cells) =>
      cells.some(
        (c) => c.note !== null || c.instrument !== null || c.volume !== null || c.effect !== null,
      ),
    ).length;
    const notes = contents.reduce((s, cells) => s + cells.filter((c) => c.note !== null).length, 0);
    lines.push(
      `pattern ${hex2(pattern)} rows=${populated} notes=${notes} orders=${song.order.filter((n) => n === pattern).length}`,
    );
  }
  const reachable = reachableRows(song);
  song.order.forEach((pattern, position) => {
    const played = rows.filter((r) => r.position === position);
    const dead = song.patterns
      .get(pattern)!
      .filter(
        (cells, row) => !reachable.has(position + ',' + row) && cells.some((c) => c.note !== null),
      ).length;
    lines.push(
      `order ${hex2(position)} pattern=${hex2(pattern)} rows=${played.length} first=${played[0]?.start ?? '-'} dead=${dead}`,
    );
  });
  for (const note of [...new Set(records.map((r) => r.note))].sort((a, b) => a - b)) {
    lines.push(`note ${noteName(note)} count=${records.filter((r) => r.note === note).length}`);
  }
  const effects = EFFECTS.filter((n) => player.effectCounts.has(n)).map(
    (n) => `${n}=${player.effectCounts.get(n)}`,
  );
  lines.push('effects ' + (effects.length ? effects.join(' ') : 'none'));
  const numbers = (values: number[]) => (values.length ? values.map(hex2).join(' ') : 'none');
  lines.push(
    'unused_instruments=' +
      numbers(
        instruments
          .filter((i) => !records.some((r) => r.instrument === i.number))
          .map((i) => i.number),
      ),
    'unused_patterns=' + numbers(patterns.filter((p) => !song.order.includes(p))),
    'unreached_orders=' +
      numbers(song.order.map((_, p) => p).filter((p) => !rows.some((r) => r.position === p))),
  );
  const durations = Array<number>(12).fill(0);
  for (const r of records) {
    if (song.instruments.get(r.instrument)!.wave !== 'NOISE') durations[r.note % 12] += r.length;
  }
  lines.push('pitch_classes ' + KEY_NAMES.map((name, i) => `${name}=${durations[i]}`).join(' '));
  const keys = KEY_WEIGHTS.flatMap((weights, mode) =>
    KEY_NAMES.map((name, tonic) => ({
      name: name + (mode === 0 ? ' major' : ' minor'),
      order: mode * 12 + tonic,
      score: durations.reduce(
        (s, duration, pitch) => s + weights[(pitch - tonic + 12) % 12] * duration,
        0,
      ),
    })),
  ).sort((a, b) => b.score - a.score || a.order - b.order);
  lines.push(
    `key=${keys[0].name} score=${keys[0].score} runner_up=${keys[1].name} score=${keys[1].score}`,
  );
  player.channels.forEach((_, i) => {
    const selected = records.filter((r) => r.channel === i);
    lines.push(
      `usage ch${i + 1} range=${noteRange(selected)}` +
        instruments
          .map(
            (ins) =>
              ` ${hex2(ins.number)}=${selected.filter((r) => r.instrument === ins.number).length}`,
          )
          .join(''),
    );
  });
  return [...lines, ...player.warnings];
}
function plot(
  values: number[],
  low: number,
  high: number,
  middle: number,
  height: number,
  width: number,
): string[] {
  const rowOf = (v: number) =>
    Math.floor((2 * (high - v) * (height - 1) + (high - low)) / (2 * (high - low)));
  const middleRow = rowOf(middle);
  const columns: [number, number][] = [];
  for (let c = 0; c < width; c++) {
    const start = Math.floor((c * values.length) / width);
    const end = Math.floor(((c + 1) * values.length) / width);
    let bottom = values[start];
    let top = values[start];
    for (let i = start + 1; i < end; i++) {
      bottom = Math.min(bottom, values[i]);
      top = Math.max(top, values[i]);
    }
    columns.push([rowOf(top), rowOf(bottom)]);
  }
  return Array.from({ length: height }, (_, row) => {
    const label = row === 0 ? high : row === middleRow ? middle : row === height - 1 ? low : '';
    return `${pad(label, 5)} |${columns.map(([top, bottom]) => (row >= top && row <= bottom ? '#' : row === middleRow ? '-' : ' ')).join('')}|`;
  });
}
function waveformLines(player: Player): string[] {
  const { start, length, width, height, scope } = player.settings.window;
  const axis =
    '      +' + Array.from({ length: width }, (_, c) => (c % 10 === 0 ? '+' : '-')).join('') + '+';
  const ms: string[] = [...'    ms'];
  for (let c = 0; c < width; c += 10) {
    const value = String(
      Math.floor(((start + Math.floor((c * length) / width)) * 1000) / player.song.rate),
    );
    while (ms.length < 7 + c) ms.push(' ');
    for (let i = 0; i < value.length; i++) ms[7 + c + i] = value[i];
  }
  const milliseconds = ms.join('');
  const lines = [
    `MIX start=${start} length=${length} width=${width} height=${height}`,
    ...plot(player.samples.slice(start, start + length), 0, 255, 128, height, width),
    axis,
    milliseconds,
  ];
  for (let i = 0; i < 4; i++) {
    lines.push(
      `CHANNEL ${i + 1}`,
      ...plot(player.lanes[i].slice(start, start + length), -3375, 3375, 0, scope, width),
    );
  }
  return [...lines, axis, milliseconds];
}
function previewLines(song: Song, settings: Settings): string[] {
  const lines: string[] = [];
  const perTick = samplesPerTick(song.rate, song.tempo);
  for (const instrument of [...song.instruments.values()].sort((a, b) => a.number - b.number)) {
    const channel = newChannel();
    channel.instrument = instrument;
    channel.mode = instrument.mode;
    channel.note = settings.preview.note;
    channel.base = channel.target = frequency(channel.note);
    const samples: number[] = [];
    const envelopes: string[] = [];
    const frequencies: number[] = [];
    for (let tick = 0; tick < settings.preview.ticks; tick++) {
      channel.age = tick;
      if (tick === settings.preview.release) keyOff(channel);
      if (tick >= 1 && instrument.sweep !== 0) {
        channel.base = clamp(channel.base + 10 * instrument.sweep, 1000, 50 * song.rate);
      }
      computeOutput(channel, tick, song.rate);
      envelopes.push(hex1(channel.envelope));
      frequencies.push(channel.outputFrequency);
      generate([channel], perTick, song.gain, [0], samples);
    }
    const stats = statistics(samples);
    lines.push(
      `instrument ${hex2(instrument.number)} ${instrument.name} wave=${instrument.wave} samples=${samples.length} peak=${stats.peak} rms=${stats.rms} adler32=${adler32(samples)}`,
      '  env ' + envelopes.join(''),
      '  freq ' + frequencies.join(' '),
    );
  }
  return lines;
}
function main(): void {
  const { song, settings } = readSong();
  const player = new Player(song, settings);
  player.play();
  const outputs: Record<string, string[]> = {
    'samples.txt': hexDump(player.samples),
    'channel_log.txt': player.log,
    'notes.txt': noteLines(player),
    'roll.txt': rollLines(player),
    'stats.txt': statsLines(player),
    'waveform.txt': waveformLines(player),
    'instruments.txt': previewLines(song, settings),
  };
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(outputs)) {
    writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
  }
}
main();
