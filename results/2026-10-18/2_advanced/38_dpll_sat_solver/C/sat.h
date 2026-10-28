#ifndef SAT_H
#define SAT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct {
    int *data;
    int count, capacity;
} IntList;
typedef IntList Clause;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    int variables;
    Clause *clauses;
    int count, capacity;
} Formula;
typedef struct {
    int values[201];
} Model;
typedef struct {
    int a, b;
} Edge;
typedef struct {
    char *name, *error;
    int vertices, degrees[31];
    Edge edges[435];
    int edge_count;
} Graph;
typedef struct {
    int decisions, propagations, conflicts, max_depth;
} Statistics;
typedef struct {
    int id;
    Clause literals;
} WorkingClause;
typedef struct {
    WorkingClause *clauses;
    int count, capacity;
    Model fixed;
    bool pure, conflict;
    int empty_clause, tautologies, duplicate_literals, unit_fixed, unit_removed, subsumed, pure_fixed,
        pure_removed;
    IntList removed[4];
} Preprocess;
typedef struct {
    Formula formula;
    char *error;
} CnfInput;
typedef struct {
    bool sat;
    Model values;
    Statistics stats;
    Lines events;
} Round;
void *resize(void *memory, size_t size);
char *text(const char *value);
char *format(const char *pattern, ...);
void int_push(IntList *list, int value);
bool int_contains(const IntList *list, int value);
Clause int_copy(const IntList *list);
void int_free(IntList *list);
void line_push(Lines *lines, char *line);
void append_lines(Lines *target, const Lines *source);
void free_lines(Lines *lines);
Lines read_lines(const char *path);
Lines words(const char *line);
void formula_push(Formula *formula, Clause clause);
Formula formula_copy(const Formula *formula);
void formula_free(Formula *formula);
bool well_number(const char *value);
CnfInput read_cnf(const char *name);
Lines model_lines(const Model *model, int variables);
Formula queens_formula(int n);
Formula pigeon_formula(int pigeons, int holes);
Formula color_formula(const Graph *graph, int colors);
IntList decode(const Model *model, int rows, int columns);
Preprocess preprocess(const Formula *formula, bool pure);
int removed_count(const Preprocess *reduced);
void preprocess_free(Preprocess *reduced);
void stats_add(Statistics *target, const Statistics *source);
Round dpll_round(const Formula *formula);
char *number_list(const IntList *values);
char *frequency_list(const int *counts, int length);
char *items(const char *prefix, int count, ...);
Lines board_lines(const IntList *columns);
void write_lines(const char *name, const Lines *lines);
void paragraph(Lines *file, const Lines *lines);
#endif
