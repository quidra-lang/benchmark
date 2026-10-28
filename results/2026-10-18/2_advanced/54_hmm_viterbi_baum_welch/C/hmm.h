#ifndef HMM_H
#define HMM_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <math.h>
#include <sys/stat.h>
typedef int64_t I;
typedef struct {
    int *data;
    int count;
} Path;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    char **data;
    int count;
} Tokens;
typedef struct {
    Tokens *data;
    int count;
} Rows;
typedef struct {
    const char *name;
    char states[5], symbols[9], missing;
    int k, m;
    double initial[4], transition[4][4], emission[4][8];
} Model;
typedef struct {
    Model model;
    Rows sequences, labeled, parameters;
} Input;
typedef struct {
    const char *name;
    const char *role;
    Path observation, truth;
} Sequence;
typedef struct {
    int iterations, folds, min_length, max_missing, segment_state, merge_gap, min_segment, first_motif,
        second_motif, min_rich, min_motif, boundary_tolerance, posterior_samples, sample_count, sample_length;
    I posterior_seed, sample_seed;
    double pseudocount, confidence, *smoothing;
    const char **candidates;
    int candidate_count;
    Path rich;
} Params;
typedef struct {
    double (*forward)[4], (*backward)[4], (*posterior)[4], (*emissions)[4], *scales;
    int length;
    double loglik;
} FB;
typedef struct {
    Path path;
    double logprob;
} Viterbi;
typedef struct {
    FB fb;
    Viterbi viterbi;
    Path posterior;
    double *confidence;
} Decoding;
typedef struct {
    Path observation, path;
} Pair;
typedef struct {
    int state, start, end;
} Run;
typedef struct {
    Run *data;
    int count;
} Runs;
typedef struct {
    int start, end;
} Region;
typedef struct {
    Region *data;
    int count;
} Regions;
typedef struct {
    I data[4][4];
} Confusion;
typedef struct {
    I predicted, truth, matched_predicted, matched_truth;
} MatchCounts;
typedef struct {
    I state;
} Generator;
void *allocate(size_t count, size_t size);
void *allocation_mark(void);
void release_to(void *mark);
void release_all(void);
char *format(const char *pattern, ...);
void load(Input *out);
void normalize(double *values, int count);
char *real(double value, int places);
void line(Lines *lines, const char *pattern, ...);
void extend(Lines *target, Lines values);
Lines model_lines(Model model);
void save(const char *name, Lines lines);
Path path_new(int count);
int maximum(const double *values, int count);
double emission(Model model, int observation, int state);
FB forward_backward(Model model, Path observation);
double transition_posterior(Model model, FB fb, int position, int state, int next);
Viterbi viterbi(Model model, Path observation);
Decoding decode(Model model, Path observation);
Model baum_welch(Model model, const Path *observations, int count, double pseudocount);
Model counting(Model model, const Pair *pairs, int count, double alpha, const char *name);
double total_loglik(Model model, const Path *observations, int count);
char *fraction(I numerator, I denominator);
void accumulate(Confusion *matrix, Path truth, Path predicted);
I correct(Path truth, Path predicted);
Lines matrix_lines(Model model, Confusion matrix);
Lines metric_lines(Model model, Confusion matrix);
Runs runs(Path path);
MatchCounts region_counts(Regions predicted, Regions truth);
MatchCounts boundary_counts(Path predicted, Path truth, int tolerance);
int draw(const double *weights, int count, Generator *generator);
Pair synthetic(Model model, int length, Generator *generator);
Path posterior_sample(Model model, FB fb, Generator *generator);
#endif
