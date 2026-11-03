#include "dsp.h"
#include <stdlib.h>

Samples envelope(Samples x,int64_t attack,int64_t release){Samples env=new_samples(x.count);int64_t e=0;for(int n=0;n<x.count;n++){int64_t a=sample_abs(x.values[n]);if(a>32767)a=32767;int64_t c=a>e?attack:release;e+=rdiv((a-e)*c,32768);env.values[n]=e;}return env;}
Samples normalize(Samples x,int64_t target,int64_t *source_peak){int64_t p=peak(x);*source_peak=p;Samples y=copy_samples(x);if(p)for(int n=0;n<x.count;n++)y.values[n]=rdiv(x.values[n]*target,p);return y;}
Samples gate(Samples x,int64_t threshold,int hold,int64_t *muted){Samples y=new_samples(x.count);int last=-x.count-hold-1;for(int n=0;n<x.count;n++){if(sample_abs(x.values[n])>=threshold)last=n;if(n-last<=hold)y.values[n]=x.values[n];else (*muted)++;}return y;}
Samples compress_signal(Samples x,int64_t threshold,int64_t ratio_num,int64_t ratio_den,int64_t attack,int64_t release,int64_t *min_gain,int64_t *reduced){Samples env=envelope(x,attack,release),y=new_samples(x.count);int64_t g=32768;*min_gain=32768;for(int n=0;n<x.count;n++){int64_t e=env.values[n],target=32768;if(e>threshold){int64_t d=threshold+rdiv((e-threshold)*ratio_den,ratio_num);target=rdiv(d*32768,e);}if(target<g)g=target;else g+=rdiv((target-g)*release,32768);if(g<*min_gain)*min_gain=g;*reduced+=g<32768;y.values[n]=rdiv(x.values[n]*g,32768);}free(env.values);return y;}
