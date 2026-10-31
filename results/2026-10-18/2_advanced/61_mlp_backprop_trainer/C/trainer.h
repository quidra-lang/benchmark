#ifndef TRAINER_H
#define TRAINER_H
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
    char id[9], pixels[65];
    int label;
    double input[64];
} Image;
typedef struct {
    int inputs, units, weights, biases;
    char function[8];
    bool output;
} Layer;
typedef struct {
    char name[17];
    int inputs, classes, weight_count, param_count, layer_count;
    Layer layers[3];
    double initial[1066];
    bool is_weight[1066];
} Network;
typedef struct {
    char name[21], optimizer[9];
    int network;
    double eta, decay, mu, beta1, beta2, epsilon;
} Run;
typedef struct {
    int64_t seed;
    int batch, epochs, patience, lr_step, stride, bins, prune[5], noise[5], prune_count,
        noise_count, run_count;
    double gamma;
    Run runs[6];
} Params;
typedef struct {
    int width, height, classes, train_count, test_count, network_count;
    Image train[200], test[200];
    Network networks[4];
    Params params;
} Input;
typedef struct {
    int64_t state;
} Random;
typedef struct {
    double z[3][12], activations[4][64], scores[10], delta[10], loss;
} Forward;
typedef struct {
    double parameters[1066], input[64];
} Backward;
typedef struct {
    double first[1066], second[1066], pi1, pi2;
} Optimizer;
void *allocate(size_t count, size_t size);
char *format(const char *pattern, ...), *joined(const char *first, const char *second);
void line(Lines *lines, const char *pattern, ...);
Lines read_lines(const char *path);
Input *load(void);
int64_t random_draw(Random *random);
void shuffle(Random *random, int *order, int count);
void add_layer(Network *network, int units, const char *function, bool output);
double activation(const char *function, double z),
    derivative(const char *function, double z, double a);
void preactivation(const double *weights, const double *input, const Layer *layer, double *out);
void propagate(const double *weights, const Layer *next, const double *delta, double *out);
void output_layer(const char *function, const double *z, int count, int label, double *scores,
                  double *delta, double *loss);
void forward(const Network *network, const double *weights, const Image *image, Forward *out);
void backward(const Network *network, const double *weights, const Forward *record, Backward *out);
void optimizer_init(Optimizer *optimizer);
void update(Optimizer *optimizer, double *weights, const double *gradient, int count,
            const Run *run, double eta);
double learning_rate(const Run *run, const Params *params, int epoch);
char *real(double value, int digits), *ratio(int64_t numerator, int64_t denominator);
int prediction(const double *scores, int count),
    second_class(const double *scores, int count, int first);
void confusion(const Image *images, const int *predictions, int count, int classes,
               int out[10][10]);
typedef struct {
    int support, predicted, true_positive;
} ClassStats;
ClassStats class_stats(const int matrix[10][10], int label, int classes);
void level_maps(Lines *lines, int levels[10][64], int classes, int width, int height);
void image_lines(Lines *lines, const Image *image, int width, int height);
void save(const char *name, Lines lines);
#endif
