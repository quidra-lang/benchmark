#include "spc.h"
#include <math.h>
#include <stdlib.h>

static void indices(double mean,double sigma,const Settings *s,double *p,double *u,double *l,double *index){*p=(s->usl-s->lsl)/(6*sigma);*u=(s->usl-mean)/(3*sigma);*l=(mean-s->lsl)/(3*sigma);*index=fmin(*u,*l);}
static void interval(double x,int n,double z,double bounds[2]){double delta=z*sqrt(1.0/(9*n)+x*x/(2*(n-1)));bounds[0]=x-delta;bounds[1]=x+delta;}
Capability capability(const Numbers *chosen,const Subgroup *groups,const Settings *s,Constants c) {
 Capability r={0};int64_t total=0,ranges=0;double sd=0.0;
 for(int j=0;j<chosen->count;j++){Subgroup g=groups[chosen->values[j]-1];total+=g.total;ranges+=g.range;sd+=g.sd;for(int k=0;k<g.count;k++)r.values[r.count++]=g.values[k];}
 r.mean=(double)total/r.count;r.within=((double)ranges/chosen->count)/c.d2;r.sbar=(sd/chosen->count)/c.c4;
 double squares=0.0;for(int j=0;j<r.count;j++){int v=r.values[j];double d=v-r.mean;squares+=d*d;r.below+=v<s->lsl;r.above+=v>s->usl;}
 r.overall=sqrt(squares/(r.count-1));indices(r.mean,r.within,s,&r.cp,&r.cpu,&r.cpl,&r.cpk);indices(r.mean,r.overall,s,&r.pp,&r.ppu,&r.ppl,&r.ppk);
 double d=r.mean-s->target;r.cpm=(s->usl-s->lsl)/(6*sqrt(r.overall*r.overall+d*d));interval(r.cpk,r.count,s->z,r.cpk_ci);interval(r.ppk,r.count,s->z,r.ppk_ci);r.ppm=(double)(1000000LL*(r.below+r.above))/r.count;r.verdict=r.cpk>=1.33?"capable":r.cpk>=1?"marginal":"incapable";return r;
}
void histogram(FILE *file,const Capability *r,const Settings *s) {
 int low=s->lsl,high=s->usl;for(int j=0;j<r->count;j++){if(r->values[j]<low)low=r->values[j];if(r->values[j]>high)high=r->values[j];}low=s->bin*(low/s->bin);high=s->bin*(high/s->bin)+s->bin;
 int length=(high-low)/s->bin,*counts=calloc((size_t)length,sizeof *counts),top=0;if(!counts)exit(1);
 for(int j=0;j<r->count;j++){int i=(r->values[j]-low)/s->bin;counts[i]++;if(counts[i]>top)top=counts[i];}
 const char *names[3]={"lsl","target","usl"};int marks[3]={s->lsl,s->target,s->usl};
 for(int j=0;j<length;j++){int a=low+j*s->bin,b=a+s->bin-1,count=counts[j];fprintf(file,"bin %d %d %d",a,b,count);if(count){fputc(' ',file);int bars=(50*count+top-1)/top;for(int k=0;k<bars;k++)fputc('#',file);}for(int k=0;k<3;k++)if(a<=marks[k]&&marks[k]<=b)fprintf(file," %s",names[k]);fputc('\n',file);}
 free(counts);
}
