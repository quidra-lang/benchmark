#ifndef AIRSPACE_H
#define AIRSPACE_H
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
typedef int64_t Integer;
#define DEFINE_VECTOR(Name, Type)                                                                  \
    typedef struct {                                                                               \
        Type *items;                                                                               \
        size_t count, capacity;                                                                    \
    } Name;                                                                                        \
    static inline void Name##_append(Name *list, Type value) {                                     \
        if (list->count == list->capacity) {                                                       \
            list->capacity = list->capacity ? 2 * list->capacity : 4;                              \
            list->items = realloc(list->items, list->capacity * sizeof *list->items);              \
        }                                                                                          \
        list->items[list->count++] = value;                                                        \
    }
typedef struct {
    char text[32];
} Name;
DEFINE_VECTOR(Names, Name)
DEFINE_VECTOR(Integers, Integer)
typedef struct {
    char name[9];
    int climb, descent, minimum;
} AircraftType;
typedef struct {
    int x, y;
    bool has_level;
    Integer level;
} Waypoint;
typedef struct {
    char callsign[9];
    int type;
    Integer departure, delay, level, offset;
    int speed_initial, speed;
    Waypoint waypoints[8];
    int waypoint_count;
    Names history;
} Plan;
typedef struct {
    char name[9];
    int x1, y1, x2, y2;
    Integer lower, upper, capacity;
} Sector;
typedef struct {
    Integer horizontal, vertical, lookahead, max_delay, level_min, level_max, sample_start,
        sample_end, radar[6], leader, alert;
    Integers snapshots;
} Params;
typedef struct {
    Plan plans[100];
    int plan_count;
    AircraftType types[10];
    int type_count;
    Sector sectors[20];
    int sector_count;
    Params params;
} Input;
void read_inputs(Input *out);
int flight_levels(const Plan *plan, Integer out[8]);
typedef struct {
    double v[3];
} Point;
typedef struct {
    int first, second;
} Pair;
typedef enum { CLIMB, DESCENT, LEVEL } Phase;
const char *phase_name(Phase phase);
typedef struct {
    int number, leg;
    Phase phase;
    double start_time, end_time;
    Point start, velocity, end;
} Segment;
typedef struct {
    double time;
    Integer level;
} Passing;
typedef struct {
    Segment segments[14];
    int count;
    double arrival, length;
    Passing passing[8];
} Trajectory;
void build_trajectory(const Plan *plan, const AircraftType *types, Trajectory *out);
Point position(const Segment *segment, double time);
const Segment *active_segment(const Trajectory *trajectory, double time);
typedef struct {
    double low, high, time, distance, vertical;
} Loss;
bool loss_interval(Point relative, Point velocity, double first, double last, double horizontal,
                   double vertical, Loss *out);
typedef struct {
    int first_segment, second_segment;
    Loss loss;
} Piece;
DEFINE_VECTOR(Pieces, Piece)
typedef struct {
    Pair pair;
    double start, end;
    Pieces pieces;
    Piece closest;
    double first_level, second_level, first_track, second_track, angle;
    int geometry, severity, sector, outcome;
} Conflict;
DEFINE_VECTOR(Conflicts, Conflict)
int conflict_compare(const void *left, const void *right);
Conflicts pair_conflicts(int first, const Trajectory *first_trajectory, int second,
                         const Trajectory *second_trajectory, const Params *params);
Conflicts all_conflicts(const Trajectory *trajectories, int count, const Params *params);
void free_conflicts(Conflicts *list);
typedef enum { CHANGE_LEVEL, CHANGE_SPEED, CHANGE_DELAY } ManoeuvreKind;
typedef struct {
    Name name;
    ManoeuvreKind kind;
    Integer amount;
} Manoeuvre;
DEFINE_VECTOR(Manoeuvres, Manoeuvre)
Manoeuvres manoeuvres(Integer max_delay);
bool propose(const Plan *plan, const Manoeuvre *manoeuvre, const AircraftType *types,
             const Params *params, Plan *out);
void priority_order(int first, int second, const Plan *plans, int out[2]);
const char *decimal(double value, int digits), *signed_integer(Integer value);
char *joined(const Names *names);
FILE *open_output(const char *name);
void frame(FILE *file, char *const *grid, size_t width, size_t height);
#endif
