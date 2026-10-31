#ifndef SYNTHESIZER_H
#define SYNTHESIZER_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <inttypes.h>
typedef int64_t Integer;
typedef struct {
    char **data;
    size_t len, cap;
} Lines;
typedef struct {
    char *data;
    size_t len, cap;
} Text;
void *allocate(size_t count, size_t size);
void grow(void **data, size_t *cap, size_t need, size_t size);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void line_add(Lines *lines, const char *pattern, ...);
void extend(Lines *out, Lines lines);
Lines read_lines(const char *path);
Lines words(const char *text);
void write_lines(const char *name, Lines lines);
char *decimal(Integer value);
char *hexadecimal(Integer value, int width);
char *aligned(Integer value, int width);
Integer floor_div(Integer a, Integer b);
Integer modulo(Integer a, Integer b);
Integer clamp(Integer value, Integer lo, Integer hi);
int note_number(const char *name);
char *note_name(int note);
typedef struct {
    char text[4], name[3];
    int argument, x, y;
} Effect;
typedef struct {
    int note, instrument, volume;
    Effect effect;
} Cell;
typedef Cell Row[4];
typedef struct {
    Row rows[64];
} Pattern;
typedef enum { PULSE, TRIANGLE, SAW, NOISE, TABLE } Wave;
typedef struct {
    bool defined;
    int number;
    char *name;
    Wave wave;
    int mode, table[32], attack, decay, sustain, release;
    bool vibrato;
    int delay, speed, depth, arpeggio[16], arpeggio_count, sweep;
} Instrument;
typedef struct {
    char *title;
    int rate, speed, tempo, gain;
    Instrument instruments[256];
    Pattern *patterns[256];
    int order[64], order_count;
} Song;
typedef struct {
    int maximum, loops, fade;
    bool muted[4];
    int start, length, width, height, scope, roll_start, roll_rows, preview_note, preview_ticks,
        preview_release;
    bool traces[64][64];
} Params;
Song *read_song(void);
Params read_params(void);
bool cell_empty(const Cell *cell);
const char *wave_name(Wave wave);
Integer frequency(int note);
Integer transpose(Integer frequency, int semitones);
Integer oscillation(Integer position, Integer depth, Integer divisor);
Integer envelope(const Instrument *i, Integer age, bool released, Integer release_age, Integer release_value);
Integer waveform(const Instrument *i, int mode, Integer phase, Integer noise);
void clock_noise(Integer *noise, int mode);
typedef struct {
    int instrument, note;
    Integer base, target, portamento, slide, detune, vibrato_speed, vibrato_depth, vibrato_position,
        tremolo_speed, tremolo_depth, tremolo_position, volume;
    int mode;
    Integer phase, noise, age;
    bool released;
    Integer release_age, release_value, env, output_frequency, output_volume, amplitude, increment;
    Effect effect;
    bool sounding;
    int record;
} Channel;
Channel channel_create(void);
typedef struct {
    int position, row;
    bool stop;
} NextRow;
int samples_per_tick(const Song *song, int tempo);
NextRow next_row(const Song *song, int position, int row);
void reachable(const Song *song, bool result[64][64]);
typedef struct {
    int *samples;
    Integer *lanes[4];
    size_t count;
    Integer clipped;
} Audio;
Audio audio_create(size_t maximum);
void generate(const Song *song, Channel channels[4], int count, const bool muted[4], Audio *audio);
void fade(Audio *audio, int count);
Integer adler32(const int *samples, size_t count);
Integer integer_sqrt(Integer value);
typedef struct {
    Integer peak, rms, crossings;
    int minimum, maximum;
} SampleStats;
SampleStats sample_stats(const int *samples, size_t count);
Lines sample_dump(const int *samples, size_t count);
#endif
