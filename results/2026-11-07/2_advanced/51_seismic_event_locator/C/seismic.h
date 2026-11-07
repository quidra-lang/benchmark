#ifndef SEISMIC_H
#define SEISMIC_H
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdarg.h>
#include <inttypes.h>
#include <sys/stat.h>
typedef int64_t I;
typedef struct {
    I sw, lw, on_p, on_q, off_p, off_q, min_duration, noise, aw, clip, window, minimum;
    double velocity;
    I gx[3], gy[3], gz[3];
    double limit, qa[3], qb[3], cluster[2], local[3], duration[3];
    I area[4], map_size[2], section[2], timeline[5];
} Params;
typedef struct {
    char code[9];
    I x, y, elevation, start, *samples, mean, peak, clipped;
    int count, triggers, short_triggers, used, mag_count;
    double noise, correction, mag_correction, first_square, final_square;
} Station;
typedef enum { USED, DROPPED, ADDED, REJECTED, UNASSOCIATED } State;
typedef struct {
    int station;
    I sample, duration, amplitude;
    double ratio;
    bool clipped, assigned;
    State state;
    int event;
    double first_residual, residual;
} Pick;
typedef struct {
    Pick *data;
    int count, capacity;
} Picks;
typedef struct {
    int data[12], count;
} Ids;
typedef struct {
    int station;
    double time;
} Observation;
typedef struct {
    Observation data[12];
    int count;
} Observations;
typedef struct {
    double data[4];
} Solution;
typedef struct {
    Solution solution;
    double rms;
} Iteration;
typedef struct {
    Solution solution, grid;
    double rms, grid_rms, *profile, residual[12];
    int depths;
    Iteration trace[8];
} Run;
typedef struct {
    Ids picks, retained, dropped;
    double drop_residual[12];
    int first, event;
    bool rejected;
    Run first_run, second_run;
} Candidate;
typedef struct {
    double smaj, smin, az, erz, ert;
} Ellipse;
typedef struct {
    double radius, md, ml;
    bool has_ml;
} PickMagnitude;
typedef struct {
    I value;
    int count;
} ClassCount;
typedef struct {
    ClassCount *counts;
    int count, nb, n;
    I completeness;
    double b, sigma, a, slope, intercept, r, mean_diff;
} Frequency;
void *allocate(size_t count, size_t size);
void release_all(void);
char *format(const char *pattern, ...);
void load(Station *stations, int *count, Params *params);
void detect_station(Station *station, int index, const Params *params, Picks *picks);
Candidate *associate(Picks *picks, const Params *params, int *count);
double distance(Solution solution, const Station *station);
void residuals(Solution solution, Observations observations, const Station *stations, double velocity,
               double *result);
double rms(Solution solution, Observations observations, const Station *stations, double velocity);
Run geiger(Solution initial, Observations observations, const Station *stations, double velocity);
Run locate(Observations observations, const Station *stations, const Params *params);
Ellipse ellipse(Solution solution, Observations observations, const Station *stations, double velocity);
double logarithm(double value);
double median(const double *values, int count);
PickMagnitude magnitude(Pick pick, double radius, const Params *params);
I scaled(double value, int places);
I floor_div(I a, I b);
char *class_text(I value);
Frequency frequency(const double *local, const double *duration, int count);
#endif
