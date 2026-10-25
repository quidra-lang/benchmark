#include "traffic.h"

i64 gcd(i64 a,i64 b) { while(b) { i64 next=a%b; a=b; b=next; } return a; }
const char *decimal(i64 a,i64 b,int places) {
 static char buffers[32][64]; static unsigned slot; char *text=buffers[slot++%32];
 if(b==0) { strcpy(text,"-"); return text; }
 i64 scale=1; for(int i=0;i<places;i++) scale*=10; i64 z=(2*a*scale+b)/(2*b);
 snprintf(text,64,"%" PRId64 ".%0*" PRId64,z/scale,places,z%scale); return text;
}
const char *fraction(i64 a,i64 b) {
 static char buffers[32][64]; static unsigned slot; char *text=buffers[slot++%32];
 if(b==0) strcpy(text,"-"); else { i64 g=gcd(a,b); snprintf(text,64,"%" PRId64 "/%" PRId64,a/g,b/g); } return text;
}
i64 percentile(const i64 *times,size_t count,int q) { return times[((size_t)q*count+99)/100-1]; }
void histogram(FILE *file,const i64 *times,size_t count,i64 width) {
 i64 first=times[0]/width,last=times[count-1]/width; size_t bins=(size_t)(last-first+1); i64 *counts=calloc(bins,sizeof(*counts)); if(!counts) abort(); i64 largest=0;
 for(size_t i=0;i<count;i++) { size_t k=(size_t)(times[i]/width-first); counts[k]++; if(counts[k]>largest) largest=counts[k]; }
 for(size_t i=0;i<bins;i++) { i64 low=(first+(i64)i)*width,c=counts[i],stars=(80*c+largest)/(2*largest); fprintf(file,"  %" PRId64 "-%" PRId64 " %" PRId64,low,low+width-1,c); if(stars>0) { fputc(' ',file); for(i64 j=0;j<stars;j++) fputc('*',file); } fputc('\n',file); }
 free(counts);
}
