import { readFileSync } from 'node:fs';

const PROTOCOLS = ['SW', 'GBN', 'SR'];
const KEYS = [
  'PROTOCOL', 'FRAMES', 'WINDOW', 'SEQBITS', 'TIMEOUT', 'DELAY',
  'INTERVAL', 'MAXTICKS', 'DUPACK', 'NAK', 'BACKOFF', 'CONGESTION',
  'UNSAFE', 'TRACE', 'RANDOM', 'LOSEDATA', 'LOSECTRL', 'CORRUPTDATA',
  'CORRUPTCTRL', 'DELAYDATA', 'DELAYCTRL', 'SNAPSHOT'
];
const REQUIRED = ['PROTOCOL', 'FRAMES', 'WINDOW', 'SEQBITS', 'TIMEOUT', 'DELAY'];
const LIST_KEYS = new Set([
  'LOSEDATA', 'LOSECTRL', 'CORRUPTDATA', 'CORRUPTCTRL',
  'DELAYDATA', 'DELAYCTRL', 'SNAPSHOT'
]);
const DELAY_KEYS = new Set(['DELAYDATA', 'DELAYCTRL']);
const CHOICES: Record<string, string[]> = {
  PROTOCOL: PROTOCOLS, NAK: ['ON', 'OFF'], BACKOFF: ['ON', 'OFF'],
  CONGESTION: ['ON', 'OFF'], UNSAFE: ['ON', 'OFF'],
  TRACE: ['ALL', 'SENDER', 'RECEIVER', 'NONE']
};
const RANGES: Record<string, [number, number]> = {
  FRAMES: [1, 60], WINDOW: [1, 32], SEQBITS: [1, 6],
  TIMEOUT: [1, 50], DELAY: [1, 10], INTERVAL: [0, 10],
  MAXTICKS: [1, 2000], DUPACK: [1, 10],
  LOSEDATA: [1, 9999], LOSECTRL: [1, 9999],
  CORRUPTDATA: [1, 9999], CORRUPTCTRL: [1, 9999], SNAPSHOT: [0, 2000]
};
const TRACE_SIDES: Record<string, string[]> = {
  ALL: ['SENDER', 'RECEIVER'], SENDER: ['SENDER'], RECEIVER: ['RECEIVER'], NONE: []
};
const RANDOM_MULTIPLIER = 48271;
const RANDOM_MODULUS = 2147483647;

type SettingLine = [string, string[]];
type Outcome = 'LOST' | 'CORRUPT' | 'NORMAL';
type ControlKind = 'ack' | 'nak';
type TransmissionKind = 'data' | ControlKind;
type Transmission = {
  number: number;
  kind: TransmissionKind;
  value: number;
  payload: number | null;
  outcome: Outcome;
  arrival: number;
};

class SettingsError extends Error {}

function truncated(numerator: number, denominator: number, digits: number): string {
  const scale = 10 ** digits;
  const value = Math.floor(numerator * scale / denominator);
  return Math.floor(value / scale) + '.' + String(value % scale).padStart(digits, '0');
}

function tickText(tick: number | null): string { return tick === null ? '-' : String(tick); }
function mod(value: number, modulus: number): number { return ((value % modulus) + modulus) % modulus; }
function option(settings: Map<string, string[]>, key: string, fallback: string): string { return (settings.get(key) ?? [fallback])[0]; }
function numberSet(settings: Map<string, string[]>, key: string): Set<number> { return new Set((settings.get(key) ?? []).map(Number)); }
function delayMap(settings: Map<string, string[]>, key: string): Map<number, number> {
  return new Map((settings.get(key) ?? []).map(value => value.split(':').map(Number) as [number, number]));
}
function inRange(value: number, bounds: [number, number]): boolean { return bounds[0] <= value && value <= bounds[1]; }
function unique<T>(values: T[]): boolean { return new Set(values).size === values.length; }
function validValue(key: string, values: string[]): boolean {
  if (Object.hasOwn(CHOICES, key)) return CHOICES[key].includes(values[0]);
  if (!LIST_KEYS.has(key) && Object.hasOwn(RANGES, key)) {
    return inRange(Number(values[0]), RANGES[key]);
  }
  if (key === 'RANDOM') {
    const [seed, loss, corrupt] = values.map(Number);
    return inRange(seed, [1, RANDOM_MODULUS - 1]) && loss >= 0 && corrupt >= 0 && loss + corrupt <= 100;
  }
  if (DELAY_KEYS.has(key)) {
    const pairs = values.map(value => value.split(':').map(Number));
    return pairs.every(([n, extra]) => inRange(n, [1, 9999]) && inRange(extra, [1, 50])) &&
      unique(pairs.map(([n]) => n));
  }
  const numbers = values.map(Number);
  return numbers.every(n => inRange(n, RANGES[key])) && unique(numbers);
}

