#include "dsp.h"
#include <stdlib.h>

Samples fir(Samples x,int64_t divisor,const int64_t *taps,int count,int64_t *clips){Samples y=new_samples(x.count);for(int n=0;n<x.count;n++){int64_t total=0;for(int k=0;k<count;k++)if(n>=k)total+=taps[k]*x.values[n-k];y.values[n]=saturate(floor_div(total,divisor),clips);}return y;}
Samples biquad(Samples x,const int64_t *coefficients,int count,int64_t *clips){Samples u=x;for(int first=0;first<count;first+=5){const int64_t *c=coefficients+first;Samples v=new_samples(x.count);for(int n=0;n<x.count;n++){int64_t total=c[0]*u.values[n];if(n>=1)total+=c[1]*u.values[n-1];if(n>=2)total+=c[2]*u.values[n-2];if(n>=1)total-=c[3]*v.values[n-1];if(n>=2)total-=c[4]*v.values[n-2];v.values[n]=saturate(floor_div(total,16384),clips);}if(u.values!=x.values)free(u.values);u=v;}return u;}
Samples moving_average(Samples x,int width){Samples y=new_samples(x.count);int64_t total=0;for(int n=0;n<x.count;n++){total+=x.values[n];if(n>=width)total-=x.values[n-width];y.values[n]=rdiv(total,width);}return y;}
Samples dc_block(Samples x,int64_t num,int64_t den,int64_t *clips){Samples y=new_samples(x.count);int64_t previous_x=0,previous_y=0;for(int n=0;n<x.count;n++){int64_t v=x.values[n];y.values[n]=saturate(v-previous_x+rdiv(num*previous_y,den),clips);previous_x=v;previous_y=y.values[n];}return y;}
