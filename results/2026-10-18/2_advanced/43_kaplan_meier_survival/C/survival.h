#ifndef SURVIVAL_H
#define SURVIVAL_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#define NORMAL_Z 1.959963984540054
typedef struct {
    double v[6];
} Vector;
typedef struct {
    double v[6][6];
} Matrix;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    int *data;
    int count, capacity;
} IntList;
typedef struct {
    int id, group, time, event, age, stage;
    char sex;
} Subject;
typedef struct {
    Subject *data;
    int count, capacity;
} Subjects;
typedef struct {
    Lines groups, subgroups, covariates;
    IntList report_times;
    int tau, life_width, life_intervals, landmark, residuals, plot_width, plot_height, plot_time,
        plot_divisions;
    char *strata;
} Params;
typedef struct {
    Subjects subjects;
    Params params;
} Dataset;
typedef struct {
    int time, risk, events, censored;
    double survival, std_err, lower, upper, hazard, hazard_se;
    bool interval_defined, error_defined;
} KMRow;
typedef struct {
    KMRow *data;
    int count;
} KMRows;
typedef struct {
    int a, b, risk, events, withdrawn, exposure2;
    double probability, survival, std_err, hazard;
} LifeRow;
typedef struct {
    LifeRow *data;
    int count;
} LifeRows;
typedef struct {
    int groups[6], count, events[6];
    Vector observed, expected;
    Matrix covariance;
    double statistic, p;
    int degrees;
} GroupTest;
typedef struct {
    int time, events;
    double s0;
    Vector s1;
} CoxTime;
typedef struct {
    double loglik;
    Vector score;
    Matrix information;
    double theta[400], risks[400];
    CoxTime times[400];
    int time_count;
} CoxEvaluation;
typedef struct {
    double loglik;
    Vector beta;
} Iteration;
typedef struct {
    Vector beta;
    CoxEvaluation initial, final;
    Iteration iterations[25];
} CoxFit;
void *resize(void *memory, size_t size);
char *text(const char *value);
char *format(const char *pattern, ...);
void line_push(Lines *lines, char *line);
void lines_extend(Lines *target, const Lines *source);
void lines_free(Lines *lines);
void int_push(IntList *list, int value);
void int_sort(IntList *list);
void subject_push(Subjects *subjects, Subject subject);
Dataset *read_dataset(void);
int risk_size(const Subjects *subjects, int time);
int event_count(const Subjects *subjects, int time);
IntList event_times(const Subjects *subjects);
KMRows kaplan_meier(const Subjects *subjects);
KMRow row_at(const KMRows *rows, int time);
LifeRows life_table(const Subjects *subjects, int width, int intervals);
Vector solve(Matrix matrix, Vector right, int size);
Matrix inverse(Matrix matrix, int size);
double log_gamma(double a);
double gamma_q(double a, double x);
double p_value(double statistic, int degrees);
GroupTest weighted_test(const Subjects *subjects, const int *groups, int group_count, int kind,
                        int total_subjects);
GroupTest combine_tests(const GroupTest *tests, int count);
void finalize_test(GroupTest *test);
CoxEvaluation cox_evaluate(const Subjects *subjects, const Vector *design, int size, Vector beta);
CoxFit *cox_fit(const Subjects *subjects, const Vector *design, int size);
Lines curve_plot(const KMRows *curves, const int *maximums, const Params *params);
#endif
