#ifndef MAPF_H
#define MAPF_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
typedef struct {
    int start, goal;
} Agent;
typedef struct {
    int width, height, agent_count;
    char rows[32][33];
    Agent agents[20];
    int distance[20][1024];
} Grid;
typedef struct {
    int items[5], count;
} Destinations;
void read_grid(Grid *);
bool free_cell(const Grid *, int);
Destinations destinations(const Grid *, int);
void distances(const Grid *, int, int[1024]);
typedef struct Path {
    size_t references;
    int *cells, count, capacity;
} Path;
typedef struct {
    Path *paths[20];
    int count;
} Plan;
Path *path_new(void);
void path_append(Path *, int);
Path *path_retain(Path *);
void path_release(Path *);
Plan plan_copy(const Plan *);
void plan_release(Plan *);
typedef struct {
    int agent, time, u, v;
    bool edge;
} Constraint;
typedef struct ConstraintList {
    size_t references, count;
    Constraint *items;
} ConstraintList;
ConstraintList *constraints_retain(ConstraintList *);
ConstraintList *constraints_append(const ConstraintList *, Constraint);
void constraints_release(ConstraintList *);
typedef struct {
    int cells, width, max_time;
    uint8_t *states, *moves;
    int permanent[1024];
} Prohibitions;
Prohibitions prohibitions_new(const Grid *, int);
void prohibitions_free(Prohibitions *);
bool allowed(const Prohibitions *, int, int, int);
int arrival_allowed(const Prohibitions *, int);
void reserve_path(Prohibitions *, const Path *, int, bool);
Prohibitions constraint_prohibitions(const Grid *, int, const ConstraintList *);
typedef struct {
    int searches, expansions, limit;
    bool aborted;
} Counters;
Path *low_level(const Grid *, int, int, int, int, const Prohibitions *, bool, Counters *);
typedef struct {
    int time, a, b, u, v;
    bool edge;
} Conflict;
typedef struct {
    Conflict *items;
    size_t count, capacity;
} Conflicts;
int position(const Path *, int);
void plan_costs(const Plan *, int *, int *);
Conflicts conflicts(const Plan *);
Constraint conflict_constraint(Conflict, int);
typedef struct TreeNode {
    int number, parent, depth, cost;
    Plan paths;
    ConstraintList *constraints[20];
    Conflicts conflicts;
} TreeNode;
bool node_less(const TreeNode *, const TreeNode *);
typedef enum { SOLVER_PP, SOLVER_CBS, SOLVER_ICBS, SOLVER_WHCA } Solver;
typedef struct {
    Solver solver;
    bool makespan;
    char name[32];
} RunDefinition;
typedef struct {
    int agent, start, length;
} Delay;
typedef struct {
    int horizon, high_budget, low_budget, window, step, frames;
    char animate[32];
    int orders[11][20], order_count;
    RunDefinition runs[10];
    int run_count;
    Delay delays[20];
    int delay_count;
} Parameters;
typedef struct {
    char **items;
    size_t count, capacity;
} Lines;
typedef struct {
    char *data;
    size_t count, capacity;
} Text;
typedef struct {
    char **items;
    size_t count;
} Words;
typedef struct {
    int cost, extra, waits, turns, arrival, leave;
    char *actions;
} AgentMetrics;
typedef struct {
    int soc, makespan, sum_extra, max_extra, waits, turns;
    AgentMetrics agents[20];
    int traffic[1024], cell_waits[1024], *arrivals, hotspots[5], hotspot_count;
} PlanMetrics;
typedef struct {
    bool deadlock;
    int time, soc, makespan, blocked, finish[20];
} Execution;
typedef struct {
    RunDefinition definition;
    const char *reason;
    char *end;
    Plan paths;
    Counters counter;
    int high, generated, pruned, open, classes[3];
    Lines specific, trace;
    TreeNode *answer;
    PlanMetrics metrics;
    Execution execution;
} Run;
typedef struct {
    Plan paths;
    int planned, failed;
} PriorityResult;
PriorityResult prioritized(const Grid *, const Parameters *, const int *, int, Run *);
void *allocate(size_t);
void *resize(void *, size_t);
char *copy_text(const char *);
char *format_text(const char *, ...);
void text_add(Text *, const char *);
void text_format(Text *, const char *, ...);
char *text_take(Text *);
void lines_add(Lines *, char *);
void lines_copy(Lines *, const Lines *);
void lines_free(Lines *);
Words split_words(char *);
FILE *open_file(const char *, const char *);
char *read_line(FILE *);
char *cell_text(const Grid *, int);
char *conflict_text(const Grid *, Conflict);
char action(const Grid *, int, int);
char *actions(const Grid *, const Path *);
char *fraction(int, int);
char *integers(const int *, int);
void write_lines(const char *, const Lines *);
const char *solver_name(Solver);
const char *cost_function(bool);
#endif
