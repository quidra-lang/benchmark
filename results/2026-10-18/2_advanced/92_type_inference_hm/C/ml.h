#ifndef MINI_ML_H
#define MINI_ML_H
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
    const char *file;
    int line, column;
} Position;
typedef struct {
    const char *kind;
    char *spelling;
    char *value;
    Position position;
    int64_t integer;
} Token;
typedef struct {
    Token *items;
    int count, capacity;
} TokenList;
typedef struct {
    char **items;
    int count, capacity;
} StringList;
bool token_name(Token);
TokenList lex(const char *, StringList);
typedef enum {
    TYPE_VAR,
    TYPE_INT,
    TYPE_BOOL,
    TYPE_STRING,
    TYPE_LIST,
    TYPE_PAIR,
    TYPE_FUNCTION
} TypeKind;
typedef struct Type {
    TypeKind kind;
    struct Type *first, *second, *binding;
} Type;
typedef struct {
    Type **items;
    int count, capacity;
} TypeList;
typedef struct {
    Type *type;
    TypeList quantified;
} Scheme;
typedef struct TypeEnv {
    const char *name;
    Scheme scheme;
    struct TypeEnv *next;
} TypeEnv;
Type *fresh(void);
Type *construct(TypeKind, Type *, Type *);
Type *primitive(TypeKind);
Type *resolve(Type *);
TypeList free_variables(Type *);
bool type_member(TypeList, Type *);
Scheme generalize(Type *, TypeEnv *);
Type *instantiate(Scheme);
TypeEnv *type_add(TypeEnv *, const char *, Scheme);
TypeEnv *type_lookup(TypeEnv *, const char *);
typedef struct {
    Type *expected, *found;
    bool infinite, nested, failed;
} UnificationFailure;
UnificationFailure unify(Type *, Type *, bool);
struct Symbol;
typedef struct Expr Expr;
typedef struct Group Group;
typedef struct Binding Binding;
typedef struct {
    Expr *pattern;
    Expr *body;
} Arm;
typedef struct {
    Expr **items;
    int count, capacity;
} ExprList;
typedef struct {
    Arm *items;
    int count, capacity;
} ArmList;
typedef struct {
    Binding **items;
    int count, capacity;
} BindingList;
struct Expr {
    const char *kind;
    char *value;
    Position position;
    int64_t integer;
    ExprList children;
    Token token;
    Group *group;
    ArmList arms;
    Type *inferred;
    struct Symbol *reference;
};
struct Binding {
    Token name;
    Expr *expr;
    Scheme scheme;
    const char *classification;
};
struct Group {
    BindingList bindings;
    bool recursive;
    Position rec;
};
typedef struct {
    const char *kind;
    Token name;
    Expr *declared;
    Group *group;
    Expr *expr;
} Item;
typedef struct {
    TokenList tokens;
    int index;
    jmp_buf jump;
    Token error;
} Parser;
Token parser_peek(Parser *);
Item *parser_item(Parser *);
void parser_recover(Parser *);
int operator_precedence(const char *, bool *);
typedef struct {
    const char *kind;
    const char *name;
    Position position;
    Type *expected, *found;
    UnificationFailure failure;
    StringList candidates;
} TypeError;
typedef struct {
    BindingList locals;
    jmp_buf jump;
    TypeError error;
} Inferencer;
Type *infer_expression(Inferencer *, Expr *, TypeEnv *);
TypeEnv *infer_group(Inferencer *, Group *, TypeEnv *, bool);
void type_fail(Inferencer *, const char *, const char *, Position, Type *, Type *);
void infer_check(Inferencer *, Type *, Type *, Position);
typedef struct Value Value;
typedef struct ValueEnv {
    const char *name;
    Value *value;
    struct ValueEnv *next;
} ValueEnv;
typedef struct {
    Value **items;
    int count, capacity;
} ValueList;
struct Value {
    const char *kind;
    char *text;
    const char *builtin;
    int64_t integer;
    bool boolean;
    ValueList items;
    Token parameter;
    Expr *body;
    ValueEnv *environment;
};
Value *make_value(const char *);
ValueEnv *value_add(ValueEnv *, const char *, Value *);
Value *value_lookup(ValueEnv *, const char *);
typedef struct {
    int64_t calls;
    jmp_buf jump;
    Position error_position;
    char *error_message;
} Evaluator;
Value *eval_expression(Evaluator *, Expr *, ValueEnv *);
ValueEnv *eval_group(Evaluator *, Group *, ValueEnv *);
void runtime_fail(Evaluator *, Position, const char *);
Value *apply_builtin(Evaluator *, const char *, Value *, Position);
char *print_value(Value *);
char *quote_string(const char *);
#endif
