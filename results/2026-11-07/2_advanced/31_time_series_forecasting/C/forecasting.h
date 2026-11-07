#ifndef FORECASTING_H
#define FORECASTING_H
#include <inttypes.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef int64_t Integer;
typedef struct {
    double values[168];
    int count;
} Vector;
typedef struct {
    int values[24], count;
} Indices;
typedef struct {
    int season, holdout, horizon, cv_start, combo, max_ar, max_lag;
    Vector alpha, beta, gamma, phi;
    Indices ljung_box;
    double outlier, z80, z95;
} Params;
typedef struct {
    char name[13], periods[168][8];
    Vector raw;
    bool missing[144];
} Series;
typedef struct {
    Integer on_hand;
    int lead_time, review;
    double service;
} Inventory;
typedef struct {
    char series[13], period[8], kind[13];
} Event;
typedef struct {
    Params params;
    Series series[3];
    int series_count;
    Event events[504];
    int event_count;
    Inventory inventory[3];
} Input;
Input read_input(void);
void next_month(const char *, char *);
char *real(double);
char *format(const char *, ...);
void write_lines(FILE *, char **, int);
double total(Vector);
double mean(Vector);
double sample_variance(Vector);
double rmse(Vector);
typedef struct {
    Vector trend, additive, multiplicative, residual_add, residual_mult;
} Decomposition;
Decomposition decompose(Vector, int);
void regression(Vector, double *, double *);
typedef struct {
    double alpha, beta, gamma, phi;
} SmoothParameters;
typedef struct {
    double level, slope, seasonal[12];
} State;
typedef struct {
    Vector residuals;
    State states[145];
} Smoothed;
Smoothed smooth(int, Vector, int, SmoothParameters);
Vector smooth_forecast(int, State, SmoothParameters, int, int, int);
Vector difference(Vector, int, int);
typedef struct {
    double mean, variance;
    Vector acf;
} Correlation;
Correlation autocorrelation(Vector, int);
typedef struct {
    double coefficients[25][25];
    Vector partial, variance;
} Levinson;
Levinson durbin_levinson(Vector, int);
Vector ar_residuals(Vector, double, Vector);
Vector ar_forecast(Vector, Vector, int, int, int, int, double, Vector);
void ljung_box(Vector, int, double *, double *);
double scale_delta(Vector, int);
double winkler(double, double, double, double);
typedef struct {
    double me, mae, rmse, mape, smape, mase, fva, cv_rmse, winkler80, winkler95;
    int cover80, cover95, rank;
} Accuracy;
Accuracy evaluate(Vector, Vector, Vector, double, double, double);
Indices rank_accuracy(Accuracy *, int);
#endif
