#ifndef BAYES_H
#define BAYES_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
#include <math.h>
#include <limits.h>
#include <sys/stat.h>
typedef int64_t I;
typedef struct {
    int values[15], count;
} Vars;
typedef struct {
    int values[15];
} Assignment;
typedef struct {
    int variable, state;
} Observation;
typedef struct {
    Observation values[15];
    int count;
} Evidence;
typedef struct {
    double (*values)[4];
    int rows, states;
} CPT;
typedef struct {
    I (*values)[4];
    int rows, states;
} Counts;
typedef struct {
    int count, sizes[15];
    char names[15][17], states[15][4][17];
    Vars parents[15];
    CPT expert[15];
    int has_expert[15];
} Network;
typedef struct {
    Network network;
    Assignment *samples;
    int sample_count;
    char *queries[40];
    int query_count;
    char *settings[20];
} Input;
typedef struct {
    char **values;
    int count, capacity;
} Lines;
typedef struct {
    char *data;
    size_t length, capacity;
} Text;
char *format(const char *pattern, ...), *read_line(FILE *input);
void text(Text *out, const char *pattern, ...), line(Lines *out, const char *pattern, ...);
Input *read_inputs(void);
int variable_id(const Network *network, const char *name),
    state_id(const Network *network, int variable, const char *name);
int contains(const Vars *variables, int variable);
Vars canonical(Vars variables), vars_union(Vars first, Vars second),
    vars_difference(Vars first, Vars second), observed(const Evidence *evidence);
I parent_row(const Vars *parents, const Assignment *assignment, const Network *network),
    entry_count(const Vars *variables, const Network *network);
Counts count_samples(int variable, const Vars *parents, const Assignment *samples, int count,
                     const Network *network);
CPT learn(const Counts *counts, double alpha);
double total(const double *values, I count), log_likelihood(const Counts *counts, const CPT *cpt),
    family_score(int variable, Vars parents, const Assignment *samples, int count,
                 const Network *network, double alpha);
I parameter_count(const Counts *counts);
Assignment decode(I index, const Vars *variables, const Network *network, Assignment initial);
int evidence_state(const Evidence *evidence, int variable);
typedef struct {
    Vars variables;
    double *values;
    I count;
    const Network *network;
} Factor;
typedef struct {
    Factor values[31];
    int count;
} Factors;
double factor_value(const Factor *factor, const Assignment *assignment);
Factor reduced(const Factor *factor, const Evidence *evidence),
    multiplied(const Factor *first, const Factor *second),
    factor_eliminate(const Factor *factor, int variable, int maximize),
    cpt_factor(int variable, const Vars *parents, const CPT *cpt, const Network *network),
    multiply(const Factors *factors, const Network *network);
typedef struct {
    unsigned neighbors[15], present;
} Graph;
Graph interaction_graph(const Factors *factors);
typedef struct {
    int variable, fill;
    Vars scope;
    I size;
} Step;
typedef struct {
    Step steps[15];
    int count;
    I maximum, total;
} Plan;
Plan make_plan(const Factors *factors, const Vars *eliminate, int given, const Vars *order,
               const Network *network);
typedef struct {
    Factor final, products[15];
    int variables[15], count;
} Execution;
Execution execute(const Factors *initial, const Plan *plan, const Network *network, int maximize);
Assignment traceback(const Execution *execution, const Network *network);
typedef struct {
    I state;
} Minstd;
double uniform(Minstd *random);
int choose(const double *probabilities, int count, Minstd *random);
typedef struct {
    Assignment assignment;
    double weight;
} Weighted;
Weighted weighted_sample(const Vars *topological, const Network *network, const CPT cpts[15],
                         const Evidence *evidence, Minstd *random);
#endif
