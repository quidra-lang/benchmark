import { readFileSync } from 'node:fs';

class CommandError extends Error {}
function fail(message: string): never { throw new CommandError(message); }
function bad(kind: string, word: string): never { return fail(`BAD ${kind} ${word}`); }
const modulo = (value: number, divisor: number): number => (value % divisor + divisor) % divisor;
const LETTERS = 'CDEFGAB';
const NATURALS = [0, 2, 4, 5, 7, 9, 11] as const;
const FIFTHS = [0, 2, 4, -1, 1, 3, 5] as const;
const ACCIDENTALS = ['bb', 'b', '', '#', 'x'] as const;
const SHARPS = 'C C# D D# E F F# G G# A A# B'.split(' ');
const FLATS = 'C Db D Eb E F Gb G Ab A Bb B'.split(' ');
const ROMANS = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'] as const;

function boundedInteger(text: string, kind: string, low: number, high: number): number {
  if (text.length > 3 || !/^(0|[1-9][0-9]*)$/.test(text)) bad(kind, text);
  const value = Number(text);
  if (value < low || value > high) bad(kind, text);
  return value;
}
function frequency(text: string, tuning: boolean): number {
  if (!/^[0-9]{1,5}(\.[0-9]{1,2})?$/.test(text)) bad('FREQUENCY', text);
  const [whole, fraction = ''] = text.split('.');
  const cents = Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
  if (cents === 0 || (tuning && (cents < 40000 || cents > 48000))) bad('FREQUENCY', text);
  return cents;
}
const frequencyText = (cents: number): string => `${Math.trunc(cents / 100)}.${String(cents % 100).padStart(2, '0')}`;

