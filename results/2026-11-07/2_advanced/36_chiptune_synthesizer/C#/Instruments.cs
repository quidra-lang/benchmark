using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Instruments {
    public static readonly int[] TONES = { 26163, 27718, 29366, 31113, 32963, 34923,
                                           36999, 39200, 41530, 44000, 46616, 49388 };
    public static readonly int[] SINE = { 0,   24,  49,  74,  97,  120, 141, 161, 180, 197, 212,
                                          224, 235, 244, 250, 253, 255, 253, 250, 244, 235, 224,
                                          212, 197, 180, 161, 141, 120, 97,  74,  49,  24 };
    public static long Floor(long value, long divisor) {
        return value / divisor - (value < 0 && value % divisor != 0 ? 1 : 0);
    }
    public static long Clamp(long value, long low, long high) {
        return Math.Min(Math.Max(value, low), high);
    }
    public static long Frequency(int note) {
        int octave = note / 12, pitch = note % 12;
        return octave >= 4 ? (long)TONES[pitch] * (1L << (octave - 4)) : TONES[pitch] / (1L << (4 - octave));
    }
    public static long Transpose(long frequency, int semitones) {
        return frequency * TONES[semitones % 12] / TONES[0] * (1L << (semitones / 12));
    }
    public static int Oscillate(int position, int depth, int divisor) {
        int value = SINE[position % 32] * depth / divisor;
        return position < 32 ? value : -value;
    }
    public static int Envelope(SongParser.Instrument instrument, int age, bool off, int releaseAge,
                               int releaseValue) {
        if (off) {
            int w = age - releaseAge;
            return w < instrument.release ? releaseValue * (instrument.release - 1 - w) / instrument.release
                                          : 0;
        }
        if (age < instrument.attack)
            return 15 * (age + 1) / instrument.attack;
        if (age < instrument.attack + instrument.decay)
            return 15 - (15 - instrument.sustain) * (age - instrument.attack + 1) / instrument.decay;
        return instrument.sustain;
    }
    public static int Wave(SongParser.Instrument instrument, int mode, int phase, int shift) {
        return (instrument.wave) switch {
            "PULSE" => phase / 8192 < new int[] { 1, 2, 4, 6 }[mode] ? 15 : 0,
            "TRIANGLE" => phase / 2048 < 16 ? 15 - phase / 2048 : phase / 2048 - 16,
            "SAW" => phase / 4096,
            "TABLE" => instrument.table[phase / 2048],
            _ => shift % 2 == 0 ? 15 : 0,
        };
    }
    public static int Clock(int shift, int mode) {
        int bit = (shift & 1) ^ ((shift >> (mode == 0 ? 1 : 6)) & 1);
        return shift / 2 + bit * 16384;
    }
}