class Config {
  readonly protocol: string;
  readonly frames: number;
  readonly window: number;
  readonly seqbits: number;
  readonly timeout: number;
  readonly delay: number;
  readonly interval: number;
  readonly limit: number;
  readonly dupack: number | null;
  readonly nak: boolean;
  readonly backoff: boolean;
  readonly congestion: boolean;
  readonly unsafe: boolean;
  readonly trace: string;
  readonly random: [number, number, number] | null;
  readonly loseData: Set<number>;
  readonly loseCtrl: Set<number>;
  readonly corruptData: Set<number>;
  readonly corruptCtrl: Set<number>;
  readonly delayData: Map<number, number>;
  readonly delayCtrl: Map<number, number>;
  readonly snapshots: Set<number>;

  constructor(settings: Map<string, string[]>) {
    this.protocol = option(settings, 'PROTOCOL', '');
    this.frames = Number(option(settings, 'FRAMES', '0'));
    this.window = Number(option(settings, 'WINDOW', '0'));
    this.seqbits = Number(option(settings, 'SEQBITS', '0'));
    this.timeout = Number(option(settings, 'TIMEOUT', '0'));
    this.delay = Number(option(settings, 'DELAY', '0'));
    this.interval = Number(option(settings, 'INTERVAL', '0'));
    this.limit = Number(option(settings, 'MAXTICKS', '1000'));
    this.dupack = settings.has('DUPACK') ? Number(settings.get('DUPACK')![0]) : null;
    this.nak = option(settings, 'NAK', 'OFF') === 'ON';
    this.backoff = option(settings, 'BACKOFF', 'OFF') === 'ON';
    this.congestion = option(settings, 'CONGESTION', 'OFF') === 'ON';
    this.unsafe = option(settings, 'UNSAFE', 'OFF') === 'ON';
    this.trace = option(settings, 'TRACE', 'ALL');
    this.random = settings.has('RANDOM') ? settings.get('RANDOM')!.map(Number) as [number, number, number] : null;
    this.loseData = numberSet(settings, 'LOSEDATA');
    this.loseCtrl = numberSet(settings, 'LOSECTRL');
    this.corruptData = numberSet(settings, 'CORRUPTDATA');
    this.corruptCtrl = numberSet(settings, 'CORRUPTCTRL');
    this.delayData = delayMap(settings, 'DELAYDATA');
    this.delayCtrl = delayMap(settings, 'DELAYCTRL');
    this.snapshots = numberSet(settings, 'SNAPSHOT');
  }

  windowLimit(): number {
    if (this.protocol === 'SW') return 1;
    if (this.protocol === 'GBN') return 2 ** this.seqbits - 1;
    return 2 ** (this.seqbits - 1);
  }

  configLine(): string {
    return `config: ${this.protocol} n=${this.frames} w=${this.window} k=${this.seqbits} T=${this.timeout} d=${this.delay}`;
  }

