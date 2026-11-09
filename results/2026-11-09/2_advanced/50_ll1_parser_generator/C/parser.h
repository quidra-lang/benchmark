#ifndef PARSER_H
#define PARSER_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
typedef struct {
    Allocation *head;
} Arena;
extern Arena *arena;
void *allocate(size_t size);
void *grow(const void *old, size_t old_size, size_t new_size);
void arena_free(Arena *values);
const char *copy_string(const char *text);
const char *substring(const char *text, size_t start, size_t length);
const char *format(const char *pattern, ...);
typedef struct {
    const char **v;
    int n, capacity;
} Strings;
void strings_add(Strings *values, const char *value);
bool strings_has(Strings values, const char *value);
bool strings_unique(Strings *values, const char *value);
Strings strings_slice(Strings values, int start, int end);
Strings strings_concat(Strings first, Strings second);
bool strings_equal(Strings first, Strings second);
void terminal_sort(Strings values);
typedef struct {
    int *v, n, capacity;
} Ints;
void ints_add(Ints *values, int value);
bool ints_has(Ints values, int value);
typedef struct {
    Strings *v;
    int n, capacity;
} Alternatives;
void alternatives_add(Alternatives *values, Strings alternative);
void alternatives_unique(Alternatives *values, Strings alternative);
bool nonterminal(const char *symbol);
const char *notation(Strings sequence);
const char *production_text(const char *lhs, Strings rhs);
typedef struct {
    const char *name;
    Alternatives alternatives;
} Rule;
typedef struct {
    Rule *v;
    int n, capacity;
    const char *start;
} Grammar;
int rule_index(const Grammar *grammar, const char *name);
void rule_add(Grammar *grammar, Rule rule, int position);
Grammar grammar_clone(const Grammar *grammar);
typedef struct {
    const char *name;
    int line;
} Occurrence;
typedef struct {
    Grammar grammar;
    Strings diagnostics, declared;
    bool declarations;
    Occurrence *words;
    int nwords, word_capacity;
} Parsed;
Parsed read_grammar(Strings lines);
Strings eliminate_recursion(Grammar *grammar);
Strings left_factor(Grammar *grammar);
typedef struct {
    const Grammar *grammar;
    bool *nullable;
    Strings *first, *follow;
    int nullable_passes, first_passes, follow_passes;
} Sets;
typedef struct {
    Strings terminals;
    bool nullable;
} First;
First first_sequence(Strings sequence, const Sets *sets);
Sets first_follow(const Grammar *grammar);
typedef struct {
    int lhs;
    Strings rhs;
} Production;
typedef struct {
    const Grammar *grammar;
    Production *productions;
    int nproductions, capacity;
    Strings *predict, *first, terminals;
    Ints *cells;
    int *chosen;
    int conflicts;
} Table;
Table build_table(const Grammar *grammar, const Sets *sets);
int terminal_index(const Table *table, const char *name);
const char *reason(const Table *table, int production, const char *terminal);
const char *conflict_kind(const Table *table, Ints cell, const char *terminal);
typedef struct {
    const char *name;
    int position;
} InputToken;
typedef struct Tree {
    const char *symbol, *mark;
    struct Tree **children;
    int nchildren;
} Tree;
typedef enum { ACCEPT, MATCH, PREDICT, SKIP, POP, MISSING } Action;
typedef struct {
    Strings stack, input;
    const char *top, *current;
    int position, production;
    Action action;
} Step;
typedef struct {
    Step *steps;
    int nsteps, capacity;
    Ints left_parse;
    Tree *tree;
    int matches, max_stack, skip, pop, missing;
} Parse;
Parse drive(const Grammar *grammar, const Sets *sets, const Table *table, const InputToken *tokens,
            int ntokens);
typedef struct {
    char *data;
    size_t size, capacity;
} Text;
void add(Text *out, const char *pattern, ...);
void line(Text *out, const char *pattern, ...);
#endif