interface Tone { readonly letters: number; readonly semitones: number }
class Pitch {
  constructor(readonly letter: number, readonly alteration: number) {}
  get pitchClass(): number { return modulo(NATURALS[this.letter] + this.alteration, 12); }
  equals(other: Pitch): boolean { return this.letter === other.letter && this.alteration === other.alteration; }
  toString(): string { return LETTERS[this.letter] + ACCIDENTALS[this.alteration + 2]; }
  raise(tone: Tone): Pitch {
    const target = this.letter + tone.letters;
    const alteration = NATURALS[this.letter] + this.alteration + tone.semitones - NATURALS[modulo(target, 7)] - 12 * Math.floor(target / 7);
    if (alteration < -2 || alteration > 2) fail('CANNOT SPELL');
    return new Pitch(modulo(target, 7), alteration);
  }
}
function pitchPrefix(text: string, kind: string): { pitch: Pitch; rest: string } {
  const match = /^([A-G])(bb|b|#|x)?/.exec(text);
  if (!match) bad(kind, text);
  return { pitch: new Pitch(LETTERS.indexOf(match[1]), ACCIDENTALS.indexOf((match[2] ?? '') as typeof ACCIDENTALS[number]) - 2), rest: text.slice(match[0].length) };
}
function parsePitch(text: string): Pitch {
  const parsed = pitchPrefix(text, 'PITCH');
  if (parsed.rest !== '') bad('PITCH', text);
  return parsed.pitch;
}
function fifthPitch(value: number): Pitch {
  return new Pitch([3, 0, 4, 1, 5, 2, 6][modulo(value + 1, 7)], Math.floor((value + 1) / 7));
}
class Note {
  constructor(readonly pitch: Pitch, readonly octave: number) {}
  get midi(): number { return 12 * (this.octave + 1) + NATURALS[this.pitch.letter] + this.pitch.alteration; }
  get position(): number { return 7 * this.octave + this.pitch.letter; }
  get valid(): boolean { return this.octave >= -1 && this.octave <= 9 && this.midi >= 0 && this.midi <= 127; }
  toString(): string { return `${this.pitch}${this.octave}`; }
}
function parseNote(text: string): Note {
  const parsed = pitchPrefix(text, 'NOTE');
  if (!/^(-1|[0-9])$/.test(parsed.rest)) bad('NOTE', text);
  const note = new Note(parsed.pitch, Number(parsed.rest));
  if (!note.valid) bad('NOTE', text);
  return note;
}
const makeNote = (pitch: Pitch, value: number): Note => new Note(pitch, (value - NATURALS[pitch.letter] - pitch.alteration) / 12 - 1);
const spelling = (value: number, flat = false): Note => new Note(parsePitch((flat ? FLATS : SHARPS)[modulo(value, 12)]), Math.floor(value / 12) - 1);

const QUALITIES = ['P', 'M', 'm', 'A', 'd', 'AA', 'dd'] as const;
type IntervalQuality = typeof QUALITIES[number];
const PERFECT_DELTAS: Readonly<Partial<Record<IntervalQuality, number>>> = { P: 0, A: 1, d: -1, AA: 2, dd: -2 };
const MAJOR_DELTAS: Readonly<Partial<Record<IntervalQuality, number>>> = { M: 0, m: -1, A: 1, d: -2, AA: 2, dd: -3 };
function qualityDelta(quality: IntervalQuality, number: number): number | undefined {
  return ([0, 3, 4].includes((number - 1) % 7) ? PERFECT_DELTAS : MAJOR_DELTAS)[quality];
}
class Interval {
  constructor(readonly quality: IntervalQuality, readonly number: number) {}
  toString(): string { return this.quality + this.number; }
  get forbidden(): boolean { return this.number === 1 && (this.quality === 'd' || this.quality === 'dd'); }
  get tone(): Tone {
    const letters = this.number - 1;
    return { letters, semitones: 12 * Math.floor(letters / 7) + NATURALS[letters % 7] + qualityDelta(this.quality, this.number)! };
  }
  get simple(): Interval {
    let number = this.number;
    while (number > 8) number -= 7;
    return new Interval(this.quality, number);
  }
  get consonance(): 'perfect' | 'imperfect' | 'dissonant' {
    const simple = this.simple;
    if (simple.quality === 'P' && [1, 5, 8].includes(simple.number)) return 'perfect';
    if ((simple.quality === 'M' || simple.quality === 'm') && [3, 6].includes(simple.number)) return 'imperfect';
    return 'dissonant';
  }
}
function parseInterval(text: string): Interval {
  const match = /^(AA|dd|P|M|m|A|d)([1-9][0-9]?)$/.exec(text);
  if (!match) bad('INTERVAL', text);
  const interval = new Interval(match[1] as IntervalQuality, Number(match[2]));
  if (qualityDelta(interval.quality, interval.number) === undefined || interval.forbidden) bad('INTERVAL', text);
  return interval;
}
interface Motion { readonly interval: Interval; readonly down: boolean; readonly semitones: number }
function between(first: Note, second: Note): Motion {
  let distance = second.position - first.position, semitones = second.midi - first.midi;
  const down = distance < 0 || (distance === 0 && semitones < 0);
  if (down) { distance = -distance; semitones = -semitones; }
  const difference = semitones - 12 * Math.floor(distance / 7) - NATURALS[distance % 7];
  const quality = QUALITIES.find(item => qualityDelta(item, distance + 1) === difference);
  if (quality === undefined) fail('UNNAMEABLE INTERVAL');
  return { interval: new Interval(quality, distance + 1), down, semitones };
}
const toneList = (text: string): readonly Tone[] => text.split(' ').map(item => parseInterval(item).tone);
const build = (root: Pitch, tones: readonly Tone[]): Pitch[] => tones.map(tone => root.raise(tone));

const SCALE_PATTERNS = {
  major: 'P1 M2 M3 P4 P5 M6 M7', natural_minor: 'P1 M2 m3 P4 P5 m6 m7',
  harmonic_minor: 'P1 M2 m3 P4 P5 m6 M7', melodic_minor: 'P1 M2 m3 P4 P5 M6 M7',
  ionian: 'P1 M2 M3 P4 P5 M6 M7', dorian: 'P1 M2 m3 P4 P5 M6 m7',
  phrygian: 'P1 m2 m3 P4 P5 m6 m7', lydian: 'P1 M2 M3 A4 P5 M6 M7',
  mixolydian: 'P1 M2 M3 P4 P5 M6 m7', aeolian: 'P1 M2 m3 P4 P5 m6 m7',
  locrian: 'P1 m2 m3 P4 d5 m6 m7', major_pentatonic: 'P1 M2 M3 P5 M6',
  minor_pentatonic: 'P1 m3 P4 P5 m7', blues: 'P1 m3 P4 A4 P5 m7',
  whole_tone: 'P1 M2 M3 A4 A5 A6',
} as const;
type ScaleName = keyof typeof SCALE_PATTERNS;
interface Scale { readonly name: ScaleName; readonly tones: readonly Tone[] }
const SCALES: readonly Scale[] = (Object.keys(SCALE_PATTERNS) as ScaleName[]).map(name => ({ name, tones: toneList(SCALE_PATTERNS[name]) }));
type ChordName = 'maj' | 'min' | 'dim' | 'aug' | 'sus2' | 'sus4' | '6' | 'm6' | '7' | 'maj7' | 'm7' | 'mMaj7' | 'm7b5' | 'dim7' | '9' | 'add9';
class Chord {
  readonly tones: readonly Tone[];
  constructor(readonly name: ChordName, readonly suffix: string, readonly lower: boolean, readonly numeralSuffix: string, pattern: string) {
    this.tones = toneList(pattern);
  }
  symbol(root: Pitch, bass: Pitch | null = null): string { return `${root}${this.suffix}${bass === null ? '' : '/' + bass}`; }
  roman(degree: number): string { return (this.lower ? ROMANS[degree].toLowerCase() : ROMANS[degree]) + this.numeralSuffix; }
}
const CHORDS: readonly Chord[] = [
  new Chord('maj', '', false, '', 'P1 M3 P5'), new Chord('min', 'm', true, '', 'P1 m3 P5'),
  new Chord('dim', 'dim', true, 'o', 'P1 m3 d5'), new Chord('aug', 'aug', false, '+', 'P1 M3 A5'),
  new Chord('sus2', 'sus2', false, 'sus2', 'P1 M2 P5'), new Chord('sus4', 'sus4', false, 'sus4', 'P1 P4 P5'),
  new Chord('6', '6', false, '6', 'P1 M3 P5 M6'), new Chord('m6', 'm6', true, '6', 'P1 m3 P5 M6'),
  new Chord('7', '7', false, '7', 'P1 M3 P5 m7'), new Chord('maj7', 'maj7', false, 'maj7', 'P1 M3 P5 M7'),
  new Chord('m7', 'm7', true, '7', 'P1 m3 P5 m7'), new Chord('mMaj7', 'mMaj7', true, 'maj7', 'P1 m3 P5 M7'),
  new Chord('m7b5', 'm7b5', true, 'h7', 'P1 m3 d5 m7'), new Chord('dim7', 'dim7', true, 'o7', 'P1 m3 d5 d7'),
  new Chord('9', '9', false, '9', 'P1 M3 P5 m7 M9'), new Chord('add9', 'add9', false, 'add9', 'P1 M3 P5 M9'),
];
type ModeName = 'major' | 'minor' | 'ionian' | 'dorian' | 'phrygian' | 'lydian' | 'mixolydian' | 'aeolian' | 'locrian';
interface Mode { readonly name: ModeName; readonly scale: ScaleName; readonly offset: number }
const MODES: readonly Mode[] = [
  { name: 'major', scale: 'major', offset: 0 }, { name: 'minor', scale: 'natural_minor', offset: -3 },
  { name: 'ionian', scale: 'ionian', offset: 0 }, { name: 'dorian', scale: 'dorian', offset: -2 },
  { name: 'phrygian', scale: 'phrygian', offset: -4 }, { name: 'lydian', scale: 'lydian', offset: 1 },
  { name: 'mixolydian', scale: 'mixolydian', offset: -1 }, { name: 'aeolian', scale: 'aeolian', offset: -3 },
  { name: 'locrian', scale: 'locrian', offset: -5 },
];
function named<T extends { readonly name: string }>(word: string, kind: string, choices: readonly T[]): T {
  const value = choices.find(item => item.name === word);
  return value ?? bad(kind, word);
}
class Key {
  readonly fifths: number;
  readonly scale: readonly Pitch[];
  constructor(readonly tonic: Pitch, readonly mode: Mode) {
    this.fifths = FIFTHS[tonic.letter] + 7 * tonic.alteration + mode.offset;
    if (this.fifths < -7 || this.fifths > 7) fail('THEORETICAL KEY');
    this.scale = build(tonic, toneList(SCALE_PATTERNS[mode.scale]));
  }
  toString(): string { return `${this.tonic} ${this.mode.name}`; }
  degree(pitch: Pitch): number { return modulo(pitch.letter - this.tonic.letter, 7); }
  prefix(pitch: Pitch): string {
    const difference = pitch.alteration - this.scale[this.degree(pitch)].alteration;
    return (difference < 0 ? 'b' : '#').repeat(Math.abs(difference));
  }
  label(pitch: Pitch): string { return this.prefix(pitch) + (this.degree(pitch) + 1); }
  get pitchClasses(): ReadonlySet<number> { return new Set(this.scale.map(pitch => pitch.pitchClass)); }
}
function parseKey(args: readonly string[], start = 0): Key {
  const tonic = parsePitch(args[start]), mode = named(args[start + 1], 'MODE', MODES);
  return new Key(tonic, mode);
}
interface Numeral { readonly alteration: number; readonly degree: number; readonly chord: Chord }
interface ChordSymbol { readonly root: Pitch; readonly chord: Chord }
function parseNumeral(text: string): Numeral {
  const start = text[0] === 'b' || text[0] === '#' ? 1 : 0;
  const alteration = start === 0 ? 0 : text[0] === 'b' ? -1 : 1;
  let end = start;
  while (end < text.length && 'IViv'.includes(text[end])) end++;
  const part = text.slice(start, end), suffix = text.slice(end);
  for (let degree = 0; degree < 7; degree++) {
    for (const chord of CHORDS) {
      const expected = chord.lower ? ROMANS[degree].toLowerCase() : ROMANS[degree];
      if (part === expected && suffix === chord.numeralSuffix) return { alteration, degree, chord };
    }
  }
  return bad('NUMERAL', text);
}
function parseSymbol(text: string): ChordSymbol {
  const parsed = pitchPrefix(text, 'SYMBOL'), chord = CHORDS.find(item => item.suffix === parsed.rest);
  if (!chord) bad('SYMBOL', text);
  return { root: parsed.pitch, chord };
}
function equalSets(first: ReadonlySet<number>, second: ReadonlySet<number>): boolean {
  return first.size === second.size && [...first].every(value => second.has(value));
}
function identify(notes: readonly Note[]): string {
  const ordered = notes.map((note, index) => ({ note, index })).sort((a, b) => a.note.midi - b.note.midi || a.index - b.index);
  const present = new Set<number>(), candidates: Note[] = [];
  for (const { note } of ordered) {
    if (present.has(note.pitch.pitchClass)) continue;
    present.add(note.pitch.pitchClass);
    candidates.push(note);
  }
  const bass = candidates[0].pitch;
  for (const root of candidates) {
    for (const chord of CHORDS) {
      const possible = chord.tones.map(tone => modulo(root.midi + tone.semitones, 12));
      if (!equalSets(new Set(possible), present)) continue;
      const inversion = possible.indexOf(bass.pitchClass);
      return `IDENTIFY ${chord.symbol(root.pitch, inversion === 0 ? null : bass)} root=${root.pitch} quality=${chord.name} inversion=${inversion}`;
    }
  }
  return 'IDENTIFY UNKNOWN';
}
function melody(notes: readonly Note[], args: readonly string[]): string {
  const values = notes.map(note => note.midi), low = values.indexOf(Math.min(...values)), high = values.indexOf(Math.max(...values));
  const range = between(notes[low], notes[high]).interval, steps: string[] = [];
  let leaps = 0;
  for (let index = 1; index < notes.length; index++) {
    const motion = between(notes[index - 1], notes[index]);
    steps.push(`${motion.down ? '-' : '+'}${motion.interval}`);
    if (Math.abs(values[index] - values[index - 1]) >= 3) leaps++;
  }
  return `MELODY n=${notes.length} low=${args[low]} high=${args[high]} range=${range} leaps=${leaps} steps=${steps.join(',')}`;
}
function cadence(numerals: readonly Numeral[]): string {
  if (numerals.length < 2) return 'none';
  const first = numerals[numerals.length - 2], second = numerals[numerals.length - 1];
  if (first.alteration === 0 && second.alteration === 0) {
    if (first.degree === 4 && second.degree === 0) return 'authentic';
    if (first.degree === 3 && second.degree === 0) return 'plagal';
    if (first.degree === 4 && second.degree === 5) return 'deceptive';
  }
  return second.alteration === 0 && second.degree === 4 ? 'half' : 'none';
}
function diatonic(key: Key): string[] {
  const rows = [`DIATONIC ${key}`], classes = key.scale.map(pitch => pitch.pitchClass);
  for (const size of [3, 4]) {
    const items: string[] = [];
    for (let degree = 0; degree < 7; degree++) {
      const third = modulo(classes[(degree + 2) % 7] - classes[degree], 12), fifth = modulo(classes[(degree + 4) % 7] - classes[degree], 12);
      let quality: ChordName;
      if (size === 3) quality = third === 4 ? 'maj' : fifth === 7 ? 'min' : 'dim';
      else {
        const seventh = modulo(classes[(degree + 6) % 7] - classes[degree], 12);
        quality = third === 4 ? seventh === 11 ? 'maj7' : '7' : fifth === 7 ? 'm7' : 'm7b5';
      }
      const chord = named(quality, 'QUALITY', CHORDS);
      items.push(`${chord.roman(degree)}=${chord.symbol(key.scale[degree])}`);
    }
    rows.push(`${size === 3 ? 'TRIADS' : 'SEVENTHS'} ${items.join(' ')}`);
  }
  return rows;
}

const ARITIES = {
  MIDI: [1,1], NOTE: [1,1], FREQ: [1,1], TUNING: [1,1], PITCH: [1,1], INTERVAL: [2,2],
  INVERT: [1,1], TRANSPOSE: [3,3], SCALE: [2,2], CHORD: [2,3], VOICE: [2,3],
  IDENTIFY: [2,15], MELODY: [2,15], ENHARMONIC: [1,1], KEYSIG: [2,2], RELATIVE: [2,2],
  CIRCLE: [1,1], DIATONIC: [2,2], PROGRESSION: [3,15], ANALYZE: [3,15], FINDKEY: [1,15],
  DEGREE: [3,3], SPELL: [3,3], KEYDIST: [4,4],
} as const;
type CommandName = keyof typeof ARITIES;
type KeyCommand = 'KEYSIG' | 'RELATIVE' | 'DIATONIC' | 'PROGRESSION' | 'ANALYZE' | 'DEGREE' | 'KEYDIST';
const isCommand = (word: string): word is CommandName => Object.hasOwn(ARITIES, word);
function executeKey(command: KeyCommand, args: readonly string[]): string[] {
  const key = parseKey(args);
  switch (command) {
    case 'KEYSIG': {
      if (key.fifths === 0) return [`KEYSIG ${key} none`];
      const names = (key.fifths > 0 ? 'F# C# G# D# A# E# B#' : 'Bb Eb Ab Db Gb Cb Fb').split(' ');
      return [`KEYSIG ${key} ${key.fifths > 0 ? 'sharps' : 'flats'}=${Math.abs(key.fifths)} ${names.slice(0, Math.abs(key.fifths)).join(' ')}`];
    }
    case 'RELATIVE': return [`RELATIVE ${key} major=${fifthPitch(key.fifths)} minor=${fifthPitch(key.fifths + 3)}`];
    case 'DIATONIC': return diatonic(key);
    case 'DEGREE': {
      const pitch = parsePitch(args[2]);
      return [`DEGREE ${key} ${args[2]} ${key.label(pitch)}`];
    }
    case 'KEYDIST': {
      const other = parseKey(args, 2);
      let distance = modulo(other.fifths - key.fifths, 12);
      if (distance > 6) distance -= 12;
      const first = key.pitchClasses, second = other.pitchClasses, sameTonic = key.tonic.pitchClass === other.tonic.pitchClass;
      const relation = equalSets(first, second) ? sameTonic ? 'same' : 'relative' : sameTonic ? 'parallel' : Math.abs(distance) === 1 ? 'close' : 'distant';
      const common = [...first].filter(value => second.has(value)).length;
      return [`KEYDIST ${key} ${other} fifths=${distance > 0 ? '+' : ''}${distance} common=${common} relation=${relation}`];
    }
    case 'ANALYZE': {
      const symbols = args.slice(2).map(parseSymbol);
      const numerals = symbols.map(symbol => key.prefix(symbol.root) + symbol.chord.roman(key.degree(symbol.root)));
      return [`ANALYZE ${key} ${numerals.join(' ')}`];
    }
    case 'PROGRESSION': {
      const numerals = args.slice(2).map(parseNumeral), rows = [`PROGRESSION ${key} ${numerals.length}`];
      for (const [index, numeral] of numerals.entries()) {
        const degree = key.scale[numeral.degree], root = new Pitch(degree.letter, degree.alteration + numeral.alteration);
        const pitches = build(root, numeral.chord.tones);
        rows.push(`${args[index + 2]} ${numeral.chord.symbol(root)} ${pitches.join(' ')}`);
      }
      rows.push(`CADENCE ${cadence(numerals)}`);
      return rows;
    }
  }
}
class Calculator {
  private tuning = 44000;

  execute(line: string): string[] {
    const words = line.split(' '), command = words[0];
    if (!isCommand(command)) fail(`UNKNOWN COMMAND ${command}`);
    const args = words.slice(1), [low, high] = ARITIES[command];
    if (args.length < low || args.length > high) fail('ARGUMENT COUNT');
    switch (command) {
      case 'MIDI': case 'FREQ': case 'ENHARMONIC': {
        const note = parseNote(args[0]), value = note.midi;
        if (command === 'MIDI') return [`MIDI ${args[0]} ${value}`];
        if (command === 'FREQ') return [`FREQ ${args[0]} ${frequencyText(Math.floor(this.tuning * 2 ** ((value - 69) / 12) + 0.5))}`];
        const equivalents: Note[] = [];
        for (let octave = -1; octave <= 9; octave++) {
          for (let letter = 0; letter < 7; letter++) {
            const alteration = value - 12 * (octave + 1) - NATURALS[letter];
            if (alteration >= -2 && alteration <= 2) equivalents.push(new Note(new Pitch(letter, alteration), octave));
          }
        }
        return [`ENHARMONIC ${args[0]} ${equivalents.join(' ')}`];
      }
      case 'NOTE': {
        const value = boundedInteger(args[0], 'NUMBER', 0, 127);
        return [`NOTE ${value} ${spelling(value)} ${spelling(value, true)}`];
      }
      case 'TUNING': case 'PITCH': {
        const value = frequency(args[0], command === 'TUNING');
        if (command === 'TUNING') {
          this.tuning = value;
          return [`TUNING ${frequencyText(value)}`];
        }
        const height = 69 + 12 * Math.log2(value / this.tuning), nearest = Math.floor(height + 0.5);
        if (nearest < 0 || nearest > 127) fail('OUT OF RANGE');
        const cents = Math.floor(100 * (height - nearest) + 0.5);
        return [`PITCH ${frequencyText(value)} ${spelling(nearest)} ${cents >= 0 ? '+' : ''}${cents}`];
      }
      case 'INTERVAL': {
        const first = parseNote(args[0]), second = parseNote(args[1]), motion = between(first, second);
        return [`INTERVAL ${args[0]} ${args[1]} ${motion.interval} ${motion.down ? 'down' : 'up'} semitones=${motion.semitones} simple=${motion.interval.simple} class=${motion.interval.consonance}`];
      }
      case 'INVERT': {
        const interval = parseInterval(args[0]), simple = interval.simple;
        const inverses: Readonly<Record<IntervalQuality, IntervalQuality>> = { P: 'P', M: 'm', m: 'M', A: 'd', d: 'A', AA: 'dd', dd: 'AA' };
        const inverse = new Interval(inverses[simple.quality], 9 - simple.number);
        if (inverse.forbidden) fail('CANNOT INVERT');
        return [`INVERT ${args[0]} ${simple} ${inverse}`];
      }
      case 'TRANSPOSE': {
        const note = parseNote(args[0]), interval = parseInterval(args[1]), direction = args[2];
        if (direction !== 'UP' && direction !== 'DOWN') bad('DIRECTION', direction);
        const sign = direction === 'UP' ? 1 : -1, tone = interval.tone;
        const target = note.position + sign * tone.letters, value = note.midi + sign * tone.semitones;
        const letter = modulo(target, 7), octave = Math.floor(target / 7), alteration = value - 12 * (octave + 1) - NATURALS[letter];
        if (alteration < -2 || alteration > 2) fail('CANNOT SPELL');
        const result = new Note(new Pitch(letter, alteration), octave);
        if (!result.valid) fail('OUT OF RANGE');
        return [`TRANSPOSE ${args[0]} ${args[1]} ${direction} ${result}`];
      }
      case 'SCALE': {
        const root = parsePitch(args[0]), scale = named(args[1], 'SCALE', SCALES), pitches = build(root, scale.tones);
        const semitones = [...scale.tones.map(tone => tone.semitones), 12];
        const steps = scale.tones.map((_, index) => semitones[index + 1] - semitones[index]);
        return [`SCALE ${args[0]} ${args[1]} ${pitches.join(' ')} steps=${steps.join(',')}`];
      }
      case 'CHORD': case 'VOICE': {
        const input = command === 'VOICE' ? parseNote(args[0]) : null, root = input?.pitch ?? parsePitch(args[0]);
        const chord = named(args[1], 'QUALITY', CHORDS);
        const inversion = args.length === 3 ? boundedInteger(args[2], 'INVERSION', 0, chord.tones.length - 1) : 0;
        const pitches = build(root, chord.tones), ordered = pitches.slice(inversion).concat(pitches.slice(0, inversion));
        const symbol = chord.symbol(root, inversion === 0 ? null : ordered[0]);
        if (command === 'CHORD') return [`CHORD ${symbol} ${ordered.join(' ')}`];
        let value = input!.midi;
        const notes: Note[] = [];
        for (const [index, pitch] of ordered.entries()) {
          if (index > 0 || inversion > 0) value += modulo(pitch.pitchClass - value, 12) || 12;
          const note = makeNote(pitch, value);
          if (!note.valid) fail('OUT OF RANGE');
          notes.push(note);
        }
        return [`VOICE ${symbol} ${notes.join(' ')} midi=${notes.map(note => note.midi).join(',')}`];
      }
      case 'IDENTIFY': case 'MELODY': {
        const notes = args.map(parseNote);
        return [command === 'IDENTIFY' ? identify(notes) : melody(notes, args)];
      }
      case 'CIRCLE': {
        const mode = named(args[0], 'MODE', MODES);
        const pitches = Array.from({ length: 15 }, (_, index) => fifthPitch(index - 7 - mode.offset));
        return [`CIRCLE ${args[0]} ${pitches.join(' ')}`];
      }
      case 'FINDKEY': {
        const pitches = args.map(parsePitch), keys: Key[] = [];
        for (let fifths = -7; fifths <= 7; fifths++) {
          for (const mode of MODES.slice(0, 2)) {
            const key = new Key(fifthPitch(fifths - mode.offset), mode);
            if (pitches.every(pitch => key.scale.some(candidate => candidate.equals(pitch)))) keys.push(key);
          }
        }
        return [`FINDKEY ${keys.length}${keys.length === 0 ? '' : ' ' + keys.join(', ')}`];
      }
      case 'SPELL': {
        const value = boundedInteger(args[0], 'NUMBER', 0, 127), key = parseKey(args, 1);
        const pitch = key.scale.find(item => item.pitchClass === modulo(value, 12)) ?? spelling(value, key.fifths < 0).pitch;
        const note = makeNote(pitch, value);
        if (!note.valid) fail('OUT OF RANGE');
        return [`SPELL ${value} ${key} ${note} ${key.label(pitch)}`];
      }
      case 'KEYSIG': case 'RELATIVE': case 'DIATONIC': case 'PROGRESSION': case 'ANALYZE': case 'DEGREE': case 'KEYDIST':
        return executeKey(command, args);
    }
  }
}

const lines = readFileSync(0, 'utf8').split(/\r?\n/), count = Number(lines[0]);
const calculator = new Calculator(), output: string[] = [];
for (let index = 1; index <= count; index++) {
  try { output.push(...calculator.execute(lines[index])); }
  catch (problem) {
    if (!(problem instanceof CommandError)) throw problem;
    output.push(`ERROR ${problem.message}`);
  }
}
process.stdout.write(output.join('\n') + '\n');
