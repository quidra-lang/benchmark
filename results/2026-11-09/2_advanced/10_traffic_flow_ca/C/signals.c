#include "traffic.h"

bool signal_green(const Junction *j,const Segment *s,int t) {
 if(j->count==0) return true;
 int tau=(t-1+j->offset)%j->cycle;
 for(int k=0;k<j->count;k++) { if(tau<j->phases[k].duration) return (j->phases[k].greens&(UINT32_C(1)<<s->index))!=0; tau-=j->phases[k].duration; }
 return false;
}
void signal_plan(FILE *file,const Junction *j) {
 if(j->count==0) { fprintf(file,"JUNCTION %s unsignalized\n",j->node); return; }
 fprintf(file,"JUNCTION %s signal cycle %d offset %d\n",j->node,j->cycle,j->offset); int start=0;
 for(int k=0;k<j->count;k++) { const Phase *p=&j->phases[k]; fprintf(file,"  PHASE %d %d-%d %s\n",k+1,start,start+p->duration-1,p->token); start+=p->duration; }
}
