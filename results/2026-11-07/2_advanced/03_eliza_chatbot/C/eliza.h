#ifndef ELIZA_H
#define ELIZA_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char **data; int count,capacity; } Strings;
typedef struct { char *data; size_t length,capacity; } Text;
typedef struct { int line,code,order; char *message; } Diagnostic;
typedef struct { char *source; Strings replacement; int line; } Substitution;
typedef struct { char *name; Strings members; int line; } Group;
typedef enum { REASM,GOTO,NEWKEY,RESTATE } ItemKind;
typedef struct { ItemKind kind; char *text; Strings args; int line,index; } Item;
typedef struct { bool memory; Strings pattern; int line,index,count; Item *items[12]; } Rule;
typedef struct { char *word; int rank,line,index,memory_count,decomp_count; Rule *memories[20],*decomps[20]; } Keyword;
typedef struct {
    Strings lines,texts[5],quit,stop;
    int memsize;
    bool persist_cycles,persist_memory;
    Substitution pres[600],posts[600]; int pre_count,post_count;
    Group groups[600]; int group_count;
    Keyword *keywords[100]; int keyword_count;
    Rule *rules[600]; int rule_count;
    Item *items[600]; int item_count;
    Diagnostic *diagnostics; int diagnostic_count,diagnostic_capacity;
} Script;
typedef struct { bool matched; Strings data[8]; int count; } Bindings;
typedef struct { int capacity; Strings texts,log; } Memory;

void *allocate(size_t size);
void *resize(void *pointer,size_t size);
char *copy_text(const char *text);
char *format(const char *pattern,...);
void text_append(Text *text,const char *part);
void strings_add(Strings *strings,const char *text);
bool strings_contains(Strings strings,const char *word);
Strings strings_split(const char *text);
Strings strings_copy(Strings source);
char *strings_join(Strings strings,const char *separator);
Strings read_lines(const char *path);
bool is_word(const char *text);
bool is_reference(const char *text);
bool is_wildcard(const char *text);
Keyword *find_keyword(Script *script,const char *word);
Group *find_group(Script *script,const char *word);
Substitution *find_substitution(Substitution *entries,int count,const char *word);
void add_diagnostic(Script *script,int line,int code,const char *message);
Script *load_script(const char *path);
Strings lint_script(Script *script);
Bindings match_pattern(Strings pattern,Strings words,Script *script);
bool pattern_covers(Strings earlier,Strings later,Script *script);
Strings reflect(Strings words,Script *script);
char *build_reply(const char *text,Bindings bindings,Script *script);
Strings restated_words(Strings args,Bindings bindings);
Strings eliza_lines(const char *text);
bool memory_store(Memory *memory,const char *prefix,const char *keyword,const char *text);
char *memory_recall(Memory *memory,const char *prefix);
void memory_clear(Memory *memory,const char *prefix);
#endif
