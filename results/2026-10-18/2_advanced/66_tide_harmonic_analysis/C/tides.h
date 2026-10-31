#ifndef TIDES_H
#define TIDES_H
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include <sys/stat.h>
typedef long long I;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    bool present, numeric;
    I milli;
} Observation;
typedef struct {
    char code[4], name[31];
    Observation observations[10001];
    int first, last, rows;
} Station;
typedef struct {
    char name[5];
    double speed;
} Constituent;
typedef struct {
    int epoch_day, flat_run, spike_window, spike_count, top, surge_hours, start, length, grid, lag,
        plot_hours, plot_top, plot_bottom, plot_step;
    double spike_factor, spike_minimum, rayleigh, snr, surge, min_range;
    char reference[4], plot[4];
} Params;
typedef struct {
    Params params;
    Station stations[6];
    int station_count;
    Constituent constituents[30];
    int constituent_count;
} Input;
typedef struct {
    int first, last;
    I milli;
} Flat;
typedef struct {
    Flat *data;
    int count;
} Flats;
typedef struct {
    int time;
    double residual, median, mad, limit;
} Spike;
typedef struct {
    Spike *data;
    int count, tested;
} Spikes;
typedef struct {
    int first, last, cause;
} Gap;
typedef struct {
    Gap *data;
    int count;
} Gaps;
typedef struct {
    int time;
    double value;
} Sample;
typedef struct {
    int count, size;
    double speeds[30], coefficients[61], amplitudes[30], phases[30], inverse[61][61];
} Model;
typedef struct {
    bool high;
    double mu, height;
    int minute, label;
} Extremum;
typedef struct {
    Extremum *data;
    int count;
} Extrema;
void *allocate(size_t count, size_t size);
char *format(const char *pattern, ...), *joined(const char *first, const char *second);
void line(Lines *lines, const char *pattern, ...);
int civil_day(int year, int month, int day), hour(const char *value, int epoch_day);
I parse_minutes(const char *value);
char *datetime(int minutes, int epoch_day), *date(int day, int epoch_day);
Input *read_inputs(void);
double median(double *values, int count);
Flats flat_runs(const Observation *observations, int first, int last, int minimum);
Spikes spikes(const Sample *residuals, int count, const Params *params);
Gaps gaps(const int *reasons, int first, int last);
double angle(double speed, double time);
void regressors(const double *speeds, int count, double time, double *out);
Model *fit(const Sample *samples, int sample_count, const double *speeds, int count);
double prediction(const Model *model, double time);
Extrema extrema(const Model *model, int start, int length, int grid);
char *real(double value, int digits);
void save(const char *name, Lines lines);
Lines plot_lines(const double *heights, Lines cells, const char *axis);
#endif
