#include "nonogram.h"

bool is_clue_line(const char *text) { if(!*text) return false; for(;*text;text++) if(*text!=' ' && (*text<'0' || *text>'9')) return false; return true; }
bool parse_clue(const char *text,Clue *clue) {
 clue->count=0; if(strcmp(text,"0")==0) return true; if(!*text) return false;
 const char *begin=text;
 for(const char *p=text;;p++) if(*p==' ' || *p==0) { ptrdiff_t length=p-begin; if(length<1 || length>2 || *begin=='0') return false; int value=0; for(const char *q=begin;q<p;q++) { if(*q<'0' || *q>'9') return false; value=value*10+*q-'0'; } clue->values[clue->count++]=value; if(!*p) break; begin=p+1; }
 return true;
}
Clue run_clue(const Cell *cells,int length) { Clue clue={0}; int run=0; for(int i=0;i<length;i++) { if(cells[i]==FILLED) run++; else if(run>0) { clue.values[clue.count++]=run; run=0; } } if(run>0) clue.values[clue.count++]=run; return clue; }
const char *clue_text(const Clue *clue,const char *separator) {
 static char buffers[16][151]; static unsigned slot; char *text=buffers[slot++%16]; size_t at=0;
 if(clue->count==0) strcpy(text,"0"); else for(int i=0;i<clue->count;i++) at+=(size_t)snprintf(text+at,151-at,"%s%d",i?separator:"",clue->values[i]);
 return text;
}
int clue_span(const Clue *clue) { int span=clue->count-1; for(int i=0;i<clue->count;i++) span+=clue->values[i]; return span; }
bool equal_clue(const Clue *a,const Clue *b) { return a->count==b->count && memcmp(a->values,b->values,(size_t)a->count*sizeof(*a->values))==0; }
