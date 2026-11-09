final class Instruments {
    static final int[] TONES = {26163, 27718, 29366, 31113, 32963, 34923,
                                36999, 39200, 41530, 44000, 46616, 49388};
    static final int[] SINE = {0,   24,  49,  74,  97,  120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
                               255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97,  74,  49,  24};
    static long floor(long value, long divisor) {
        return Math.floorDiv(value, divisor);
    }
    static long clamp(long value, long low, long high) {
        return Math.min(Math.max(value, low), high);
    }
    static long frequency(int note) {
        int octave = note / 12, pitch = note % 12;
        return octave >= 4 ? (long)TONES[pitch] * (1L << (octave - 4)) : TONES[pitch] / (1L << (4 - octave));
    }
    static long transpose(long frequency, int semitones) {
        return frequency * TONES[semitones % 12] / TONES[0] * (1L << (semitones / 12));
    }
    static int oscillate(int position, int depth, int divisor) {
        int value = SINE[position % 32] * depth / divisor;
        return position < 32 ? value : -value;
    }
    static int envelope(SongParser.Instrument instrument, int age, boolean off, int releaseAge,
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
    static int wave(SongParser.Instrument instrument, int mode, int phase, int shift) {
        return switch (instrument.wave) {
            case "PULSE" -> phase / 8192 < new int[] {1, 2, 4, 6}[mode] ? 15 : 0;
            case "TRIANGLE" -> phase / 2048 < 16 ? 15 - phase / 2048 : phase / 2048 - 16;
            case "SAW" -> phase / 4096;
            case "TABLE" -> instrument.table[phase / 2048];
            default -> shift % 2 == 0 ? 15 : 0;
        };
    }
    static int clock(int shift, int mode) {
        int bit = (shift & 1) ^ ((shift >> (mode == 0 ? 1 : 6)) & 1);
        return shift / 2 + bit * 16384;
    }
}