  optionsLine(): string {
    const dupack = this.dupack === null ? 'off' : this.dupack;
    const random = this.random === null ? 'off' : this.random.join('/');
    const switchText = (flag: boolean): string => flag ? 'on' : 'off';
    return `options: interval=${this.interval} limit=${this.limit} dupack=${dupack} ` +
      `nak=${switchText(this.nak)} backoff=${switchText(this.backoff)} ` +
      `congestion=${switchText(this.congestion)} unsafe=${switchText(this.unsafe)} ` +
      `trace=${this.trace.toLowerCase()} random=${random}`;
  }
}

function checkSettings(lines: SettingLine[]): Config {
  const settings = new Map<string, string[]>();
  for (const [key, values] of lines) {
    if (!KEYS.includes(key)) throw new SettingsError(`unknown key ${key}`);
    if (settings.has(key)) throw new SettingsError(`duplicate key ${key}`);
    const countMatches = key === 'RANDOM' ? values.length === 3 :
      LIST_KEYS.has(key) ? values.length >= 1 : values.length === 1;
    if (!countMatches) throw new SettingsError(`wrong number of values for ${key}`);
    settings.set(key, values);
  }
  for (const key of REQUIRED) {
    if (!settings.has(key)) throw new SettingsError(`missing key ${key}`);
  }
  for (const key of KEYS) {
    if (settings.has(key) && !validValue(key, settings.get(key)!)) {
      throw new SettingsError(`bad value for ${key}`);
    }
  }
  const config = new Config(settings);
  if (config.protocol === 'SR' && config.dupack !== null) {
    throw new SettingsError('DUPACK not supported for SR');
  }
  const limit = config.windowLimit();
  if ((config.protocol === 'SW' || !config.unsafe) && config.window > limit) {
    throw new SettingsError(`window ${config.window} exceeds limit ${limit} for ${config.protocol}`);
  }
  const dataBoth = [...config.loseData].filter(n => config.corruptData.has(n));
  if (dataBoth.length) throw new SettingsError(`data #${Math.min(...dataBoth)} both lost and corrupted`);
  const ctrlBoth = [...config.loseCtrl].filter(n => config.corruptCtrl.has(n));
  if (ctrlBoth.length) throw new SettingsError(`control #${Math.min(...ctrlBoth)} both lost and corrupted`);
  return config;
}

class FrameRecord {
  transmissions = 0;
  first: number | null = null;
  delivered: number | null = null;
  acked: number | null = null;
}

class LossGenerator {
  state: number;
  readonly loss: number;
  readonly corruption: number;

  constructor(seed: number, loss: number, corruption: number) {
    this.state = seed;
    this.loss = loss;
    this.corruption = corruption;
  }

  nextOutcome(): Outcome {
    this.state = RANDOM_MULTIPLIER * this.state % RANDOM_MODULUS;
    const roll = this.state % 100;
    if (roll < this.loss) return 'LOST';
    if (roll < this.loss + this.corruption) return 'CORRUPT';
    return 'NORMAL';
  }
}

class Channel {
  readonly delay: number;
  readonly losses: Set<number>;
  readonly corruptions: Set<number>;
  readonly extraDelays: Map<number, number>;
  sent = 0;
  lost = 0;
  corrupted = 0;
  inTransit: Transmission[] = [];

  constructor(delay: number, losses: Set<number>, corruptions: Set<number>, extraDelays: Map<number, number>) {
    this.delay = delay;
    this.losses = losses;
    this.corruptions = corruptions;
    this.extraDelays = extraDelays;
  }

  send(kind: TransmissionKind, value: number, payload: number | null, tick: number, generator: LossGenerator | null): Transmission {
    const number = ++this.sent;
    let outcome = generator === null ? 'NORMAL' : generator.nextOutcome();
    if (this.losses.has(number)) outcome = 'LOST';
    else if (this.corruptions.has(number)) outcome = 'CORRUPT';
    const item = {
      number, kind, value, payload, outcome,
      arrival: tick + this.delay + (this.extraDelays.get(number) ?? 0)
    };
    this.inTransit.push(item);
    return item;
  }

