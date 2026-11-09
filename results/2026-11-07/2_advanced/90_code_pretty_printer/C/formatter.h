#ifndef FORMATTER_H
#define FORMATTER_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
typedef struct {
    char **data;
    int count, capacity;
} TextLines;
typedef struct {
    int line, column;
} Position;
typedef struct {
    Position position;
    char *message;
} FileError;
typedef enum {
    TOKEN_IDENTIFIER,
    TOKEN_KEYWORD,
    TOKEN_NUMBER,
    TOKEN_STRING,
    TOKEN_SYMBOL,
    TOKEN_END
} TokenKind;
typedef struct {
    char *value;
    bool line, own;
    Position position;
    int blank;
} Comment;
typedef struct {
    Comment **data;
    int count, capacity;
} Comments;
typedef struct {
    char *value;
    TokenKind kind;
    Position position;
    int blank, index;
    Comments leading, trailing;
    bool original_trailing;
} Token;
typedef struct {
    Token **data;
    int count, capacity;
} Tokens;
typedef struct {
    Token *token;
    Comment *comment;
} Lexeme;
typedef struct {
    Tokens tokens;
    Comments comments;
    Lexeme *items;
    int item_count, item_capacity;
    FileError error;
} Lexed;
typedef enum {
    N_PROGRAM,
    N_FUNCTION,
    N_DECLARATION,
    N_PARAMETER,
    N_LIST,
    N_DIMENSION,
    N_BLOCK,
    N_IF,
    N_WHILE,
    N_FOR,
    N_SWITCH,
    N_SWITCH_BODY,
    N_CLAUSE,
    N_RETURN,
    N_BREAK,
    N_CONTINUE,
    N_SIMPLE,
    N_ASSIGNMENT,
    N_CONDITIONAL,
    N_BINARY,
    N_UNARY,
    N_ATOM,
    N_PAREN,
    N_CALL,
    N_INDEX,
    N_MEMBER
} NodeKind;
typedef struct Node Node;
typedef struct {
    Node **data;
    int count, capacity;
} Nodes;
struct Node {
    NodeKind kind;
    const char *value;
    int first, last;
    Token *token, *name, *open, *close, *op, *colon, *else_token, *semi, *semi2, *trailing;
    Node *expr, *left, *right, *then_part, *else_part, *body, *init, *condition, *update;
    Nodes elements, dimensions;
    Tokens commas;
};
typedef struct {
    Nodes nodes;
} NodePool;
typedef struct {
    const Tokens *tokens;
    int position;
    FileError error;
    NodePool pool;
} Parser;
typedef enum {
    D_TEXT,
    D_LINE,
    D_SOFTLINE,
    D_HARDLINE,
    D_BREAK_PARENT,
    D_SUFFIX,
    D_IF_BREAK,
    D_GROUP,
    D_NEST,
    D_ALIGN,
    D_CONCAT
} DocKind;
typedef enum { MODE_FLAT, MODE_BREAK, MODE_FORCED } Mode;
typedef struct Doc Doc;
typedef struct {
    Doc **data;
    int count, capacity;
} Docs;
struct Doc {
    DocKind kind;
    char *value, *other;
    Mode mode;
    int number;
    Docs children;
    bool forced;
};
typedef struct {
    Docs docs;
} DocPool;
typedef struct {
    int groups, broken, forced;
} GroupMetrics;
void *allocate(size_t size);
void *resize(void *data, size_t size);
char *copy_text(const char *text);
char *format_text(const char *format, ...);
char *repeated(char character, int count);
char *trim_right(char *text);
void lines_push(TextLines *lines, char *text);
void lines_add(TextLines *lines, const char *text);
void lines_append(TextLines *lines, const TextLines *from);
void lines_free(TextLines *lines);
TextLines read_lines(const char *path);
char *join_texts(const TextLines *texts, const char *separator);
bool word_in(const char *words, const char *word);
void comments_push(Comments *comments, Comment *comment);
void tokens_push(Tokens *tokens, Token *token);
Lexed lex(const TextLines *source);
void lex_free(Lexed *lexed);
void nodes_push(Nodes *nodes, Node *node);
Nodes node_children(const Node *node);
bool type_name(const Token *token);
int precedence(const char *op);
int expression_level(const Node *node);
Node *parse_program(Parser *parser);
void parser_free(Parser *parser);
void docs_push(Docs *docs, Doc *doc);
Doc *doc_text(DocPool *pool, const char *value);
Doc *doc_marker(DocPool *pool, DocKind kind);
Doc *doc_cat(DocPool *pool, Docs docs);
Doc *concat(DocPool *pool, int count, ...);
Doc *doc_group(DocPool *pool, Doc *child);
Doc *doc_nest(DocPool *pool, int amount, Doc *child);
Doc *doc_align(DocPool *pool, Doc *child);
Doc *doc_suffix(DocPool *pool, const char *value);
Doc *doc_if_break(DocPool *pool, const char *broken, const char *flat);
GroupMetrics group_metrics(const Doc *doc);
void doc_pool_free(DocPool *pool);
TextLines print_doc(Doc *doc, int width, int comment_column);
TextLines doc_tree(const Doc *doc, int depth);
TextLines diff_lines(const TextLines *before, const TextLines *after);
#endif
