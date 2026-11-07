#include "dsp.h"
#include <string.h>

Samples gain(Samples x,int64_t num,int64_t den,int64_t *clips){Samples y=new_samples(x.count);for(int j=0;j<x.count;j++)y.values[j]=saturate(rdiv(x.values[j]*num,den),clips);return y;}
Samples mix(Signal *const *signals,const int64_t *weights,int count,int64_t den,int64_t *clips){int length=0;for(int k=0;k<count;k++)if(signals[k]->samples.count>length)length=signals[k]->samples.count;Samples y=new_samples(length);for(int j=0;j<length;j++){int64_t total=0;for(int k=0;k<count;k++)if(j<signals[k]->samples.count)total+=weights[k]*signals[k]->samples.values[j];y.values[j]=saturate(rdiv(total,den),clips);}return y;}
Samples delay(Samples x,int count){Samples y=new_samples(x.count+count);memcpy(y.values+count,x.values,(size_t)x.count*sizeof *x.values);return y;}
Samples echo(Samples x,int lag,int64_t num,int64_t den,int tail,int64_t *clips){Samples y=new_samples(x.count+tail);memcpy(y.values,x.values,(size_t)x.count*sizeof *x.values);for(int j=lag;j<y.count;j++)y.values[j]=saturate(y.values[j]+rdiv(num*y.values[j-lag],den),clips);return y;}
Samples resample(Samples x,int old_rate,int new_rate){int length=(int)((int64_t)(x.count-1)*new_rate/old_rate+1);Samples y=new_samples(length);for(int j=0;j<length;j++){int64_t position=(int64_t)j*old_rate;int p=(int)(position/new_rate);int64_t q=position%new_rate;y.values[j]=x.values[p];if(q)y.values[j]+=rdiv((x.values[p+1]-x.values[p])*q,new_rate);}return y;}
Samples fade(Samples x,int fade_in,int fade_out){Samples y=copy_samples(x);for(int j=0;j<fade_in;j++)y.values[j]=rdiv(y.values[j]*j,fade_in);for(int j=x.count-fade_out;j<x.count;j++)y.values[j]=rdiv(y.values[j]*(x.count-1-j),fade_out);return y;}