  arrivals(tick: number): Transmission[] {
    const arrived = this.inTransit.filter(item => item.arrival === tick);
    this.inTransit = this.inTransit.filter(item => item.arrival !== tick);
    return arrived;
  }

  countDamage(item: Transmission): void {
    if (item.outcome === 'LOST') ++this.lost;
    else ++this.corrupted;
  }
}

class Simulation {
  readonly config: Config;
  readonly selective: boolean;
  readonly modulus: number;
  readonly visible: Set<string>;
  readonly generator: LossGenerator | null;
  readonly dataChannel: Channel;
  readonly controlChannel: Channel;
  readonly records: FrameRecord[];
  readonly lines: string[];
  tick: number;
  base: number;
  framesSent: number;
  nextFrame: number;
  timerLength: number;
  timer: number | null;
  duplicates: number;
  acked: boolean[];
  timers: (number | null)[];
  queue: number[];
  cwnd: number;
  ssthresh: number;
  roundAcks: number;
  expected: number;
  nakSent: boolean;
  buffer: Map<number, number>;
  resent: number;
  naks: number;
  timeouts: number;
  fastRetransmits: number;
  delivered: number;
  errors: number;
  discarded: number;
  maxBuffer: number;
  completion: number | null;

  constructor(config: Config) {
    this.config = config;
    this.selective = config.protocol === 'SR';
    this.modulus = 2 ** config.seqbits;
    this.visible = new Set(TRACE_SIDES[config.trace]);
    this.generator = config.random === null ? null : new LossGenerator(...config.random);
    this.dataChannel = new Channel(config.delay, config.loseData, config.corruptData, config.delayData);
    this.controlChannel = new Channel(config.delay, config.loseCtrl, config.corruptCtrl, config.delayCtrl);
    this.records = Array.from({ length: config.frames }, () => new FrameRecord());
    this.lines = [];
    this.tick = 0;
    this.base = 0;
    this.framesSent = 0;
    this.nextFrame = 0;
    this.timerLength = config.timeout;
    this.timer = null;
    this.duplicates = 0;
    this.acked = Array(config.frames).fill(false);
    this.timers = Array<number | null>(config.frames).fill(null);
    this.queue = [];
    this.cwnd = 1;
    this.ssthresh = config.window;
    this.roundAcks = 0;
    this.expected = 0;
    this.nakSent = false;
    this.buffer = new Map<number, number>();
    this.resent = 0;
    this.naks = 0;
    this.timeouts = 0;
    this.fastRetransmits = 0;
    this.delivered = 0;
    this.errors = 0;
    this.discarded = 0;
    this.maxBuffer = 0;
    this.completion = null;
  }

  emit(...parts: (string | number)[]): void { this.lines.push([this.tick, ...parts].join(' ')); }
  trace(side: string, ...parts: (string | number)[]): void { if (this.visible.has(side)) this.emit(...parts); }
  frameOf(value: number): number { return this.base + mod(value - this.base, this.modulus); }
  effectiveWindow(): number { return this.config.congestion ? Math.min(this.config.window, this.cwnd) : this.config.window; }

  run(): void {
    for (let tick = 0; tick <= this.config.limit; ++tick) {
      this.tick = tick;
      for (const item of this.dataChannel.arrivals(tick)) {
        if (item.outcome === 'NORMAL') this.receiveData(item);
        else this.reportDamage(this.dataChannel, item, 'RECEIVER');
      }
      for (const item of this.controlChannel.arrivals(tick)) {
        if (item.outcome === 'NORMAL') this.receiveControl(item);
        else this.reportDamage(this.controlChannel, item, 'SENDER');
      }
      const completed = this.base === this.config.frames;
      if (!completed) {
        this.processTimeouts();
        this.sendData();
      }
      if (this.config.snapshots.has(tick)) this.snapshot();
      if (completed) {
        this.completion = tick;
        this.emit('DONE');
        return;
      }
    }
    this.emit('ABORT');
  }

