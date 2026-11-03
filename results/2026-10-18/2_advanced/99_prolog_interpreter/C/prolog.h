#ifndef PROLOG_H
#define PROLOG_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include <limits.h>
#include <stdarg.h>
#include <setjmp.h>
typedef struct Memory Memory;
struct Memory { Memory *next; };
extern Memory *memory;
void *make(size_t n);
char *copy_string(const char *s);
void release_to(Memory *mark);
typedef struct { char *text; size_t length,capacity; } Buffer;
void add_bytes(Buffer *b,const char *s,size_t n);
void add_text(Buffer *b,const char *s);
void add_format(Buffer *b,const char *fmt,...);
char *file_text(const char *path);
char *line_read(FILE *f);
enum { TERM_INTEGER,TERM_ATOM,TERM_VARIABLE,TERM_COMPOUND };
typedef struct Term Term;
struct Term { int kind,arity; long long integer; char *name; Term **args,*binding; };
Term *integer(long long n);
Term *atom(const char *name);
Term *fresh(void);
Term *compound(const char *name,int arity,Term **args);
Term *unary(const char *name,Term *a);
Term *binary(const char *name,Term *a,Term *b);
Term *ternary(const char *name,Term *a,Term *b,Term *c);
Term *dereference(Term *t);
int is_term(Term *t,const char *name,int arity);
int empty_list(Term *t);
Term *list(Term **items,int count,Term *tail);
int list_items(Term *t,Term ***items,Term **tail);
Term *copy_term(Term *t);
Term *copy_pair(Term *head,Term *body,Term **new_body);
Term *indicator(const char *name,int arity);
Term *type_error(const char *expected,Term *actual);
Term *domain_error(const char *domain,Term *actual);
Term *evaluation_error(const char *name);
typedef struct { Term **variables; int count,capacity; } Trail;
int unify(Trail *trail,Term *a,Term *b);
void undo(Trail *trail,int mark);
int identical(Term *a,Term *b);
typedef struct { char *name; int priority,left,right,prefix; } Operator;
const Operator *infix_operator(const char *name);
int prefix_priority(const char *name);
int symbol_character(int c);
enum { TOKEN_INTEGER,TOKEN_NAME,TOKEN_QUOTED,TOKEN_VARIABLE,TOKEN_PUNCT,TOKEN_END,TOKEN_EOF,TOKEN_INVALID };
typedef struct { int kind,line,column,space; char *text,*name; long long integer; } Token;
typedef struct { char *name; Term *term; int occurrences; } ReadVariable;
typedef struct { Token *tokens; int count,at,error_at; char *error; ReadVariable *variables; int nv; jmp_buf failure; } Reader;
Reader tokenize(const char *text,int column);
Term *read_clause(Reader *r,int query);
void reader_reset_variables(Reader *r);
typedef struct { Term *head,*body; int file,line; } Clause;
typedef struct { char *name; int arity; Clause **clauses; int count; int warned[2]; } Predicate;
typedef struct { Predicate **predicates; int count; } Database;
Predicate *predicate(Database *d,const char *name,int arity,int create);
void add_clause(Predicate *p,Clause *c);
Clause **candidate_clauses(Predicate *p,Term *goal,int *count);
int control(const char *name,int arity);
int builtin_predicate(const char *name,int arity);
Term *convert_goal(Term *goal,int *valid);
typedef struct { Term *variable; char *name; int count; } VariableName;
typedef struct { VariableName *items; int count,next; } Names;
char *write_term(Term *t,int quoted,int limit,int operand,Names *names);
char *indicator_string(const char *name,int arity);
typedef struct { Trail *trail; Buffer *output; Term *error; } BuiltinState;
int deterministic(BuiltinState *state,Term *goal);
int integer_check(BuiltinState *state,Term *t);
#endif
