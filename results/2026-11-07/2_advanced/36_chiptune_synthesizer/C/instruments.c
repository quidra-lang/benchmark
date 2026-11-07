#include "synthesizer.h"
Integer floor_div(Integer a, Integer b) {
    return a / b - (a % b < 0 ? 1 : 0);
}
Integer modulo(Integer a, Integer b) {
    return a - b * floor_div(a, b);
}
Integer clamp(Integer value, Integer lo, Integer hi) {
    return value < lo ? lo : value > hi ? hi : value;
}
const char *wave_name(Wave wave) {
    const char *names[5] = {"PULSE", "TRIANGLE", "SAW", "NOISE", "TABLE"};
    return names[wave];
}
static const Integer frequencies[12] = {26163, 27718, 29366, 31113, 32963, 34923,
                                        36999, 39200, 41530, 44000, 46616, 49388};
Integer frequency(int note) {
    int octave = note / 12;
    return octave >= 4 ? frequencies[note % 12] * (INT64_C(1) << (octave - 4))
                       : floor_div(frequencies[note % 12], INT64_C(1) << (4 - octave));
}
Integer transpose(Integer f, int semitones) {
    return floor_div(f * frequencies[semitones % 12], frequencies[0]) * (INT64_C(1) << (semitones / 12));
}
Integer oscillation(Integer position, Integer depth, Integer divisor) {
    const Integer sine[32] = {0,   24,  49,  74,  97,  120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
                              255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97,  74,  49,  24};
    Integer q = floor_div(sine[position % 32] * depth, divisor);
    return position < 32 ? q : -q;
}
Integer envelope(const Instrument *i, Integer age, bool released, Integer release_age,
                 Integer release_value) {
    if (released) {
        Integer w = age - release_age;
        return w < i->release ? floor_div(release_value * (i->release - 1 - w), i->release) : 0;
    }
    if (age < i->attack)
        return floor_div(15 * (age + 1), i->attack);
    if (age < i->attack + i->decay)
        return 15 - floor_div((15 - i->sustain) * (age - i->attack + 1), i->decay);
    return i->sustain;
}
Integer waveform(const Instrument *i, int mode, Integer phase, Integer noise) {
    if (i->wave == PULSE) {
        const int duty[4] = {1, 2, 4, 6};
        return phase / 8192 < duty[mode] ? 15 : 0;
    }
    if (i->wave == TRIANGLE) {
        Integer j = phase / 2048;
        return j < 16 ? 15 - j : j - 16;
    }
    if (i->wave == SAW)
        return phase / 4096;
    if (i->wave == TABLE)
        return i->table[phase / 2048];
    return noise % 2 == 0 ? 15 : 0;
}
void clock_noise(Integer *noise, int mode) {
    Integer bit = (*noise & 1) ^ ((*noise >> (mode == 0 ? 1 : 6)) & 1);
    *noise = *noise / 2 + bit * 16384;
}
