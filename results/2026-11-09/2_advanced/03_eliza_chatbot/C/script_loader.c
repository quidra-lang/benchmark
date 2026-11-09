#include "eliza.h"
#include <stdarg.h>

enum { D_INITIAL,D_FINAL,D_DEFAULT,D_QUESTION,D_REPEAT,D_QUIT,D_STOP,D_MEMSIZE,D_PERSIST,D_POST,D_PRE,D_SYNON,D_KEY,D_DECOMP,D_MEMORY,D_REASM,D_GOTO,D_NEWKEY,D_RESTATE,D_COUNT };

void *allocate(size_t size) { void *result=calloc(1,size ? size : 1); if (!result) exit(EXIT_FAILURE); return result; }
void *resize(void *pointer,size_t size) { void *result=realloc(pointer,size ? size : 1); if (!result) exit(EXIT_FAILURE); return result; }
char *copy_text(const char *text) { char *result=allocate(strlen(text)+1); strcpy(result,text); return result; }
char *format(const char *pattern,...) {
    va_list args,copy; va_start(args,pattern); va_copy(copy,args); int length=vsnprintf(NULL,0,pattern,args); va_end(args);
    char *result=allocate((size_t)length+1); vsnprintf(result,(size_t)length+1,pattern,copy); va_end(copy); return result;
}
void text_append(Text *text,const char *part) {
    size_t length=strlen(part),needed=text->length+length+1;
    if (needed>text->capacity) { size_t capacity=text->capacity ? text->capacity : 64; while (capacity<needed) capacity*=2; text->data=resize(text->data,capacity); text->capacity=capacity; }
    memcpy(text->data+text->length,part,length+1); text->length+=length;
}
void strings_add(Strings *strings,const char *text) { if (strings->count==strings->capacity) { strings->capacity=strings->capacity ? strings->capacity*2 : 8; strings->data=resize(strings->data,(size_t)strings->capacity*sizeof(*strings->data)); } strings->data[strings->count++]=copy_text(text); }
bool strings_contains(Strings strings,const char *word) { for (int i=0;i<strings.count;i++) if (!strcmp(strings.data[i],word)) return true; return false; }
Strings strings_split(const char *text) {
    Strings result={0}; const char *p=text;
    while (*p) { while (*p==' ') p++; if (!*p) break; const char *start=p; while (*p && *p!=' ') p++; char *word=allocate((size_t)(p-start)+1); memcpy(word,start,(size_t)(p-start)); strings_add(&result,word); }
    return result;
}
Strings strings_copy(Strings source) { Strings result={0}; if (source.count) { result.data=allocate((size_t)source.count*sizeof(*result.data)); memcpy(result.data,source.data,(size_t)source.count*sizeof(*result.data)); result.count=result.capacity=source.count; } return result; }
char *strings_join(Strings strings,const char *separator) { Text result={0}; for (int i=0;i<strings.count;i++) { if (i) text_append(&result,separator); text_append(&result,strings.data[i]); } return result.data ? result.data : copy_text(""); }
Strings read_lines(const char *path) {
    FILE *file=fopen(path,"r"); if (!file) exit(EXIT_FAILURE); Strings lines={0}; Text line={0}; int c;
    while ((c=fgetc(file))!=EOF) { if (c=='\n') { strings_add(&lines,line.data ? line.data : ""); line.length=0; if (line.data) line.data[0]='\0'; } else { char part[2]={(char)c,0}; text_append(&line,part); } }
    if (ferror(file)) exit(EXIT_FAILURE); fclose(file); free(line.data); return lines;
}
bool is_word(const char *text) { size_t length=strlen(text); if (!length || text[0]=='\'' || text[length-1]=='\'') return false; for (;*text;text++) if (!(*text>='a' && *text<='z') && !(*text>='0' && *text<='9') && *text!='\'') return false; return true; }
bool is_reference(const char *text) { return strlen(text)==3 && text[0]=='(' && text[1]>='0' && text[1]<='9' && text[2]==')'; }
bool is_wildcard(const char *text) { return !strcmp(text,"*") || !strcmp(text,"#") || text[0]=='@'; }
Keyword *find_keyword(Script *s,const char *word) { for (int i=0;i<s->keyword_count;i++) if (!strcmp(s->keywords[i]->word,word)) return s->keywords[i]; return NULL; }
Group *find_group(Script *s,const char *word) { for (int i=0;i<s->group_count;i++) if (!strcmp(s->groups[i].name,word)) return &s->groups[i]; return NULL; }
Substitution *find_substitution(Substitution *entries,int count,const char *word) { for (int i=0;i<count;i++) if (!strcmp(entries[i].source,word)) return &entries[i]; return NULL; }
void add_diagnostic(Script *s,int line,int code,const char *message) {
    if (s->diagnostic_count==s->diagnostic_capacity) { s->diagnostic_capacity=s->diagnostic_capacity ? s->diagnostic_capacity*2 : 32; s->diagnostics=resize(s->diagnostics,(size_t)s->diagnostic_capacity*sizeof(*s->diagnostics)); }
    int index=s->diagnostic_count++; s->diagnostics[index]=(Diagnostic){line,code,index,copy_text(message)};
}
static int name_index(const char *name,const char *const *names,int count) { for (int i=0;i<count;i++) if (!strcmp(name,names[i])) return i; return -1; }
static bool number(const char *text) { size_t n=strlen(text); return n>=1 && n<=2 && text[0]>='0' && text[0]<='9' && (n==1 || (text[1]>='0' && text[1]<='9')); }
static bool formed(int directive,Strings args) {
    int n=args.count;
    if (directive<D_QUIT || directive==D_REASM) return n>=1;
    if (directive==D_PRE || directive==D_SYNON) { if (n<2) return false; }
    else if (directive==D_QUIT || directive==D_STOP || directive==D_DECOMP || directive==D_MEMORY) { if (n<1) return false; }
    else if (directive==D_MEMSIZE) return n==1 && number(args.data[0]) && atoi(args.data[0])>=1 && atoi(args.data[0])<=20;
    else if (directive==D_PERSIST) return n==1 && (!strcmp(args.data[0],"cycles") || !strcmp(args.data[0],"memory"));
    else if (directive==D_POST) return n>=2 && is_word(args.data[0]);
    else if (directive==D_KEY) return n==2 && is_word(args.data[0]) && number(args.data[1]);
    else if (directive==D_GOTO) return n==1 && is_word(args.data[0]);
    else if (directive==D_NEWKEY) return n==0;
    else if (directive==D_RESTATE) { if (n<2 || !is_word(args.data[0])) return false; for (int i=1;i<n;i++) if (!is_word(args.data[i]) && !is_reference(args.data[i])) return false; return true; }
    for (int i=0;i<n;i++) {
        char *arg=args.data[i];
        if (directive==D_DECOMP || directive==D_MEMORY) { if (strcmp(arg,"*") && strcmp(arg,"#") && !(arg[0]=='@' && is_word(arg+1)) && !is_word(arg)) return false; }
        else if (!is_word(arg)) return false;
    }
    return true;
}
Script *load_script(const char *path) {
    static const char *const names[]={"INITIAL","FINAL","DEFAULT","QUESTION","REPEAT","QUIT","STOP","MEMSIZE","PERSIST","POST","PRE","SYNON","KEY","DECOMP","MEMORY","REASM","GOTO","NEWKEY","RESTATE"};
    Script *s=allocate(sizeof(*s)); s->lines=read_lines(path); s->memsize=3;
    Keyword *keyword=NULL; Rule *rule=NULL; bool ignoring=false; Strings definitions={0}; int definition_lines[600];
    for (int line=0;line<s->lines.count;line++) {
        char *raw=s->lines.data[line]; if (!*raw || *raw=='#') continue;
        Strings words=strings_split(raw); char *name=words.data[0]; char *space=strchr(raw,' '); char *text=space ? space+1 : ""; Strings args=strings_split(text);
        int directive=name_index(name,names,D_COUNT);
        if ((directive>=0 && directive<=D_KEY)) { keyword=NULL; rule=NULL; ignoring=false; }
        else if (directive>=D_DECOMP) { if (ignoring) continue; if (directive==D_DECOMP || directive==D_MEMORY) rule=NULL; }
        char *definition=NULL;
        if (directive==D_MEMSIZE) definition="MEMSIZE";
        else if (directive==D_PERSIST || directive==D_POST || directive==D_PRE || directive==D_SYNON || directive==D_KEY) { if (args.count) definition=format("%s %s",name,args.data[0]); }
        int code=-1; char *message=NULL; int duplicate=-1;
        if (definition) for (int i=0;i<definitions.count;i++) if (!strcmp(definition,definitions.data[i])) { duplicate=i; break; }
        if (directive<0) { code=0; message=format("unknown directive %s",name); }
        else if (!formed(directive,args)) { code=0; message=format("bad arguments for %s",name); }
        else if ((directive==D_DECOMP || directive==D_MEMORY) && !keyword) { code=1; message=format("%s without KEY",name); }
        else if (directive==D_REASM && !rule) { code=1; message="REASM without DECOMP or MEMORY"; }
        else if (directive>=D_GOTO && (!rule || rule->memory)) { code=1; message=format("%s without DECOMP",name); }
        else if (duplicate>=0) { code=2; message=format("%s first defined at line %d",definition,definition_lines[duplicate]); if (directive==D_KEY) ignoring=true; }
        if (code>=0) { add_diagnostic(s,line+1,code,message); continue; }
        if (definition) { definition_lines[definitions.count]=line+1; strings_add(&definitions,definition); }
        if (directive<D_QUIT) strings_add(&s->texts[directive],text);
        else if (directive==D_QUIT || directive==D_STOP) { Strings *set=directive==D_QUIT ? &s->quit : &s->stop; for (int i=0;i<args.count;i++) if (!strings_contains(*set,args.data[i])) strings_add(set,args.data[i]); }
        else if (directive==D_MEMSIZE) s->memsize=atoi(args.data[0]);
        else if (directive==D_PERSIST) { if (!strcmp(args.data[0],"cycles")) s->persist_cycles=true; else s->persist_memory=true; }
        else if (directive==D_POST || directive==D_PRE) { Substitution entry={args.data[0],{args.data+1,args.count-1,0},line+1}; if (directive==D_POST) s->posts[s->post_count++]=entry; else s->pres[s->pre_count++]=entry; }
        else if (directive==D_SYNON) s->groups[s->group_count++]=(Group){args.data[0],args,line+1};
        else if (directive==D_KEY) { keyword=allocate(sizeof(*keyword)); keyword->word=args.data[0]; keyword->rank=atoi(args.data[1]); keyword->line=line+1; keyword->index=s->keyword_count; s->keywords[s->keyword_count++]=keyword; }
        else if (directive==D_DECOMP || directive==D_MEMORY) { rule=allocate(sizeof(*rule)); rule->memory=directive==D_MEMORY; rule->pattern=args; rule->line=line+1; rule->index=s->rule_count; s->rules[s->rule_count++]=rule; if (rule->memory) keyword->memories[keyword->memory_count++]=rule; else keyword->decomps[keyword->decomp_count++]=rule; }
        else { Item *item=allocate(sizeof(*item)); item->kind=(ItemKind)(directive-D_REASM); item->text=text; item->args=args; item->line=line+1; item->index=s->item_count; s->items[s->item_count++]=item; rule->items[rule->count++]=item; }
    }
    return s;
}
