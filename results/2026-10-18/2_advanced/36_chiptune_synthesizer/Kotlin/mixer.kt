class Mixer(capacity: Int, channelCount: Int, val gain: Int, val mute: IntArray) {
    val samples = IntArray(capacity);
    val lanes = Array(channelCount) {
        IntArray(capacity)
    };
    var size = 0;
    var clipped = 0
    companion object {
        fun channel(channel: Channel): Int {
            if (!channel.sounding) return 0;
            val instrument = channel.instrument!!;
            val value = (2 * Instruments.wave(instrument,channel.mode,channel.phase,channel.shift) - 15) * channel.amplitude;
            channel.phase += channel.increment;
            if (channel.phase >= 65536) {
                channel.phase -= 65536;
                if (instrument.wave == "NOISE") channel.shift = Instruments.clock(channel.shift,channel.mode)
            };
            return value
        }
    }
    fun generate(channels: Array<Channel>, count: Int) {
        repeat(count) {
            var total = 0;
            for (c in channels.indices) {
                val value = channel(channels[c]);
                lanes[c][size] = value;
                if (mute[c] == 0) total += value
            };
            val value = 128 + Instruments.floor(gain.toLong() * total,4096);
            if (value < 0 || value > 255) clipped++;
            samples[size++] = Instruments.clamp(value,0,255).toInt()
        }
    }
    fun fade(length: Int) {
        val count = minOf(length,size);
        for (i in size - count until size) samples[i] = 128 + Instruments.floor((samples[i] - 128).toLong() * (size - 1 - i),count.toLong()).toInt()
    }
}
