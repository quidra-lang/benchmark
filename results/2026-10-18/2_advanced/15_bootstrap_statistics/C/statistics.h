#ifndef STATISTICS_H
#define STATISTICS_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include <sys/stat.h>
#include <errno.h>

typedef long long Integer;
typedef struct { Integer *v; int n; } Sample;
typedef struct { double *v; int n; } Values;
typedef struct { char **items; int count, capacity; } Lines;
typedef struct { char name[17]; Integer values[80]; int count; } Group;
typedef struct { Integer seed; int bootstrap, permutations, confidence, pilot, simulations, inner_permutations, bins; } Settings;
typedef struct {
    Group groups[4]; int group_count;
    Integer before[60], after[60], differences[60]; int subjects;
    int pairs[6][2], pair_count;
    Settings settings;
} Dataset;
typedef struct { Integer state; } Minstd;
typedef struct { double sd, second, third, fourth; } Moments;
typedef struct { double average, se; } Spread;
typedef struct { Integer numerator, denominator; } Fraction;
typedef struct { double between, within, f, means[4]; int count; } Anova;
void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
void extend(Lines *target, Lines source);
Lines read_lines(const char *path);
void load_dataset(Dataset *data);
Sample group_sample(const Group *group);
Integer draw(Minstd *generator);
int below(Minstd *generator, int limit);
void shuffle(Minstd *generator, int *values, int count);
Integer sample_sum(Sample values);
double sequential_sum(Values values);
double mean(Sample values);
Integer doubled_median(Sample values);
double median(Sample values);
double trimmed_mean(Sample values);
Moments moments(Sample values);
double sd(Sample values);
double mad(Sample values);
Integer quantile_numerator(Sample values, int percent);
void winsorized(Sample values, Integer *result);
double mean_difference(Sample first, Sample second);
double median_ratio(Sample first, Sample second);
double hodges_lehmann(Sample first, Sample second);
double pooled_sd(Sample first, Sample second);
double cohen_d(Sample first, Sample second);
double correlation(Sample first, Sample second);
void group_statistics(Sample sample, double result[4]);
void pair_statistics(Sample first, Sample second, double result[4]);
void resample_indices(Minstd *generator, int size, int *result);
int *ordinary_indices(Minstd *generator, int size, int count);
int *balanced_indices(Minstd *generator, int size, int count);
Sample without(Sample values, int index, Integer *storage);
Sample chosen(Sample values, const int *indices, int count, Integer *storage);
Spread mean_and_se(Values values);
double phi(double value);
double phi_inverse(double probability);
int compare_integer(const void *first, const void *second);
int compare_real(const void *first, const void *second);
Fraction reduced(Integer numerator, Integer denominator);
Integer contrast(Sample first, Sample second);
void doubled_ranks(Sample values, Integer *result);
int value_counts(Sample values, Integer *keys, Integer *counts);
void divide(Sample values, const int *sizes, int count, Sample *result);
bool next_choice(int *choice, int size, int total);
Anova anova(const Sample *samples, int count);
double kruskal(const Sample *rank_groups, int count, double correction);
char *real_text(double value);
char *p_value(Integer numerator, Integer denominator);
char *number_list(const int *numbers, int count);
int bin_number(double value, double low, double high, int bins);
char *bar(int count, int top);
void write_lines(const char *name, Lines lines);
#endif
