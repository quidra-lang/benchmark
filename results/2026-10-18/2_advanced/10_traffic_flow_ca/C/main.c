#include "traffic.h"
#include <sys/stat.h>

#define APPEND(values,count,capacity,value) do { if((count)==(capacity)) { (capacity)=(capacity)?(capacity)*2:8; (values)=resize((values),(capacity)*sizeof(*(values))); } (values)[(count)++]=(value); } while(0)

typedef struct { i64 n,d; } Ratio;
typedef struct { Segment *segments[30]; int count; Ratio share; char sink[9]; } Route;
typedef struct { int rate; i64 end; } Rate;
struct Source { char node[9]; Segment *entry; Rate *rates; size_t rate_count,rate_capacity; int *queue; size_t queue_count,queue_capacity,head; int wait,maximum; Route routes[30]; int route_count; };
typedef struct { i64 passing,occupancy,speed; } DetectorTotal;
typedef struct { char name[9]; Segment *segment; int cell,width; DetectorTotal *totals; } Detector;
typedef struct { Segment *segment; int lane,start,end; Lines lines; } Diagram;
typedef struct { int length,vmax,warm,measure; i64 seed; int *counts; size_t count,capacity; } Ring;
typedef struct { i64 arrived,inserted,exited,steps,speed; } Interval;
typedef struct {
 Segment segments[30]; int segment_count; Junction junctions[30]; int junction_count; BusStop stops[30]; int stop_count;
 Incident *incidents; size_t incident_count,incident_capacity;
 VehicleClass classes[9]; int class_count; Source sources[30]; int source_count; char sinks[30][9]; int sink_count;
 Detector *detectors; size_t detector_count,detector_capacity; Diagram *diagrams; size_t diagram_count,diagram_capacity;
 i64 *tracks; size_t track_count,track_capacity; bool tracked[100001]; Ring *rings; size_t ring_count,ring_capacity;
 Minstd random; int steps,p,p0,interval; i64 bin; Vehicle **vehicles; int vehicle_count; Interval *totals; Lines events;
} Simulation;
typedef struct { Vehicle *vehicle; int lane,kind; } LaneChange;
typedef struct { Vehicle *vehicle; Segment *segment; int cell,u; } Move;

