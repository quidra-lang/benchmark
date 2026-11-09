#ifndef MINING_H
#define MINING_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
typedef int64_t I;
typedef struct {
    I n, d;
} Fraction;
Fraction ratio(I n, I d), plus(Fraction a, Fraction b), minus(Fraction a, Fraction b),
    times(Fraction a, Fraction b);
int compare(Fraction a, Fraction b);
char *format(const char *pattern, ...), *fraction(Fraction value), *percentage(I n, I d),
    *names(const char *const *values, int count);
typedef struct {
    char **values;
    int count, capacity;
} Lines;
void line(Lines *lines, const char *pattern, ...), save(const char *name, const Lines *lines);
typedef struct {
    char *data;
    size_t size, capacity;
} Text;
void text(Text *out, const char *pattern, ...);
typedef struct {
    int line;
    char case_id[9], activity[21], timestamp[17], resource[13];
    I time;
} Event;
typedef struct {
    char keys[8][32], values[8][32];
    Event *rows;
    int row_count;
} Input;
typedef struct {
    char id[9];
    Event *events[50];
    int trace[50], count;
    I duration;
} Case;
Input read_inputs(void);
int timestamp_minutes(const char *value, I *time);
Case *group_cases(Event *events, int event_count, int *case_count);
Fraction median(const I *values, int count);
typedef struct {
    int activity[50], length;
    I weight;
} Trace;
typedef struct {
    Trace entries[300];
    int count;
} Log;
typedef struct {
    I values[12][12];
} Counts;
typedef enum { UNRELATED, FORWARD, BACKWARD, PARALLEL } Relation;
typedef struct {
    Relation values[12][12];
} Relations;
Counts directly_follows(const Log *log), triangle_counts(const Log *log);
Relation basic_relation(const Counts *counts, int a, int b),
    plus_relation(const Counts *counts, const Counts *triangles, int a, int b);
const char *symbol(Relation relation);
void table(Lines *out, char ***rows, int count, int width);
void footprint(Lines *out, char activities[12][21], const int *ids, int count,
               const Relations *relation);
typedef struct {
    unsigned first, second;
} Candidate;
int extend_pair(Candidate pair, int activity, int side, const Relations *relation,
                Candidate *result),
    pair_order(const void *a, const void *b);
Fraction dependency(const Counts *counts, int a, int b), loop_measure(I count),
    split_measure(const Counts *counts, int a, int b, int c),
    join_measure(const Counts *counts, int a, int b, int c);
typedef struct {
    int place_count, transition_count, initial, final, arc_count;
    char (*places)[21];
    char transitions[12][21];
    unsigned char *inputs, *outputs;
} Net;
Net read_model(void), net_create(char (*places)[21], int place_count, char transitions[12][21],
                                 int transition_count, const char *initial, const char *final);
void net_arc(Net *net, const char *from, const char *to);
int transition_index(const Net *net, const char *name),
    enabled(const Net *net, const unsigned char *marking, int transition);
void fire(const Net *net, const unsigned char *before, int transition, unsigned char *after);
unsigned char *initial_marking(const Net *net), *final_marking(const Net *net);
typedef struct {
    I missing, remaining, consumed, produced, skipped;
    I *place_missing, *place_remaining, *deviating, *wait_count, *wait_sum, *wait_max, *routes;
} Replay;
Replay replay_create(const Net *net);
void replay_free(Replay *replay);
Fraction fitness(const Replay *replay);
#endif
