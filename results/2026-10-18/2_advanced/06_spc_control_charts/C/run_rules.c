#include "spc.h"
#include <stdlib.h>

Zones chart_zones(Limits l){double a=(l.ucl-l.cl)/3,b=(l.cl-l.lcl)/3;return (Zones){l,l.cl+a,l.cl+2*a,l.cl-b,l.cl-2*b};}
const char *zone_name(Limits l,double v){Zones z=chart_zones(l);if(v>l.ucl)return "OUT+";if(v<l.lcl)return "OUT-";if(v>z.u2)return "A+";if(v>z.u1)return "B+";if(v>l.cl)return "C+";if(v<z.l2)return "A-";if(v<z.l1)return "B-";if(v<l.cl)return "C-";return "C0";}
void append_signal(Signals *list,Signal signal){if(list->count==list->capacity){list->capacity=list->capacity?list->capacity*2:64;Signal *data=realloc(list->data,(size_t)list->capacity*sizeof *data);if(!data)exit(1);list->data=data;}list->data[list->count++]=signal;}
Signals check_rules(int chart,const Series *s,Limits l,const RuleSet *rules) {
 static const int lengths[9]={0,1,3,5,8,6,14,15,8};Zones z=chart_zones(l);Signals signals={0};
 for(int k=1;k<=s->count;k++)for(int rj=0;rj<rules->count;rj++) {
  int r=rules->values[rj],w=lengths[r];if(k<w)continue;int first=k-w,direction=2;double v=s->values[k-1];
  if(r==1){if(outside(l,v))direction=v>l.cl?1:-1;}
  else if(r==2||r==3){double u=r==2?z.u2:z.u1,d=r==2?z.l2:z.l1;int needed=r==2?2:4,up=0,down=0;for(int j=first;j<k;j++){up+=s->values[j]>u;down+=s->values[j]<d;}if(v>u&&up>=needed)direction=1;else if(v<d&&down>=needed)direction=-1;}
  else if(r==4||r==5){bool up=true,down=true;for(int j=first+(r==5);j<k;j++){double previous=r==5?s->values[j-1]:l.cl;up=up&&s->values[j]>previous;down=down&&s->values[j]<previous;}if(up)direction=1;else if(down)direction=-1;}
  else if(r==6){bool ok=true;double previous=0;for(int j=first+1;j<k;j++){double d=s->values[j]-s->values[j-1];if(d==0||(j>first+1&&(d>0)==(previous>0)))ok=false;previous=d;}if(ok)direction=0;}
  else if(r==7){bool ok=true;for(int j=first;j<k;j++)ok=ok&&z.l1<s->values[j]&&s->values[j]<z.u1;if(ok)direction=0;}
  else {bool ok=true,up=false,down=false;for(int j=first;j<k;j++){double x=s->values[j];ok=ok&&(x>z.u1||x<z.l1);up=up||x>z.u1;down=down||x<z.l1;}if(ok&&up&&down)direction=0;}
  if(direction!=2)append_signal(&signals,(Signal){chart,r,s->numbers[first],s->numbers[k-1],v,direction});
 }
 return signals;
}
