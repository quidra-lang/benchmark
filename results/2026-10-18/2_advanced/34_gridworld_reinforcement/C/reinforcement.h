#ifndef REINFORCEMENT_H
#define REINFORCEMENT_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <inttypes.h>
typedef int64_t Integer;
typedef Integer (*Table)[4];
typedef struct {
    char **data;
    size_t len, cap;
} Lines;
typedef struct {
    char *data;
    size_t len, cap;
} Text;
void *allocate(size_t count, size_t size);
void grow(void **data, size_t *cap, size_t need, size_t size);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void line_add(Lines *lines, const char *pattern, ...);
void extend(Lines *out, Lines lines);
Lines read_lines(const char *path);
char *number(Integer value);
Integer floor_div(Integer a, Integer b);
Integer absolute(Integer value);
typedef struct {
    int rows, cols, start, n, nt;
    char *cells;
    int *states, *terminals, *index, *terminal_index, *wind;
    Integer *rewards;
    int (*moves)[4];
} World;
World read_world(void);
int move_cell(const World *w, int cell, int action);
Integer reward(const World *w, int cell, Integer step_reward);
bool terminal(const World *w, int cell);
const char *ending(const World *w, int cell);
typedef struct {
    int cell;
    Integer weight;
} Transition;
typedef struct {
    Transition data[3];
    int count;
} Transitions;
typedef struct {
    const World *world;
    Integer q, floor_slip, ice_slip, step_reward;
} Model;
Transitions transitions(const Model *model, int state, int action);
typedef struct {
    Integer value;
} Random;
Integer draw(Random *random);
typedef struct {
    int cell;
    Integer reward;
} Outcome;
Outcome step(const Model *model, int state, int action, Random *random);
int first_maximum(const Integer values[4]);
Integer bellman(const Model *model, const Integer *values, int state, int action, Integer gamma);
Table action_values(const Model *model, const Integer *values, Integer gamma);
int *greedy(Table values, int count);
typedef struct {
    Integer *values, *deltas;
    size_t count, cap;
    Table actions;
    int *policy;
} Iteration;
Iteration value_iteration(const Model *model, Integer gamma, Integer theta);
typedef struct {
    Integer *values;
    int sweeps;
} Evaluation;
Evaluation in_place(const Model *model, Integer gamma, Integer theta);
Evaluation evaluate(const Model *model, const int *policy, Integer *values, Integer gamma, Integer theta);
typedef struct {
    int sweeps, changed;
    Integer start;
} Round;
typedef struct {
    Integer *values;
    int *policy;
    Round *rounds;
    size_t count, cap;
} PolicyIteration;
PolicyIteration policy_iteration(const Model *model, Integer gamma, Integer theta);
int choose(Table q, int state, Integer epsilon, Random *random);
Integer next_value(Table q, int state, Integer epsilon, bool expected);
void td_update(const Model *model, Table q, int state, int action, int next, Integer r, Integer gamma,
               Integer alpha, Integer f);
typedef struct {
    int state, action;
    Integer reward;
} Sample;
typedef struct {
    int state, action;
} Pair;
typedef struct {
    bool known;
    int next;
    Integer reward;
} ModelEntry;
typedef struct {
    ModelEntry (*entries)[4];
    Pair *observed;
    size_t count;
} Dyna;
Dyna dyna_create(int states);
void dyna_record(Dyna *dyna, int state, int action, int next, Integer r);
void dyna_plan(Dyna *dyna, const Model *model, Table q, int count, Integer gamma, Integer alpha,
               Random *random);
void monte_carlo(const Sample *steps, int count, Table q, Table sums, Table counts, int states,
                 Integer gamma);
Integer discounted(const Integer *rewards, int count, Integer gamma);
char *fixed(Integer value);
char *average(Integer total, Integer count);
char *cell_text(const World *w, int cell);
char *cells_text(const World *w, const int *cells, int count);
Lines grid(const World *w, char **fields, const char *separator);
Lines value_grid(const World *w, const Integer *values);
Lines policy_grid(const World *w, const int *policy);
Lines q_rows(const World *w, const char *name, Table q, Table visits);
Lines parts(Lines *parts, int count);
void write_lines(const char *name, Lines lines);
#endif
