'use strict';

const T = [26163, 27718, 29366, 31113, 32963, 34923, 36999, 39200, 41530, 44000, 46616, 49388];
const S = [0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253, 255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24];

function frequency(note) {
    const octave = Math.floor(note / 12);
    return octave >= 4 ? T[note % 12] * 2 ** (octave - 4) : Math.floor(T[note % 12] / 2 ** (4 - octave));
}

const transpose = (value, semitones) => Math.floor(value * T[semitones % 12] / T[0]) * 2 ** Math.floor(semitones / 12);

function oscillation(position, depth, divisor) {
    const value = Math.floor(S[position % 32] * depth / divisor);
    return position < 32 ? value : -value;
}

function envelope(channel) {
    const [attack, decay, sustain, release] = channel.instrument.envelope;
    const age = channel.age;
    if (channel.keyedOff) {
        const elapsed = age - channel.offAge;
        return elapsed < release ? Math.floor(channel.offEnvelope * (release - 1 - elapsed) / release) : 0;
    }
    if (age < attack) return Math.floor(15 * (age + 1) / attack);
    if (age < attack + decay) return 15 - Math.floor((15 - sustain) * (age - attack + 1) / decay);
    return sustain;
}

function waveform(channel) {
    const { instrument, phase, mode, register } = channel;
    if (instrument.wave === 'PULSE') return Math.floor(phase / 8192) < [1, 2, 4, 6][mode] ? 15 : 0;
    if (instrument.wave === 'TRIANGLE') {
        const step = Math.floor(phase / 2048);
        return step < 16 ? 15 - step : step - 16;
    }
    if (instrument.wave === 'SAW') return Math.floor(phase / 4096);
    if (instrument.wave === 'TABLE') return instrument.table[Math.floor(phase / 2048)];
    return register % 2 === 0 ? 15 : 0;
}

function clockNoise(register, mode) {
    const bit = (register & 1) ^ ((register >> (mode === 0 ? 1 : 6)) & 1);
    return Math.floor(register / 2) + bit * 16384;
}

module.exports = { frequency, transpose, oscillation, envelope, waveform, clockNoise };
