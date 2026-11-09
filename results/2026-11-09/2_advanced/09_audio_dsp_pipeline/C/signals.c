#include "dsp.h"
#include <stdlib.h>
#include <string.h>

int64_t floor_div(int64_t a,int64_t b){int64_t q=a/b,r=a%b;if(r&&((r>0)!=(b>0)))q--;return q;}
int64_t rdiv(int64_t a,int64_t b){return floor_div(2*a+b,2*b);}
int64_t sample_abs(int64_t v){return v<0?-v:v;}
int64_t saturate(int64_t v,int64_t *clips){if(v< -32768){if(clips)(*clips)++;return -32768;}if(v>32767){if(clips)(*clips)++;return 32767;}return v;}
Samples new_samples(int count){Samples x={calloc((size_t)count,sizeof *x.values),count};if(count&&!x.values)exit(1);return x;}
Samples copy_samples(Samples x){Samples y=new_samples(x.count);memcpy(y.values,x.values,(size_t)x.count*sizeof *x.values);return y;}
int64_t peak(Samples x){int64_t p=0;for(int j=0;j<x.count;j++){int64_t v=sample_abs(x.values[j]);if(v>p)p=v;}return p;}
int64_t sample_sum(Samples x){int64_t total=0;for(int j=0;j<x.count;j++)total+=x.values[j];return total;}
int read_signals(Signal **signals){FILE *file=fopen("input/signals.txt","r");if(!file)exit(1);char keyword[16],name[17];int rate,count,total=0;while(fscanf(file,"%15s %16s %d %d",keyword,name,&rate,&count)==4){Signal *s=calloc(1,sizeof *s);if(!s)exit(1);strcpy(s->name,name);strcpy(s->origin,"input");s->rate=rate;s->samples=new_samples(count);for(int j=0;j<count;j++){long long value;if(fscanf(file,"%lld",&value)!=1)exit(1);s->samples.values[j]=(int64_t)value;}signals[total++]=s;}fclose(file);return total;}
Samples test_signal(const char *command,int count,int pos,int64_t amp,int64_t seed){Samples x=new_samples(count);if(!strcmp(command,"IMPULSE"))x.values[pos]=amp;else if(!strcmp(command,"STEP")){for(int j=pos;j<count;j++)x.values[j]=amp;}else{int64_t state=seed;for(int j=0;j<count;j++){state=48271*state%2147483647;x.values[j]=state%65536-32768;}}return x;}
void format_signal(const Signal *s,Lines *lines){add_line(lines,"SIGNAL %s %d %d",s->name,s->rate,s->samples.count);for(int first=0;first<s->samples.count;first+=16){char text[128]="";int last=first+16<s->samples.count?first+16:s->samples.count;for(int j=first;j<last;j++)snprintf(text+strlen(text),sizeof text-strlen(text),"%s%lld",j>first?" ":"",(long long)s->samples.values[j]);add_line(lines,"%s",text);}}
