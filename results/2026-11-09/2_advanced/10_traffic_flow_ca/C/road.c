#include "traffic.h"

int road_free(const Segment *s,int lane,int x,int cap) { int n=0; while(n<cap && x+n+1<s->length && s->cells[lane][x+n+1]==0) n++; return n; }
int road_first(const Segment *s,int lane) { for(int x=0;x<s->length;x++) if(s->cells[lane][x]!=0) return x; return s->length; }
bool road_safe(const Segment *s,int lane,int x) { for(int i=maximum(0,x-s->limit);i<=x;i++) if(s->cells[lane][i]!=0) return false; return true; }
void road_cells(const Segment *s,int lane,Vehicle *const *vehicles,char *text) { for(int x=0;x<s->length;x++) { int id=s->cells[lane][x]; text[x]=id==0?'.':id<0?'#':(char)('0'+vehicles[id-1]->speed); } text[s->length]=0; }
const char *incident_update(Incident *i,int t) {
 const char *event=NULL; Segment *s=i->segment;
 if(i->state==1 && t>i->end) { i->state=2; s->cells[i->lane][i->cell]=0; event="INCIDENT_END"; }
 else if(i->state==0 && t>i->end) i->state=3;
 else if(i->state==0 && t>=i->start && s->cells[i->lane][i->cell]==0) { i->state=1; s->cells[i->lane][i->cell]=-1; i->active_start=t; event="INCIDENT_START"; }
 if(i->state==1) i->active_end=t;
 return event;
}
