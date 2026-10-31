#ifndef SPC_H
#define SPC_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#define MAX_SAMPLES 1000
#define MAX_GROUPS 100
#define MAX_LOTS 100

typedef struct { int values[MAX_SAMPLES],count; } Numbers;
typedef struct { int values[8],count; } RuleSet;
typedef struct {
 char name[33];int lsl,usl,target,size,phase1,passes,span,gap,bin,window,step;
 double k,h,lambda,e,z;RuleSet rules[7];
} Settings;
typedef struct {double a2,a3,b3,b4,d3,d4,d2,c4;} Constants;
typedef struct {int number,inspected,defectives,defects;} Lot;
typedef struct {Settings settings;int values[MAX_SAMPLES],count;Lot lots[MAX_LOTS];int lot_count;} Dataset;
typedef struct {int values[10],count;int64_t total,squares,range;double mean,sd;} Subgroup;
typedef struct {double lcl,cl,ucl;} Limits;
typedef struct {int numbers[MAX_SAMPLES],count;double values[MAX_SAMPLES];} Series;
typedef struct {double value,fraction;} Center;
typedef struct {double value,lcl,ucl,z;int status;} LotPoint;
typedef struct {int chart,rule,start,end;double value;int direction;} Signal;
typedef struct {Signal *data;int count,capacity;} Signals;
typedef struct {Limits limits;double u1,u2,l1,l2;} Zones;
typedef struct {
 int count,below,above,values[MAX_SAMPLES];
 double mean,within,sbar,overall,cp,cpu,cpl,cpk,pp,ppu,ppl,ppk,cpm,ppm,cpk_ci[2],ppk_ci[2];
 const char *verdict;
} Capability;
extern const Constants control_constants[9];
extern const char *const chart_names[9];
extern const char *const family_names[3];
extern const char *const attribute_names[4];
Dataset read_dataset(void);
int subgroup_statistics(const Dataset *data,Subgroup *groups);
void family_limits(int family,const Numbers *chosen,const Subgroup *groups,const Dataset *data,Limits limits[2]);
void family_series(int family,const Numbers *chosen,const Subgroup *groups,const Dataset *data,Series series[2]);
bool outside(Limits limits,double value);
Center attribute_center(int chart,const Numbers *chosen,const Dataset *data);
LotPoint attribute_point(int chart,Lot lot,Center center);
Zones chart_zones(Limits limits);
const char *zone_name(Limits limits,double value);
void append_signal(Signals *signals,Signal signal);
Signals check_rules(int chart,const Series *series,Limits limits,const RuleSet *rules);
Capability capability(const Numbers *chosen,const Subgroup *groups,const Settings *s,Constants c);
void histogram(FILE *file,const Capability *result,const Settings *s);
void limits_band(char band[62],Limits limits,double value,bool signalled);
void cusum_band(char band[62],double upper,double lower,double h,bool up,bool down);
void width_band(char band[62],double scale,double width,double value,double center,bool signalled);
void standard_band(char band[62],double z,bool ok);

#endif