  reportDamage(channel: Channel, item: Transmission, side: string): void {
    channel.countDamage(item);
    this.trace(side, item.outcome, item.kind, `#${item.number}`);
  }

  receiveData(item: Transmission): void {
    this.trace('RECEIVER', 'RECV', `seq=${item.value}`, `#${item.number}`);
    if (this.selective) this.selectiveReceive(item.value, item.payload!);
    else this.goBackNReceive(item.value, item.payload!);
  }

  goBackNReceive(seq: number, payload: number): void {
    if (seq === this.expected % this.modulus) {
      this.deliver(payload);
      this.sendControl('ack', seq);
      return;
    }
    this.discard(seq);
    if (this.config.nak && !this.nakSent) {
      this.sendControl('nak', this.expected % this.modulus);
      this.nakSent = true;
    } else if (this.expected > 0) {
      this.sendControl('ack', (this.expected - 1) % this.modulus);
    }
  }

  selectiveReceive(seq: number, payload: number): void {
    const offset = mod(seq - this.expected, this.modulus);
    if (offset >= this.config.window) {
      this.discard(seq);
      if (mod(this.expected - seq, this.modulus) <= this.config.window) {
        this.sendControl('ack', seq);
      }
      return;
    }
    const position = this.expected + offset;
    if (this.buffer.has(position)) {
      this.discard(seq);
      this.sendControl('ack', seq);
    } else if (offset === 0) {
      this.deliver(payload);
      while (this.buffer.has(this.expected)) {
        const waiting = this.buffer.get(this.expected);
        this.buffer.delete(this.expected);
        this.deliver(waiting!);
      }
      this.sendControl('ack', seq);
    } else {
      this.buffer.set(position, payload);
      this.maxBuffer = Math.max(this.maxBuffer, this.buffer.size);
      this.trace('RECEIVER', 'BUFFER', `f=${position}`);
      this.sendControl('ack', seq);
      if (this.config.nak && !this.nakSent) {
        this.sendControl('nak', this.expected % this.modulus);
        this.nakSent = true;
      }
    }
  }

  deliver(payload: number): void {
    const position = this.expected;
    if (payload === position) {
      ++this.delivered;
      this.records[payload].delivered = this.tick;
      this.trace('RECEIVER', 'DELIVER', `f=${position}`);
    } else {
      ++this.errors;
      this.trace('RECEIVER', 'DELIVER', `f=${position}`, `wrong=${payload}`);
    }
    ++this.expected;
    this.nakSent = false;
  }

  discard(seq: number): void {
    ++this.discarded;
    this.trace('RECEIVER', 'DISCARD', `seq=${seq}`);
  }

  sendControl(kind: ControlKind, value: number): void {
    const item = this.controlChannel.send(kind, value, null, this.tick, this.generator);
    if (kind === 'nak') ++this.naks;
    this.trace('RECEIVER', kind.toUpperCase(), `a=${value}`, `#${item.number}`);
  }

  receiveControl(item: Transmission): void {
    const before: [number, number] = [this.cwnd, this.ssthresh];
    if (item.kind === 'ack') {
      if (this.selective) this.selectiveAck(item);
      else this.goBackNAck(item);
    } else if (this.selective) this.selectiveNak(item);
    else this.goBackNNak(item);
    this.reportWindow(before);
  }

  controlLine(item: Transmission, accepted: boolean): void {
    const parts = [`${accepted ? 'GOT' : 'OLD'}${item.kind.toUpperCase()}`,
      `a=${item.value}`, `#${item.number}`];
    if (accepted) parts.push(`base=${this.base}`);
    this.trace('SENDER', ...parts);
  }

