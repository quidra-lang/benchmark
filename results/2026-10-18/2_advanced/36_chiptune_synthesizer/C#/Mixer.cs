using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class Mixer {
    public readonly int[] samples;
    public readonly int[][] lanes;
    public readonly int[] mute;
    public readonly int gain;
    public int size, clipped;
    public Mixer(int capacity, int channels, int gain, int[] mute) {
        samples = new int[capacity];
        lanes = Enumerable.Range(0, channels)
                    .Select(
                        _ => new int[capacity])
                    .ToArray();
        this.gain = gain;
        this.mute = mute;
    }
    public static int Channel(Program.Channel channel) {
        if (!channel.sounding)
            return 0;
        int value =
            (2 * Instruments.Wave(channel.instrument, channel.mode, channel.phase, channel.shift) - 15) *
            channel.amplitude;
        channel.phase += channel.increment;
        if (channel.phase >= 65536) {
            channel.phase -= 65536;
            if (channel.instrument.wave.Equals("NOISE"))
                channel.shift = Instruments.Clock(channel.shift, channel.mode);
        }
        return value;
    }
    public void Generate(Program.Channel[] channels, int count) {
        for (int i = 0; i < count; i++) {
            int total = 0;
            for (int c = 0; c < channels.Length; c++) {
                int value = Channel(channels[c]);
                lanes[c][size] = value;
                if (mute[c] == 0)
                    total += value;
            }
            long value = 128 + Instruments.Floor((long)gain * total, 4096);
            if (value < 0 || value > 255)
                clipped++;
            samples[size++] = (int)Instruments.Clamp(value, 0, 255);
        }
    }
    public void Fade(int length) {
        int count = Math.Min(length, size);
        for (int i = size - count; i < size; i++)
            samples[i] = 128 + (int)Instruments.Floor((long)(samples[i] - 128) * (size - 1 - i), count);
    }
}
