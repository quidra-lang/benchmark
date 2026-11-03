#ifndef TIMETABLE_H
#define TIMETABLE_H
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <errno.h>
#include <stddef.h>

enum { MAX_COURSES = 100, MAX_STUDENTS = 3000, MAX_ROOMS = 20, MAX_SLOTS = 35 };
typedef struct { char **items; int count, capacity; } Lines;
typedef struct { int items[MAX_COURSES], count; } Courses;
typedef struct { char id[9], name[41]; int duration, size, students[MAX_STUDENTS]; } Course;
typedef struct { char id[9]; int courses[12], count; bool unavailable[MAX_SLOTS + 1]; } Student;
typedef struct { char id[9]; int capacity; } Room;
typedef struct { int course, room, first, last; } Placement;
typedef struct { int later, earlier; } Order;
typedef struct { int course, slot, saturation; } Choice;
typedef struct { int size, dead_ends, failed_course; } AttemptRecord;
typedef struct { int course, slot, increase; } Insertion;
typedef struct { int counts[3], late, total; } Breakdown;
typedef struct { int counts[3], total; Courses assigned; } StudentStats;
typedef struct {
    Course courses[MAX_COURSES]; Student students[MAX_STUDENTS]; Room rooms[MAX_ROOMS];
    int course_count, student_count, room_count, enrolment_count;
    int shared[MAX_COURSES][MAX_COURSES], degree[MAX_COURSES];
    int days, periods, lengths[5], limit, weights[4], front_count, deadline, ratio, slots, largest_room;
    bool closed[MAX_SLOTS + 1], fixed_slots[MAX_SLOTS + 1], excluded[MAX_COURSES];
    int fixed[MAX_COURSES], assignment[MAX_COURSES]; Order orders[100]; int order_count;
    Courses empty, oversized, schedulable, vertices, front_load;
    Lines errors, exchange_log, swap_log; char *reasons[MAX_COURSES][MAX_SLOTS + 1];
    AttemptRecord attempts[MAX_COURSES + 1]; int attempt_count;
    Choice choices[MAX_COURSES]; int choice_count;
    Insertion insertions[MAX_COURSES]; int insertion_count;
    Breakdown initial, exchanged, final; int penalty;
    Placement placements[MAX_COURSES], packed[MAX_SLOTS + 1][MAX_COURSES];
    int packed_count[MAX_SLOTS + 1], contributions[MAX_COURSES];
    StudentStats statistics[MAX_STUDENTS];
} Scheduler;
typedef struct {
    Scheduler *scheduler; Courses pending; int dead_ends, dead_end_course, choice_count;
    bool aborted; Choice choices[MAX_COURSES];
} Attempt;
typedef struct { Courses members; } Component;

void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
void append_lines(Lines *target, const Lines *source);
Lines read_lines(const char *path);
void write_lines(const char *name, const Lines *lines);
char *fixed_width(const char *label, char *const *cells, int count, int label_width, int cell_width);
int rounded_percent(int part, int whole);
void load_courses(Scheduler *scheduler);
void load_enrolments(Scheduler *scheduler);
int find_course(const Scheduler *scheduler, const char *id);
int find_student(const Scheduler *scheduler, const char *id);
void sort_courses(const Scheduler *scheduler, Courses *courses, const int *values);
void load_rooms(Scheduler *scheduler);
bool pack(const Scheduler *scheduler, Courses courses, Placement *placements);
void build_graph(Scheduler *scheduler);
int components(const Scheduler *scheduler, Component *result);
Courses greedy_clique(const Scheduler *scheduler);
Courses kempe_chain(const Scheduler *scheduler, int start, int home, int target);
bool reachable(const Scheduler *scheduler, int source, int target);
bool search_attempt(Attempt *attempt);
int greedy_numbering(const Scheduler *scheduler, Courses order);
Courses candidate_slots(const Scheduler *scheduler, int course, const int *assignment);
int saturation(const Scheduler *scheduler, int course, const int *assignment);
#endif
