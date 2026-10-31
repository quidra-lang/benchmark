#ifndef MACRO_PREPROCESSOR_H
#define MACRO_PREPROCESSOR_H
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
    char **items;
    int count, capacity;
} StringList;
bool string_member(StringList, const char *);
void string_insert(StringList *, const char *);
StringList names_union(StringList, StringList);
StringList names_intersection(StringList, StringList);
typedef struct {
    const char *file;
    int line;
} Position;
char *position_text(Position);
typedef struct {
    const char *kind;
    const char *spelling;
    int line;
    bool space;
    StringList hide;
} Token;
typedef struct {
    Token *items;
    int count, capacity;
} Tokens;
typedef struct {
    Tokens *items;
    int count, capacity;
} TokenGroups;
typedef struct {
    Tokens tokens;
    int start, end;
} LogicalLine;
typedef struct {
    LogicalLine *items;
    int count, capacity;
} LogicalLines;
typedef struct {
    const char *kind;
    char *spelling;
    size_t end;
} ReadToken;
ReadToken read_token(const char *, size_t, bool);
LogicalLines lex_source(const char *);
Tokens lex_definition(const char *, int);
Tokens copy_tokens(Tokens);
char *render(Tokens);
const char *single_token(const char *);
typedef struct Macro {
    const char *name;
    bool function, variadic;
    StringList parameters;
    Tokens replacement;
    Position position;
    bool main_file;
    int expanded, tested;
    StringList references;
} Macro;
typedef struct {
    Macro **items;
    int count, capacity;
} MacroList;
bool builtin(const char *);
char *signature(Macro *);
char *check_name(Tokens, const char *);
Macro *parse_definition(Tokens, Position, bool, char **);
bool identical(Macro *, Macro *);
typedef struct {
    const char *path;
    char *guard;
    LogicalLines lines;
    int physical_lines, entered, skipped, output_lines, skipped_lines;
    bool once;
} FileData;
typedef struct {
    FileData **items;
    int count, capacity;
} FileList;
typedef struct {
    FileList files;
} IncludeManager;
const char *directive_name(Tokens);
char *search_include(const char *, bool);
FileData *find_file(IncludeManager *, const char *);
FileData *load_file(IncludeManager *, const char *);
typedef struct {
    const char *kind;
    Position start;
    bool parent, chosen, active, else_seen;
    int skip_start;
} ConditionalBlock;
typedef struct {
    ConditionalBlock **items;
    int count, capacity;
} BlockList;
typedef struct {
    FileData *source;
    int depth;
    const char *display_file;
    int offset;
    BlockList stack;
    Tokens segment;
} Inclusion;
Position display_position(Inclusion *, int);
bool skipping(Inclusion *);
typedef struct {
    bool present;
    char *rendering;
    char *name;
    bool quoted;
    int next;
    char *error;
} Header;
Header read_header(Tokens, int);
typedef struct ConditionExpr ConditionExpr;
struct ConditionExpr {
    const char *kind;
    const char *op;
    const char *name;
    int64_t value;
    ConditionExpr *first, *second, *third;
};
ConditionExpr *parse_condition(Tokens, const char *, char **);
typedef struct Preprocessor Preprocessor;
bool evaluate_condition(Preprocessor *, Position, ConditionExpr *, int64_t *, char **);
typedef struct MacroEntry {
    const char *name;
    Macro *macro;
    struct MacroEntry *next;
} MacroEntry;
typedef struct Saved {
    const char *name;
    MacroList stack;
    struct Saved *next;
} Saved;
struct Preprocessor {
    MacroEntry *macros;
    StringList ever_defined, poisoned;
    Saved *saved;
    IncludeManager manager;
    StringList output, history, diagnostics, tree, conditionals, regions;
    int errors, warnings, condition_counts[5], builtin_counts[3], counter;
    Position previous;
};
Macro *find_macro(Preprocessor *, const char *);
void set_macro(Preprocessor *, const char *, Macro *);
void diagnostic(Preprocessor *, Position, const char *, const char *);
Tokens expand(Preprocessor *, Inclusion *, Tokens);
#endif
