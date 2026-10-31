#ifndef CLASSIFIER_H
#define CLASSIFIER_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <math.h>
#include <sys/stat.h>
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    char id[9];
    double point[2];
    int label;
} Example;
typedef struct {
    char name[9], kind[7];
    int degree;
    double gamma, coef0;
} Kernel;
typedef struct {
    double c_grid[6], tolerance, epsilon, multi_c, lambda, x_min, x_max, y_min, y_max;
    int c_count, kernel_count, max_passes, folds, newton_iterations, pegasos_iterations, width,
        height, learning[10], learning_count;
    int64_t seed;
    Kernel kernels[4];
    char multi_name[9];
} Params;
typedef struct {
    Example train[200], test[100], multi_train[150], multi_test[100];
    int train_count, test_count, multi_train_count, multi_test_count;
    Params params;
} Input;
typedef struct {
    bool full;
    int examined, changed;
    double *alpha;
} Pass;
typedef struct {
    const Example *data;
    const double *matrix;
    int count;
    Kernel kernel;
    double c, b, alpha[200];
    int full, nonbound, examined, steps, choices[3], clipping[3];
    bool converged;
    Pass *passes;
    int pass_count, pass_capacity;
} Model;
void *allocate(size_t count, size_t size);
char *format(const char *pattern, ...), *joined(const char *first, const char *second);
void line(Lines *lines, const char *pattern, ...);
Lines read_lines(const char *path);
Input *load(void);
double kernel_value(Kernel kernel, const double *first, const double *second);
double *kernel_matrix(Kernel kernel, const Example *data, int count);
char *kernel_description(Kernel kernel);
Model train(const Example *data, int count, Kernel kernel, const double *matrix, double c,
            const Params *params);
void free_model(Model *model);
double decision(const Model *model, const double *point);
void training_decisions(const Model *model, double *out);
typedef struct {
    Model rest[3], pairs[3];
} Multi;
typedef struct {
    double rest[3], pairs[3], scores[3];
    int votes[3], ovr, ovo;
    bool tie;
} MultiPrediction;
Multi *train_multi(const Input *input, Kernel kernel);
MultiPrediction classify(const Multi *models, const double *point);
int sign(double value);
typedef struct {
    int train[200], test[200], train_count, test_count;
} Fold;
Fold *folds(int count, int k);
typedef struct {
    int tp, fp, tn, fn;
} Evaluation;
Evaluation evaluate(const Example *data, const double *values, int count);
double auc(const Example *data, const double *values, int count);
char *real(double value, int digits), *ratio(int numerator, int denominator);
void confusion_matrix(const Example *data, const MultiPrediction *predictions, int count, bool rest,
                      int out[3][3]);
void save(const char *name, Lines lines);
#endif
