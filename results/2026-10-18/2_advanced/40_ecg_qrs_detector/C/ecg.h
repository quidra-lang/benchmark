#ifndef ECG_H
#define ECG_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
typedef int64_t Integer;
typedef struct {
    Integer *data;
    int count, capacity;
} Values;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    Integer refractory_ms, twave_ms, searchback_percent, premature_percent, qrs_width_ms, match_ms, pause_ms,
        brady_ms, tachy_ms, excerpt_ms, segment_ms, strip_start_ms, strip_ms, strip_rows, chart_rows,
        poincare_size;
} Params;
typedef struct {
    int sample;
    char label;
    int beat;
} Annotation;
typedef struct {
    Integer ecg[12000];
    int count;
    Annotation annotations[300];
    int annotation_count;
    Params params;
} Input;
typedef struct {
    Integer lowpass[12000], bandpass[12000], derivative[12000], squared[12000], integrated[12000];
    int count;
} Signals;
typedef enum { QRS, SEARCHBACK, TWAVE, REFRACTORY, NOISE, PENDING } PeakClass;
typedef struct {
    int time, r;
    Integer integrated, filtered, slope, thr_i, thr_f;
    PeakClass kind;
} Peak;
typedef struct {
    Peak data[600];
    int count;
} Peaks;
typedef struct {
    Integer spki, npki, spkf, npkf;
} Levels;
typedef struct {
    Integer bin;
    int count;
} Bin;
typedef struct {
    Bin *data;
    int count;
} Histogram;
typedef struct {
    int first, last;
} Range;
typedef struct {
    Range *data;
    int count;
} Ranges;
void *resize(void *memory, size_t size);
char *text(const char *value);
char *format(const char *pattern, ...);
void value_push(Values *values, Integer value);
void line_push(Lines *lines, char *line);
void lines_extend(Lines *target, const Lines *source);
void lines_free(Lines *lines);
Input *read_input(void);
void write_lines(const char *name, const Lines *lines);
Signals *filter(const Input *input);
Peaks find_peaks(const Signals *signals);
Integer qrs_width(const Signals *signals, int r);
Levels initial_levels(const Signals *signals);
Integer floor_div(Integer a, Integer b);
Integer rdiv(Integer a, Integer b);
char *decimal2(Integer value);
char *decimal4(Integer value);
char *reduced(Integer a, Integer b);
char *ratio(Integer a, Integer b);
char *optional_number(bool exists, Integer value);
Integer integer_sqrt(Integer value);
Integer root(Integer numerator, Integer denominator);
Integer mean_scaled(const Values *values);
Integer mean_hr(const Values *intervals);
Integer sample_deviation(const Values *values, Integer multiplier);
Integer rms(const Values *values);
Histogram histogram(const Values *intervals);
Ranges ranges(const bool *flags, int count);
#endif
