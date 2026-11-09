#ifndef PLANNER_H
#define PLANNER_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
typedef long long Value;
#define INFINITY_VALUE (1LL << 60)
typedef struct {
    int *data;
    int count, capacity;
} IntList;
typedef struct {
    char **data;
    int count, capacity;
} TextLines;
typedef struct {
    uint64_t words[4];
} State;
typedef struct {
    int name, type;
} Typed;
typedef struct {
    Typed *data;
    int count, capacity;
} TypedList;
typedef struct {
    int predicate;
    IntList terms;
} Atom;
typedef struct {
    int atom;
    bool negative;
} Literal;
typedef struct {
    Literal *data;
    int count, capacity;
} LiteralList;
typedef struct {
    int name;
    IntList types;
} Predicate;
typedef struct {
    int name;
    TypedList parameters;
    LiteralList conditions, effects;
    Value cost;
} Schema;
typedef struct {
    int name;
    IntList types;
    TypedList parents;
    Predicate predicates[15];
    int predicate_count;
    Schema actions[10];
    int action_count;
    bool fluent[15];
    TextLines diagnostics;
} Domain;
typedef struct {
    int name;
    TypedList objects;
    IntList initial, goals;
    TextLines diagnostics;
} Problem;
typedef struct {
    int schema;
    IntList arguments;
    Value cost;
    State pre, neg, add, del;
} GroundAction;
typedef struct {
    int assignments, candidates, reachable;
} SchemaCount;
typedef struct {
    Value goalcount, hmax, hadd, ff, lmcount;
    IntList relaxed, helpful;
    State landmarks;
} Heuristic;
typedef struct {
    State state;
    Heuristic *heuristic;
} HeuristicEntry;
typedef struct {
    const Domain *domain;
    const Problem *problem;
    IntList facts, unreachable;
    GroundAction actions[300];
    int action_count;
    State initial, goal;
    SchemaCount counts[10];
    int candidate_count, static_facts;
    HeuristicEntry *cache;
    int cache_count, cache_capacity;
    int *cache_slots, cache_slot_count;
} GroundProblem;
typedef struct {
    State state;
    Value value;
} StateEntry;
typedef struct {
    StateEntry *data;
    int count, capacity;
    int *slots, slot_count;
} StateTable;
typedef struct {
    const char *algorithm, *heuristic;
} SearchSettings;
typedef struct {
    int budget, weight, level_limit;
    SearchSettings runs[12], repair;
    int run_count;
} Settings;
typedef struct {
    int name;
    IntList arguments;
} Step;
typedef struct {
    Step *data;
    int count, capacity;
} StepList;
typedef struct {
    int problem, label;
    StepList steps;
} CandidatePlan;
typedef struct {
    const char *status;
    IntList plan;
    Value expanded, generated;
} SearchResult;
typedef struct {
    IntList *data;
    int count, capacity;
} Layers;
typedef struct {
    int action, fact;
    State pre, add, del;
} GraphElement;
typedef struct {
    const char *status;
    IntList plan;
    Layers layers;
    Value searched, memo_hits, tried;
    TextLines logs;
} GraphPlanResult;
void *allocate(size_t size);
void *resize(void *data, size_t size);
char *copy_text(const char *text);
char *format_text(const char *format, ...);
void int_push(IntList *list, int value);
void int_add(IntList *list, int value);
bool int_has(const IntList *list, int value);
IntList int_copy(const IntList *list);
void int_free(IntList *list);
void lines_push(TextLines *lines, char *text);
void lines_add(TextLines *lines, const char *text);
void lines_append(TextLines *lines, const TextLines *from);
void lines_free(TextLines *lines);
TextLines read_lines(const char *path);
IntList split_words(const char *text);
char *join_words(const IntList *words, const char *separator);
char *join_texts(const TextLines *texts, const char *separator);
int symbol(const char *name);
const char *symbol_name(int id);
int intern_atom(int predicate, const IntList *terms);
const Atom *get_atom(int id);
char *atom_text(int atom);
char *literal_text(Literal literal);
void symbols_destroy(void);
Domain read_domain(void);
Problem *read_problems(int *count);
void domain_free(Domain *domain);
void problem_free(Problem *problem);
int predicate_index(const Domain *domain, int name);
bool subtype(const Domain *domain, int type, int expected);
void classify(Domain *domain);
int typed_find(const TypedList *types, int name);
int substitute_atom(int atom, const TypedList *assignment);
IntList objects_of_type(const Domain *domain, const Problem *problem, int type);
GroundProblem ground(const Domain *domain, const Problem *problem);
void ground_free(GroundProblem *ground);
bool state_has(State state, int fact);
void state_put(State *state, int fact);
State state_union(State a, State b);
State state_without(State a, State b);
State state_intersection(State a, State b);
bool state_contains(State a, State b);
bool state_intersects(State a, State b);
bool state_equal(State a, State b);
IntList state_numbers(State state);
int state_count(State state);
uint64_t state_hash(State state);
bool state_table_get(const StateTable *table, State state, Value *value);
void state_table_set(StateTable *table, State state, Value value);
void state_table_free(StateTable *table);
bool applicable(const GroundAction *action, State state);
State apply(const GroundAction *action, State state);
Heuristic *heuristics(GroundProblem *ground, State state);
Value heuristic_value(const Heuristic *heuristic, const char *name);
SearchResult search(GroundProblem *ground, State start, SearchSettings settings, int budget,
                    int weight);
GraphPlanResult graph_plan(const GraphElement *actions, int action_count, State initial, State goal,
                           int limit);
void layers_push(Layers *layers, IntList layer);
void layers_free(Layers *layers);
void graph_result_free(GraphPlanResult *result);
#endif
