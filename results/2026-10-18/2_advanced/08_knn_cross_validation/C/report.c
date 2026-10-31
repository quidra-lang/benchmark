#include "knn.h"
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

const char *fixed(double value,int places){static char buffers[128][384];static unsigned next;char *text=buffers[next++%128];snprintf(text,384,"%.*f",places,value);if(text[0]=='-'&&strtod(text,NULL)==0)memmove(text,text+1,strlen(text));return text;}
const char *real(double value){return fixed(value,4);}
double four(double value){return strtod(fixed(value,4),NULL);}
const char *ratio(int numerator,int denominator){static char buffers[32][448];static unsigned next;char *text=buffers[next++%32];snprintf(text,448,"%d/%d %s",numerator,denominator,real((double)numerator/denominator));return text;}
const char *fraction_metric(int numerator,int denominator){if(!denominator)return "- -";int a=numerator,b=denominator;while(b){int r=a%b;a=b;b=r;}static char buffers[32][448];static unsigned next;char *text=buffers[next++%32];snprintf(text,448,"%d/%d %s",numerator/a,denominator/a,real((double)numerator/denominator));return text;}
void add_line(Lines *lines,const char *format,...){if(lines->count==lines->capacity){lines->capacity=lines->capacity?lines->capacity*2:64;char **grown=realloc(lines->values,(size_t)lines->capacity*sizeof *grown);if(!grown)exit(1);lines->values=grown;}va_list args,copy;va_start(args,format);va_copy(copy,args);int length=vsnprintf(NULL,0,format,copy);va_end(copy);char *text=malloc((size_t)length+1);if(!text)exit(1);vsnprintf(text,(size_t)length+1,format,args);va_end(args);lines->values[lines->count++]=text;}
void append_lines(Lines *to,const Lines *from){for(int j=0;j<from->count;j++)add_line(to,"%s",from->values[j]);}
void append_part(Lines *to,const Lines *part){if(to->count)add_line(to,"");append_lines(to,part);}
void write_report(const char *name,const Lines *lines){mkdir("output",0755);char path[128];snprintf(path,sizeof path,"output/%s",name);FILE *file=fopen(path,"w");if(!file)exit(1);for(int j=0;j<lines->count;j++)fprintf(file,"%s\n",lines->values[j]);if(fclose(file))exit(1);}
