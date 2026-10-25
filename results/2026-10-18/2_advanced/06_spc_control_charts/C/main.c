#include "spc.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

typedef struct {int count;Limits limits[2];Numbers out;} Pass;
typedef struct {Pass passes[10];int pass_count;bool converged;Numbers retained,removed;Limits limits[2];} Estimate;
typedef struct {int count;Signals signals;} Pattern;
typedef struct {double value,width;} BandPoint;
typedef struct {int start,end,onset,out,total,kind,counts[5],detection[9];double shift,spread;} Event;
typedef struct {int count;Center center;Numbers out;} AttributePass;
typedef struct {AttributePass passes[10];int pass_count;bool converged;Numbers retained,removed;LotPoint points[MAX_LOTS];Signals signals;} Attribute;
typedef struct {
 Dataset data;Subgroup groups[MAX_GROUPS];int group_count;Constants constants;
 Estimate estimates[3];Pattern patterns[6];Pass proposals[3];Signals signals;
 Event events[MAX_GROUPS];int event_count;Attribute attributes[4];
 double upper[MAX_GROUPS+1],lower[MAX_GROUPS+1];BandPoint ewma[MAX_GROUPS+1],ma[MAX_GROUPS+1];
 double mu,sigma,reference,h,sbar,ew,mw;
} Analysis;
static Numbers numbers(int first,int last){Numbers ns={0};for(int i=first;i<=last;i++)ns.values[ns.count++]=i;return ns;}
static bool contains(const Numbers *ns,int n){for(int j=0;j<ns->count;j++)if(ns->values[j]==n)return true;return false;}
static Numbers without(const Numbers *all,const Numbers *removed){Numbers r={0};for(int j=0;j<all->count;j++)if(!contains(removed,all->values[j]))r.values[r.count++]=all->values[j];return r;}
static const char *real(double v){static char buffers[64][384];static unsigned next;char *s=buffers[next++%64];snprintf(s,384,"%.4f",v);if(!strcmp(s,"-0.0000"))strcpy(s,"0.0000");return s;}
static const char *status(bool converged){return converged?"converged":"stopped";}
static const char *direction(int d){return d>0?"UP":d<0?"DOWN":"NONE";}
static const char *rule_name(int r){static const char *const names[11]={"","1","2","3","4","5","6","7","8","UPPER","LOWER"};return names[r];}
static void number_list(FILE *f,const Numbers *ns){if(!ns->count){fputs("none",f);return;}for(int j=0;j<ns->count;j++)fprintf(f,"%s%d",j?" ":"",ns->values[j]);}
static void limits_text(FILE *f,const char *label,Limits l){fprintf(f,"%s lcl %s cl %s ucl %s",label,real(l.lcl),real(l.cl),real(l.ucl));}
static void pair_text(FILE *f,int family,const Limits limits[2]){static const char *const labels[3][2]={{"XBAR","R"},{"XBAR","S"},{"I","MR"}};limits_text(f,labels[family][0],limits[0]);fputc(' ',f);limits_text(f,labels[family][1],limits[1]);}
static void estimate(Analysis *a,int family){
 Settings *s=&a->data.settings;Numbers initial=numbers(1,s->phase1*(family==2?s->size:1)),chosen=initial;Estimate *e=&a->estimates[family];
 for(int p=1;p<=s->passes;p++){
  Limits limits[2];family_limits(family,&chosen,a->groups,&a->data,limits);Series series[2];family_series(family,&chosen,a->groups,&a->data,series);bool found[MAX_SAMPLES+1]={0};
  for(int j=0;j<2;j++)for(int k=0;k<series[j].count;k++)if(outside(limits[j],series[j].values[k]))found[series[j].numbers[k]]=true;
  Numbers out={0};for(int j=0;j<chosen.count;j++)if(found[chosen.values[j]])out.values[out.count++]=chosen.values[j];Pass *pass=&e->passes[e->pass_count++];pass->count=chosen.count;memcpy(pass->limits,limits,sizeof limits);pass->out=out;memcpy(e->limits,limits,sizeof limits);
  if(!out.count){e->converged=true;break;}if(p==s->passes)break;chosen=without(&chosen,&out);
 }
 e->retained=chosen;e->removed=without(&initial,&chosen);Series series[2];family_series(family,&chosen,a->groups,&a->data,series);
 for(int j=0;j<2;j++){int chart=family*2+j;a->patterns[chart].count=series[j].count;a->patterns[chart].signals=check_rules(chart,&series[j],e->limits[j],&s->rules[chart]);}
}
static int signal_group(const Analysis *a,Signal s){return s.chart==4||s.chart==5?(s.end-1)/a->data.settings.size+1:s.end;}
static int event_of(const Analysis *a,int i){for(int j=0;j<a->event_count;j++)if(a->events[j].start<=i&&i<=a->events[j].end)return j+1;return 0;}
static bool has_signal(const Analysis *a,int chart,int end,int rule){for(int j=0;j<a->signals.count;j++){Signal s=a->signals.data[j];if(s.chart==chart&&s.end==end&&(!rule||s.rule==rule))return true;}return false;}
static void band_signal(Analysis *a,int chart,int start,int end,BandPoint p){if(p.value>a->mu+p.width)append_signal(&a->signals,(Signal){chart,9,start,end,p.value,1});else if(p.value<a->mu-p.width)append_signal(&a->signals,(Signal){chart,10,start,end,p.value,-1});}
static int compare_signals(const void *left,const void *right){const Signal *a=left,*b=right;if(a->chart!=b->chart)return a->chart-b->chart;if(a->end!=b->end)return a->end-b->end;return a->rule-b->rule;}
static void monitor(Analysis *a){
 Settings *s=&a->data.settings;a->mu=a->estimates[0].limits[0].cl;a->sigma=a->estimates[0].limits[1].cl/a->constants.d2/sqrt(s->size);a->reference=s->k*a->sigma;a->h=s->h*a->sigma;a->sbar=a->estimates[1].limits[1].cl;
 for(int chart=0;chart<6;chart++){
  Series seq={0};int first=chart<4?s->phase1+1:s->phase1*s->size+1,last=chart<4?a->group_count:a->data.count;
  for(int i=first;i<=last;i++){double v;if(chart==0||chart==2)v=a->groups[i-1].mean;else if(chart==1)v=(double)a->groups[i-1].range;else if(chart==3)v=a->groups[i-1].sd;else if(chart==4)v=a->data.values[i-1];else v=abs(a->data.values[i-1]-a->data.values[i-2]);seq.numbers[seq.count]=i;seq.values[seq.count++]=v;}
  Signals signals=check_rules(chart,&seq,a->estimates[chart/2].limits[chart%2],&s->rules[chart]);for(int j=0;j<signals.count;j++)append_signal(&a->signals,signals.data[j]);free(signals.data);
 }
 double upper=0,lower=0,z=a->mu,factor=1,q=(1-s->lambda)*(1-s->lambda),rho=s->lambda/(2-s->lambda);int ur=0,lr=0;a->ew=s->e*a->sigma*sqrt(rho);a->mw=3*a->sigma/sqrt(s->span);
 for(int i=s->phase1+1;i<=a->group_count;i++){
  double mean=a->groups[i-1].mean;upper=fmax(0,upper+(mean-a->mu-a->reference));lower=fmax(0,lower+(a->mu-mean-a->reference));ur=upper>0?ur+1:0;lr=lower>0?lr+1:0;a->upper[i]=upper;a->lower[i]=lower;
  if(upper>a->h){append_signal(&a->signals,(Signal){6,9,i-ur+1,i,upper,1});upper=0;ur=0;}if(lower>a->h){append_signal(&a->signals,(Signal){6,10,i-lr+1,i,lower,-1});lower=0;lr=0;}
  z=s->lambda*mean+(1-s->lambda)*z;factor=factor*q;double width=s->e*a->sigma*sqrt(rho*(1-factor));a->ewma[i]=(BandPoint){z,width};band_signal(a,7,i,i,a->ewma[i]);
  int first=i-s->span+1;if(first<s->phase1+1)first=s->phase1+1;int64_t total=0;for(int j=first;j<=i;j++)total+=a->groups[j-1].total;a->ma[i]=(BandPoint){(double)total/(s->size*(i-first+1)),3*a->sigma/sqrt(i-first+1)};band_signal(a,8,first,i,a->ma[i]);
 }
 if(a->signals.count>1)qsort(a->signals.data,(size_t)a->signals.count,sizeof *a->signals.data,compare_signals);
}
static void build_events(Analysis *a){
 Settings *s=&a->data.settings;bool found[MAX_GROUPS+1]={0};for(int j=0;j<a->signals.count;j++)found[signal_group(a,a->signals.data[j])]=true;
 for(int i=s->phase1+1;i<=a->group_count;i++)if(found[i]){if(a->event_count&&i-a->events[a->event_count-1].end-1<=s->gap)a->events[a->event_count-1].end=i;else a->events[a->event_count++]=(Event){.start=i,.end=i};}
 for(int j=0;j<a->event_count;j++){
  Event *e=&a->events[j];e->onset=e->start;bool cusum=false;
  for(int k=0;k<a->signals.count;k++){Signal signal=a->signals.data[k];int g=signal_group(a,signal);if(g<e->start||g>e->end)continue;e->total++;int *d=&e->detection[signal.chart];if(!*d||g<*d)*d=g;int index=4;if(signal.direction){index=signal.chart==1||signal.chart==3||signal.chart==5?2:0;if(signal.direction<0)index++;}e->counts[index]++;if(signal.chart==6&&(!cusum||signal.start<e->onset)){e->onset=signal.start;cusum=true;}}
  for(int k=1;k<5;k++)if(e->counts[k]>e->counts[e->kind])e->kind=k;
  int64_t total=0;double sd=0.0;for(int i=e->start;i<=e->end;i++){Subgroup g=a->groups[i-1];total+=g.total;sd+=g.sd;for(int k=0;k<g.count;k++)e->out+=g.values[k]<s->lsl||g.values[k]>s->usl;}
  int length=e->end-e->start+1;double mean=(double)total/(s->size*length);e->shift=(mean-a->mu)/a->sigma;e->spread=(sd/length)/a->sbar;
 }
 for(int f=0;f<3;f++){Numbers ns=a->estimates[f].retained;for(int i=s->phase1+1;i<=a->group_count;i++)if(!event_of(a,i)){if(f==2){for(int t=(i-1)*s->size+1;t<=i*s->size;t++)ns.values[ns.count++]=t;}else ns.values[ns.count++]=i;}a->proposals[f].count=ns.count;family_limits(f,&ns,a->groups,&a->data,a->proposals[f].limits);}
}
static void estimate_attributes(Analysis *a){
 Settings *s=&a->data.settings;
 for(int chart=0;chart<4;chart++){
  Attribute *r=&a->attributes[chart];Numbers initial=numbers(1,a->data.lot_count),chosen=initial;Center center={0};
  for(int p=1;p<=s->passes;p++){center=attribute_center(chart,&chosen,&a->data);Numbers out={0};for(int j=0;j<chosen.count;j++){int i=chosen.values[j];if(attribute_point(chart,a->data.lots[i-1],center).status)out.values[out.count++]=i;}r->passes[r->pass_count++]=(AttributePass){chosen.count,center,out};if(!out.count){r->converged=true;break;}if(p==s->passes)break;chosen=without(&chosen,&out);}
  r->retained=chosen;r->removed=without(&initial,&chosen);Series seq={0};for(int j=0;j<a->data.lot_count;j++){r->points[j]=attribute_point(chart,a->data.lots[j],center);seq.numbers[seq.count]=j+1;seq.values[seq.count++]=r->points[j].z;}r->signals=check_rules(chart,&seq,(Limits){-3,0,3},&s->rules[6]);
 }
}
static void write_limits(FILE *file,const Analysis *a){
 const Settings *s=&a->data.settings;fprintf(file,"characteristic %s\nsubgroup_size %d\nsubgroups %d\nsamples %d\nphase1_subgroups %d\n",s->name,s->size,a->group_count,a->data.count,s->phase1);
 for(int f=0;f<3;f++){const Estimate *e=&a->estimates[f];fprintf(file,"family %s\n",family_names[f]);for(int p=0;p<e->pass_count;p++){const Pass *r=&e->passes[p];fprintf(file,"pass %d points %d ",p+1,r->count);pair_text(file,f,r->limits);fputs(" out ",file);number_list(file,&r->out);fputc('\n',file);}fprintf(file,"result %s passes %d retained %d removed ",status(e->converged),e->pass_count,e->retained.count);number_list(file,&e->removed);fputc('\n',file);}
 for(int chart=0;chart<6;chart++){Pattern p=a->patterns[chart];for(int j=0;j<p.signals.count;j++){Signal signal=p.signals.data[j];fprintf(file,"phase1_signal %s %d %d %d %s\n",chart_names[chart],signal.rule,signal.start,signal.end,real(signal.value));}fprintf(file,"phase1_check %s points %d signals %d\n",chart_names[chart],p.count,p.signals.count);}
 for(int f=0;f<3;f++){fprintf(file,"proposed %s points %d ",family_names[f],a->proposals[f].count);pair_text(file,f,a->proposals[f].limits);fputc('\n',file);}
 fprintf(file,"cusum target %s sigma %s k %s h %s\n",real(a->mu),real(a->sigma),real(a->reference),real(a->h));fprintf(file,"ewma target %s sigma %s lcl %s ucl %s\n",real(a->mu),real(a->sigma),real(a->mu-a->ew),real(a->mu+a->ew));fprintf(file,"ma target %s sigma %s span %d lcl %s ucl %s\n",real(a->mu),real(a->sigma),s->span,real(a->mu-a->mw),real(a->mu+a->mw));
 for(int chart=0;chart<9;chart++){
  int count=0,counts[11]={0},first=0,distinct=0;bool ends[MAX_SAMPLES+1]={0};
  for(int j=0;j<a->signals.count;j++){Signal signal=a->signals.data[j];if(signal.chart!=chart)continue;count++;counts[signal.rule]++;ends[signal.end]=true;if(!first||signal.end<first)first=signal.end;}
  for(int i=1;i<=MAX_SAMPLES;i++)distinct+=ends[i];int points=a->group_count-s->phase1;if(chart==4||chart==5)points*=s->size;
  fprintf(file,"phase2 %s points %d signals %d signalled %d first ",chart_names[chart],points,count,distinct);if(first)fprintf(file,"%d",first);else fputs("none",file);fputs(" by_rule",file);
  if(chart<6){for(int j=0;j<s->rules[chart].count;j++){int r=s->rules[chart].values[j];fprintf(file," %d:%d",r,counts[r]);}}else fprintf(file," UPPER:%d LOWER:%d",counts[9],counts[10]);fputc('\n',file);
 }
}
static void write_signals(FILE *file,const Analysis *a){fputs("chart,rule,start,end,value,direction\n",file);for(int j=0;j<a->signals.count;j++){Signal s=a->signals.data[j];fprintf(file,"%s,%s,%d,%d,%s,%s\n",chart_names[s.chart],rule_name(s.rule),s.start,s.end,real(s.value),direction(s.direction));}}
static void write_events(FILE *file,const Analysis *a){
 const char *const kinds[5]={"SHIFT_UP","SHIFT_DOWN","SPREAD_UP","SPREAD_DOWN","PATTERN"};fprintf(file,"events %d\n",a->event_count);
 for(int j=0;j<a->event_count;j++){const Event *e=&a->events[j];fprintf(file,"event %d start %d end %d length %d signals %d charts ",j+1,e->start,e->end,e->end-e->start+1,e->total);bool comma=false;for(int c=0;c<9;c++)if(e->detection[c]){fprintf(file,"%s%s",comma?",":"",chart_names[c]);comma=true;}fprintf(file," location_up %d location_down %d spread_up %d spread_down %d pattern %d onset %d shift %s spread %s out_of_spec %d type %s\n",e->counts[0],e->counts[1],e->counts[2],e->counts[3],e->counts[4],e->onset,real(e->shift),real(e->spread),e->out,kinds[e->kind]);fprintf(file,"detection %d",j+1);for(int c=0;c<9;c++){fprintf(file," %s:",chart_names[c]);if(e->detection[c])fprintf(file,"%d",e->detection[c]);else fputc('-',file);}fputc('\n',file);}
}
static void write_subgroups(FILE *file,const Analysis *a){
 const Settings *s=&a->data.settings;fputs("subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event\n",file);
 for(int i=1;i<=a->group_count;i++){Subgroup g=a->groups[i-1];const char *phase=i>s->phase1?"phase2":contains(&a->estimates[0].removed,i)?"excluded":"phase1";fprintf(file,"%d,%s,%s,%s,%lld,%s,",i,phase,real(g.mean),zone_name(a->estimates[0].limits[0],g.mean),(long long)g.range,real(g.sd));if(i>s->phase1)fprintf(file,"%s,%s,%s,%s,",real(a->upper[i]),real(a->lower[i]),real(a->ewma[i].value),real(a->ma[i].value));else fputs("-,-,-,-,",file);int count=0;for(int j=0;j<a->signals.count;j++)count+=signal_group(a,a->signals.data[j])==i;fprintf(file,"%d,",count);int event=event_of(a,i);if(event)fprintf(file,"%d",event);else fputc('-',file);fputc('\n',file);}
}
static void write_attributes(FILE *file,const Analysis *a){
 for(int chart=0;chart<4;chart++){const Attribute *r=&a->attributes[chart];fprintf(file,"chart %s\n",attribute_names[chart]);for(int p=0;p<r->pass_count;p++){AttributePass record=r->passes[p];fprintf(file,"pass %d lots %d center %s out ",p+1,record.count,real(record.center.value));number_list(file,&record.out);fputc('\n',file);}fprintf(file,"result %s passes %d retained %d removed ",status(r->converged),r->pass_count,r->retained.count);number_list(file,&r->removed);fputc('\n',file);
  for(int j=0;j<a->data.lot_count;j++){Lot l=a->data.lots[j];LotPoint p=r->points[j];fprintf(file,"lot %d size %d value ",l.number,l.inspected);if(chart==1||chart==2)fprintf(file,"%d",(int)p.value);else fputs(real(p.value),file);fprintf(file," lcl %s ucl %s z %s status %s\n",real(p.lcl),real(p.ucl),real(p.z),p.status>0?"high":p.status<0?"low":"ok");}
  for(int j=0;j<r->signals.count;j++){Signal signal=r->signals.data[j];fprintf(file,"signal %d %d %d %s\n",signal.rule,signal.start,signal.end,real(signal.value));}fprintf(file,"signals %d\n",r->signals.count);
 }
}
static void write_capability(FILE *file,const Analysis *a){
 const Settings *s=&a->data.settings;const char *const names[13]={"mean","sigma_within","sigma_sbar","sigma_overall","cp","cpu","cpl","cpk","pp","ppu","ppl","ppk","cpm"};
 for(int j=0;j<2;j++){
  Numbers chosen=j?numbers(s->phase1+1,a->group_count):a->estimates[0].retained;Capability r=capability(&chosen,a->groups,s,a->constants);fprintf(file,"group %s subgroups %d values %d\n",j?"phase2":"phase1",chosen.count,r.count);double values[13]={r.mean,r.within,r.sbar,r.overall,r.cp,r.cpu,r.cpl,r.cpk,r.pp,r.ppu,r.ppl,r.ppk,r.cpm};for(int k=0;k<13;k++)fprintf(file,"%s %s\n",names[k],real(values[k]));fprintf(file,"cpk_ci %s %s\nppk_ci %s %s\nbelow_lsl %d\nabove_usl %d\nppm %s\n",real(r.cpk_ci[0]),real(r.cpk_ci[1]),real(r.ppk_ci[0]),real(r.ppk_ci[1]),r.below,r.above,real(r.ppm));
  for(int k=0;k<chosen.count;k++){int i=chosen.values[k];Subgroup g=a->groups[i-1];for(int p=0;p<g.count;p++){int v=g.values[p];const char *side=v<s->lsl?"low":v>s->usl?"high":NULL;if(side)fprintf(file,"out_of_spec sample %d subgroup %d value %d side %s\n",(i-1)*s->size+p+1,i,v,side);}}
  fprintf(file,"verdict %s\n",r.verdict);histogram(file,&r,s);
 }
 for(int first=s->phase1+1;first+s->window-1<=a->group_count;first+=s->step){int last=first+s->window-1;Numbers chosen=numbers(first,last);Capability r=capability(&chosen,a->groups,s,a->constants);fprintf(file,"rolling %d %d mean %s sigma_within %s sigma_overall %s cpk %s ppk %s verdict %s\n",first,last,real(r.mean),real(r.within),real(r.overall),real(r.cpk),real(r.ppk),r.verdict);}
}
static void write_charts(FILE *file,const Analysis *a){
 const Settings *s=&a->data.settings;char band[62];const int charts[3]={0,1,3};
 for(int j=0;j<3;j++){
  int chart=charts[j],family=chart/2;Limits limits=a->estimates[family].limits[chart%2];fprintf(file,"chart ");limits_text(file,chart==0?"XBAR":chart_names[chart],limits);fputc('\n',file);
  for(int i=1;i<=a->group_count;i++){Subgroup g=a->groups[i-1];char mark=i>s->phase1?'2':contains(&a->estimates[family].removed,i)?'x':'1';double v=chart==0?g.mean:chart==1?(double)g.range:g.sd;limits_band(band,limits,v,i>s->phase1&&has_signal(a,chart,i,0));fprintf(file,"%3d %c %s %s\n",i,mark,band,real(v));}
 }
 fprintf(file,"chart CUSUM h %s\n",real(a->h));for(int i=s->phase1+1;i<=a->group_count;i++){cusum_band(band,a->upper[i],a->lower[i],a->h,has_signal(a,6,i,9),has_signal(a,6,i,10));fprintf(file,"%3d %s %s %s\n",i,band,real(a->upper[i]),real(a->lower[i]));}
 for(int chart=7;chart<=8;chart++){double scale=chart==7?a->ew:a->mw;const BandPoint *points=chart==7?a->ewma:a->ma;fputs("chart ",file);limits_text(file,chart_names[chart],(Limits){a->mu-scale,a->mu,a->mu+scale});fputc('\n',file);for(int i=s->phase1+1;i<=a->group_count;i++){BandPoint p=points[i];width_band(band,scale,p.width,p.value,a->mu,has_signal(a,chart,i,0));fprintf(file,"%3d %s %s %s %s\n",i,band,real(p.value),real(a->mu-p.width),real(a->mu+p.width));}}
 const char *const pictures[4]={"P_STD","NP_STD","C_STD","U_STD"};for(int c=0;c<4;c++){fprintf(file,"chart %s lcl -3.0000 cl 0.0000 ucl 3.0000\n",pictures[c]);for(int j=0;j<a->data.lot_count;j++){LotPoint p=a->attributes[c].points[j];standard_band(band,p.z,p.status==0);fprintf(file,"%3d %s %s\n",a->data.lots[j].number,band,real(p.z));}}
}
int main(void){
 Analysis *a=calloc(1,sizeof *a);if(!a)return 1;a->data=read_dataset();a->constants=control_constants[a->data.settings.size-2];a->group_count=subgroup_statistics(&a->data,a->groups);for(int f=0;f<3;f++)estimate(a,f);monitor(a);build_events(a);estimate_attributes(a);mkdir("output",0755);
 const char *const names[7]={"limits.txt","signals.csv","events.txt","subgroups.csv","attribute_charts.txt","capability.txt","charts.txt"};void (*writers[7])(FILE *,const Analysis *)={write_limits,write_signals,write_events,write_subgroups,write_attributes,write_capability,write_charts};
 for(int j=0;j<7;j++){char path[128];snprintf(path,sizeof path,"output/%s",names[j]);FILE *file=fopen(path,"w");if(!file)return 1;writers[j](file,a);if(fclose(file))return 1;}
 for(int j=0;j<6;j++)free(a->patterns[j].signals.data);for(int j=0;j<4;j++)free(a->attributes[j].signals.data);free(a->signals.data);free(a);return 0;
}
