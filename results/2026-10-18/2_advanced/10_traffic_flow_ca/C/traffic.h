#ifndef TRAFFIC_H
#define TRAFFIC_H
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

typedef int64_t i64;
typedef struct Segment Segment;
typedef struct Vehicle Vehicle;
typedef struct Source Source;
typedef struct Junction Junction;
typedef struct { char **data; size_t count,capacity; } Lines;
typedef struct { i64 state; } Minstd;
typedef struct { Segment *target; int weight; i64 vehicles; } Turn;
typedef struct { Segment *segment; int cell,dwell; i64 buses; } BusStop;
typedef struct { int duration; char token[270]; uint32_t greens; } Phase;
struct Junction { char node[9]; int offset,cycle,count; Phase phases[8]; };
struct Segment {
 char id[9],from[9],to[9]; int index,length,lanes,limit,cells[3][200]; Junction *junction;
 Turn turns[30]; int turn_count; BusStop *stop;
 i64 entered,vehicle_sum,speed_sum,green_count,queue_sum,failures,passed,blocked,changes[3];
 int max_vehicles,max_queue;
};
typedef struct { Segment *segment; int lane,cell,state,active_start,active_end; i64 start,end; } Incident;
typedef struct { char name[9]; int vmax,weight; bool overtake,stops; } VehicleClass;
struct Vehicle {
 int number; VehicleClass *class; Source *source; int arrival,inserted,exited;
 char sink[9]; Segment *segment; int lane,cell,speed; Turn *turn;
 Segment *route[30]; int route_count; i64 steps,distance,stopped_steps,stop_count,lane_changes;
 int dwell; uint32_t completed; Lines trajectory;
};
void *resize(void *pointer,size_t bytes);
void add_line(Lines *lines,const char *format,...);
void free_lines(Lines *lines);
i64 draw(Minstd *random);
int select_weight(const int *weights,int count,i64 value);
int road_free(const Segment *s,int lane,int x,int cap);
int road_first(const Segment *s,int lane);
bool road_safe(const Segment *s,int lane,int x);
void road_cells(const Segment *s,int lane,Vehicle *const *vehicles,char *text);
const char *incident_update(Incident *incident,int t);
int vehicle_maximum(const Vehicle *vehicle);
void vehicle_place(Vehicle *vehicle,Segment *segment,int lane,int cell);
void vehicle_leave(Vehicle *vehicle);
bool vehicle_heading(const Vehicle *vehicle);
i64 vehicle_travel(const Vehicle *vehicle);
int random_slowdown(int speed,int previous,i64 value,int p,int p0);
bool signal_green(const Junction *junction,const Segment *segment,int t);
void signal_plan(FILE *file,const Junction *junction);
i64 gcd(i64 a,i64 b);
const char *decimal(i64 numerator,i64 denominator,int places);
const char *fraction(i64 numerator,i64 denominator);
i64 percentile(const i64 *times,size_t count,int q);
void histogram(FILE *file,const i64 *times,size_t count,i64 width);
static inline int minimum(int a,int b) { return a<b?a:b; }
static inline int maximum(int a,int b) { return a>b?a:b; }
#endif
