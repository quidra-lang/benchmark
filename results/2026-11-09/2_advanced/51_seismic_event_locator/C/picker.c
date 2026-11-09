#include "seismic.h"
static I absolute(I value) {
    return value < 0 ? -value : value;
}
static void push(Picks *picks, Pick value) {
    if (picks->count == picks->capacity) {
        const int capacity = picks->capacity ? picks->capacity * 2 : 32;
        Pick *data = allocate(capacity, sizeof(Pick));
        if (picks->count)
            memcpy(data, picks->data, picks->count * sizeof(Pick));
        picks->data = data;
        picks->capacity = capacity;
    }
    picks->data[picks->count++] = value;
}
static void finish(Station *s, int station, const Params *p, Picks *picks, const I *d, const I *energy,
                   int begin, int end, double maximum) {
    ++s->triggers;
    const int duration = end - begin;
    if (duration < p->min_duration) {
        ++s->short_triggers;
        return;
    }
    int k = begin;
    while (k - 1 >= begin - p->sw + 1 && energy[k - 1] >= p->noise)
        --k;
    I amplitude = 0;
    bool clipped = false;
    for (int j = k; j < s->count && j < k + p->aw; ++j) {
        I value = absolute(d[j]);
        if (value > amplitude)
            amplitude = value;
        if (absolute(s->samples[j]) >= p->clip)
            clipped = true;
    }
    push(picks, (Pick){.station = station,
                       .sample = s->start + k,
                       .duration = duration,
                       .amplitude = amplitude,
                       .ratio = maximum,
                       .clipped = clipped,
                       .state = UNASSOCIATED});
}
void detect_station(Station *s, int station, const Params *p, Picks *picks) {
    const int count = s->count;
    I sum = 0;
    for (int i = 0; i < count; ++i)
        sum += s->samples[i];
    s->mean = floor_div(sum, count);
    I *d = allocate(count, sizeof(I));
    I *energy = allocate(count, sizeof(I));
    I *prefix = allocate(count + 1, sizeof(I));
    double *amplitudes = allocate(count, sizeof(double));
    for (int i = 0; i < count; ++i) {
        d[i] = s->samples[i] - s->mean;
        energy[i] = d[i] * d[i];
        prefix[i + 1] = prefix[i] + energy[i];
        amplitudes[i] = (double)absolute(d[i]);
        if (absolute(d[i]) > s->peak)
            s->peak = absolute(d[i]);
        s->clipped += absolute(s->samples[i]) >= p->clip;
    }
    s->noise = median(amplitudes, count);
    bool on = false;
    int beginning = 0;
    double maximum = 0;
    for (int i = (int)(p->sw + p->lw - 1); i < count; ++i) {
        I sta = prefix[i + 1] - prefix[i - p->sw + 1],
          lta = prefix[i - p->sw + 1] - prefix[i - p->sw - p->lw + 1];
        if (!on) {
            if (sta * p->lw * p->on_q >= p->on_p * lta * p->sw) {
                on = true;
                beginning = i;
                maximum = (double)(sta * p->lw) / (double)(lta * p->sw);
            }
        } else if (sta * p->lw * p->off_q < p->off_p * lta * p->sw) {
            finish(s, station, p, picks, d, energy, beginning, i, maximum);
            on = false;
        } else {
            double ratio = (double)(sta * p->lw) / (double)(lta * p->sw);
            if (ratio > maximum)
                maximum = ratio;
        }
    }
    if (on)
        finish(s, station, p, picks, d, energy, beginning, count, maximum);
}
