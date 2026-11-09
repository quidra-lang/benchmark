#include "spc.h"
#include <math.h>
#include <stdlib.h>

int subgroup_statistics(const Dataset *d,Subgroup *groups) {
 int n=d->settings.size,count=d->count/n;
 for(int i=0;i<count;i++) {
  Subgroup g={.count=n};int low=d->values[i*n],high=low;
  for(int j=0;j<n;j++){int v=d->values[i*n+j];g.values[j]=v;g.total+=v;g.squares+=(int64_t)v*v;if(v<low)low=v;if(v>high)high=v;}
  g.range=high-low;g.mean=(double)g.total/n;g.sd=sqrt((double)(n*g.squares-g.total*g.total)/(n*(n-1)));groups[i]=g;
 }
 return count;
}
bool outside(Limits l,double v){return v<l.lcl||v>l.ucl;}
void family_limits(int f,const Numbers *ns,const Subgroup *groups,const Dataset *d,Limits limits[2]) {
 int64_t total=0,spread=0;double sd=0.0;int count=ns->count;Constants c=control_constants[d->settings.size-2];
 if(f==2) {
  for(int j=0;j<count;j++){int t=ns->values[j];total+=d->values[t-1];if(j>0)spread+=abs(d->values[t-1]-d->values[ns->values[j-1]-1]);}
  double mean=(double)total/count,r=(double)spread/(count-1);c=control_constants[0];limits[0]=(Limits){mean-3*r/c.d2,mean,mean+3*r/c.d2};limits[1]=(Limits){c.d3*r,r,c.d4*r};return;
 }
 for(int j=0;j<count;j++){Subgroup g=groups[ns->values[j]-1];total+=g.total;spread+=g.range;sd+=g.sd;}
 double mean=(double)total/(count*d->settings.size);
 if(f==0){double r=(double)spread/count;limits[0]=(Limits){mean-c.a2*r,mean,mean+c.a2*r};limits[1]=(Limits){c.d3*r,r,c.d4*r};}
 else {sd/=count;limits[0]=(Limits){mean-c.a3*sd,mean,mean+c.a3*sd};limits[1]=(Limits){c.b3*sd,sd,c.b4*sd};}
}
void family_series(int f,const Numbers *ns,const Subgroup *groups,const Dataset *d,Series series[2]) {
 series[0].count=series[1].count=0;
 for(int j=0;j<ns->count;j++) {
  int t=ns->values[j],a=series[0].count++;series[0].numbers[a]=t;
  if(f==2){series[0].values[a]=d->values[t-1];if(j>0){int b=series[1].count++;series[1].numbers[b]=t;series[1].values[b]=abs(d->values[t-1]-d->values[ns->values[j-1]-1]);}}
  else {Subgroup g=groups[t-1];series[0].values[a]=g.mean;int b=series[1].count++;series[1].numbers[b]=t;series[1].values[b]=f==0?(double)g.range:g.sd;}
 }
}
