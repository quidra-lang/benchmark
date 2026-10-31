#include "dsp.h"

int64_t energy(Samples x){int64_t total=0;for(int j=0;j<x.count;j++)total+=x.values[j]*x.values[j];return total;}
int64_t integer_sqrt(int64_t n){int64_t low=0,high=n+1;while(low+1<high){int64_t middle=low+(high-low)/2;if(middle<=n/middle)low=middle;else high=middle;}return low;}
int64_t rms(Samples x){return integer_sqrt(energy(x)/x.count);}
int64_t zero_crossings(Samples x){int64_t count=0;for(int j=1;j<x.count;j++)count+=(x.values[j-1]<0)!=(x.values[j]<0);return count;}
int64_t clipped(Samples x){int64_t count=0;for(int j=0;j<x.count;j++)count+=x.values[j]==32767||x.values[j]== -32768;return count;}
const char *crest_fraction(Samples x){int64_t e=energy(x);if(!e)return "none";int64_t p=peak(x),n=p*p*x.count,d=e,a=n,b=d;while(b){int64_t remainder=a%b;a=b;b=remainder;}static char buffers[16][64];static unsigned next;char *text=buffers[next++%16];snprintf(text,64,"%lld/%lld",(long long)(n/a),(long long)(d/a));return text;}
int pitch_lag(Samples x,int low,int high){int best=low;int64_t largest=0;for(int lag=low;lag<=high;lag++){int64_t correlation=0;for(int n=0;n+lag<x.count;n++)correlation+=x.values[n]*x.values[n+lag];if(lag==low||correlation>largest){best=lag;largest=correlation;}}return largest>0?best:0;}
const char *decimal_two(int64_t h){static char buffers[32][64];static unsigned next;char *text=buffers[next++%32];snprintf(text,64,"%lld.%02lld",(long long)(h/100),(long long)(h%100));return text;}
const char *frequency(int rate,int lag){return decimal_two(rdiv((int64_t)100*rate,lag));}