  goBackNAck(item: Transmission): void {
    const frame = this.frameOf(item.value);
    if (frame < this.framesSent) {
      this.growWindow(frame - this.base + 1);
      this.moveBase(frame + 1);
      if (this.nextFrame < this.base) this.nextFrame = this.base;
      this.timer = this.base === this.nextFrame ? null : this.tick + this.timerLength;
      this.controlLine(item, true);
      return;
    }
    this.controlLine(item, false);
    if (this.config.dupack === null || this.base < 1) return;
    if (item.value === (this.base - 1) % this.modulus) {
      ++this.duplicates;
      if (this.duplicates === this.config.dupack) {
        ++this.fastRetransmits;
        this.trace('SENDER', 'FASTRETX', `f=${this.base}`);
        this.goBack();
        this.halveWindow();
      }
    }
  }

  goBackNNak(item: Transmission): void {
    const frame = this.frameOf(item.value);
    if (frame > this.framesSent) {
      this.controlLine(item, false);
      return;
    }
    this.growWindow(frame - this.base);
    this.moveBase(frame);
    this.goBack();
    this.halveWindow();
    this.controlLine(item, true);
  }

  selectiveAck(item: Transmission): void {
    const frame = this.frameOf(item.value);
    if (frame >= this.framesSent || this.acked[frame]) {
      this.controlLine(item, false);
      return;
    }
    this.acked[frame] = true;
    this.records[frame].acked = this.tick;
    this.timers[frame] = null;
    this.queue = this.queue.filter(waiting => waiting !== frame);
    this.growWindow(1);
    const previous = this.base;
    while (this.base < this.framesSent && this.acked[this.base]) ++this.base;
    if (this.base > previous) this.timerLength = this.config.timeout;
    this.controlLine(item, true);
  }

  selectiveNak(item: Transmission): void {
    const frame = this.frameOf(item.value);
    if (frame >= this.framesSent || this.acked[frame]) {
      this.controlLine(item, false);
      return;
    }
    this.timers[frame] = null;
    if (!this.queue.includes(frame)) this.queue.push(frame);
    this.halveWindow();
    this.controlLine(item, true);
  }

  moveBase(newBase: number): void {
    if (newBase <= this.base) return;
    for (let frame = this.base; frame < newBase; ++frame) this.records[frame].acked = this.tick;
    this.base = newBase;
    this.timerLength = this.config.timeout;
    this.duplicates = 0;
  }

  goBack(): void { this.nextFrame = this.base; this.timer = null; this.duplicates = 0; }

  growWindow(count: number): void {
    if (!this.config.congestion) return;
    for (let i = 0; i < count; ++i) {
      if (this.cwnd >= this.config.window) continue;
      if (this.cwnd < this.ssthresh) ++this.cwnd;
      else {
        ++this.roundAcks;
        if (this.roundAcks === this.cwnd) {
          ++this.cwnd;
          this.roundAcks = 0;
        }
      }
    }
  }

  halveWindow(): void {
    if (!this.config.congestion) return;
    this.ssthresh = Math.max(Math.floor(this.cwnd / 2), 1);
    this.cwnd = this.ssthresh;
    this.roundAcks = 0;
  }

  collapseWindow(): void {
    if (!this.config.congestion) return;
    this.ssthresh = Math.max(Math.floor(this.cwnd / 2), 1);
    this.cwnd = 1;
    this.roundAcks = 0;
  }

  reportWindow(before: [number, number]): void {
    if (this.cwnd !== before[0] || this.ssthresh !== before[1]) {
      this.trace('SENDER', 'CWND', this.cwnd, `ssthresh=${this.ssthresh}`);
    }
  }

  processTimeouts(): void {
    if (this.selective) {
      for (let frame = this.base; frame < this.framesSent; ++frame) {
        if (this.timers[frame] === this.tick) {
          this.timers[frame] = null;
          this.queue.push(frame);
          this.timeOut(frame);
        }
      }
    } else if (this.timer === this.tick) {
      this.timeOut(this.base);
      this.goBack();
    }
  }

  timeOut(frame: number): void {
    const before: [number, number] = [this.cwnd, this.ssthresh];
    ++this.timeouts;
    this.trace('SENDER', 'TIMEOUT', `f=${frame}`);
    if (this.config.backoff) this.timerLength = Math.min(2 * this.timerLength, 8 * this.config.timeout);
    this.collapseWindow();
    this.reportWindow(before);
  }

