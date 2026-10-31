#ifndef SCHEDULER_H
#define SCHEDULER_H
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
typedef int64_t Integer;
typedef struct {
    int ids[100], count;
} Sequence;
typedef struct {
    Sequence machines[10];
} Order;
typedef Sequence Chromosome;
typedef struct {
    int job, index, machine, duration, head, tail, previous, next;
} Operation;
typedef struct {
    int number, work;
    Sequence operations;
} Job;
typedef struct {
    int count, load, head, tail, bound;
} Machine;
typedef struct {
    int machines, count, job_count, work, error_count;
    Operation operations[100];
    Job jobs[13];
    Machine machine[10];
    char *errors[13];
} Instance;
char *read_line(FILE *);
Instance read_instance(void);
char *notation(Operation);
typedef struct {
    Integer state;
} Minstd;
Integer draw(Minstd *);
int below(Minstd *, int);
bool chance(Minstd *, int, int);
void shuffle(Minstd *, Chromosome *);
typedef struct {
    int start[100], finish[100], previous[100], next[100], makespan, decisions, ties;
    Order order;
} Schedule;
Schedule schedule_order(const Instance *, Order, int);
Schedule from_starts(const Instance *, const int *);
Chromosome chromosome(const Instance *, const Schedule *);
Schedule dispatch(const Instance *, const char *, const Chromosome *);
Schedule decode(const Instance *, const Chromosome *);
int tournament(Minstd *, const int *, int, int);
void crossover(Minstd *, const Instance *, const Chromosome *, const Chromosome *, Chromosome *,
               Chromosome *);
void swap_mutation(Minstd *, Chromosome *);
void insertion_mutation(Minstd *, Chromosome *);
typedef struct {
    int scale, columns, count;
    char *lines[25];
} Chart;
Chart gantt(const Instance *, const Schedule *, const Sequence *, int);
#endif
