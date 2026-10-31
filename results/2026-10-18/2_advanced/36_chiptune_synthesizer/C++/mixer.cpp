#include "synthesizer.hpp"
void generate(const Song &song, std::array<Channel, 4> &channels, int count, const std::array<bool, 4> &muted,
              std::vector<int> &samples, std::array<std::vector<Integer>, 4> &lanes, Integer &clipped) {
    for (int i = 0; i < count; ++i) {
        Integer mixed = 0;
        for (int k = 0; k < 4; ++k) {
            Channel &channel = channels[k];
            Integer value = 0;
            if (channel.sounding) {
                const Instrument &instrument = song.instruments.at(channel.instrument);
                const Integer level = waveform(instrument, channel.mode, channel.phase, channel.noise);
                value = (2 * level - 15) * channel.amplitude;
                channel.phase += channel.increment;
                if (channel.phase >= 65536) {
                    channel.phase -= 65536;
                    if (instrument.wave == "NOISE")
                        clock_noise(channel.noise, channel.mode);
                }
            }
            lanes[k].push_back(value);
            if (!muted[k])
                mixed += value;
        }
        Integer sample = 128 + floor_div(song.gain * mixed, 4096);
        if (sample < 0 || sample > 255)
            ++clipped;
        samples.push_back(int(clamp(sample, 0, 255)));
    }
}
void fade(std::vector<int> &samples, int count) {
    const int n = samples.size(), m = std::min(count, n);
    for (int i = n - m; i < n; ++i)
        samples[i] = int(128 + floor_div(Integer(samples[i] - 128) * (n - 1 - i), m));
}
