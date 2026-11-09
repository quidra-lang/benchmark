#ifndef RAILWAY_H
#define RAILWAY_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

typedef enum { DIR_UP, DIR_DOWN } Direction;
typedef enum { ASPECT_RED, ASPECT_YELLOW, ASPECT_GREEN } Aspect;
typedef enum { ROUTE_NONE, ROUTE_LOCKED, ROUTE_USED, ROUTE_APPROACH } RouteState;
typedef enum { TRAIN_WAITING, TRAIN_RUNNING, TRAIN_EXITED } TrainState;
typedef enum { END_SECTION, END_POINT, END_BUFFER, END_BOUNDARY, END_IMPASSABLE } EndKind;
typedef struct {
    EndKind kind;
    int index;
    bool common;
} Endpoint;
typedef struct {
    char name[13];
    int length, row, first, last;
    bool failed;
    uint32_t occupants, trains;
    int route;
    uint64_t overlaps;
    int occupied_ticks, locked_ticks;
} Section;
typedef struct {
    char name[13], side, position, target;
    int common, normal, reverse, row, col, completion;
    bool moving, failed;
    uint64_t normal_locks, reverse_locks;
    int throws, locked_ticks, moving_ticks;
} Point;
typedef struct {
    char name[13];
    int section, row, col;
    Direction direction;
    Aspect aspect;
    int ticks[3], passes;
} Signal;
typedef struct {
    char name[13], end;
    int section, row, col;
} Buffer;
typedef struct {
    char name[13], end;
    int section;
} Boundary;
typedef struct {
    int row, col;
    char text[152];
} Label;
typedef struct {
    Section sections[40];
    Point points[20];
    Signal signals[30];
    Buffer buffers[10];
    Boundary boundaries[10];
    Label labels[20];
    int section_count, point_count, signal_count, buffer_count, boundary_count, label_count, height,
        width;
    Endpoint ends[40][2];
    int signal_at[40][2];
} Layout;
typedef struct {
    int point;
    char position;
} Requirement;
typedef struct {
    char name[13], finish[13];
    int start;
    Direction direction;
    RouteState state;
    Requirement *points, *flank;
    size_t point_count, flank_count;
    int sections[10], overlap[5], section_count, overlap_count;
    int *conflicts;
    size_t conflict_count;
    char *conflict_text;
    int approach, release_time, overlap_counter;
    bool overlap_locked, passed[40];
    int requests, grants, uses, cancels, wait, maxwait, locked_ticks;
} Route;
typedef struct {
    Route routes[40];
    int count;
} Interlocking;
typedef struct {
    bool turn;
    int section, dwell, scheduled_arrival, scheduled_departure, arrival, departure;
} Stop;
typedef struct {
    int section, start;
} PathSection;
typedef struct {
    char name[13], symbol;
    int length, acceleration, deceleration, max_speed, entry, scheduled_entry, entry_speed,
        actual_entry, exit, scheduled_exit, actual_exit;
    Stop stops[5];
    int stop_count;
    TrainState state;
    Direction direction;
    PathSection path[40];
    int path_count, head, speed, next_stop;
    bool dwelling;
    int await_departure;
    bool emergency, crossed;
    int boundary_coordinate, distance, recorded_max, standing, passes;
} Train;
typedef struct {
    int train, route, time;
} TrainRequest;
typedef struct {
    char **items;
    size_t count, capacity;
} TextLines;
typedef struct {
    int checks[4], violations[4];
    TextLines records;
} Safety;
typedef struct {
    char *items[32];
    int count;
} Words;
void *checked_realloc(void *, size_t);
char *copy_string(const char *);
char *format_text(const char *, ...);
FILE *open_file(const char *, const char *);
char *read_line(FILE *);
Words split_words(char *);
void lines_add(TextLines *, char *);
void lines_free(TextLines *);
int bit_count(uint64_t);
int section_index(const Layout *, const char *);
int point_index(const Layout *, const char *);
int signal_index(const Layout *, const char *);
int buffer_index(const Layout *, const char *);
int boundary_index(const Layout *, const char *);
int route_index(const Interlocking *, const char *);
bool occupied(const Section *);
bool detected(const Point *);
void read_layout(Layout *);
Endpoint beyond(const Layout *, int, Direction);
void read_interlocking(Interlocking *, Layout *);
Requirement requirement_at(const Route *, size_t);
size_t requirement_count(const Route *);
void lock_route(Interlocking *, Layout *, int);
void unlock_section(Interlocking *, Layout *, int, int);
void unlock_overlap(Interlocking *, Layout *, int);
void release_route(Interlocking *, Layout *, int);
void signal_aspects(const Layout *, const Interlocking *, Aspect[30]);
void read_trains(Layout *, Interlocking *, Train[26], int *, TrainRequest[500], int *);
int braking_distance(int, int);
int select_speed(const Train *, int);
PathSection head_section(const Train *);
int occupied_sections(const Train *, const Layout *, PathSection[40]);
void safety_violation(Safety *, int, int, const char *);
void safety_signal_passing(Safety *, int, const Train *, const Signal *);
void safety_check(Safety *, int, const Layout *, const Interlocking *, const Train[26], int);
void safety_write(const Safety *, FILE *);
extern const char *const direction_names[2],
    *const aspect_names[3], *const route_state_names[4], *const train_state_names[3];
#endif
