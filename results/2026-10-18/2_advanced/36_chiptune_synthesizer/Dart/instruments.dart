part of 'main.dart';

const noteTable = [
  26163,
  27718,
  29366,
  31113,
  32963,
  34923,
  36999,
  39200,
  41530,
  44000,
  46616,
  49388,
];
const sineTable = [
  0,
  24,
  49,
  74,
  97,
  120,
  141,
  161,
  180,
  197,
  212,
  224,
  235,
  244,
  250,
  253,
  255,
  253,
  250,
  244,
  235,
  224,
  212,
  197,
  180,
  161,
  141,
  120,
  97,
  74,
  49,
  24,
];
const pulseWidths = [1, 2, 4, 6];
int floorDiv(int a, int b) => a ~/ b - (a < 0 && a.remainder(b) != 0 ? 1 : 0);
int clamp(int v, int lo, int hi) => math.min(math.max(v, lo), hi);
int noteFrequency(int n) => n ~/ 12 >= 4
    ? noteTable[n % 12] << (n ~/ 12 - 4)
    : noteTable[n % 12] >> (4 - n ~/ 12);
int transpose(int frequency, int semitones) =>
    (frequency * noteTable[semitones % 12] ~/ noteTable[0]) <<
    (semitones ~/ 12);
int oscillation(int position, int depth, int divisor) {
  final value = sineTable[position % 32] * depth ~/ divisor;
  return position < 32 ? value : -value;
}

int envelopeValue(
  Instrument ins,
  int age,
  bool released,
  int releaseAge,
  int releaseLevel,
) {
  if (released) {
    final elapsed = age - releaseAge;
    return elapsed < ins.release
        ? floorDiv(releaseLevel * (ins.release - 1 - elapsed), ins.release)
        : 0;
  }
  if (age < ins.attack) return 15 * (age + 1) ~/ ins.attack;
  if (age < ins.attack + ins.decay)
    return 15 - (15 - ins.sustain) * (age - ins.attack + 1) ~/ ins.decay;
  return ins.sustain;
}

int waveValue(Instrument ins, int mode, int phase, int register) {
  switch (ins.wave) {
    case 'PULSE':
      return phase ~/ 8192 < pulseWidths[mode] ? 15 : 0;
    case 'TRIANGLE':
      final j = phase ~/ 2048;
      return j < 16 ? 15 - j : j - 16;
    case 'SAW':
      return phase ~/ 4096;
    case 'TABLE':
      return ins.table[phase ~/ 2048];
    default:
      return register % 2 == 0 ? 15 : 0;
  }
}

int clockRegister(int register, int mode) =>
    register ~/ 2 +
    ((register ^ (register >> (mode == 0 ? 1 : 6))) & 1) * 16384;
