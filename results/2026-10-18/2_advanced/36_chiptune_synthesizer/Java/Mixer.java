final class Mixer {
    final int[] samples;
    final int[][] lanes;
    final int[] mute;
    final int gain;
    int size, clipped;
    Mixer(int capacity, int channels, int gain, int[] mute) {
        samples = new int[capacity];
        lanes = new int[channels][capacity];
        this.gain = gain;
        this.mute = mute;
    }
    static int channel(Main.Channel channel) {
        if (!channel.sounding)
            return 0;
        int value =
            (2 * Instruments.wave(channel.instrument, channel.mode, channel.phase, channel.shift) - 15) *
            channel.amplitude;
        channel.phase += channel.increment;
        if (channel.phase >= 65536) {
            channel.phase -= 65536;
            if (channel.instrument.wave.equals("NOISE"))
                channel.shift = Instruments.clock(channel.shift, channel.mode);
        }
        return value;
    }
    void generate(Main.Channel[] channels, int count) {
        for (int i = 0; i < count; i++) {
            int total = 0;
            for (int c = 0; c < channels.length; c++) {
                int value = channel(channels[c]);
                lanes[c][size] = value;
                if (mute[c] == 0)
                    total += value;
            }
            long value = 128 + Instruments.floor((long)gain * total, 4096);
            if (value < 0 || value > 255)
                clipped++;
            samples[size++] = (int)Instruments.clamp(value, 0, 255);
        }
    }
    void fade(int length) {
        int count = Math.min(length, size);
        for (int i = size - count; i < size; i++)
            samples[i] = 128 + (int)Instruments.floor((long)(samples[i] - 128) * (size - 1 - i), count);
    }
}
