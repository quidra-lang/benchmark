#include "mining.h"
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

const char *fraction_text(Fraction value){static char buffers[64][128];static unsigned next;char *text=buffers[next++%64];bool negative=value.n<0;int64_t n=negative?-value.n:value.n,scaled=10000*n/value.d;snprintf(text,128,"%s%lld/%lld=%s%lld.%04lld",negative?"-":"",(long long)n,(long long)value.d,negative&&scaled?"-":"",(long long)(scaled/10000),(long long)(scaled%10000));return text;}
const char *percentage(int64_t part,int64_t whole){static char buffers[32][64];static unsigned next;char *text=buffers[next++%32];int64_t scaled=10000*part/whole;snprintf(text,64,"%lld.%02lld%%",(long long)(scaled/100),(long long)(scaled%100));return text;}
const char *money(int64_t cents){static char buffers[32][64];static unsigned next;char *text=buffers[next++%32];snprintf(text,64,"%lld.%02lld",(long long)(cents/100),(long long)(cents%100));return text;}
const char *ids_text(const int *ids,int count,const Dataset *d){static char buffers[32][2048];static unsigned next;char *text=buffers[next++%32];text[0]='\0';for(int j=0;j<count;j++){if(j)strcat(text,"+");strcat(text,d->names[ids[j]]);}return text;}
const char *itemset_text(Itemset set,const Dataset *d){return ids_text(set.ids,set.size,d);}
const char *rule_arrow(Rule rule,const Dataset *d){static char buffers[32][256];static unsigned next;char *text=buffers[next++%32];snprintf(text,256,"%s -> %s",itemset_text(rule.x,d),itemset_text(rule.y,d));return text;}
void add_line(Lines *lines,const char *format,...){if(lines->count==lines->capacity){lines->capacity=lines->capacity?lines->capacity*2:64;char **grown=realloc(lines->values,(size_t)lines->capacity*sizeof *grown);if(!grown)exit(1);lines->values=grown;}va_list args,copy;va_start(args,format);va_copy(copy,args);int length=vsnprintf(NULL,0,format,copy);va_end(copy);char *text=malloc((size_t)length+1);if(!text)exit(1);vsnprintf(text,(size_t)length+1,format,args);va_end(args);lines->values[lines->count++]=text;}
void append_lines(Lines *to,const Lines *from){for(int j=0;j<from->count;j++)add_line(to,"%s",from->values[j]);}
Lines rules_csv(const RuleSet *rules,const Dataset *d){Lines lines={0};add_line(&lines,"rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement");for(int j=0;j<rules->count;j++){Rule r=rules->values[j];add_line(&lines,"%d,%s,%s,%lld,%s,%s,%s,%s,%s,%s",r.rank,itemset_text(r.x,d),itemset_text(r.y,d),(long long)r.count,fraction_text(r.support),fraction_text(r.confidence),fraction_text(r.lift),fraction_text(r.leverage),r.infinite?"INF":fraction_text(r.conviction),fraction_text(r.improvement));}return lines;}
void write_report(const char *name,const Lines *lines){mkdir("output",0755);char path[128];snprintf(path,sizeof path,"output/%s",name);FILE *file=fopen(path,"w");if(!file)exit(1);for(int j=0;j<lines->count;j++)fprintf(file,"%s\n",lines->values[j]);if(fclose(file))exit(1);}