  maySendNew(frame: number): boolean {
    return frame < this.config.frames && frame < this.base + this.effectiveWindow() &&
      frame * this.config.interval <= this.tick;
  }

  sendData(): void { if (this.selective) this.selectiveSend(); else this.goBackNSend(); }

  goBackNSend(): void {
    const frame = this.nextFrame;
    if (frame >= this.config.frames || frame >= this.base + this.effectiveWindow()) return;
    if (frame >= this.framesSent && frame * this.config.interval > this.tick) return;
    this.transmit(frame);
    this.framesSent = Math.max(this.framesSent, frame + 1);
    ++this.nextFrame;
    if (this.timer === null) this.timer = this.tick + this.timerLength;
  }

  selectiveSend(): void {
    let frame;
    if (this.queue.length) frame = this.queue.shift();
    else if (this.maySendNew(this.framesSent)) frame = this.framesSent++;
    else return;
    this.transmit(frame!);
    this.timers[frame!] = this.tick + this.timerLength;
  }

  transmit(frame: number): void {
    const record = this.records[frame], seq = frame % this.modulus;
    const item = this.dataChannel.send('data', seq, frame, this.tick, this.generator);
    ++record.transmissions;
    let label;
    if (record.transmissions === 1) {
      record.first = this.tick;
      label = 'SEND';
    } else {
      ++this.resent;
      label = 'RESEND';
    }
    this.trace('SENDER', label, `f=${frame}`, `seq=${seq}`, `#${item.number}`);
  }

  senderMark(frame: number): string {
    let acknowledged, waiting, sent;
    if (this.selective) {
      acknowledged = this.acked[frame];
      waiting = this.queue.includes(frame);
      sent = frame < this.framesSent;
    } else {
      acknowledged = frame < this.base;
      waiting = this.nextFrame <= frame && frame < this.framesSent;
      sent = frame < this.nextFrame;
    }
    if (acknowledged) return 'A';
    if (waiting) return 'R';
    if (sent) return 'O';
    if (frame < this.base + this.effectiveWindow()) return 'W';
    return '.';
  }

  receiverMark(position: number): string {
    if (position < this.expected) return 'D';
    if (this.selective) {
      if (this.buffer.has(position)) return 'B';
      if (position < this.expected + this.config.window) return 'W';
    } else if (position === this.expected) return 'W';
    return '.';
  }

  snapshot(): void {
    const positions = Array.from({length: this.config.frames}, (_, i) => i);
    const sender = positions.map(frame => this.senderMark(frame)).join('');
    const receiver = positions.map(position => this.receiverMark(position)).join('');
    this.emit('SNAPSHOT', `sender=${sender}`, `receiver=${receiver}`);
  }

  dataCount(): number { return this.dataChannel.sent; }
  goodputText(): string { return truncated(this.delivered, this.completion!, 2); }
  efficiencyText(): string { return truncated(100 * this.delivered, this.dataCount(), 1); }
  latencyText(): string {
    if (this.delivered === 0) return '-';
    const total = this.records.reduce((sum, record) =>
      sum + (record.delivered === null ? 0 : record.delivered - record.first!), 0);
    return truncated(total, this.delivered, 2);
  }

