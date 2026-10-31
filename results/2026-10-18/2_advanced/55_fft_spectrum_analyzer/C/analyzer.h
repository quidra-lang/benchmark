#ifndef ANALYZER_H
#define ANALYZER_H
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdarg.h>
#include <string.h>
#include <math.h>
#include <complex.h>
#include <sys/stat.h>
typedef int64_t Int;
typedef double complex Complex;
typedef struct {
    double *data;
    int count;
} Values;
typedef struct {
    Complex *data;
    int count;
} Complexes;
typedef struct {
    int *data;
    int count;
} Ids;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    int main_length, peak_count, search, welch_length, frame_length, hop, shade, pitch_low, pitch_high,
        band_low, band_high, notch_frequency, notch_width, envelope_low, envelope_high, zoom_low, zoom_high,
        zoom_points, max_lag, third_low, third_high, block_length;
    const char *main_window;
    const char *welch_window;
    const char *frame_window;
    double peak_threshold, fundamental, onset_factor;
    Values fir;
    Ids bands;
} Params;
typedef struct {
    int fs;
    Values signal[2];
    Params params;
} Input;
typedef struct {
    double s1, s2, coherent, enbw, enbw_hz, scalloping;
} WindowFigures;
typedef struct {
    Values windowed, amplitude;
    Complexes transformed;
    WindowFigures figures;
} Spectrum;
typedef struct {
    double position, value;
} Interpolation;
typedef struct {
    Values psd, coherence;
    Complexes transfer;
    int segments;
    double packing_error;
} Welch;
typedef struct {
    Values *magnitudes;
    int count;
    double packing_error;
} Frames;
void *allocate(size_t count, size_t size);
void release_one(void *value);
void release_all(void);
char *format(const char *pattern, ...);
Values values_new(int count);
Complexes complex_new(int count);
Complexes complex_values(Values values, int length);
Input load(void);
int pow2(int value);
bool power_of_two(int value);
Complex rot(double angle);
double norm(Complex value);
Complexes radix2(Complexes values, bool inverse);
Complexes dft(Complexes values);
Complexes idft(Complexes values);
Complexes packed_real(Values values);
Values convolution(Values a, Values b);
Complexes chirp_z(Values windowed, int fs, int low, int high, int points);
Values window(const char *name, int length);
WindowFigures window_figures(Values values, int fs);
Spectrum spectrum(Values signal, int length, const char *name, int fs);
void release_spectrum(Spectrum value);
Welch welch(Values x, Values y, const Params *params, int fs);
Frames frames(Values x, const Params *params);
bool local_maximum(Values values, int index);
Interpolation interpolate(Values values, int index, bool logarithmic);
double median(Values values);
char *real(double value);
void line(Lines *lines, const char *pattern, ...);
char *shade_line(double frequency, Frames magnitudes, int bin, double maximum, int band);
void save(const char *name, Lines lines);
#endif
