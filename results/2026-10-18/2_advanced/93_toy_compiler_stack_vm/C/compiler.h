#ifndef TOY_COMPILER_H
#define TOY_COMPILER_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <setjmp.h>
#include <sys/stat.h>
void *ml_alloc(size_t);
void *ml_grow(void *, int *, size_t, int);
char *ml_text(const char *, size_t);
char *ml_format(const char *, ...);
void ml_cleanup(void);
#define PUSH(v, x)                                                                                 \
    do {                                                                                           \
        if ((v).count == (v).capacity)                                                             \
            (v).items = ml_grow((v).items, &(v).capacity, sizeof(*(v).items), (v).count);          \
        (v).items[(v).count++] = (x);                                                              \
    } while (0)
typedef struct {
    char *items;
    int count, capacity;
} Text;
void text_add(Text *, const char *);
void text_char(Text *, char);
char *text_value(Text *);
bool equal(const char *, const char *);
bool word_in(const char *, const char *);
typedef struct {
    int line, column;
} Position;
bool earlier(Position, Position);
char *position_text(Position);
typedef struct {
    const char *kind;
    char *spelling;
    int64_t integer;
    Position position;
} Token;
typedef struct {
    Token *items;
    int count, capacity;
} TokenList;
typedef struct {
    char **items;
    int count, capacity;
} StringList;
typedef struct {
    int *items;
    int count, capacity;
} IntList;
typedef struct {
    int64_t *items;
    int count, capacity;
} NumberList;
typedef struct {
    const char *kind;
    char *message;
    Position position;
    jmp_buf jump;
} CompileContext;
void compile_fail(CompileContext *, const char *, Position, const char *);
TokenList tokenize(StringList, int, CompileContext *);
typedef enum { TOY_INT, TOY_BOOL, TOY_VOID } ToyType;
const char *type_text(ToyType);
typedef struct Symbol Symbol;
typedef struct Declaration Declaration;
typedef struct Statement Statement;
typedef struct Expr Expr;
typedef struct {
    Expr **items;
    int count, capacity;
} ExprList;
typedef struct {
    Declaration **items;
    int count, capacity;
} DeclarationList;
typedef struct {
    Statement **items;
    int count, capacity;
} StatementList;
typedef struct {
    Symbol **items;
    int count, capacity;
} SymbolList;
struct Expr {
    const char *kind;
    ToyType type;
    Token token;
    int64_t value;
    ExprList children;
    Symbol *referent;
};
struct Declaration {
    ToyType type;
    Token name, size;
    bool array, function;
    Expr *initializer;
    DeclarationList parameters;
    Statement *body;
    Symbol *symbol;
    SymbolList slots;
};
struct Statement {
    const char *kind;
    Token token, close;
    Declaration *declaration;
    Expr *expr, *index, *condition;
    ExprList expressions;
    StatementList statements;
    Statement *yes, *no, *body, *init, *update;
    Symbol *referent;
};
typedef struct NameEntry {
    const char *name;
    Symbol *symbol;
    struct NameEntry *next;
} NameEntry;
typedef struct {
    DeclarationList declarations, globals, functions;
    Token end;
    NameEntry *names;
    SymbolList symbols;
} Program;
Expr *new_expr(const char *, Token);
Statement *new_statement(const char *, Token);
typedef struct {
    TokenList tokens;
    int index;
    CompileContext *context;
} Parser;
Program *parse(Parser *);
struct Symbol {
    const char *name;
    ToyType type;
    const char *kind;
    Declaration *declaration;
    bool array;
    int size, address, slot, reads;
    IntList reference_lines;
    SymbolList calls;
};
typedef struct Scope {
    NameEntry *names;
    struct Scope *parent;
} Scope;
typedef struct {
    Program *program;
    Scope *scope;
    Declaration *function;
    int loops;
    CompileContext *context;
} Semantics;
NameEntry *name_add(NameEntry *, const char *, Symbol *);
Symbol *name_lookup(NameEntry *, const char *);
bool symbol_member(SymbolList, Symbol *);
void analyze(Semantics *);
bool can_complete(Statement *);
void walk_statements(Statement *, void (*)(Statement *, void *), void *);
typedef struct {
    const char *op;
    int64_t a, b;
    Position position;
    Declaration *callee;
} Instruction;
typedef struct {
    Instruction *items;
    int count, capacity;
} Code;
typedef struct {
    int first, last, successors[2], successor_count;
} BasicBlock;
typedef struct {
    BasicBlock *items;
    int count, capacity;
} BlockList;
typedef struct {
    const char *name;
    Declaration *function;
    Code code;
    int start, slots, stack;
    BlockList blocks;
} Unit;
typedef struct {
    Unit **items;
    int count, capacity;
} UnitList;
bool jump(const char *);
bool conditional(const char *);
bool transfer(const char *);
typedef struct {
    int leave, again;
} Loop;
typedef struct {
    Loop *items;
    int count, capacity;
} LoopList;
typedef struct {
    Unit *unit;
    IntList labels;
    LoopList loops;
} Generator;
typedef struct {
    UnitList units;
    int cells;
} Generation;
Generation generate(Program *, SymbolList);
typedef struct {
    Instruction instruction;
    int unit;
} Executable;
typedef struct {
    Executable *items;
    int count, capacity;
} ExecutableList;
typedef struct {
    int from, to, count;
} CallPair;
typedef struct {
    CallPair *items;
    int count, capacity;
} PairList;
typedef struct {
    StringList output;
    int executed, maximum_stack, maximum_depth, fault_pc;
    int *counts;
    int *calls;
    PairList pairs;
    const char *error;
    IntList returns;
} RunResult;
ExecutableList flatten(UnitList);
RunResult *execute(UnitList, int, NumberList);
#endif