  report(): string[] {
    const lines = this.records.map((record, frame) =>
      `frame ${frame}: seq=${frame % this.modulus} tx=${record.transmissions} ` +
      `first=${tickText(record.first)} delivered=${tickText(record.delivered)} ` +
      `acked=${tickText(record.acked)}`);
    const data = this.dataChannel, control = this.controlChannel;
    lines.push(`totals: data=${data.sent} resent=${this.resent} control=${control.sent} ` +
      `nak=${this.naks} timeouts=${this.timeouts} fastretx=${this.fastRetransmits}`);
    lines.push(`channel: lost_data=${data.lost} lost_ctrl=${control.lost} ` +
      `corrupt_data=${data.corrupted} corrupt_ctrl=${control.corrupted}`);
    lines.push(`receiver: delivered=${this.delivered} errors=${this.errors} ` +
      `discarded=${this.discarded} max_buffer=${this.maxBuffer}`);
    const completion = this.completion === null ? '-' : String(this.completion);
    const goodput = this.completion === null ? '-' : this.goodputText();
    const utilization = truncated(100 * data.sent, this.tick + 1, 1);
    lines.push(`result: completion=${completion} goodput=${goodput} ` +
      `efficiency=${this.efficiencyText()}% utilization=${utilization}% latency=${this.latencyText()}`);
    return lines;
  }
}

class Scenario {
  readonly name: string;
  readonly settings: SettingLine[];
  config: Config | null = null;
  simulation: Simulation | null = null;

  constructor(name: string, settings: SettingLine[]) {
    this.name = name;
    this.settings = settings;

  }

  completed(): boolean { return this.simulation !== null && this.simulation.completion !== null; }
  status(): string { return this.simulation === null ? 'invalid' : 'aborted'; }

  execute(output: string[]): void {
    output.push(`== ${this.name} ==`);
    try { this.config = checkSettings(this.settings); }
    catch (error) {
      if (!(error instanceof SettingsError)) throw error;
      output.push(`error: ${error.message}`);
      return;
    }
    output.push(this.config.configLine(), this.config.optionsLine());
    this.simulation = new Simulation(this.config);
    this.simulation.run();
    output.push(...this.simulation.lines, ...this.simulation.report());
  }
}

function rankingLines(scenarios: Scenario[]): string[] {
  const lines = ['== ranking =='];
  const completed = scenarios.filter(scenario => scenario.completed());
  completed.sort((a, b) => {
    const x = a.simulation!, y = b.simulation!;
    const first = y.delivered * x.completion! - x.delivered * y.completion!;
    if (first !== 0) return first;
    return y.delivered * x.dataCount() - x.delivered * y.dataCount();
  });
  completed.forEach((scenario, i) => {
    const run = scenario.simulation!;
    lines.push(`${i + 1}. ${scenario.name} ${scenario.config!.protocol} ` +
      `goodput=${run.goodputText()} efficiency=${run.efficiencyText()}%`);
  });
  for (const scenario of scenarios) {
    if (!scenario.completed()) lines.push(`- ${scenario.name} ${scenario.status()}`);
  }
  return lines;
}

function protocolLines(scenarios: Scenario[]): string[] {
  const lines = ['== protocols =='];
  for (const protocol of PROTOCOLS) {
    const runs = scenarios.filter(s => s.completed() && s.config!.protocol === protocol)
      .map(s => s.simulation!);
    if (!runs.length) continue;
    const delivered = runs.reduce((sum, r) => sum + r.delivered, 0);
    const ticks = runs.reduce((sum, r) => sum + r.completion!, 0);
    const data = runs.reduce((sum, r) => sum + r.dataCount(), 0);
    lines.push(`${protocol}: runs=${runs.length} goodput=${truncated(delivered, ticks, 2)} ` +
      `efficiency=${truncated(100 * delivered, data, 1)}%`);
  }
  return lines;
}

function main(): void {
  const lines = readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
  const count = Number(lines[0]);
  let index = 1;
  const scenarios: Scenario[] = [];
  for (let i = 0; i < count; ++i) {
    const name = lines[index++].split(' ')[1];
    const settings: SettingLine[] = [];
    while (lines[index] !== 'END') {
      const [key, ...values] = lines[index++].split(' ');
      settings.push([key, values]);
    }
    ++index;
    scenarios.push(new Scenario(name, settings));
  }
  const output: string[] = [];
  for (const scenario of scenarios) scenario.execute(output);
  output.push(...rankingLines(scenarios), ...protocolLines(scenarios));
  process.stdout.write(output.join('\n') + '\n');
}

main();