void *resize(void *pointer,size_t bytes) { void *result=realloc(pointer,bytes); if(!result && bytes) abort(); return result; }
void add_line(Lines *lines,const char *format,...) {
 va_list args,copy; va_start(args,format); va_copy(copy,args); int length=vsnprintf(NULL,0,format,copy); va_end(copy); if(length<0) abort(); char *text=resize(NULL,(size_t)length+1); vsnprintf(text,(size_t)length+1,format,args); va_end(args); APPEND(lines->data,lines->count,lines->capacity,text);
}
void free_lines(Lines *lines) { for(size_t i=0;i<lines->count;i++) free(lines->data[i]); free(lines->data); }
static void write_lines(FILE *file,const Lines *lines) { for(size_t i=0;i<lines->count;i++) fprintf(file,"%s\n",lines->data[i]); }
static char *read_line(FILE *file) {
 char *line=NULL; size_t n=0,cap=0; int c;
 while((c=fgetc(file))!=EOF && c!='\n') { if(n+1>=cap) { cap=cap?cap*2:128; line=resize(line,cap); } line[n++]=(char)c; }
 if(c==EOF && n==0) { free(line); return NULL; } if(n+1>=cap) line=resize(line,n+1); line[n]=0; return line;
}
static char **split(char *line,size_t *count) {
 char **parts=NULL; size_t capacity=0; *count=0; char *begin=line;
 for(char *p=line;;p++) if(*p==' ' || *p==0) { bool last=*p==0; *p=0; APPEND(parts,*count,capacity,begin); if(last) break; begin=p+1; }
 return parts;
}
static i64 number(const char *text) { return strtoll(text,NULL,10); }
static Segment *find_segment(Simulation *m,const char *id) { for(int i=0;i<m->segment_count;i++) if(strcmp(m->segments[i].id,id)==0) return &m->segments[i]; abort(); }
static Ratio ratio(i64 n,i64 d) { i64 g=gcd(n,d); return (Ratio){n/g,d/g}; }
static Ratio multiply(Ratio r,i64 n,i64 d) { i64 a=gcd(r.n,d),b=gcd(n,r.d); return ratio((r.n/a)*(n/b),(r.d/b)*(d/a)); }
static Ratio add(Ratio r,Ratio s) { i64 g=gcd(r.d,s.d); return ratio(r.n*(s.d/g)+s.n*(r.d/g),r.d*(s.d/g)); }
static void enumerate(Source *source,Segment *s,Segment **path,int depth,Ratio share) {
 path[depth]=s;
 if(!s->junction) { Route *r=&source->routes[source->route_count++]; r->count=depth+1; memcpy(r->segments,path,(size_t)r->count*sizeof(*path)); r->share=share; strcpy(r->sink,s->to); return; }
 int total=0; for(int i=0;i<s->turn_count;i++) total+=s->turns[i].weight;
 for(int i=0;i<s->turn_count;i++) { Turn *turn=&s->turns[i]; enumerate(source,turn->target,path,depth+1,multiply(share,turn->weight,total)); }
}
static FILE *input_file(const char *path) { FILE *file=fopen(path,"r"); if(!file) abort(); return file; }
static Simulation *read_simulation(void) {
 Simulation *m=calloc(1,sizeof(*m)); if(!m) abort(); m->vehicles=calloc(100000,sizeof(*m->vehicles)); if(!m->vehicles) abort();
 FILE *file=input_file("input/network.txt"); char *line;
 while((line=read_line(file))) {
  size_t count; char **p=split(line,&count);
  if(strcmp(p[0],"SEGMENT")==0) { Segment *s=&m->segments[m->segment_count]; s->index=m->segment_count++; strcpy(s->id,p[1]); strcpy(s->from,p[2]); strcpy(s->to,p[3]); s->length=(int)number(p[4]); s->lanes=(int)number(p[5]); s->limit=(int)number(p[6]); }
  else if(strcmp(p[0],"JUNCTION")==0) {
   Junction *j=&m->junctions[m->junction_count++]; strcpy(j->node,p[1]); j->offset=(int)number(p[2]);
   for(size_t k=3;k<count;k++) { Phase *ph=&j->phases[j->count++]; char *colon=strchr(p[k],':'); *colon=0; ph->duration=(int)number(p[k]); j->cycle+=ph->duration; strcpy(ph->token,colon+1); if(strcmp(ph->token,"-")!=0) { char greens[270]; strcpy(greens,ph->token); for(char *id=strtok(greens,",");id;id=strtok(NULL,",")) ph->greens|=UINT32_C(1)<<find_segment(m,id)->index; } }
  }
  else if(strcmp(p[0],"INCIDENT")==0) { Incident i={.segment=find_segment(m,p[1]),.lane=(int)number(p[2])-1,.cell=(int)number(p[3]),.start=number(p[4]),.end=number(p[5])}; APPEND(m->incidents,m->incident_count,m->incident_capacity,i); }
  else if(strcmp(p[0],"STOP")==0) { BusStop *s=&m->stops[m->stop_count++]; s->segment=find_segment(m,p[1]); s->cell=(int)number(p[2]); s->dwell=(int)number(p[3]); s->segment->stop=s; }
  free(p); free(line);
 }
 fclose(file);
 for(int i=0;i<m->segment_count;i++) for(int k=0;k<m->junction_count;k++) if(strcmp(m->segments[i].to,m->junctions[k].node)==0) m->segments[i].junction=&m->junctions[k];
 file=input_file("input/demand.txt");
 while((line=read_line(file))) {
  size_t count; char **p=split(line,&count);
  if(strcmp(p[0],"CLASS")==0) { VehicleClass *c=&m->classes[m->class_count++]; strcpy(c->name,p[1]); c->vmax=(int)number(p[2]); c->weight=(int)number(p[3]); c->overtake=strcmp(p[4],"Y")==0; c->stops=strcmp(p[5],"Y")==0; }
  else if(strcmp(p[0],"SOURCE")==0) { Source *s=&m->sources[m->source_count++]; strcpy(s->node,p[1]); for(int i=0;i<m->segment_count;i++) if(strcmp(m->segments[i].from,s->node)==0) s->entry=&m->segments[i]; for(size_t k=2;k<count;k++) { char *colon=strchr(p[k],':'); *colon=0; Rate r={(int)number(p[k]),number(colon+1)}; APPEND(s->rates,s->rate_count,s->rate_capacity,r); } }
  else if(strcmp(p[0],"SINK")==0) strcpy(m->sinks[m->sink_count++],p[1]);
  else if(strcmp(p[0],"TURN")==0) { Segment *s=find_segment(m,p[1]); Turn *turn=&s->turns[s->turn_count++]; turn->target=find_segment(m,p[2]); turn->weight=(int)number(p[3]); }
  free(p); free(line);
 }
 fclose(file); file=input_file("input/params.txt");
 while((line=read_line(file))) {
  size_t count; char **p=split(line,&count);
  if(strcmp(p[0],"seed")==0) m->random.state=number(p[1]);
  else if(strcmp(p[0],"steps")==0) m->steps=(int)number(p[1]);
  else if(strcmp(p[0],"dawdle")==0) { m->p=(int)number(p[1]); m->p0=(int)number(p[2]); }
  else if(strcmp(p[0],"interval")==0) m->interval=(int)number(p[1]);
  else if(strcmp(p[0],"bin")==0) m->bin=number(p[1]);
  else if(strcmp(p[0],"detector")==0) { Detector d={.segment=find_segment(m,p[2]),.cell=(int)number(p[3]),.width=(int)number(p[4])}; strcpy(d.name,p[1]); APPEND(m->detectors,m->detector_count,m->detector_capacity,d); }
  else if(strcmp(p[0],"diagram")==0) { Diagram d={.segment=find_segment(m,p[1]),.lane=(int)number(p[2])-1,.start=(int)number(p[3]),.end=(int)number(p[4])}; APPEND(m->diagrams,m->diagram_count,m->diagram_capacity,d); }
  else if(strcmp(p[0],"track")==0) { for(size_t k=1;k<count;k++) { i64 id=number(p[k]); APPEND(m->tracks,m->track_count,m->track_capacity,id); if(id<=100000) m->tracked[id]=true; } }
  else if(strcmp(p[0],"ring")==0) { Ring r={.length=(int)number(p[1]),.vmax=(int)number(p[2]),.warm=(int)number(p[3]),.measure=(int)number(p[4]),.seed=number(p[5])}; for(size_t k=6;k<count;k++) { int n=(int)number(p[k]); APPEND(r.counts,r.count,r.capacity,n); } APPEND(m->rings,m->ring_count,m->ring_capacity,r); }
  free(p); free(line);
 }
 fclose(file); size_t intervals=(size_t)(m->steps/m->interval); m->totals=calloc(intervals,sizeof(*m->totals)); if(!m->totals) abort();
 for(size_t i=0;i<m->detector_count;i++) { m->detectors[i].totals=calloc(intervals,sizeof(DetectorTotal)); if(!m->detectors[i].totals) abort(); }
 Segment *path[30]; for(int i=0;i<m->source_count;i++) enumerate(&m->sources[i],m->sources[i].entry,path,0,(Ratio){1,1});
 return m;
}
static void enter(Simulation *m,Vehicle *v,Segment *s) {
 v->route[v->route_count++]=s; s->entered++; v->turn=NULL;
 if(s->junction) { int weights[30]; for(int i=0;i<s->turn_count;i++) weights[i]=s->turns[i].weight; v->turn=&s->turns[select_weight(weights,s->turn_count,draw(&m->random))]; }
}
static int desired_lane(const Vehicle *v,int *kind) {
 Segment *s=v->segment; int lane=v->lane,x=v->cell,V=vehicle_maximum(v),here=road_free(s,lane,x,V+1),want=minimum(v->speed+1,V);
 if(here<V+1 && x+here+1<s->length && s->cells[lane][x+here+1]<0) { int choices[]={lane+1,lane-1}; for(int i=0;i<2;i++) { int l=choices[i]; if(l>=0 && l<s->lanes && road_free(s,l,x,V+1)>here && road_safe(s,l,x)) { *kind=2; return l; } } }
 if(vehicle_heading(v)) { if(lane>=1 && road_safe(s,lane-1,x)) { *kind=1; return lane-1; } return lane; }
 if(v->class->overtake && lane+1<s->lanes && here<want && road_free(s,lane+1,x,V+1)>here && road_safe(s,lane+1,x)) { *kind=0; return lane+1; }
 if(lane>=1 && road_free(s,lane-1,x,V+1)>want && road_safe(s,lane-1,x)) { *kind=1; return lane-1; }
 return lane;
}
static void run(Simulation *m) {
 int weights[9]; for(int i=0;i<m->class_count;i++) weights[i]=m->classes[i].weight;
 LaneChange *changes=NULL; Move *moves=NULL; size_t change_capacity=0,move_capacity=0;
 for(int t=1;t<=m->steps;t++) {
  for(size_t k=0;k<m->incident_count;k++) { Incident *i=&m->incidents[k]; const char *event=incident_update(i,t); if(event) add_line(&m->events,"%04d %s %s lane %d cell %d",t,event,i->segment->id,i->lane+1,i->cell); }
  int index=(t-1)/m->interval; Interval *interval=&m->totals[index];
  for(int k=0;k<m->source_count;k++) { Source *s=&m->sources[k]; int rate=0; for(size_t i=0;i<s->rate_count;i++) if(t<=s->rates[i].end) { rate=s->rates[i].rate; break; }
   if(draw(&m->random)%1000<rate) { int c=select_weight(weights,m->class_count,draw(&m->random)); Vehicle *v=calloc(1,sizeof(*v)); if(!v) abort(); v->number=m->vehicle_count+1; v->class=&m->classes[c]; v->source=s; v->arrival=t; m->vehicles[m->vehicle_count++]=v; APPEND(s->queue,s->queue_count,s->queue_capacity,v->number); interval->arrived++; }
  }
  for(int k=0;k<m->source_count;k++) { Source *source=&m->sources[k]; Segment *s=source->entry;
   while(source->head<source->queue_count) { int lane=-1,first=-1; for(int l=0;l<s->lanes;l++) if(s->cells[l][0]==0 && road_first(s,l)>first) { lane=l; first=road_first(s,l); } if(lane<0) break; Vehicle *v=m->vehicles[source->queue[source->head++]-1]; vehicle_place(v,s,lane,0); v->inserted=t; enter(m,v,s); interval->inserted++; }
   int waiting=(int)(source->queue_count-source->head); if(waiting>0 && source->wait==0) { source->wait=t; source->maximum=0; } if(source->wait!=0) { source->maximum=maximum(source->maximum,waiting); if(waiting==0) { add_line(&m->events,"%04d QUEUE %s from %d max %d",t,source->node,source->wait,source->maximum); source->wait=0; } }
  }
  size_t change_count=0;
  for(int k=0;k<m->segment_count;k++) { Segment *s=&m->segments[k]; if(s->lanes<2) continue; bool reserved[3][200]={{false}};
   for(int l=0;l<s->lanes;l++) for(int x=0;x<s->length;x++) { int id=s->cells[l][x]; if(id<=0) continue; Vehicle *v=m->vehicles[id-1]; if(v->dwell>0) continue; int kind=-1,lane=desired_lane(v,&kind); if(lane!=l && !reserved[lane][x]) { reserved[lane][x]=true; LaneChange change={v,lane,kind}; APPEND(changes,change_count,change_capacity,change); } }
  }
  for(size_t k=0;k<change_count;k++) { LaneChange c=changes[k]; Vehicle *v=c.vehicle; Segment *s=v->segment; vehicle_place(v,s,c.lane,v->cell); v->lane_changes++; s->changes[c.kind]++; }
  size_t move_count=0;
  for(int k=0;k<m->segment_count;k++) { Segment *s=&m->segments[k]; for(int l=0;l<s->lanes;l++) for(int x=s->length-1;x>=0;x--) { int id=s->cells[l][x]; if(id<=0) continue; Vehicle *v=m->vehicles[id-1]; int a=minimum(v->speed+1,vehicle_maximum(v)),gap=road_free(s,l,x,a);
   if(gap<a && x+gap==s->length-1) { if(!s->junction) gap=a; else if(signal_green(s->junction,s,t)) { Segment *target=v->turn->target; gap+=road_free(target,minimum(l,target->lanes-1),-1,a-gap); } }
   if(vehicle_heading(v)) gap=minimum(gap,s->stop->cell-x); int u=random_slowdown(minimum(a,gap),v->speed,draw(&m->random),m->p,m->p0); if(v->dwell>0) { u=0; v->dwell--; } Move move={v,s,x,u}; APPEND(moves,move_count,move_capacity,move);
  } }
  for(size_t k=0;k<move_count;k++) { Move *move=&moves[k]; Vehicle *v=move->vehicle; Segment *s=move->segment; int x=move->cell;
   if(x+move->u<s->length) vehicle_place(v,s,v->lane,x+move->u); else if(!s->junction) { vehicle_leave(v); v->exited=t; strcpy(v->sink,s->to); interval->exited++; }
  }
  for(size_t k=0;k<move_count;k++) { Move *move=&moves[k]; Vehicle *v=move->vehicle; Segment *s=move->segment; int x=move->cell; if(x+move->u<s->length || !s->junction) continue;
   Turn *turn=v->turn; Segment *target=turn->target; int lane=minimum(v->lane,target->lanes-1),want=x+move->u-s->length,pos=minimum(want,road_first(target,lane)-1); if(pos<want) s->blocked++;
   if(pos>=0) { vehicle_place(v,target,lane,pos); move->u=s->length-x+pos; s->passed++; turn->vehicles++; enter(m,v,target); } else { vehicle_place(v,s,v->lane,s->length-1); move->u=s->length-1-x; }
  }
  for(size_t k=0;k<move_count;k++) { Move *move=&moves[k]; Vehicle *v=move->vehicle; int u=move->u;
   v->steps++; v->distance+=u; if(u==0) { v->stopped_steps++; if(v->speed>0) v->stop_count++; } v->speed=u; interval->steps++; interval->speed+=u;
   if(vehicle_heading(v) && v->lane==0 && v->cell==v->segment->stop->cell) { Segment *s=v->segment; v->completed|=UINT32_C(1)<<s->index; v->dwell=s->stop->dwell; s->stop->buses++; add_line(&m->events,"%04d BUS_STOP %d %s cell %d",t,v->number,s->id,v->cell); }
   if(m->tracked[v->number]) { if(v->segment) add_line(&v->trajectory,"%04d %s %d %d %d",t,v->segment->id,v->lane+1,v->cell,v->speed); else add_line(&v->trajectory,"%04d EXIT %d",t,v->speed); }
   for(size_t i=0;i<m->detector_count;i++) { Detector *d=&m->detectors[i]; if(move->segment==d->segment && move->cell<d->cell && (v->segment!=d->segment || v->cell>=d->cell)) d->totals[index].passing++; }
  }
  for(size_t k=0;k<m->detector_count;k++) { Detector *d=&m->detectors[k]; for(int l=0;l<d->segment->lanes;l++) for(int x=d->cell;x<d->cell+d->width;x++) { int id=d->segment->cells[l][x]; if(id>0) { d->totals[index].occupancy++; d->totals[index].speed+=m->vehicles[id-1]->speed; } } }
  for(int k=0;k<m->segment_count;k++) { Segment *s=&m->segments[k]; int count=0,queued=0; i64 speed=0; for(int l=0;l<s->lanes;l++) for(int x=0;x<s->length;x++) { int id=s->cells[l][x]; if(id>0) { Vehicle *v=m->vehicles[id-1]; count++; speed+=v->speed; if(v->speed==0) queued++; } } s->vehicle_sum+=count; s->speed_sum+=speed; s->max_vehicles=maximum(s->max_vehicles,count);
   if(s->junction) { bool green=signal_green(s->junction,s,t); if(green) s->green_count++; s->queue_sum+=queued; s->max_queue=maximum(s->max_queue,queued); if(t<m->steps && queued>0 && green && !signal_green(s->junction,s,t+1)) s->failures++; }
  }
  for(size_t k=0;k<m->diagram_count;k++) { Diagram *d=&m->diagrams[k]; if(d->start<=t && t<=d->end) { char cells[201],signal='E'; road_cells(d->segment,d->lane,m->vehicles,cells); if(d->segment->junction) signal=signal_green(d->segment->junction,d->segment,t)?'G':'R'; add_line(&d->lines,"%04d %s %c",t,cells,signal); } }
 }
 for(int k=0;k<m->source_count;k++) { Source *s=&m->sources[k]; if(s->wait!=0) add_line(&m->events,"%04d QUEUE %s from %d max %d open",m->steps,s->node,s->wait,s->maximum); }
 free(changes); free(moves);
}
static int compare_times(const void *left,const void *right) { i64 a=*(const i64 *)left,b=*(const i64 *)right; return (a>b)-(a<b); }
static void travel_block(FILE *file,const char *heading,Vehicle *const *vehicles,size_t count,i64 bin) {
 i64 *times=resize(NULL,count*sizeof(*times)),total=0; size_t n=0;
 for(size_t i=0;i<count;i++) if(vehicles[i]->exited) { times[n++]=vehicle_travel(vehicles[i]); total+=times[n-1]; }
 if(n==0) { fprintf(file,"%s exited 0\n",heading); free(times); return; }
 qsort(times,n,sizeof(*times),compare_times);
 fprintf(file,"%s exited %zu min %" PRId64 " p50 %" PRId64 " p90 %" PRId64 " max %" PRId64 " mean %s\n",heading,n,times[0],percentile(times,n,50),percentile(times,n,90),times[n-1],decimal(total,(i64)n,2));
 histogram(file,times,n,bin); free(times);
}
static void class_block(FILE *file,const char *heading,Vehicle *const *vehicles,size_t count) {
 i64 inserted=0,exited=0,steps=0,distance=0,travel=0,delay=0,stopped=0,stops=0,changes=0;
 for(size_t i=0;i<count;i++) { const Vehicle *v=vehicles[i]; if(v->inserted) inserted++; steps+=v->steps; distance+=v->distance; if(v->exited) { exited++; travel+=vehicle_travel(v); delay+=v->inserted-v->arrival; stopped+=v->stopped_steps; stops+=v->stop_count; changes+=v->lane_changes; } }
 fprintf(file,"%s\n  generated %zu inserted %" PRId64 " exited %" PRId64 " in_network %" PRId64 " queued %" PRId64 "\n",heading,count,inserted,exited,inserted-exited,(i64)count-inserted);
 fprintf(file,"  vehicle_steps %" PRId64 " distance %" PRId64 " mean_speed %s = %s\n",steps,distance,fraction(distance,steps),decimal(distance,steps,3));
 fprintf(file,"  travel %s entry_delay %s stopped %s stops %s lane_changes %s\n",decimal(travel,exited,2),decimal(delay,exited,2),decimal(stopped,exited,2),decimal(stops,exited,2),decimal(changes,exited,2));
}
static void write_route(FILE *file,Segment *const *segments,int count,const char *separator) { for(int i=0;i<count;i++) fprintf(file,"%s%s",i?separator:"",segments[i]->id); }
static bool same_route(const Vehicle *v,const Route *r) { if(v->route_count!=r->count) return false; for(int i=0;i<r->count;i++) if(v->route[i]!=r->segments[i]) return false; return true; }
typedef struct { int position,speed; } RingCar;
static int compare_cars(const void *left,const void *right) { const RingCar *a=left,*b=right; return (a->position<b->position)-(a->position>b->position); }
static i64 ring_experiment(const Simulation *m,const Ring *r,int count) {
 RingCar *cars=resize(NULL,(size_t)count*sizeof(*cars)); int *speeds=resize(NULL,(size_t)count*sizeof(*speeds)); for(int i=0;i<count;i++) cars[i]=(RingCar){i*r->length/count,0}; Minstd random={r->seed}; i64 total=0;
 for(int t=1;t<=r->warm+r->measure;t++) { qsort(cars,(size_t)count,sizeof(*cars),compare_cars); for(int i=0;i<count;i++) { int ahead=cars[(i+count-1)%count].position,gap=(ahead-cars[i].position-1+r->length)%r->length; speeds[i]=random_slowdown(minimum(minimum(cars[i].speed+1,r->vmax),gap),cars[i].speed,draw(&random),m->p,m->p0); }
  for(int i=0;i<count;i++) { cars[i].position=(cars[i].position+speeds[i])%r->length; cars[i].speed=speeds[i]; if(t>r->warm) total+=speeds[i]; }
 }
 free(cars); free(speeds); return total;
}
static FILE *output_file(const char *name) { char path[64]; snprintf(path,sizeof(path),"output/%s",name); FILE *file=fopen(path,"w"); if(!file) abort(); return file; }
static void output(Simulation *m) {
 mkdir("output",0777);
 FILE *spacetime=output_file("spacetime.txt"),*detectors=output_file("detectors.csv"),*travel=output_file("travel_times.txt"),*classes=output_file("class_stats.txt"),*network=output_file("network_stats.txt"),*timeline=output_file("timeline.csv"),*tracks=output_file("tracks.txt"),*fundamental=output_file("fundamental.csv"),*events=output_file("events.txt");
 for(size_t k=0;k<m->diagram_count;k++) { const Diagram *d=&m->diagrams[k]; fprintf(spacetime,"DIAGRAM %s lane %d steps %d-%d\n",d->segment->id,d->lane+1,d->start,d->end); write_lines(spacetime,&d->lines); }
 fputs("detector,interval,flow,density,speed\n",detectors);
 for(size_t i=0;i<m->detector_count;i++) { const Detector *d=&m->detectors[i]; for(int k=0;k<m->steps/m->interval;k++) { const DetectorTotal *total=&d->totals[k]; fprintf(detectors,"%s,%d,%" PRId64 ",%s,%s\n",d->name,k+1,total->passing,decimal(total->occupancy,(i64)m->interval*d->width*d->segment->lanes,4),decimal(total->speed,total->occupancy,2)); } }
 Vehicle **selected=resize(NULL,(size_t)m->vehicle_count*sizeof(*selected));
 for(int k=0;k<m->class_count;k++) { const VehicleClass *c=&m->classes[k]; size_t count=0; for(int i=0;i<m->vehicle_count;i++) if(m->vehicles[i]->class==c) selected[count++]=m->vehicles[i]; char heading[128]; snprintf(heading,sizeof(heading),"CLASS %s",c->name); travel_block(travel,heading,selected,count,m->bin); snprintf(heading,sizeof(heading),"CLASS %s vmax %d weight %d overtake %c stops %c",c->name,c->vmax,c->weight,c->overtake?'Y':'N',c->stops?'Y':'N'); class_block(classes,heading,selected,count); }
 travel_block(travel,"ALL",m->vehicles,(size_t)m->vehicle_count,m->bin); class_block(classes,"ALL",m->vehicles,(size_t)m->vehicle_count);
 for(int k=0;k<m->source_count;k++) { Source *s=&m->sources[k]; size_t count=0; for(int i=0;i<m->vehicle_count;i++) if(m->vehicles[i]->source==s && m->vehicles[i]->exited) selected[count++]=m->vehicles[i]; fprintf(travel,"SOURCE %s exited %zu\n",s->node,count);
  for(int i=0;i<s->route_count;i++) { const Route *r=&s->routes[i]; i64 n=0,total=0; for(size_t j=0;j<count;j++) if(same_route(selected[j],r)) { n++; total+=vehicle_travel(selected[j]); } fputs("  ROUTE ",travel); write_route(travel,r->segments,r->count,","); fprintf(travel," expected %s vehicles %" PRId64 " share %s mean %s\n",fraction(r->share.n,r->share.d),n,fraction(n,(i64)count),decimal(total,n,2)); }
  for(int i=0;i<m->sink_count;i++) { Ratio share={0,1}; bool found=false; for(int j=0;j<s->route_count;j++) if(strcmp(s->routes[j].sink,m->sinks[i])==0) { share=add(share,s->routes[j].share); found=true; } if(!found) continue; i64 n=0,total=0; for(size_t j=0;j<count;j++) if(strcmp(selected[j]->sink,m->sinks[i])==0) { n++; total+=vehicle_travel(selected[j]); } fprintf(travel,"  SINK %s expected %s vehicles %" PRId64 " share %s mean %s\n",m->sinks[i],fraction(share.n,share.d),n,fraction(n,(i64)count),decimal(total,n,2)); }
 }
 free(selected);
 for(int k=0;k<m->segment_count;k++) { const Segment *s=&m->segments[k]; fprintf(network,"SEGMENT %s %s %s length %d lanes %d limit %d entered %" PRId64 " mean_vehicles %s density %s mean_speed %s max_vehicles %d changes %" PRId64 "/%" PRId64 "/%" PRId64 "\n",s->id,s->from,s->to,s->length,s->lanes,s->limit,s->entered,decimal(s->vehicle_sum,m->steps,3),decimal(s->vehicle_sum,(i64)m->steps*s->length*s->lanes,4),decimal(s->speed_sum,s->vehicle_sum,2),s->max_vehicles,s->changes[0],s->changes[1],s->changes[2]); }
 for(int k=0;k<m->junction_count;k++) { const Junction *j=&m->junctions[k]; signal_plan(network,j); for(int i=0;i<m->segment_count;i++) { const Segment *s=&m->segments[i]; if(s->junction!=j) continue; fprintf(network,"  IN %s green %" PRId64 " passed %" PRId64 " blocked %" PRId64 " max_queue %d mean_queue %s failures %" PRId64 "\n",s->id,s->green_count,s->passed,s->blocked,s->max_queue,decimal(s->queue_sum,m->steps,3),s->failures); for(int n=0;n<s->turn_count;n++) fprintf(network,"    TURN %s weight %d vehicles %" PRId64 "\n",s->turns[n].target->id,s->turns[n].weight,s->turns[n].vehicles); } }
 for(int k=0;k<m->stop_count;k++) { const BusStop *s=&m->stops[k]; fprintf(network,"STOP %s cell %d dwell %d buses %" PRId64 "\n",s->segment->id,s->cell,s->dwell,s->buses); }
 for(size_t k=0;k<m->incident_count;k++) { const Incident *i=&m->incidents[k]; fprintf(network,"INCIDENT %s lane %d cell %d planned %" PRId64 "-%" PRId64 " active ",i->segment->id,i->lane+1,i->cell,i->start,i->end); if(i->active_start) fprintf(network,"%d-%d\n",i->active_start,i->active_end); else fputs("none\n",network); }
 fputs("interval,arrived,inserted,exited,in_network,queued,mean_speed\n",timeline); i64 on_road=0,queued=0;
 for(int k=0;k<m->steps/m->interval;k++) { const Interval *total=&m->totals[k]; on_road+=total->inserted-total->exited; queued+=total->arrived-total->inserted; fprintf(timeline,"%d,%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%s\n",k+1,total->arrived,total->inserted,total->exited,on_road,queued,decimal(total->speed,total->steps,2)); }
 for(size_t k=0;k<m->track_count;k++) { i64 id=m->tracks[k]; if(id>m->vehicle_count) { fprintf(tracks,"VEHICLE %" PRId64 " none\n",id); continue; } const Vehicle *v=m->vehicles[(size_t)id-1]; fprintf(tracks,"VEHICLE %" PRId64 " class %s source %s arrival %d inserted ",id,v->class->name,v->source->node,v->arrival); if(v->inserted) fprintf(tracks,"%d",v->inserted); else fputc('-',tracks); fputs(" exited ",tracks); if(v->exited) fprintf(tracks,"%d sink %s\n",v->exited,v->sink); else fputs("- sink -\n",tracks); fputs("ROUTE ",tracks); if(v->route_count) write_route(tracks,v->route,v->route_count," "); else fputc('-',tracks); fputc('\n',tracks); write_lines(tracks,&v->trajectory); }
 fputs("ring,vehicles,density,flow,speed\n",fundamental);
 for(size_t k=0;k<m->ring_count;k++) { const Ring *r=&m->rings[k]; for(size_t i=0;i<r->count;i++) { int count=r->counts[i]; i64 total=ring_experiment(m,r,count); fprintf(fundamental,"%zu,%d,%s,%s,%s\n",k+1,count,decimal(count,r->length,4),decimal(total,(i64)r->length*r->measure,4),decimal(total,(i64)count*r->measure,3)); } }
 write_lines(events,&m->events);
 fclose(spacetime); fclose(detectors); fclose(travel); fclose(classes); fclose(network); fclose(timeline); fclose(tracks); fclose(fundamental); fclose(events);
}
static void destroy(Simulation *m) {
 for(int i=0;i<m->vehicle_count;i++) { free_lines(&m->vehicles[i]->trajectory); free(m->vehicles[i]); } free(m->vehicles);
 for(int i=0;i<m->source_count;i++) { free(m->sources[i].rates); free(m->sources[i].queue); }
 for(size_t i=0;i<m->detector_count;i++) free(m->detectors[i].totals);
 for(size_t i=0;i<m->diagram_count;i++) free_lines(&m->diagrams[i].lines);
 for(size_t i=0;i<m->ring_count;i++) free(m->rings[i].counts);
 free(m->incidents); free(m->detectors); free(m->diagrams); free(m->tracks); free(m->rings); free(m->totals); free_lines(&m->events); free(m);
}
int main(void) { Simulation *simulation=read_simulation(); run(simulation); output(simulation); destroy(simulation); return 0; }
