'use strict';

const { waveform, clockNoise } = require('./instruments');

function generate(channels, count, gain, mute, samples, lanes = null) {
    let clipped = 0;
    for (let i = 0; i < count; i++) {
        let mixed = 0;
        for (let k = 0; k < channels.length; k++) {
            const channel = channels[k];
            let value = 0;
            if (channel.sounding) {
                value = (2 * waveform(channel) - 15) * channel.amplitude;
                channel.phase += channel.increment;
                if (channel.phase >= 65536) {
                    channel.phase -= 65536;
                    if (channel.instrument.wave === 'NOISE') channel.register = clockNoise(channel.register, channel.mode);
                }
            }
            if (lanes !== null) lanes[k].push(value);
            if (mute[k] === 0) mixed += value;
        }
        let sample = 128 + Math.floor(gain * mixed / 4096);
        if (sample < 0 || sample > 255) { clipped++; sample = Math.min(255, Math.max(0, sample)); }
        samples.push(sample);
    }
    return clipped;
}

function fadeOut(samples, length) {
    const count = Math.min(length, samples.length);
    for (let i = samples.length - count; i < samples.length; i++)
        samples[i] = 128 + Math.floor((samples[i] - 128) * (samples.length - 1 - i) / count);
}

module.exports = { generate, fadeOut };
