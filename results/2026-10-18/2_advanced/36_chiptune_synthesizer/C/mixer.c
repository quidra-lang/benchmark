#include "synthesizer.h"
Audio audio_create(size_t maximum) {
    Audio out = {0};
    out.samples = allocate(maximum, sizeof *out.samples);
    for (int k = 0; k < 4; ++k)
        out.lanes[k] = allocate(maximum, sizeof *out.lanes[k]);
    return out;
}
void generate(const Song *song, Channel channels[4], int count, const bool muted[4], Audio *audio) {
    for (int i = 0; i < count; ++i) {
        Integer mixed = 0;
        for (int k = 0; k < 4; ++k) {
            Channel *c = &channels[k];
            Integer value = 0;
            if (c->sounding) {
                const Instrument *instrument = &song->instruments[c->instrument];
                Integer level = waveform(instrument, c->mode, c->phase, c->noise);
                value = (2 * level - 15) * c->amplitude;
                c->phase += c->increment;
                if (c->phase >= 65536) {
                    c->phase -= 65536;
                    if (instrument->wave == NOISE)
                        clock_noise(&c->noise, c->mode);
                }
            }
            audio->lanes[k][audio->count] = value;
            if (!muted[k])
                mixed += value;
        }
        Integer sample = 128 + floor_div(song->gain * mixed, 4096);
        if (sample < 0 || sample > 255)
            ++audio->clipped;
        audio->samples[audio->count++] = (int)clamp(sample, 0, 255);
    }
}
void fade(Audio *audio, int count) {
    int n = (int)audio->count, m = count < n ? count : n;
    for (int i = n - m; i < n; ++i)
        audio->samples[i] = (int)(128 + floor_div((Integer)(audio->samples[i] - 128) * (n - 1 - i), m));
}
