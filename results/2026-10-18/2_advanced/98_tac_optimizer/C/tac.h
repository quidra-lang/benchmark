#ifndef TAC_H
#define TAC_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <limits.h>
#include <stdarg.h>
#include <ctype.h>
#define NAME 32
#define TEXT 160
enum { COPY, BIN, LOAD, STORE, GOTO, IF, PARAM, CALL, RETURN, READ, PRINT, KIND_COUNT };
extern const char *kind_names[KIND_COUNT];
typedef struct { int kind, number, count; char dest[NAME], a[NAME], b[NAME], op[NAME], target[NAME]; } Instruction;
typedef struct { char name[NAME]; char (*params)[NAME]; int np; Instruction *code; int count, capacity, temporary, preheader, removed; } Function;
typedef struct { char name[NAME]; int size; } Array;
typedef struct { Function *functions; int count; Array *arrays; int na; } Program;
typedef struct { int *data; int count, capacity; } Ints;
typedef struct { char **data; int count, capacity; } Strings;
typedef struct { unsigned char *bits; int size; } Set;
typedef struct { int first, last, startline, endline, successors[2], ns; Ints predecessors; Set dom; int reachable, idom, depth; } Block;
typedef struct { int header, depth; Set blocks, latches, exits, outside; } Loop;
typedef struct { char name[NAME]; int number, line; } Definition;
typedef struct { Instruction instruction; char text[TEXT]; } Expression;
typedef struct { char x[NAME], y[NAME]; } Copy;
typedef struct {
    Function *function; Ints instructions, postorder, order;
    Block *blocks; int nb, *iblock, *lineblock;
    Loop *loops; int nl;
    char (*variables)[NAME]; int nv;
    Definition *definitions; int nd;
    Expression *expressions; int ne;
    Copy *copies; int nc;
    Set *in[4], *out[4], *before[4], *after_live;
    int iterations[4];
} Analysis;
typedef struct { uint32_t *digits; int length,capacity; } Big;
typedef struct { int *colors, *order, *potential_degree; Big *cost; unsigned char *edges, *partners; int nodes, edge_count; } Allocation;
void *allocate(size_t n);
void *resize(void *p, size_t n);
char *string_copy(const char *s);
void ints_add(Ints *a, int value);
void strings_add(Strings *a, const char *text);
void strings_format(Strings *a, const char *format, ...);
void strings_free(Strings *a);
Set set_new(int n, int full);
Set set_copy(Set s);
void set_assign(Set a, Set b);
void set_union(Set a, Set b);
void set_intersect(Set a, Set b);
int set_equal(Set a, Set b);
int set_count(Set s);
int constant(const char *s);
long long operation(const char *op, long long a, long long b);
const char *defined(const Instruction *s);
int used(Instruction *s, char **values);
int expression_equal(const Instruction *a, const Instruction *b);
void expression_text(const Instruction *s, char *out);
void instruction_text(const Instruction *s, char *out);
void code_add(Function *f, Instruction s);
Function function_copy(const Function *f);
void function_free(Function *f);
Program read_program(const char *path);
Program program_copy(const Program *p);
void program_free(Program *p);
void write_function(FILE *f, const Function *fn);
void write_program(FILE *f, const Program *p);
Analysis analyze(Function *f);
void analysis_free(Analysis *a);
void solve_dataflow(Analysis *a);
void transfer(Analysis *a, int type, Set state, const Instruction *s);
int variable_index(const Analysis *a, const char *name);
int expr_index(const Analysis *a, const Instruction *s);
void filter_code(Function *f, const unsigned char *deleted);
int fold_instruction(Instruction *s);
void cse_rewrite(Function *f, const Analysis *a, const unsigned char *candidates, const unsigned char *sources, const char *temp);
void hoist_code(Function *f, const Analysis *a, int loop, Ints move, int preheader, const char *label);
Allocation allocate_registers(Analysis *a, int registers);
char *big_string(const Big *value);
void allocation_free(Allocation *a);
#endif
