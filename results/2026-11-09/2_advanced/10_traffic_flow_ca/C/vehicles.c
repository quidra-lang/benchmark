#include "traffic.h"

int vehicle_maximum(const Vehicle *v) { return minimum(v->class->vmax,v->segment->limit); }
void vehicle_place(Vehicle *v,Segment *s,int lane,int cell) { if(v->segment) v->segment->cells[v->lane][v->cell]=0; s->cells[lane][cell]=v->number; v->segment=s; v->lane=lane; v->cell=cell; }
void vehicle_leave(Vehicle *v) { v->segment->cells[v->lane][v->cell]=0; v->segment=NULL; }
bool vehicle_heading(const Vehicle *v) { Segment *s=v->segment; return s && v->class->stops && s->stop && !(v->completed&(UINT32_C(1)<<s->index)) && v->cell<=s->stop->cell; }
i64 vehicle_travel(const Vehicle *v) { return v->exited-v->inserted+1; }
int random_slowdown(int speed,int previous,i64 value,int p,int p0) { int probability=previous==0?p0:p; return speed>0 && value%1000<probability?speed-1:speed; }
