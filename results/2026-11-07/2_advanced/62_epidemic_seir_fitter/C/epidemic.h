#ifndef EPIDEMIC_H
#define EPIDEMIC_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <math.h>
#include <float.h>
#include <sys/stat.h>
typedef long long I;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    char name[13];
    I population;
    double fatality;
} Group;
typedef struct {
    int day;
    double multiplier;
} Intervention;
typedef struct {
    char name[13];
    double multiplier;
} Scenario;
typedef struct {
    char name[13], group[13];
    double factor;
} ContactChange;
typedef struct {
    double sigma, gamma, e0, i0, beta_min, beta_max, rho_min, rho_max, delta_beta, delta_gamma,
        alpha, chi, psi, omega, effect_width, outlier, threshold;
    int beta_count, rho_count, golden, rounds, nelder, holdout, death_lag, generation, horizon;
    I milestones[5];
    int milestone_count, scenario_count, change_count;
    Scenario scenarios[5];
    ContactChange changes[5];
} Params;
typedef struct {
    I cases[200], deaths[200];
    int days, group_count, intervention_count;
    Group groups[6];
    double contacts[6][6];
    Intervention interventions[10];
    Params params;
} Input;
enum Kind { K_SEIRD, K_SIR, K_AGE, K_GENERATION };
typedef struct {
    double values[36];
    int count;
} State;
typedef struct {
    State *states;
    int count;
} Trajectory;
typedef struct {
    int kind, group_count;
    double beta, gamma, sigma, population, fatality, e0, i0;
    const Group *groups;
    const double (*contacts)[6];
} Model;
typedef struct {
    double a, b, c, d, fc, fd;
} GoldenRecord;
typedef struct {
    double point, value;
    GoldenRecord records[41];
    int count;
} Golden;
typedef struct {
    double value[2];
} Point;
typedef struct {
    Point point;
    double value;
    int number;
} Vertex;
typedef struct {
    const char *operation;
    Vertex best;
} SimplexRecord;
typedef struct {
    Vertex initial[3], final[3];
    SimplexRecord records[100];
    int count;
} Simplex;
void *allocate(size_t count, size_t size);
char *format(const char *pattern, ...), *joined(const char *first, const char *second);
void line(Lines *lines, const char *pattern, ...);
Lines read_lines(const char *path);
Input *load(void);
void save(const char *name, Lines lines);
State initial_state(const Model *model);
State rates(const Model *model, State state, double multiplier);
void reset(const Model *model, State *state);
State rk4(const Model *model, State state, double multiplier);
Trajectory simulate(const Model *model, State state, const double *multipliers, int count);
Golden golden(double (*function)(double, void *), void *context, double a, double b,
              int iterations);
Simplex nelder_mead(double (*function)(Point, void *), void *context, Point start,
                    const Params *params);
char *real(double value, int digits);
Lines curve_plot(const I *cases, const double *fitted, int count);
#endif
