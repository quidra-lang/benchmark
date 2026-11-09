#ifndef DSP_H
#define DSP_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

typedef struct {int64_t *values;int count;} Samples;
typedef struct Signal {char name[17],origin[64];int rate;Samples samples;struct Signal *ingredients[8];int ingredient_count;} Signal;
typedef struct {char **values;int count,capacity;} Lines;
int64_t floor_div(int64_t numerator,int64_t denominator);
int64_t rdiv(int64_t numerator,int64_t denominator);
int64_t sample_abs(int64_t value);
int64_t saturate(int64_t value,int64_t *clips);
Samples new_samples(int count);
Samples copy_samples(Samples source);
int64_t peak(Samples samples);
int64_t sample_sum(Samples samples);
int read_signals(Signal **signals);
Samples test_signal(const char *command,int count,int pos,int64_t amp,int64_t seed);
void format_signal(const Signal *signal,Lines *lines);
Samples gain(Samples x,int64_t num,int64_t den,int64_t *clips);
Samples mix(Signal *const *signals,const int64_t *weights,int count,int64_t den,int64_t *clips);
Samples delay(Samples x,int count);
Samples echo(Samples x,int lag,int64_t num,int64_t den,int tail,int64_t *clips);
Samples resample(Samples x,int old_rate,int new_rate);
Samples fade(Samples x,int fade_in,int fade_out);
Samples fir(Samples x,int64_t divisor,const int64_t *taps,int tap_count,int64_t *clips);
Samples biquad(Samples x,const int64_t *coefficients,int count,int64_t *clips);
Samples moving_average(Samples x,int width);
Samples dc_block(Samples x,int64_t num,int64_t den,int64_t *clips);
Samples envelope(Samples x,int64_t attack,int64_t release);
Samples normalize(Samples x,int64_t target,int64_t *source_peak);
Samples gate(Samples x,int64_t threshold,int hold,int64_t *muted);
Samples compress_signal(Samples x,int64_t threshold,int64_t ratio_num,int64_t ratio_den,int64_t attack,int64_t release,int64_t *min_gain,int64_t *reduced);
int64_t energy(Samples x);
int64_t integer_sqrt(int64_t value);
int64_t rms(Samples x);
int64_t zero_crossings(Samples x);
int64_t clipped(Samples x);
const char *crest_fraction(Samples x);
int pitch_lag(Samples x,int low,int high);
const char *decimal_two(int64_t hundredths);
const char *frequency(int rate,int lag);
void add_line(Lines *lines,const char *format,...);
void append_lines(Lines *to,const Lines *from);

#endif
